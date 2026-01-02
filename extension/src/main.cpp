// SideFX Modulation Engine - REAPER Extension
// Sample-accurate modulation with Bezier curve LFOs

#include "reaper_plugin.h"
#include "modulator.h"
#include "audio_hook.h"

#include <cstring>
#include <string>

// REAPER API function pointers we need
static int (*plugin_register)(const char* name, void* infostruct);
static int (*Audio_RegHardwareHook)(bool isAdd, audio_hook_register_t* reg);
static bool (*TrackFX_SetParamNormalized)(MediaTrack* track, int fx, int param, double value);
static int (*GetPlayState)();
static double (*GetPlayPosition)();
static double (*TimeMap_GetDividedBpmAtTime)(double time);
static int (*ShowMessageBox)(const char* msg, const char* title, int type);
static void (*ShowConsoleMsg)(const char* msg);
static double (*Track_GetPeakInfo)(MediaTrack* track, int chan);
static int (*MIDI_GetRecentInputEvents)(int idx, char* buf, int buf_sz);

// Envelope/Automation APIs
static TrackEnvelope* (*GetFXEnvelope)(MediaTrack* track, int fxidx, int parmidx, bool create);
static bool (*InsertEnvelopePoint)(TrackEnvelope* env, double time, double value, int shape, double tension, bool selected, bool* noSortIn);
static bool (*DeleteEnvelopePointRange)(TrackEnvelope* env, double time_start, double time_end);
static bool (*Envelope_SortPoints)(TrackEnvelope* env);

// Action command ID
static int g_commandId = 0;

// Global plugin handle
REAPER_PLUGIN_HINSTANCE g_hInst;
HWND g_hwndParent;

// Clamp helper to avoid SWELL macro conflicts
static inline double clamp01(double v) {
    if (v < 0.0) return 0.0;
    if (v > 1.0) return 1.0;
    return v;
}

//------------------------------------------------------------------------------
// Lua API Functions
//------------------------------------------------------------------------------

// Create a new modulator, returns ID
static int SideFX_Mod_Create(const char* name) {
    return sidefx::ModulatorManager::instance().createModulator(name ? name : "");
}

// Destroy a modulator
static void SideFX_Mod_Destroy(int id) {
    sidefx::ModulatorManager::instance().destroyModulator(id);
}

// Set Bezier curve from 8 doubles [x0,y0, x1,y1, x2,y2, x3,y3]
static bool SideFX_Mod_SetCurve(int id, double x0, double y0,
                                 double x1, double y1,
                                 double x2, double y2,
                                 double x3, double y3) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (!mod) return false;

    sidefx::CubicBezier bez(
        {x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}
    );
    mod->curve.setSingleSegment(bez);
    return true;
}

// Set curve to preset shape
static bool SideFX_Mod_SetPreset(int id, const char* preset) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (!mod || !preset) return false;

    sidefx::CubicBezier bez;
    if (strcmp(preset, "sine") == 0) {
        bez = sidefx::presets::sine();
    } else if (strcmp(preset, "triangle") == 0) {
        bez = sidefx::presets::triangle();
    } else if (strcmp(preset, "saw_up") == 0) {
        bez = sidefx::presets::sawUp();
    } else if (strcmp(preset, "saw_down") == 0) {
        bez = sidefx::presets::sawDown();
    } else if (strcmp(preset, "square") == 0) {
        bez = sidefx::presets::square();
    } else if (strcmp(preset, "ease") == 0) {
        bez = sidefx::presets::easeInOut();
    } else {
        return false;
    }

    mod->curve.setSingleSegment(bez);
    return true;
}

// Link modulator to FX parameter
static bool SideFX_Mod_Link(int id, MediaTrack* track, int fx_idx, int param_idx) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (!mod) return false;

    mod->target.track = track;
    mod->target.fx_index = fx_idx;
    mod->target.param_index = param_idx;
    return true;
}

// Unlink modulator
static void SideFX_Mod_Unlink(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->target = {};
    }
}

// Set rate in Hz
static void SideFX_Mod_SetRateHz(int id, double hz) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->rateMode = sidefx::RateMode::FreeHz;
        mod->rateHz = hz;
    }
}

