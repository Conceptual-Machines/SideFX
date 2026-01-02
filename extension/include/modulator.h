#pragma once

#include "bezier.h"
#include <string>
#include <vector>
#include <unordered_map>
#include <mutex>
#include <atomic>
#include <memory>

// Forward declare REAPER types
class MediaTrack;
class TrackEnvelope;

namespace sidefx {

//------------------------------------------------------------------------------
// Modulation Target
//------------------------------------------------------------------------------

struct ModulationTarget {
    MediaTrack* track = nullptr;
    int fx_index = -1;
    int param_index = -1;

    bool isValid() const {
        return track != nullptr && fx_index >= 0 && param_index >= 0;
    }
};

//------------------------------------------------------------------------------
// Trigger Mode - What starts/restarts the modulation
//------------------------------------------------------------------------------

enum class TriggerMode {
    Free,           // Continuous, no trigger (classic LFO)
    AudioLevel,     // Trigger when audio crosses threshold
    AudioTransient, // Trigger on audio attack/transient
    MidiNote,       // Trigger on MIDI note-on
    Manual          // Trigger via API call only
};

//------------------------------------------------------------------------------
// Playback Mode - How the shape plays
//------------------------------------------------------------------------------

enum class PlaybackMode {
    Loop,       // Repeats continuously (LFO style)
    OneShot     // Plays once, holds at end (envelope style)
};

//------------------------------------------------------------------------------
// Rate Mode - Free Hz or tempo-synced
//------------------------------------------------------------------------------

enum class RateMode {
    FreeHz,     // Rate in Hz
    TempoSync   // Rate as beat division
};

//------------------------------------------------------------------------------
// Tempo Sync Divisions
//------------------------------------------------------------------------------

enum class SyncDivision {
    Bar4 = 0, Bar2, Bar1, Half, Quarter, Eighth, Sixteenth, ThirtySecond,
    DottedHalf, DottedQuarter, DottedEighth,
    TripletHalf, TripletQuarter, TripletEighth
};

inline double getSyncBeats(SyncDivision div) {
    switch (div) {
        case SyncDivision::Bar4:          return 16.0;
        case SyncDivision::Bar2:          return 8.0;
        case SyncDivision::Bar1:          return 4.0;
        case SyncDivision::Half:          return 2.0;
        case SyncDivision::Quarter:       return 1.0;
        case SyncDivision::Eighth:        return 0.5;
        case SyncDivision::Sixteenth:     return 0.25;
        case SyncDivision::ThirtySecond:  return 0.125;
        case SyncDivision::DottedHalf:    return 3.0;
        case SyncDivision::DottedQuarter: return 1.5;
        case SyncDivision::DottedEighth:  return 0.75;
        case SyncDivision::TripletHalf:   return 4.0 / 3.0;
        case SyncDivision::TripletQuarter:return 2.0 / 3.0;
        case SyncDivision::TripletEighth: return 1.0 / 3.0;
        default: return 1.0;
    }
}

//------------------------------------------------------------------------------
// Recorded Automation Point
//------------------------------------------------------------------------------

struct AutomationPoint {
    double time;    // Project time in seconds
    double value;   // Normalized value 0-1
};

//------------------------------------------------------------------------------
// Modulator - Main class
//------------------------------------------------------------------------------

class Modulator {
public:
    int id = -1;
    std::string name;

    //=== SHAPE (Bezier curve) ===
    BezierCurve curve;              // The modulation shape

    //=== PLAYBACK ===
    PlaybackMode playbackMode = PlaybackMode::Loop;
    RateMode rateMode = RateMode::FreeHz;
    double rateHz = 1.0;
    SyncDivision syncDivision = SyncDivision::Quarter;

    //=== TRIGGER ===
    TriggerMode triggerMode = TriggerMode::Free;
    
    // Audio trigger settings
    MediaTrack* triggerTrack = nullptr;
    double audioThreshold = 0.1;        // 0-1
    double retriggerDelayMs = 50.0;     // Minimum ms between triggers
    double lastTriggerTime = 0.0;       // For retrigger delay
    double lastPeakValue = 0.0;         // For transient detection
    
    // MIDI trigger settings
    int midiChannel = -1;               // -1 = omni
    int midiNote = -1;                  // -1 = any
    bool velocityToDepth = false;       // Scale depth by velocity
    double velocityDepthScale = 1.0;    // Current velocity scaling

    //=== OUTPUT ===
    ModulationTarget target;
    double depth = 1.0;                 // 0-1
    double offset = 0.5;                // 0-1 center
    bool bipolar = true;

    //=== STATE ===
    std::atomic<double> phase{0.0};     // Current phase 0-1
    double phaseOffset = 0.0;           // Starting phase
    std::atomic<bool> enabled{false};
    std::atomic<bool> triggered{false}; // Has been triggered (for one-shot)
    std::atomic<bool> playing{false};   // Currently playing

    //=== RECORDING ===
    std::atomic<bool> recording{false};
    double recordStartTime = 0.0;
    double recordEndTime = 0.0;
    double recordResolution = 0.01;     // Seconds between points (10ms default)
    std::vector<AutomationPoint> recordedPoints;
    std::mutex recordMutex;

