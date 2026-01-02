#include "audio_hook.h"
#include "modulator.h"
#include "reaper_plugin.h"

#include <atomic>
#include <cmath>

// External function pointers from main.cpp
extern void* getAudioRegHookAdd();
extern void* getAudioRegHookRemove();
extern void* getTrackFXSetParamNormalized();
extern void* getGetPlayState();
extern void* getGetPlayPosition();
extern void* getTimeMapGetDividedBpmAtTime();

namespace sidefx {

static std::atomic<bool> g_audioHookActive{false};
static audio_hook_register_t g_audioHook;

// Audio hook callback - runs at audio thread rate
static void audioHookCallback(bool isPost, int len, double srate,
                               struct audio_hook_register_t* reg) {
    if (!isPost) return;  // Only process after REAPER's audio

    // Calculate delta time from samples
    double deltaSeconds = static_cast<double>(len) / srate;

    // Get function pointers
    auto TrackFX_SetParamNormalized = (bool (*)(MediaTrack*, int, int, double))getTrackFXSetParamNormalized();
    auto GetPlayState = (int (*)())getGetPlayState();
    auto GetPlayPosition = (double (*)())getGetPlayPosition();
    auto TimeMap_GetDividedBpmAtTime = (double (*)(double))getTimeMapGetDividedBpmAtTime();

    // Get current BPM
    double bpm = 120.0;  // Default
    if (GetPlayState && GetPlayPosition && TimeMap_GetDividedBpmAtTime) {
        double pos = GetPlayPosition();
        bpm = TimeMap_GetDividedBpmAtTime(pos);
    }

    // Get all active modulators and update them
    auto& manager = ModulatorManager::instance();
    auto modulators = manager.getActiveModulators();

    for (Modulator* mod : modulators) {
        if (!mod || !mod->enabled.load()) continue;

        // Advance phase
        mod->advancePhase(deltaSeconds, bpm);

        // Get current modulation value
        double value = mod->getCurrentValue();

        // Clamp to valid range
        if (value < 0.0) value = 0.0;
        if (value > 1.0) value = 1.0;

        // Apply to target parameter
        if (mod->target.isValid() && TrackFX_SetParamNormalized) {
            TrackFX_SetParamNormalized(
                mod->target.track,
                mod->target.fx_index,
                mod->target.param_index,
                value
            );
        }
    }
}

void initAudioHook() {
    if (g_audioHookActive.load()) return;

    auto Audio_RegHookAdd = (void (*)(audio_hook_register_t*))getAudioRegHookAdd();
    if (!Audio_RegHookAdd) return;

    g_audioHook.OnAudioBuffer = audioHookCallback;
    g_audioHook.userdata1 = nullptr;
    g_audioHook.userdata2 = nullptr;

    Audio_RegHookAdd(&g_audioHook);
    g_audioHookActive.store(true);
}

void cleanupAudioHook() {
    if (!g_audioHookActive.load()) return;

    auto Audio_RegHookRemove = (void (*)(audio_hook_register_t*))getAudioRegHookRemove();
    if (Audio_RegHookRemove) {
        Audio_RegHookRemove(&g_audioHook);
    }
    g_audioHookActive.store(false);
}

bool isAudioHookActive() {
    return g_audioHookActive.load();
}

} // namespace sidefx