// Set tempo-synced rate
static void SideFX_Mod_SetRateSync(int id, int division) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod && division >= 0 && division <= 13) {
        mod->rateMode = sidefx::RateMode::TempoSync;
        mod->syncDivision = static_cast<sidefx::SyncDivision>(division);
    }
}

// Set depth (0-1)
static void SideFX_Mod_SetDepth(int id, double depth) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->depth = clamp01(depth);
    }
}

// Set offset/center (0-1)
static void SideFX_Mod_SetOffset(int id, double offset) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->offset = clamp01(offset);
    }
}

// Set phase offset (0-1)
static void SideFX_Mod_SetPhaseOffset(int id, double phase) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->phaseOffset = phase - std::floor(phase);
        mod->reset();
    }
}

// Enable/disable modulator
static void SideFX_Mod_SetEnabled(int id, bool enabled) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->enabled.store(enabled);
        if (enabled) {
            mod->reset();
        }
    }
}

// Get current phase (0-1)
static double SideFX_Mod_GetPhase(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    return mod ? mod->phase.load() : 0.0;
}

// Get current output value (0-1)
static double SideFX_Mod_GetValue(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    return mod ? mod->getCurrentValue() : 0.0;
}

// Check if modulator is enabled
static bool SideFX_Mod_IsEnabled(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    return mod ? mod->enabled.load() : false;
}

// Set bipolar mode
static void SideFX_Mod_SetBipolar(int id, bool bipolar) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->bipolar = bipolar;
    }
}

//------------------------------------------------------------------------------
// Trigger Settings
//------------------------------------------------------------------------------

// Set trigger mode: 0=Free, 1=AudioLevel, 2=AudioTransient, 3=MidiNote, 4=Manual
static void SideFX_Mod_SetTriggerMode(int id, int mode) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod && mode >= 0 && mode <= 4) {
        mod->triggerMode = static_cast<sidefx::TriggerMode>(mode);
        mod->reset();
    }
}

// Set playback mode: 0=Loop (LFO), 1=OneShot (envelope)
static void SideFX_Mod_SetPlaybackMode(int id, int mode) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod && mode >= 0 && mode <= 1) {
        mod->playbackMode = static_cast<sidefx::PlaybackMode>(mode);
    }
}

// Set trigger source track (for audio triggers)
static void SideFX_Mod_SetTriggerTrack(int id, MediaTrack* track) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->triggerTrack = track;
    }
}

// Set audio trigger threshold (0-1)
static void SideFX_Mod_SetAudioThreshold(int id, double threshold) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->audioThreshold = clamp01(threshold);
    }
}

// Set retrigger delay in ms
static void SideFX_Mod_SetRetriggerDelay(int id, double delayMs) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->retriggerDelayMs = delayMs > 0 ? delayMs : 0;
    }
}

// Set MIDI channel (-1 = omni, 0-15 = specific)
static void SideFX_Mod_SetMidiChannel(int id, int channel) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod && channel >= -1 && channel <= 15) {
        mod->midiChannel = channel;
    }
}

// Set MIDI note filter (-1 = any, 0-127 = specific note)
static void SideFX_Mod_SetMidiNote(int id, int note) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod && note >= -1 && note <= 127) {
        mod->midiNote = note;
    }
}

// Set velocity to depth mapping
static void SideFX_Mod_SetVelocityToDepth(int id, bool enabled) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->velocityToDepth = enabled;
    }
}

// Manual trigger
static void SideFX_Mod_Trigger(int id, double velocity) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->trigger(velocity);
    }
}

// Check if modulator is currently playing
static bool SideFX_Mod_IsPlaying(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    return mod ? mod->playing.load() : false;
}

//------------------------------------------------------------------------------
// Recording & Automation
//------------------------------------------------------------------------------

// Start recording modulation values
static void SideFX_Mod_StartRecording(int id, double startTime, double endTime, double resolution) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->startRecording(startTime, endTime, resolution > 0 ? resolution : 0.01);
    }
}

// Stop recording
static void SideFX_Mod_StopRecording(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->stopRecording();
    }
}