    //=== METHODS ===

    // Get current output value (0-1 normalized)
    double getCurrentValue() const {
        if (!playing.load() && playbackMode == PlaybackMode::OneShot) {
            // One-shot not triggered or finished - return offset
            double p = phase.load();
            if (p >= 1.0 || !triggered.load()) {
                // Return end value or offset based on curve
                return bipolar ? offset : offset;
            }
        }

        double curveValue = curve.evaluate(phase.load());
        double effectiveDepth = depth * velocityDepthScale;

        if (bipolar) {
            return offset + (curveValue - 0.5) * effectiveDepth;
        } else {
            return offset + curveValue * effectiveDepth;
        }
    }

    // Trigger the modulator (restart from beginning)
    void trigger(double velocity = 1.0) {
        phase.store(phaseOffset);
        triggered.store(true);
        playing.store(true);
        
        if (velocityToDepth) {
            velocityDepthScale = velocity;
        }
    }

    // Advance phase by delta time
    void advancePhase(double deltaSeconds, double bpm) {
        if (!enabled.load()) return;

        // Free mode always plays, other modes need trigger
        if (triggerMode != TriggerMode::Free && !playing.load()) return;

        double cyclesPerSecond;
        if (rateMode == RateMode::FreeHz) {
            cyclesPerSecond = rateHz;
        } else {
            double beatsPerSecond = bpm / 60.0;
            double beatsPerCycle = getSyncBeats(syncDivision);
            cyclesPerSecond = beatsPerSecond / beatsPerCycle;
        }

        double newPhase = phase.load() + deltaSeconds * cyclesPerSecond;

        if (playbackMode == PlaybackMode::Loop) {
            newPhase = newPhase - std::floor(newPhase);
        } else {
            // One-shot: clamp at 1.0
            if (newPhase >= 1.0) {
                newPhase = 1.0;
                playing.store(false);
            }
        }

        phase.store(newPhase);
    }

    // Check audio trigger
    bool checkAudioTrigger(double peak, double currentTime) {
        if (triggerMode == TriggerMode::AudioLevel) {
            bool shouldTrigger = peak > audioThreshold && 
                                 lastPeakValue <= audioThreshold &&
                                 (currentTime - lastTriggerTime) * 1000.0 > retriggerDelayMs;
            lastPeakValue = peak;
            if (shouldTrigger) {
                lastTriggerTime = currentTime;
                return true;
            }
        }
        else if (triggerMode == TriggerMode::AudioTransient) {
            // Simple transient detection: rising edge above threshold
            double diff = peak - lastPeakValue;
            bool shouldTrigger = diff > audioThreshold &&
                                 (currentTime - lastTriggerTime) * 1000.0 > retriggerDelayMs;
            lastPeakValue = peak;
            if (shouldTrigger) {
                lastTriggerTime = currentTime;
                return true;
            }
        }
        return false;
    }

    // Check MIDI trigger
    bool checkMidiTrigger(int channel, int note, int velocity) {
        if (triggerMode != TriggerMode::MidiNote) return false;
        if (midiChannel >= 0 && midiChannel != channel) return false;
        if (midiNote >= 0 && midiNote != note) return false;

        velocityDepthScale = velocityToDepth ? (velocity / 127.0) : 1.0;
        return true;
    }

    // Record a point
    void recordPoint(double time, double value) {
        if (!recording.load()) return;
        std::lock_guard<std::mutex> lock(recordMutex);
        recordedPoints.push_back({time, value});
    }

    // Start recording
    void startRecording(double startTime, double endTime, double resolution = 0.01) {
        std::lock_guard<std::mutex> lock(recordMutex);
        recordedPoints.clear();
        recordStartTime = startTime;
        recordEndTime = endTime;
        recordResolution = resolution;
        recording.store(true);
    }

    // Stop recording
    void stopRecording() {
        recording.store(false);
    }

    // Get recorded points (for printing to automation)
    std::vector<AutomationPoint> getRecordedPoints() {
        std::lock_guard<std::mutex> lock(recordMutex);
        return recordedPoints;
    }

    // Reset
    void reset() {
        phase.store(phaseOffset);
        triggered.store(false);
        playing.store(triggerMode == TriggerMode::Free);
        velocityDepthScale = 1.0;
        lastPeakValue = 0.0;
    }
};

//------------------------------------------------------------------------------
// Modulator Manager
//------------------------------------------------------------------------------

class ModulatorManager {
public:
    static ModulatorManager& instance() {
        static ModulatorManager mgr;
        return mgr;
    }

    int createModulator(const std::string& name = "");
    void destroyModulator(int id);
    Modulator* getModulator(int id);
    std::vector<Modulator*> getActiveModulators();

    std::unique_lock<std::mutex> lock() {
        return std::unique_lock<std::mutex>(mutex_);
    }

private:
    ModulatorManager() = default;
    ~ModulatorManager() = default;
    ModulatorManager(const ModulatorManager&) = delete;
    ModulatorManager& operator=(const ModulatorManager&) = delete;

    std::mutex mutex_;
    std::unordered_map<int, std::unique_ptr<Modulator>> modulators_;
    int nextId_ = 1;
};

} // namespace sidefx
