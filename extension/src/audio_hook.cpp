#include "audio_hook.h"
#include "modulator.h"
#include "reaper_plugin.h"

#include <atomic>
#include <cmath>
#include <cstring>

// External function pointers from main.cpp
extern void* getAudioRegHardwareHook();
extern void* getTrackFXSetParamNormalized();
extern void* getGetPlayState();
extern void* getGetPlayPosition();
extern void* getTimeMapGetDividedBpmAtTime();
extern void* getTrackGetPeakInfo();
extern void* getMidiGetRecentInputEvents();

namespace sidefx {

static std::atomic<bool> g_audioHookActive{false};
static audio_hook_register_t g_audioHook;
static double g_lastRecordTime = 0.0;

// Process MIDI input for triggers
static void processMidiTriggers(double currentTime) {
    auto MIDI_GetRecentInputEvents = (int (*)(int, char*, int))getMidiGetRecentInputEvents();
    if (!MIDI_GetRecentInputEvents) return;

    char buf[1024];
    int idx = 0;
    int ret;

    while ((ret = MIDI_GetRecentInputEvents(idx++, buf, sizeof(buf))) > 0) {
        if (ret >= 3) {
            unsigned char status = (unsigned char)buf[0];
            unsigned char data1 = (unsigned char)buf[1];
            unsigned char data2 = (unsigned char)buf[2];

            int msgType = status & 0xF0;
            int channel = status & 0x0F;

            // Only process Note On messages
            if (msgType == 0x90 && data2 > 0) {
                auto& manager = ModulatorManager::instance();
                auto modulators = manager.getActiveModulators();

                for (Modulator* mod : modulators) {
                    if (!mod || !mod->enabled.load()) continue;
                    
                    if (mod->checkMidiTrigger(channel, data1, data2)) {
                        mod->trigger(data2 / 127.0);
                    }
                }
            }
        }
    }
}

// Process audio triggers
static void processAudioTriggers(double currentTime) {
    auto Track_GetPeakInfo = (double (*)(MediaTrack*, int))getTrackGetPeakInfo();
    if (!Track_GetPeakInfo) return;

    auto& manager = ModulatorManager::instance();
    auto modulators = manager.getActiveModulators();

    for (Modulator* mod : modulators) {
        if (!mod || !mod->enabled.load()) continue;
        if (mod->triggerMode != TriggerMode::AudioLevel && 
            mod->triggerMode != TriggerMode::AudioTransient) continue;
        if (!mod->triggerTrack) continue;

        // Get peak from trigger track
        double peakL = Track_GetPeakInfo(mod->triggerTrack, 0);
        double peakR = Track_GetPeakInfo(mod->triggerTrack, 1);
        double peak = peakL > peakR ? peakL : peakR;
        if (peak > 1.0) peak = 1.0;
        if (peak < 0.0) peak = 0.0;

        if (mod->checkAudioTrigger(peak, currentTime)) {
            mod->trigger(1.0);
        }
    }
}

// Audio hook callback
static void audioHookCallback(bool isPost, int len, double srate,
                               struct audio_hook_register_t* reg) {
    if (!isPost) return;

    double deltaSeconds = static_cast<double>(len) / srate;

    auto TrackFX_SetParamNormalized = (bool (*)(MediaTrack*, int, int, double))getTrackFXSetParamNormalized();
    auto GetPlayState = (int (*)())getGetPlayState();
    auto GetPlayPosition = (double (*)())getGetPlayPosition();
    auto TimeMap_GetDividedBpmAtTime = (double (*)(double))getTimeMapGetDividedBpmAtTime();

    // Get current time and BPM
    double currentTime = 0.0;
    double bpm = 120.0;
    if (GetPlayState && GetPlayPosition && TimeMap_GetDividedBpmAtTime) {
        currentTime = GetPlayPosition();
        bpm = TimeMap_GetDividedBpmAtTime(currentTime);
    }

    // Process triggers
    processMidiTriggers(currentTime);
    processAudioTriggers(currentTime);

    // Update all modulators
    auto& manager = ModulatorManager::instance();
    auto modulators = manager.getActiveModulators();

    for (Modulator* mod : modulators) {
        if (!mod || !mod->enabled.load()) continue;

        // Advance phase
        mod->advancePhase(deltaSeconds, bpm);

        // Get current value
        double value = mod->getCurrentValue();

        // Clamp
        if (value < 0.0) value = 0.0;
        if (value > 1.0) value = 1.0;

        // Record if enabled
        if (mod->recording.load()) {
            if (currentTime >= mod->recordStartTime && currentTime <= mod->recordEndTime) {
                // Record at specified resolution
                if (currentTime - g_lastRecordTime >= mod->recordResolution) {
                    mod->recordPoint(currentTime, value);
                    g_lastRecordTime = currentTime;
                }
            } else if (currentTime > mod->recordEndTime) {
                mod->stopRecording();
            }
        }

        // Apply to target
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

    auto Audio_RegHardwareHook = (int (*)(bool, audio_hook_register_t*))getAudioRegHardwareHook();
    if (!Audio_RegHardwareHook) return;

    g_audioHook.OnAudioBuffer = audioHookCallback;
    g_audioHook.userdata1 = nullptr;
    g_audioHook.userdata2 = nullptr;

    Audio_RegHardwareHook(true, &g_audioHook);
    g_audioHookActive.store(true);
}

void cleanupAudioHook() {
    if (!g_audioHookActive.load()) return;

    auto Audio_RegHardwareHook = (int (*)(bool, audio_hook_register_t*))getAudioRegHardwareHook();
    if (Audio_RegHardwareHook) {
        Audio_RegHardwareHook(false, &g_audioHook);
    }
    g_audioHookActive.store(false);
}

bool isAudioHookActive() {
    return g_audioHookActive.load();
}

} // namespace sidefx
