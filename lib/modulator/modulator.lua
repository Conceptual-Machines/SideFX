--- SideFX Modulator Operations.
-- Functions for managing SideFX_Modulator JSFX and parameter links.
-- @module modulator
-- @author Nomad Monad
-- @license MIT

local r = reaper

local state_module = require('lib.core.state')
local fx_utils = require('lib.fx.fx_utils')

local M = {}

-- Local reference to state singleton
local state = state_module.state

-- Optional refresh callback (set via init)
local refresh_callback = nil

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

--- Initialize modulator module with optional refresh callback
-- @param on_refresh function|nil Callback to refresh FX list: () -> nil
function M.init(on_refresh)
    refresh_callback = on_refresh
end

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

M.MODULATOR_JSFX = "JS:SideFX/Utils/SideFX_Modulator"
M.MODULATOR_DISPLAY_PATTERN = "SideFX[_ ]Modulator"  -- Pattern for matching display name
M.MOD_OUTPUT_PARAM = 3  -- slider4 in JSFX (0-indexed)

--------------------------------------------------------------------------------
-- Modulator Discovery
--------------------------------------------------------------------------------

--- Find all modulators on the current track.
-- @return table Array of {fx, fx_idx, name}
function M.find_modulators_on_track()
    if not state.track then return {} end
    local modulators = {}
    -- Search all FX including nested ones
    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local name = fx:get_name()
        if name and name:match(M.MODULATOR_DISPLAY_PATTERN) then
            table.insert(modulators, {
                fx = fx,
                fx_idx = fx.pointer,
                name = "LFO " .. (#modulators + 1),
            })
        end
    end
    return modulators
end

--- Add a new modulator to the track.
-- @return TrackFX|nil The new modulator FX
function M.add_modulator()
    if not state.track then return end
    r.Undo_BeginBlock()
    -- Add at position 0 (before instruments)
    local fx = state.track:add_fx_by_name(M.MODULATOR_JSFX, false, -1000)
    -- Select first preset (Sine) by default
    if fx and fx.pointer >= 0 then
        r.TrackFX_SetPresetByIndex(state.track.pointer, fx.pointer, 0)
    end
    r.Undo_EndBlock("Add SideFX Modulator", -1)
    if fx and refresh_callback then
        refresh_callback()
    end
    return fx
end

--- Delete a modulator by FX index.
-- @param fx_idx number FX index
function M.delete_modulator(fx_idx)
    if not state.track then return end
    r.Undo_BeginBlock()
    r.TrackFX_Delete(state.track.pointer, fx_idx)
    r.Undo_EndBlock("Delete SideFX Modulator", -1)
    if refresh_callback then
        refresh_callback()
    end
end

--------------------------------------------------------------------------------
-- Linkable FX
--------------------------------------------------------------------------------

--- Get list of FX that can be modulated.
-- Excludes modulators, containers, and internal SideFX components.
-- @return table Array of {fx, fx_idx, name, params}
function M.get_linkable_fx()
    if not state.track then return {} end
    local linkable = {}
    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local name = fx:get_name()
        -- Use fx_utils to properly detect internal components
        -- Filter out all containers (racks, chains, devices) and internal JSFX
        local is_container = fx:is_container()  -- Filters racks, chains, devices
        local is_internal_jsfx = fx_utils.is_mixer_fx(fx) or
                                fx_utils.is_utility_fx(fx) or
                                fx_utils.is_modulator_fx(fx)
        local is_internal = is_container or is_internal_jsfx

        if name and not is_internal then
            local params = {}
            local param_count = fx:get_num_params()
            for p = 0, param_count - 1 do
                local pname = fx:get_param_name(p)
                table.insert(params, {idx = p, name = pname})
            end
            -- Use custom display name if available, otherwise use FX name
            local guid = fx:get_guid()
            local custom_name = state.display_names[guid]
            local base_name = custom_name or name
            -- Add depth indicator to name for nested FX
            local display_name = fx_info.depth > 0 and string.rep("  ", fx_info.depth) .. "↳ " .. base_name or base_name
            table.insert(linkable, {fx = fx, fx_idx = fx.pointer, name = display_name, params = params})
        end
    end
    return linkable
end

--------------------------------------------------------------------------------
-- Parameter Links
--------------------------------------------------------------------------------

--- Create a parameter modulation link.
-- @param mod_fx TrackFX|number Modulator FX object or index (must be top-level)
-- @param target_fx TrackFX|number Target FX object or index
-- @param target_param_idx number Target parameter index
-- @return boolean Success
function M.create_param_link(mod_fx, target_fx, target_param_idx)
    if not state.track then return false end

    -- Get FX objects
    local mod_fx_obj = type(mod_fx) == "number" and state.track:get_track_fx(mod_fx) or mod_fx
    local target_fx_obj = type(target_fx) == "number" and state.track:get_track_fx(target_fx) or target_fx

    if not mod_fx_obj or not target_fx_obj then return false end

    -- Check if target FX is in a container
    local target_parent = target_fx_obj:get_parent_container()

    if target_parent then
        -- Target is nested - move modulator into the same container
        -- Store GUIDs before moving (indices will change!)
        local mod_guid = mod_fx_obj:get_guid()
        local target_guid = target_fx_obj:get_guid()

        -- Add modulator at END of container so it receives audio from main FX
        -- (Position 0 would put it BEFORE the audio source, breaking audio trigger)
        local insert_pos = target_parent:get_container_child_count()
        local success = target_parent:add_fx_to_container(mod_fx_obj, insert_pos)
        if not success then
            return false
        end

        -- Refresh FX list after moving
        if state_module.refresh_fx_list then
            state_module.refresh_fx_list()
        end

        -- Re-find both FX by GUID to get their new indices
        mod_fx_obj = state.track:find_fx_by_guid(mod_guid)
        if not mod_fx_obj then
            return false
        end

        target_fx_obj = state.track:find_fx_by_guid(target_guid)
        if not target_fx_obj then
            return false
        end
    end

    -- Get the (possibly new) indices after moving
    local mod_fx_idx = mod_fx_obj.pointer
    local target_fx_idx = target_fx_obj.pointer

    -- Determine the plink effect index to use
    -- If both FX are in the same container, use LOCAL index (position within container)
    -- Otherwise, use the global encoded index
    local plink_effect_idx = mod_fx_idx

    if target_parent then
        -- Both FX are now in the same container - find modulator's LOCAL position
        local children = target_parent:get_container_children()
        local mod_guid = mod_fx_obj:get_guid()

        for i, child in ipairs(children) do
            if child:get_guid() == mod_guid then
                plink_effect_idx = i - 1  -- Convert to 0-based index
                break
            end
        end
    end

    -- Get current parameter value to use as baseline offset
    local current_value = r.TrackFX_GetParamNormalized(state.track.pointer, target_fx_idx, target_param_idx)

    local plink_prefix = string.format("param.%d.plink.", target_param_idx)

    -- Create the parameter link with proper scale/offset to preserve current value
    local ok1 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "active", "1")
    local ok2 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "effect", tostring(plink_effect_idx))
    local ok3 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "param", tostring(M.MOD_OUTPUT_PARAM))
    -- Set offset to current value so parameter doesn't jump
    local ok4 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "offset", tostring(current_value))
    -- Set scale to 0 initially - user increases via Depth control
    local ok5 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "scale", "0")

    return ok1 and ok2 and ok3 and ok4 and ok5
