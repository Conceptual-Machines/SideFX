--- SideFX Container Operations.
-- High-level container operations that use the state singleton.
-- Low-level container methods are provided by ReaWrap's TrackFX class.
-- @module container
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

-- Lazy load state module to avoid circular dependency
local _state_module = nil
local function get_state()
    if not _state_module then
        _state_module = require('lib.core.state')
    end
    return _state_module.state
end

--------------------------------------------------------------------------------
-- Container Operations
--------------------------------------------------------------------------------

--- Add FX to a new container.
-- @param fx_list table Array of FX objects to add
-- @return TrackFX|nil New container or nil
function M.add_to_new_container(fx_list)
    local state = get_state()
    if #fx_list == 0 then return end
    if not state.track then return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local container = state.track:add_fx_to_new_container(fx_list)

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add to Container", -1)

    return container
end

--------------------------------------------------------------------------------
-- Device Utilities
--------------------------------------------------------------------------------

--- Convert a chain (C-container) to devices by extracting all devices to track level.
-- The chain container is deleted after extraction. If the parent rack becomes empty
-- (only mixer remaining), the rack is also deleted.
-- @param chain TrackFX Chain container to convert
-- @return table Array of extracted device containers
function M.convert_chain_to_devices(chain)
    local state = get_state()
    local naming = require('lib.utils.naming')
    local fx_utils = require('lib.fx.fx_utils')

    if not chain or not chain:is_container() then return {} end
    if not state.track then return {} end

    -- Check if this is a C-container (chain container)
    local ok_name, name = pcall(function() return chain:get_name() end)
    if not ok_name or not name or not name:match("^R%d+_C%d+") then
        return {}  -- Not a C-container
    end

    local chain_guid = chain:get_guid()

    -- Get parent rack info before we start modifying
    local parent_rack = chain:get_parent_container()
    local rack_guid = parent_rack and parent_rack:get_guid() or nil

    -- Collect all children GUIDs before we start moving them
    local child_guids = {}
    for child in chain:iter_container_children() do
        local ok, guid = pcall(function() return child:get_guid() end)
        if ok and guid then
            child_guids[#child_guids + 1] = guid
        end
    end

    if #child_guids == 0 then
        -- Empty chain, just delete it
        chain:delete()
        return {}
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Move all children to track level (not just out of chain)
    local extracted = {}
    local fx_count = r.TrackFX_GetCount(state.track.pointer)

    for _, child_guid in ipairs(child_guids) do
        local child = state.track:find_fx_by_guid(child_guid)
        if child then
            -- Move directly to track level
            r.TrackFX_CopyToTrack(
                state.track.pointer,
                child.pointer,
                state.track.pointer,
                fx_count,  -- Add at end of track FX chain
                true  -- move (not copy)
            )
            fx_count = fx_count + 1

            -- Re-find child after move and rename to D-container format
            child = state.track:find_fx_by_guid(child_guid)
            if child then
                -- Get next available device index
                local next_idx = fx_utils.get_next_device_index(state.track)
                local child_name = child:get_name() or "Device"
                -- Extract short name from chain device name (R1_C1_D1: Name -> Name)
                local short_name = child_name:match("R%d+_C%d+_D%d+:%s*(.+)") or
                                   child_name:match("D%d+:%s*(.+)") or
                                   child_name
                local new_name = naming.build_device_name(next_idx, short_name)
                child:set_named_config_param("renamed_name", new_name)

                extracted[#extracted + 1] = child
            end
        end
    end

    -- Re-find and delete the now-empty chain
    chain = state.track:find_fx_by_guid(chain_guid)
    if chain then
        chain:delete()
    end

    -- Check if rack should be deleted (only mixer remaining)
    if rack_guid then
        local rack = state.track:find_fx_by_guid(rack_guid)
        if rack then
            local remaining_children = 0
            local only_mixer = true
            for child in rack:iter_container_children() do
                remaining_children = remaining_children + 1
                local child_name = child:get_name() or ""
                if not child_name:match("^_R%d+_M") then
                    only_mixer = false
                end
            end
            -- Delete rack if only mixer remains (or empty)
            if remaining_children <= 1 and only_mixer then
                rack:delete()
            end
        end
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Convert Chain to Devices", -1)

    return extracted
end

--- Convert a device (D-container) to a rack by wrapping it in a new rack.
-- @param device TrackFX Device container to convert
-- @return TrackFX|nil New rack container, or nil on failure
function M.convert_device_to_rack(device)
    local state = get_state()
    local fx_utils = require('lib.fx.fx_utils')
    local rack_module = require('lib.rack.rack')
    local naming = require('lib.utils.naming')
    local state_module = require('lib.core.state')

    if not device or not device:is_container() then return nil end
    if not state.track then return nil end

    -- Check if this is a D-container (device container)
    local ok_name, device_name = pcall(function() return device:get_name() end)
    if not ok_name or not device_name or not device_name:match("^D%d+") then
        return nil  -- Not a D-container
    end

    local device_guid = device:get_guid()

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get device position for placing the rack
    local device_idx = device.pointer
    local rack_position = device_idx >= 0 and device_idx or nil

    -- Create a new rack at the device's position
    local rack = rack_module.add_rack_to_track(rack_position)
    if not rack then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Convert Device to Rack (failed)", -1)
        return nil
    end

    local rack_guid = rack:get_guid()
    local rack_name = rack:get_name()
    local rack_idx = naming.parse_rack_index(rack_name) or 1

    -- Re-find device (may have moved due to rack insertion)
    device = state.track:find_fx_by_guid(device_guid)
    if not device then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Convert Device to Rack (device lost)", -1)
        return nil
    end

    -- Add an empty chain to the rack
    rack = state.track:find_fx_by_guid(rack_guid)
    local chain = rack_module.add_empty_chain_to_rack(rack)
    if not chain then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Convert Device to Rack (chain failed)", -1)
        return nil
    end

    local chain_guid = chain:get_guid()

    -- Re-find device and chain
    device = state.track:find_fx_by_guid(device_guid)
    chain = state.track:find_fx_by_guid(chain_guid)
    rack = state.track:find_fx_by_guid(rack_guid)

    if not device or not chain then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Convert Device to Rack (lost FX)", -1)
        return nil
    end

    -- Refresh pointer for deeply nested chains
    if chain.pointer and chain.pointer >= 0x2000000 and chain.refresh_pointer then
        chain:refresh_pointer()
    end

    -- Move device into the chain
    local success = chain:add_fx_to_container(device, 0)
    if not success then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Convert Device to Rack (move failed)", -1)
        return nil
    end

    -- Rename the device to match chain naming convention
    device = state.track:find_fx_by_guid(device_guid)
    if device then
        -- Parse device short name from D-container name (e.g., "D1: ProQ 3" -> "ProQ 3")
        local short_name = device_name:match("^D%d+:%s*(.+)$") or device_name:match("^D%d+:%s*(.+)_FX$") or "Device"
        local new_device_name = naming.build_chain_device_name(rack_idx, 1, 1, short_name)
        device:set_named_config_param("renamed_name", new_device_name)

        -- Also rename the FX inside the device
        local main_fx = fx_utils.get_device_main_fx(device)
        if main_fx then
            local fx_rename = naming.build_chain_device_fx_name(rack_idx, 1, 1, short_name)
            main_fx:set_named_config_param("renamed_name", fx_rename)
        end

        -- Rename utility
        local utility = fx_utils.get_device_utility(device)
        if utility then
            local util_rename = naming.build_chain_device_util_name(rack_idx, 1, 1)
            utility:set_named_config_param("renamed_name", util_rename)
        end
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Convert Device to Rack", -1)

    -- Mark track as SideFX track
    if state.track then
        state_module.mark_track_as_sidefx(state.track)
    end

    -- Expand the rack and chain by default so user sees the device
    state.expanded_racks = state.expanded_racks or {}
    state.expanded_racks[rack_guid] = true
    state.expanded_nested_chains = state.expanded_nested_chains or {}
    state.expanded_nested_chains[rack_guid] = chain_guid

    return state.track:find_fx_by_guid(rack_guid)
end

return M