// Check if recording
static bool SideFX_Mod_IsRecording(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    return mod ? mod->recording.load() : false;
}

// Print recorded modulation to track automation
static int SideFX_Mod_PrintToAutomation(int id, int shape) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (!mod || !mod->target.isValid()) return 0;

    if (!GetFXEnvelope || !InsertEnvelopePoint || !DeleteEnvelopePointRange || !Envelope_SortPoints) {
        return -1;  // API not available
    }

    // Get or create the envelope for the target parameter
    TrackEnvelope* env = GetFXEnvelope(mod->target.track, mod->target.fx_index, 
                                        mod->target.param_index, true);
    if (!env) return -2;

    // Get recorded points
    auto points = mod->getRecordedPoints();
    if (points.empty()) return 0;

    // Delete existing points in range
    double startTime = points.front().time;
    double endTime = points.back().time;
    DeleteEnvelopePointRange(env, startTime, endTime);

    // Insert new points
    bool noSort = true;
    for (const auto& pt : points) {
        InsertEnvelopePoint(env, pt.time, pt.value, shape, 0.0, false, &noSort);
    }

    // Sort after batch insert
    Envelope_SortPoints(env);

    return (int)points.size();
}

// Get number of recorded points
static int SideFX_Mod_GetRecordedPointCount(int id) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (!mod) return 0;
    auto points = mod->getRecordedPoints();
    return (int)points.size();
}

//------------------------------------------------------------------------------
// Test Action
//------------------------------------------------------------------------------

static bool onTestAction() {
    // Create a test modulator
    int id = sidefx::ModulatorManager::instance().createModulator("Test Modulator");
    
    char msg[512];
    snprintf(msg, sizeof(msg),
        "=== SideFX Modulation Engine v0.1.0 ===\n"
        "Extension loaded successfully!\n"
        "Created test modulator ID: %d\n"
        "Audio hook active: %s\n"
        "API functions: SideFX_Mod_Create, SetCurve, Link, etc.\n"
        "=====================================\n",
        id,
        sidefx::isAudioHookActive() ? "YES" : "NO"
    );
    
    // Try console first (more reliable)
    if (ShowConsoleMsg) {
        ShowConsoleMsg(msg);
    }
    
    // Also show message box
    if (ShowMessageBox) {
        ShowMessageBox(msg, "SideFX Modulation Engine", 0);
    }
    
    // Cleanup test modulator
    sidefx::ModulatorManager::instance().destroyModulator(id);
    
    return true;
}

// hookcommand2 is needed for custom_action (section-aware)
static bool hookCommandProc2(KbdSectionInfo* sec, int command, int val, int valhw, int relmode, HWND hwnd) {
    if (sec && sec->uniqueID == 0 && command == g_commandId) {
        onTestAction();
        return true;
    }
    return false;
}

//------------------------------------------------------------------------------
// Plugin Registration
//------------------------------------------------------------------------------