end

--- Remove a parameter modulation link.
-- @param target_fx TrackFX|number Target FX object or index
-- @param target_param_idx number Target parameter index
function M.remove_param_link(target_fx, target_param_idx)
    if not state.track then return end

    local target_fx_idx = type(target_fx) == "number" and target_fx or target_fx.pointer

    local plink_prefix = string.format("param.%d.plink.", target_param_idx)
    r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "active", "0")
end

--- Get all parameters linked to a modulator.
-- @param mod_fx TrackFX|number Modulator FX object or index
-- @return table Array of link info
function M.get_modulator_links(mod_fx)
    if not state.track then return {} end
    local links = {}
    local mod_fx_idx = type(mod_fx) == "number" and mod_fx or mod_fx.pointer

    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local fx_name = fx:get_name()
        local fx_idx = fx.pointer
        -- Skip modulators and containers
        if fx_name and not (fx_name:match(M.MODULATOR_DISPLAY_PATTERN) or fx_name:find("Container")) then
            local param_count = fx:get_num_params()
            for param_idx = 0, param_count - 1 do
                local plink_prefix = string.format("param.%d.plink.", param_idx)
                -- Use raw REAPER API
                local rv, active = r.TrackFX_GetNamedConfigParm(state.track.pointer, fx_idx, plink_prefix .. "active")
                if rv and active == "1" then
                    local _, effect = r.TrackFX_GetNamedConfigParm(state.track.pointer, fx_idx, plink_prefix .. "effect")
                    local _, param = r.TrackFX_GetNamedConfigParm(state.track.pointer, fx_idx, plink_prefix .. "param")
                    if tonumber(effect) == mod_fx_idx and tonumber(param) == M.MOD_OUTPUT_PARAM then
                        local param_name = fx:get_param_name(param_idx)
                        table.insert(links, {
                            target_fx = fx,
                            target_fx_idx = fx_idx,  -- Keep for UI compatibility
                            target_fx_name = fx_name,
                            target_param_idx = param_idx,
                            target_param_name = param_name,
                        })
                    end
                end
            end
        end
    end
    return links
