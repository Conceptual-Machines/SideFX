-- Parameter Index Resolver for SideFX_Modulator
-- Dynamically finds parameter indices by name (handles REAPER's implicit params)

local M = {}

local r = reaper

-- Cache of parameter indices per FX (keyed by FX GUID)
local param_cache = {}

-- Parameter names we need to find
local PARAM_NAMES = {
    "Tempo Mode",      -- Free/Sync
    "Rate (Hz)",       -- Rate in free mode
    "Sync Rate",       -- Rate in sync mode
    "Output",          -- LFO output
    "Phase",           -- Phase offset
    "Depth",           -- Modulation depth
    "Trigger Mode",    -- Free/Transport/MIDI/Audio
    "MIDI Source",     -- This Track/MIDI Bus
    "MIDI Note (0=any)",
    "Audio Threshold",
    "Attack (ms)",
    "Release (ms)",
    "LFO Mode",        -- Loop/One Shot
    "Curve Shape",     -- Global curve shape
    "Grid",
    "Snap",
    "Num Points",
    "Playhead Position",
    "Offset",
    "Bipolar Mode",
}

-- Build index map for an FX
local function build_param_map(track_ptr, fx_ptr)
    local map = {}
    local num_params = r.TrackFX_GetNumParams(track_ptr, fx_ptr)
    
    for i = 0, num_params - 1 do
        local _, name = r.TrackFX_GetParamName(track_ptr, fx_ptr, i)
        if name then
            map[name] = i
        end
    end
    
    return map
end

-- Get parameter index by name for a modulator FX
-- Returns the index or nil if not found
function M.get_index(track, modulator, param_name)
    local track_ptr = track.pointer or track
    local mod_ptr = modulator.pointer or modulator
    local mod_guid = type(modulator) == "table" and modulator.get_guid and modulator:get_guid() or tostring(mod_ptr)
    
    -- Check cache
    if not param_cache[mod_guid] then
        param_cache[mod_guid] = build_param_map(track_ptr, mod_ptr)
    end
    
    return param_cache[mod_guid][param_name]
end

-- Get multiple parameter indices at once
-- Returns a table of name -> index mappings
function M.get_indices(track, modulator, param_names)
    local result = {}
    for _, name in ipairs(param_names) do
        result[name] = M.get_index(track, modulator, name)
    end
    return result
end

-- Invalidate cache for a specific FX (call when FX is modified/reloaded)
function M.invalidate(modulator)
    local mod_guid = type(modulator) == "table" and modulator.get_guid and modulator:get_guid() or tostring(modulator)
    param_cache[mod_guid] = nil
end

-- Clear entire cache
function M.clear_cache()
    param_cache = {}
end

-- Convenience: Get common modulator params all at once
function M.get_modulator_params(track, modulator)
    local track_ptr = track.pointer or track
    local mod_ptr = modulator.pointer or modulator
    local mod_guid = type(modulator) == "table" and modulator.get_guid and modulator:get_guid() or tostring(mod_ptr)
    
    -- Build cache if needed
    if not param_cache[mod_guid] then
        param_cache[mod_guid] = build_param_map(track_ptr, mod_ptr)
    end
    
    local map = param_cache[mod_guid]
    
    -- Return a structured object with all indices
    return {
        tempo_mode = map["Tempo Mode"],
        rate_hz = map["Rate (Hz)"],
        sync_rate = map["Sync Rate"],
        output = map["Output"],
        phase = map["Phase"],
        depth = map["Depth"],
        trigger_mode = map["Trigger Mode"],
        midi_source = map["MIDI Source"],
        midi_note = map["MIDI Note (0=any)"],
        audio_threshold = map["Audio Threshold"],
        attack = map["Attack (ms)"],
        release = map["Release (ms)"],
        lfo_mode = map["LFO Mode"],
        curve_shape = map["Curve Shape"],
        grid = map["Grid"],
        snap = map["Snap"],
        num_points = map["Num Points"],
        playhead = map["Playhead Position"],
        offset = map["Offset"],
        bipolar = map["Bipolar Mode"],
    }
end

return M