static void registerAPI() {
    plugin_register("API_SideFX_Mod_Create", (void*)&SideFX_Mod_Create);
    plugin_register("APIdef_SideFX_Mod_Create",
        (void*)"int\0const char*\0name\0"
        "Create a new SideFX modulator. Returns modulator ID.");

    plugin_register("API_SideFX_Mod_Destroy", (void*)&SideFX_Mod_Destroy);
    plugin_register("APIdef_SideFX_Mod_Destroy",
        (void*)"void\0int\0id\0"
        "Destroy a SideFX modulator.");

    plugin_register("API_SideFX_Mod_SetCurve", (void*)&SideFX_Mod_SetCurve);
    plugin_register("APIdef_SideFX_Mod_SetCurve",
        (void*)"bool\0int,double,double,double,double,double,double,double,double\0"
        "id,x0,y0,x1,y1,x2,y2,x3,y3\0"
        "Set Bezier curve control points (4 points: P0, P1, P2, P3).");

    plugin_register("API_SideFX_Mod_SetPreset", (void*)&SideFX_Mod_SetPreset);
    plugin_register("APIdef_SideFX_Mod_SetPreset",
        (void*)"bool\0int,const char*\0id,preset\0"
        "Set curve to preset: sine, triangle, saw_up, saw_down, square, ease.");

    plugin_register("API_SideFX_Mod_Link", (void*)&SideFX_Mod_Link);
    plugin_register("APIdef_SideFX_Mod_Link",
        (void*)"bool\0int,MediaTrack*,int,int\0id,track,fx_idx,param_idx\0"
        "Link modulator to an FX parameter.");

    plugin_register("API_SideFX_Mod_Unlink", (void*)&SideFX_Mod_Unlink);
    plugin_register("APIdef_SideFX_Mod_Unlink",
        (void*)"void\0int\0id\0"
        "Unlink modulator from target parameter.");

    plugin_register("API_SideFX_Mod_SetRateHz", (void*)&SideFX_Mod_SetRateHz);
    plugin_register("APIdef_SideFX_Mod_SetRateHz",
        (void*)"void\0int,double\0id,hz\0"
        "Set modulator rate in Hz (free-running).");

    plugin_register("API_SideFX_Mod_SetRateSync", (void*)&SideFX_Mod_SetRateSync);
    plugin_register("APIdef_SideFX_Mod_SetRateSync",
        (void*)"void\0int,int\0id,division\0"
        "Set tempo-synced rate. Division: 0=4bar, 1=2bar, 2=1bar, 3=1/2, 4=1/4, 5=1/8, 6=1/16, 7=1/32.");

    plugin_register("API_SideFX_Mod_SetDepth", (void*)&SideFX_Mod_SetDepth);
    plugin_register("APIdef_SideFX_Mod_SetDepth",
        (void*)"void\0int,double\0id,depth\0"
        "Set modulation depth (0-1).");

    plugin_register("API_SideFX_Mod_SetOffset", (void*)&SideFX_Mod_SetOffset);
    plugin_register("APIdef_SideFX_Mod_SetOffset",
        (void*)"void\0int,double\0id,offset\0"
        "Set modulation center/offset (0-1).");

    plugin_register("API_SideFX_Mod_SetPhaseOffset", (void*)&SideFX_Mod_SetPhaseOffset);
    plugin_register("APIdef_SideFX_Mod_SetPhaseOffset",
        (void*)"void\0int,double\0id,phase\0"
        "Set starting phase offset (0-1).");

    plugin_register("API_SideFX_Mod_SetEnabled", (void*)&SideFX_Mod_SetEnabled);
    plugin_register("APIdef_SideFX_Mod_SetEnabled",
        (void*)"void\0int,bool\0id,enabled\0"
        "Enable or disable modulator.");

    plugin_register("API_SideFX_Mod_GetPhase", (void*)&SideFX_Mod_GetPhase);
    plugin_register("APIdef_SideFX_Mod_GetPhase",
        (void*)"double\0int\0id\0"
        "Get current modulator phase (0-1).");

    plugin_register("API_SideFX_Mod_GetValue", (void*)&SideFX_Mod_GetValue);
    plugin_register("APIdef_SideFX_Mod_GetValue",
        (void*)"double\0int\0id\0"
        "Get current modulator output value (0-1).");

    plugin_register("API_SideFX_Mod_IsEnabled", (void*)&SideFX_Mod_IsEnabled);
    plugin_register("APIdef_SideFX_Mod_IsEnabled",
        (void*)"bool\0int\0id\0"
        "Check if modulator is enabled.");

    plugin_register("API_SideFX_Mod_SetBipolar", (void*)&SideFX_Mod_SetBipolar);
    plugin_register("APIdef_SideFX_Mod_SetBipolar",
        (void*)"void\0int,bool\0id,bipolar\0"
        "Set bipolar mode (true: modulates around offset, false: 0 to depth).");

    // Trigger mode
    plugin_register("API_SideFX_Mod_SetTriggerMode", (void*)&SideFX_Mod_SetTriggerMode);
    plugin_register("APIdef_SideFX_Mod_SetTriggerMode",
        (void*)"void\0int,int\0id,mode\0"
        "Set trigger mode: 0=Free, 1=AudioLevel, 2=AudioTransient, 3=MidiNote, 4=Manual.");

    plugin_register("API_SideFX_Mod_SetPlaybackMode", (void*)&SideFX_Mod_SetPlaybackMode);
    plugin_register("APIdef_SideFX_Mod_SetPlaybackMode",
        (void*)"void\0int,int\0id,mode\0"
        "Set playback mode: 0=Loop (LFO), 1=OneShot (envelope).");

    // Audio trigger settings
    plugin_register("API_SideFX_Mod_SetTriggerTrack", (void*)&SideFX_Mod_SetTriggerTrack);
    plugin_register("APIdef_SideFX_Mod_SetTriggerTrack",
        (void*)"void\0int,MediaTrack*\0id,track\0"
        "Set source track for audio triggers.");

    plugin_register("API_SideFX_Mod_SetAudioThreshold", (void*)&SideFX_Mod_SetAudioThreshold);
    plugin_register("APIdef_SideFX_Mod_SetAudioThreshold",
        (void*)"void\0int,double\0id,threshold\0"
        "Set audio trigger threshold (0-1).");

    plugin_register("API_SideFX_Mod_SetRetriggerDelay", (void*)&SideFX_Mod_SetRetriggerDelay);
    plugin_register("APIdef_SideFX_Mod_SetRetriggerDelay",
        (void*)"void\0int,double\0id,delay_ms\0"
        "Set minimum time between triggers in milliseconds.");

    // MIDI trigger settings
    plugin_register("API_SideFX_Mod_SetMidiChannel", (void*)&SideFX_Mod_SetMidiChannel);
    plugin_register("APIdef_SideFX_Mod_SetMidiChannel",
        (void*)"void\0int,int\0id,channel\0"
        "Set MIDI channel (-1=omni, 0-15=specific).");

    plugin_register("API_SideFX_Mod_SetMidiNote", (void*)&SideFX_Mod_SetMidiNote);
    plugin_register("APIdef_SideFX_Mod_SetMidiNote",
        (void*)"void\0int,int\0id,note\0"
        "Set MIDI note filter (-1=any, 0-127=specific).");

    plugin_register("API_SideFX_Mod_SetVelocityToDepth", (void*)&SideFX_Mod_SetVelocityToDepth);
    plugin_register("APIdef_SideFX_Mod_SetVelocityToDepth",
        (void*)"void\0int,bool\0id,enabled\0"
        "Enable velocity-to-depth mapping for MIDI triggers.");

    // Manual trigger
    plugin_register("API_SideFX_Mod_Trigger", (void*)&SideFX_Mod_Trigger);
    plugin_register("APIdef_SideFX_Mod_Trigger",
        (void*)"void\0int,double\0id,velocity\0"
        "Manually trigger the modulator (velocity 0-1).");

    plugin_register("API_SideFX_Mod_IsPlaying", (void*)&SideFX_Mod_IsPlaying);
    plugin_register("APIdef_SideFX_Mod_IsPlaying",
        (void*)"bool\0int\0id\0"
        "Check if modulator is currently playing.");

    // Recording & Automation
    plugin_register("API_SideFX_Mod_StartRecording", (void*)&SideFX_Mod_StartRecording);
    plugin_register("APIdef_SideFX_Mod_StartRecording",
        (void*)"void\0int,double,double,double\0id,start_time,end_time,resolution\0"
        "Start recording modulation values. Resolution in seconds (e.g. 0.01 = 10ms).");

    plugin_register("API_SideFX_Mod_StopRecording", (void*)&SideFX_Mod_StopRecording);
    plugin_register("APIdef_SideFX_Mod_StopRecording",
        (void*)"void\0int\0id\0"
        "Stop recording modulation values.");

    plugin_register("API_SideFX_Mod_IsRecording", (void*)&SideFX_Mod_IsRecording);
    plugin_register("APIdef_SideFX_Mod_IsRecording",
        (void*)"bool\0int\0id\0"
        "Check if modulator is currently recording.");

    plugin_register("API_SideFX_Mod_PrintToAutomation", (void*)&SideFX_Mod_PrintToAutomation);
    plugin_register("APIdef_SideFX_Mod_PrintToAutomation",
        (void*)"int\0int,int\0id,shape\0"
        "Print recorded modulation to track automation. Shape: 0=linear, 1=square, etc. Returns point count.");

    plugin_register("API_SideFX_Mod_GetRecordedPointCount", (void*)&SideFX_Mod_GetRecordedPointCount);
    plugin_register("APIdef_SideFX_Mod_GetRecordedPointCount",
        (void*)"int\0int\0id\0"
        "Get number of recorded automation points.");
}