end

--- Check if an FX is a modulator.
-- @param fx TrackFX FX object
-- @return boolean
function M.is_modulator_fx(fx)
    if not fx then return false end
    local name = fx:get_name()
    return name and name:match(M.MODULATOR_DISPLAY_PATTERN)
end

--------------------------------------------------------------------------------
-- Device Modulator Operations
--------------------------------------------------------------------------------

--- Add a modulator inside a device container.
-- Uses GUID-based refinding for robustness with nested containers.
-- @param device_container TrackFX Device container
-- @param modulator_type table Modulator type {id, name, jsfx}
-- @param track TrackFX|nil Track (optional, uses state.track if nil)
-- @return TrackFX|nil Created modulator FX or nil on failure
function M.add_modulator_to_device(device_container, modulator_type, track)
    track = track or state.track
    if not track or not device_container then return nil end
    if not device_container:is_container() then return nil end

    local naming = require('lib.utils.naming')
    local fx_utils = require('lib.fx.fx_utils')

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get container GUID before operations (GUID is stable)
    local container_guid = device_container:get_guid()
    if not container_guid then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (failed)", -1)
        return nil
    end

    -- Add modulator JSFX at track level first
    local modulator = track:add_fx_by_name(modulator_type.jsfx, false, -1)
    if not modulator or modulator.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (failed)", -1)
        return nil
    end

    local mod_guid = modulator:get_guid()

    -- Refind container by GUID (important for nested containers)
    local fresh_container = track:find_fx_by_guid(container_guid)
    if not fresh_container then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (container lost)", -1)
        return nil
    end

    -- Refresh pointer for deeply nested containers
    if fresh_container.pointer and fresh_container.pointer >= 0x2000000 and fresh_container.refresh_pointer then
        fresh_container:refresh_pointer()
    end

    -- Refind modulator by GUID
    modulator = track:find_fx_by_guid(mod_guid)
    if not modulator then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (modulator lost)", -1)
        return nil
    end

    -- Get insert position (append to end of container)
    local insert_pos = fresh_container:get_container_child_count()

    -- Move modulator into container
    local success = fresh_container:add_fx_to_container(modulator, insert_pos)

    if not success then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (move failed)", -1)
        return nil
    end

    -- Refind BOTH modulator and container after move (pointers changed)
    local moved_modulator = track:find_fx_by_guid(mod_guid)
    local final_container = track:find_fx_by_guid(container_guid)

    if moved_modulator and final_container then
        -- Name the modulator with hierarchical convention
        local ok_name, container_name = pcall(function() return final_container:get_name() end)
        if ok_name and container_name then
            local device_path_str = naming.extract_path_from_name(container_name)
            if device_path_str then
                -- Count existing modulators in this device to get next index
                local modulator_count = 0
                local ok_iter, iter = pcall(function() return final_container:iter_container_children() end)
                if ok_iter and iter then
                    for child in iter do
                        if fx_utils.is_modulator_fx(child) then
                            modulator_count = modulator_count + 1
                        end
                    end
                end

                -- Build modulator name using general hierarchical function
                local mod_name = naming.build_hierarchical_name(device_path_str, "modulator", modulator_count, "SideFX Modulator")
                pcall(function() moved_modulator:set_named_config_param("renamed_name", mod_name) end)
            end
        end

        -- Initialize default parameter values
        -- Set LFO Mode to Loop (0) by default
        local PARAM = require('lib.modulator.modulator_constants')
        pcall(function() moved_modulator:set_param(PARAM.PARAM_LFO_MODE, 0) end)

        -- Select first preset (Sine) by default
        if moved_modulator.pointer >= 0 then
            r.TrackFX_SetPresetByIndex(track.pointer, moved_modulator.pointer, 0)
        end
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Modulator to Device", -1)

    if refresh_callback then
        refresh_callback()
    end

    return moved_modulator
end

return M
