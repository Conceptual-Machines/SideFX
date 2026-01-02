// SideFX Modulation Engine - REAPER Extension
// Sample-accurate modulation with Bezier curve LFOs

#include "reaper_plugin.h"
#include "modulator.h"
#include "audio_hook.h"

#include <cstring>
#include <string>

// REAPER API function pointers we need
static int (*plugin_register)(const char* name, void* infostruct);
static void (*Audio_RegHookAdd)(audio_hook_register_t* hook);
static void (*Audio_RegHookRemove)(audio_hook_register_t* hook);
static bool (*TrackFX_SetParamNormalized)(MediaTrack* track, int fx, int param, double value);
static int (*GetPlayState)();
static double (*GetPlayPosition)();
static double (*TimeMap_GetDividedBpmAtTime)(double time);

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
        mod->resetPhase();
    }
}

// Enable/disable modulator
static void SideFX_Mod_SetEnabled(int id, bool enabled) {
    auto* mod = sidefx::ModulatorManager::instance().getModulator(id);
    if (mod) {
        mod->enabled.store(enabled);
        if (enabled) {
            mod->resetPhase();
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
    *((void**)&Audio_RegHookAdd) = rec->GetFunc("Audio_RegHookAdd");
    *((void**)&Audio_RegHookRemove) = rec->GetFunc("Audio_RegHookRemove");
    *((void**)&TrackFX_SetParamNormalized) = rec->GetFunc("TrackFX_SetParamNormalized");
    *((void**)&GetPlayState) = rec->GetFunc("GetPlayState");
    *((void**)&GetPlayPosition) = rec->GetFunc("GetPlayPosition");
    *((void**)&TimeMap_GetDividedBpmAtTime) = rec->GetFunc("TimeMap_GetDividedBpmAtTime");

    if (!plugin_register) {
        return 0;
    }

    // Register our API functions
    registerAPI();

    // Initialize audio hook for sample-accurate modulation
    sidefx::initAudioHook();

    return 1;  // Success
}

} // extern "C"

// Export audio hook registration functions for audio_hook.cpp
void* getAudioRegHookAdd() { return (void*)Audio_RegHookAdd; }
void* getAudioRegHookRemove() { return (void*)Audio_RegHookRemove; }
void* getTrackFXSetParamNormalized() { return (void*)TrackFX_SetParamNormalized; }
void* getGetPlayState() { return (void*)GetPlayState; }
void* getGetPlayPosition() { return (void*)GetPlayPosition; }
void* getTimeMapGetDividedBpmAtTime() { return (void*)TimeMap_GetDividedBpmAtTime; }
