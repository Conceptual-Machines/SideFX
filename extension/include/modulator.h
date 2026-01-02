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

    // Curve shape
    BezierCurve curve;

    // Target parameter
    ModulationTarget target;

    // Rate settings
    RateMode rateMode = RateMode::FreeHz;
    double rateHz = 1.0;                        // Free rate in Hz
    SyncDivision syncDivision = SyncDivision::Quarter;

    // Modulation depth and offset
    double depth = 1.0;     // 0-1, how much modulation affects param
    double offset = 0.5;    // 0-1, center point of modulation

    // Phase
    std::atomic<double> phase{0.0};  // Current phase 0-1
    double phaseOffset = 0.0;        // Starting phase offset

    // State
    std::atomic<bool> enabled{false};
    bool bipolar = true;    // true: modulates around offset, false: 0 to depth

    // Get the current modulation value (0-1)
    double getCurrentValue() const {
        double curveValue = curve.evaluate(phase.load());

        if (bipolar) {
            // Bipolar: curve 0-1 maps to (offset - depth/2) to (offset + depth/2)
            return offset + (curveValue - 0.5) * depth;
        } else {
            // Unipolar: curve 0-1 maps to offset to (offset + depth)
            return offset + curveValue * depth;
        }
    }

    // Advance phase by delta time
    void advancePhase(double deltaSeconds, double bpm) {
        if (!enabled.load()) return;

        double cyclesPerSecond;
        if (rateMode == RateMode::FreeHz) {
            cyclesPerSecond = rateHz;
        } else {
            // Tempo sync: convert beat division to Hz
            double beatsPerSecond = bpm / 60.0;
            double beatsPerCycle = getSyncBeats(syncDivision);
            cyclesPerSecond = beatsPerSecond / beatsPerCycle;
        }

        double newPhase = phase.load() + deltaSeconds * cyclesPerSecond;

        // Wrap phase to 0-1
        newPhase = newPhase - std::floor(newPhase);
        phase.store(newPhase);
    }

    // Reset phase to starting position
    void resetPhase() {
        phase.store(phaseOffset);
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

