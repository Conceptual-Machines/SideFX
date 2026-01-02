#pragma once

#include "bezier.h"
#include <string>
#include <unordered_map>
#include <mutex>
#include <atomic>

// Forward declare REAPER types (matching reaper_plugin.h)
class MediaTrack;

namespace sidefx {

// Modulation target: which FX parameter to modulate
struct ModulationTarget {
    MediaTrack* track = nullptr;
    int fx_index = -1;
    int param_index = -1;

    bool isValid() const {
        return track != nullptr && fx_index >= 0 && param_index >= 0;
    }
};

// Modulation source type
enum class ModSource {
    LFO,            // Bezier curve LFO (default)
    AudioEnvelope,  // Envelope follower from track audio
    MidiCC,         // MIDI CC value
    MidiNote        // MIDI note velocity/gate
};

// Rate mode: free Hz or tempo-synced
enum class RateMode {
    FreeHz,         // Rate in Hz
    TempoSync       // Rate as beat division
};

// Tempo sync divisions
enum class SyncDivision {
    Bar4 = 0,       // 4 bars
    Bar2,           // 2 bars
    Bar1,           // 1 bar
    Half,           // 1/2 note
    Quarter,        // 1/4 note
    Eighth,         // 1/8 note
    Sixteenth,      // 1/16 note
    ThirtySecond,   // 1/32 note
    DottedHalf,     // Dotted 1/2
    DottedQuarter,  // Dotted 1/4
    DottedEighth,   // Dotted 1/8
    TripletHalf,    // Triplet 1/2
    TripletQuarter, // Triplet 1/4
    TripletEighth   // Triplet 1/8
};

// Get beats for a sync division (assuming 4/4)
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

// A single modulator instance
class Modulator {
public:
    int id = -1;
    std::string name;

    // Source type
    ModSource source = ModSource::LFO;

    // === LFO Settings ===
    BezierCurve curve;                          // LFO shape
    RateMode rateMode = RateMode::FreeHz;
    double rateHz = 1.0;                        // Free rate in Hz
    SyncDivision syncDivision = SyncDivision::Quarter;
    std::atomic<double> phase{0.0};             // Current phase 0-1
    double phaseOffset = 0.0;                   // Starting phase offset

    // === Audio Envelope Follower Settings ===
    MediaTrack* sourceTrack = nullptr;          // Track to follow
    double attackMs = 10.0;                     // Attack time in ms
    double releaseMs = 100.0;                   // Release time in ms
    std::atomic<double> envelopeValue{0.0};     // Current envelope value (smoothed)
    double lastPeak = 0.0;                      // Last raw peak for smoothing

    // === MIDI Settings ===
    int midiChannel = -1;                       // -1 = omni, 0-15 = specific channel
    int midiCC = 1;                             // CC number (1 = mod wheel)
    int midiNote = -1;                          // Note number for note tracking (-1 = any)
    std::atomic<double> midiValue{0.0};         // Current MIDI value (0-1)
    std::atomic<double> midiVelocity{0.0};      // Last note velocity (0-1)
    std::atomic<bool> midiNoteOn{false};        // Note gate

    // === Target & Output ===
    ModulationTarget target;                    // Target FX parameter
    double depth = 1.0;                         // 0-1, modulation amount
    double offset = 0.5;                        // 0-1, center point
    bool bipolar = true;                        // true: around offset, false: 0 to depth
    std::atomic<bool> enabled{false};

    // Get the current modulation value (0-1)
    double getCurrentValue() const {
        double rawValue = 0.0;

        switch (source) {
            case ModSource::LFO:
                rawValue = curve.evaluate(phase.load());
                break;
            case ModSource::AudioEnvelope:
                rawValue = envelopeValue.load();
                break;
            case ModSource::MidiCC:
                rawValue = midiValue.load();
                break;
            case ModSource::MidiNote:
                rawValue = midiNoteOn.load() ? midiVelocity.load() : 0.0;
                break;
        }

        if (bipolar) {
            return offset + (rawValue - 0.5) * depth;
        } else {
            return offset + rawValue * depth;
        }
    }

    // Advance LFO phase by delta time (only for LFO source)
    void advancePhase(double deltaSeconds, double bpm) {
        if (!enabled.load() || source != ModSource::LFO) return;

        double cyclesPerSecond;
        if (rateMode == RateMode::FreeHz) {
            cyclesPerSecond = rateHz;
        } else {
            double beatsPerSecond = bpm / 60.0;
            double beatsPerCycle = getSyncBeats(syncDivision);
            cyclesPerSecond = beatsPerSecond / beatsPerCycle;
        }

        double newPhase = phase.load() + deltaSeconds * cyclesPerSecond;
        newPhase = newPhase - std::floor(newPhase);
        phase.store(newPhase);
    }

    // Update envelope follower (call with current peak value)
    void updateEnvelope(double peak, double deltaSeconds) {
        if (!enabled.load() || source != ModSource::AudioEnvelope) return;

        double current = envelopeValue.load();
        double attackCoef = 1.0 - std::exp(-deltaSeconds * 1000.0 / attackMs);
        double releaseCoef = 1.0 - std::exp(-deltaSeconds * 1000.0 / releaseMs);

        double newValue;
        if (peak > current) {
            newValue = current + (peak - current) * attackCoef;
        } else {
            newValue = current + (peak - current) * releaseCoef;
        }
        envelopeValue.store(newValue);
    }

    // Update MIDI CC value
    void updateMidiCC(int cc, int value) {
        if (source != ModSource::MidiCC || cc != midiCC) return;
        midiValue.store(value / 127.0);
    }

    // Update MIDI note
    void updateMidiNote(int note, int velocity, bool noteOn) {
        if (source != ModSource::MidiNote) return;
        if (midiNote >= 0 && note != midiNote) return;  // Filter by note number

        if (noteOn) {
            midiVelocity.store(velocity / 127.0);
            midiNoteOn.store(true);
        } else {
            midiNoteOn.store(false);
        }
    }

    void resetPhase() {
        phase.store(phaseOffset);
        envelopeValue.store(0.0);
    }
};

// Modulator manager - thread-safe storage of all modulators
class ModulatorManager {
public:
    static ModulatorManager& instance() {
        static ModulatorManager mgr;
        return mgr;
    }

    // Create a new modulator, returns ID
    int createModulator(const std::string& name = "");

    // Destroy a modulator
    void destroyModulator(int id);

    // Get modulator by ID (nullptr if not found)
    Modulator* getModulator(int id);

    // Get all active modulators for audio processing
    std::vector<Modulator*> getActiveModulators();

    // Lock for iteration (use RAII)
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

