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

// Process MIDI input events for all modulators
static void processMidiInput() {
    auto MIDI_GetRecentInputEvents = (int (*)(int, char*, int))getMidiGetRecentInputEvents();
    if (!MIDI_GetRecentInputEvents) return;

    char buf[1024];
    int idx = 0;
    int ret;

    // Read all recent MIDI events
    while ((ret = MIDI_GetRecentInputEvents(idx++, buf, sizeof(buf))) > 0) {
        // Parse MIDI messages (each message is 3 bytes + timestamp)
        // Format depends on REAPER version, typically: offset, msg1, msg2, msg3
        if (ret >= 3) {
            unsigned char status = (unsigned char)buf[0];
            unsigned char data1 = (unsigned char)buf[1];
            unsigned char data2 = (unsigned char)buf[2];

            int msgType = status & 0xF0;
            int channel = status & 0x0F;

            auto& manager = ModulatorManager::instance();
            auto modulators = manager.getActiveModulators();

            for (Modulator* mod : modulators) {
                if (!mod || !mod->enabled.load()) continue;

                // Check channel filter
                if (mod->midiChannel >= 0 && mod->midiChannel != channel) continue;

                if (mod->source == ModSource::MidiCC && msgType == 0xB0) {
                    // Control Change
                    mod->updateMidiCC(data1, data2);
                }
                else if (mod->source == ModSource::MidiNote) {
                    if (msgType == 0x90 && data2 > 0) {
                        // Note On
                        mod->updateMidiNote(data1, data2, true);
                    }
                    else if (msgType == 0x80 || (msgType == 0x90 && data2 == 0)) {
                        // Note Off
                        mod->updateMidiNote(data1, data2, false);
                    }
                }
            }
        }
    }
}

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
    auto Track_GetPeakInfo = (double (*)(MediaTrack*, int))getTrackGetPeakInfo();

    // Process MIDI input
    processMidiInput();

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

        // Update based on source type
        switch (mod->source) {
            case ModSource::LFO:
                mod->advancePhase(deltaSeconds, bpm);
                break;

            case ModSource::AudioEnvelope:
                if (mod->sourceTrack && Track_GetPeakInfo) {
                    // Get peak from both channels and use max
                    double peakL = Track_GetPeakInfo(mod->sourceTrack, 0);
                    double peakR = Track_GetPeakInfo(mod->sourceTrack, 1);
                    double peak = peakL > peakR ? peakL : peakR;
                    // Convert from dB-ish to linear (Track_GetPeakInfo returns linear 0-1+ values)
                    if (peak > 1.0) peak = 1.0;
                    if (peak < 0.0) peak = 0.0;
                    mod->updateEnvelope(peak, deltaSeconds);
                }
                break;

            case ModSource::MidiCC:
            case ModSource::MidiNote:
                // Already handled in processMidiInput()
                break;
        }

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

    auto Audio_RegHardwareHook = (int (*)(bool, audio_hook_register_t*))getAudioRegHardwareHook();
    if (!Audio_RegHardwareHook) return;

    g_audioHook.OnAudioBuffer = audioHookCallback;
    g_audioHook.userdata1 = nullptr;
    g_audioHook.userdata2 = nullptr;

    Audio_RegHardwareHook(true, &g_audioHook);  // true = add
    g_audioHookActive.store(true);
}

void cleanupAudioHook() {
    if (!g_audioHookActive.load()) return;

    auto Audio_RegHardwareHook = (int (*)(bool, audio_hook_register_t*))getAudioRegHardwareHook();
    if (Audio_RegHardwareHook) {
        Audio_RegHardwareHook(false, &g_audioHook);  // false = remove
    }
    g_audioHookActive.store(false);
}

bool isAudioHookActive() {
    return g_audioHookActive.load();
}

} // namespace sidefx