//------------------------------------------------------------------------------
// Plugin Entry Point
//------------------------------------------------------------------------------

extern "C" {

REAPER_PLUGIN_DLL_EXPORT int REAPER_PLUGIN_ENTRYPOINT(
    REAPER_PLUGIN_HINSTANCE hInstance, reaper_plugin_info_t* rec)
{
    if (!rec) {
        // Cleanup on unload
        sidefx::cleanupAudioHook();
        return 0;
    }

    if (rec->caller_version != REAPER_PLUGIN_VERSION) {
        return 0;
    }

    g_hInst = hInstance;
    g_hwndParent = rec->hwnd_main;

    // Import REAPER API functions
    if (!rec->GetFunc) {
        return 0;
    }

    // Load required API functions
    *((void**)&plugin_register) = rec->GetFunc("plugin_register");
    *((void**)&Audio_RegHardwareHook) = rec->GetFunc("Audio_RegHardwareHook");
    *((void**)&TrackFX_SetParamNormalized) = rec->GetFunc("TrackFX_SetParamNormalized");
    *((void**)&GetPlayState) = rec->GetFunc("GetPlayState");
    *((void**)&GetPlayPosition) = rec->GetFunc("GetPlayPosition");
    *((void**)&TimeMap_GetDividedBpmAtTime) = rec->GetFunc("TimeMap_GetDividedBpmAtTime");
    *((void**)&ShowMessageBox) = rec->GetFunc("ShowMessageBox");
    *((void**)&ShowConsoleMsg) = rec->GetFunc("ShowConsoleMsg");
    *((void**)&Track_GetPeakInfo) = rec->GetFunc("Track_GetPeakInfo");
    *((void**)&MIDI_GetRecentInputEvents) = rec->GetFunc("MIDI_GetRecentInputEvents");
    
    // Envelope/Automation APIs
    *((void**)&GetFXEnvelope) = rec->GetFunc("GetFXEnvelope");
    *((void**)&InsertEnvelopePoint) = rec->GetFunc("InsertEnvelopePoint");
    *((void**)&DeleteEnvelopePointRange) = rec->GetFunc("DeleteEnvelopePointRange");
    *((void**)&Envelope_SortPoints) = rec->GetFunc("Envelope_SortPoints");

    if (!plugin_register) {
        return 0;
    }

    // Register test action
    static custom_action_register_t action = {
        0,          // section (main)
        "SIDEFX_TEST_MOD_ENGINE",  // idStr  
        "SideFX: Test Modulation Engine",  // name
        nullptr     // extra (not used)
    };
    g_commandId = plugin_register("custom_action", &action);
    if (g_commandId) {
        plugin_register("hookcommand2", (void*)hookCommandProc2);
    }

    // Register our API functions
    registerAPI();

    // Initialize audio hook for sample-accurate modulation
    sidefx::initAudioHook();

    return 1;  // Success
}

} // extern "C"

// Export audio hook registration function for audio_hook.cpp
void* getAudioRegHardwareHook() { return (void*)Audio_RegHardwareHook; }
void* getTrackFXSetParamNormalized() { return (void*)TrackFX_SetParamNormalized; }
void* getGetPlayState() { return (void*)GetPlayState; }
void* getGetPlayPosition() { return (void*)GetPlayPosition; }
void* getTimeMapGetDividedBpmAtTime() { return (void*)TimeMap_GetDividedBpmAtTime; }
void* getTrackGetPeakInfo() { return (void*)Track_GetPeakInfo; }
void* getMidiGetRecentInputEvents() { return (void*)MIDI_GetRecentInputEvents; }
