--- SideFX Presets.
-- Chain preset save/load operations.
-- @module presets
-- @author Nomad Monad
-- @license MIT

local r = reaper
local state_mod = require('lib.state')

local M = {}

-- Presets folder path (must be set via init before use)
local presets_folder = nil

--- Initialize the presets module with the script path.
-- @param script_path string Path to the SideFX script folder
function M.init(script_path)
    presets_folder = script_path .. "presets/"
end

--- Ensure the presets folder structure exists.
function M.ensure_folder()
    if not presets_folder then return end
    r.RecursiveCreateDirectory(presets_folder, 0)
    r.RecursiveCreateDirectory(presets_folder .. "chains/", 0)
end

--- Save the current track's FX chain as a preset.
-- @param preset_name string Name for the preset
-- @return boolean Success
function M.save_chain(preset_name)
    local state = state_mod.state
    if not state.track or not preset_name or preset_name == "" then return false end
    if not presets_folder then return false end
    
    M.ensure_folder()
    
    -- Use REAPER's native FX chain preset system
    local path = presets_folder .. "chains/" .. preset_name .. ".RfxChain"
    r.TrackFX_SavePresetBank(state.track.pointer, path)
    return true
end

--- Load a chain preset onto the current track.
-- @param preset_name string Name of the preset to load
-- @return boolean Success
function M.load_chain(preset_name)
    local state = state_mod.state
    if not state.track or not preset_name then return false end
    if not presets_folder then return false end
    
    local path = presets_folder .. "chains/" .. preset_name .. ".RfxChain"
    r.Undo_BeginBlock()
    -- Clear existing FX using ReaWrap
    while state.track:get_track_fx_count() > 0 do
        local fx = state.track:get_track_fx(0)
        fx:delete()
    end
    -- Load chain
    state.track:add_by_name(path, false, -1)
    r.Undo_EndBlock("Load FX Chain Preset", -1)
    state_mod.refresh_fx_list()
    return true
end

--- Get the presets folder path.
-- @return string|nil Presets folder path or nil if not initialized
function M.get_folder()
    return presets_folder
end

return M

