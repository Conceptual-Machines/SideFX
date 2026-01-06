--- SideFX Modulator Operations.
-- Functions for managing SideFX_Modulator JSFX and parameter links.
-- @module modulator
-- @author Nomad Monad
-- @license MIT

local r = reaper

local state_module = require('lib.state')
local fx_utils = require('lib.fx_utils')

local M = {}

-- Local reference to state singleton
local state = state_module.state

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

M.MODULATOR_JSFX = "JS:SideFX/SideFX_Modulator"
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
        if name and (name:find(M.MODULATOR_JSFX) or name:find("SideFX Modulator")) then
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
    r.Undo_EndBlock("Add SideFX Modulator", -1)
    return fx
end

--- Delete a modulator by FX index.
-- @param fx_idx number FX index
function M.delete_modulator(fx_idx)
    if not state.track then return end
    r.Undo_BeginBlock()
    r.TrackFX_Delete(state.track.pointer, fx_idx)
    r.Undo_EndBlock("Delete SideFX Modulator", -1)
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

    -- Debug: show which FX we're linking
    local param_name = target_fx_obj:get_param_name(target_param_idx) or "unknown"
    r.ShowConsoleMsg(string.format("Target FX: %s, param idx: %d (%s)\n",
        target_fx_obj:get_name() or "unknown", target_param_idx, param_name))

    -- Check if target FX is in a container
    local target_parent = target_fx_obj:get_parent_container()

    if target_parent then
        -- Target is nested - move modulator into the same container
        r.ShowConsoleMsg(string.format("Moving modulator into container with target FX\n"))

        -- Store GUIDs before moving (indices will change!)
        local mod_guid = mod_fx_obj:get_guid()
        local target_guid = target_fx_obj:get_guid()

        local success = target_parent:add_fx_to_container(mod_fx_obj)
        if not success then
            r.ShowConsoleMsg("Failed to move modulator into container\n")
            return false
        end

        -- Refresh FX list after moving
        if state_module.refresh_fx_list then
            state_module.refresh_fx_list()
        end

        -- Re-find both FX by GUID to get their new indices
        mod_fx_obj = state.track:find_fx_by_guid(mod_guid)
        if not mod_fx_obj then
            r.ShowConsoleMsg("Failed to find modulator after moving\n")
            return false
        end

        target_fx_obj = state.track:find_fx_by_guid(target_guid)
        if not target_fx_obj then
            r.ShowConsoleMsg("Failed to find target FX after moving\n")
            return false
        end

        r.ShowConsoleMsg(string.format("Modulator moved - new index: %d\n", mod_fx_obj.pointer))
        r.ShowConsoleMsg(string.format("Target FX after move - new index: %d\n", target_fx_obj.pointer))
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
                r.ShowConsoleMsg(string.format("Using LOCAL index %d for modulator in container\n", plink_effect_idx))
                break
            end
        end
    end

    r.ShowConsoleMsg(string.format("Creating plink: mod_idx=%d (plink_effect=%d), target_idx=%d, param=%d\n",
        mod_fx_idx, plink_effect_idx, target_fx_idx, target_param_idx))

    local plink_prefix = string.format("param.%d.plink.", target_param_idx)

    -- Create the parameter link
    local ok1 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "active", "1")
    local ok2 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "effect", tostring(plink_effect_idx))
    local ok3 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "param", tostring(M.MOD_OUTPUT_PARAM))

    r.ShowConsoleMsg(string.format("Plink result: ok1=%s ok2=%s ok3=%s\n",
        tostring(ok1), tostring(ok2), tostring(ok3)))

    -- Verify what was actually created by reading back the plink
    if ok1 and ok2 and ok3 then
        local _, actual_effect = r.TrackFX_GetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "effect")
        local _, actual_param = r.TrackFX_GetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "param")
        r.ShowConsoleMsg(string.format("Plink verification: effect=%s, param=%s (expected effect=%d, param=%d)\n",
            actual_effect or "nil", actual_param or "nil", plink_effect_idx, M.MOD_OUTPUT_PARAM))

        -- Also verify the target FX and parameter after moving
        local final_target_fx = state.track:get_track_fx(target_fx_idx)
        if final_target_fx then
            local final_param_name = final_target_fx:get_param_name(target_param_idx)
            r.ShowConsoleMsg(string.format("Final target verification: FX=%s, param=%d (%s)\n",
                final_target_fx:get_name(), target_param_idx, final_param_name))
        end
    end

    return ok1 and ok2 and ok3
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
        if fx_name and not (fx_name:find(M.MODULATOR_JSFX) or fx_name:find("SideFX Modulator") or fx_name:find("Container")) then
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
    return name and (name:find(M.MODULATOR_JSFX) or name:find("SideFX Modulator"))
end

return M
