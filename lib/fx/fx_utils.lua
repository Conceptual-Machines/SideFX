--- SideFX FX Utilities.
-- Functions for working with ReaWrap FX objects.
-- @module fx_utils
-- @author Nomad Monad
-- @license MIT

local r = reaper
local naming = require('lib.utils.naming')

local M = {}

--------------------------------------------------------------------------------
-- FX Type Detection (using ReaWrap FX objects)
--------------------------------------------------------------------------------

--- Check if an FX is a utility.
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_utility_fx(fx)
    if not fx then return false end
    local ok, name = pcall(function() return fx:get_name() end)
    if not ok or not name then return false end
    return naming.is_utility_name(name)
end

--- Check if an FX is a modulator.
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_modulator_fx(fx)
    if not fx then return false end
    local ok, name = pcall(function() return fx:get_name() end)
    if not ok or not name then return false end
    return naming.is_modulator_name(name)
end

--- Check if an FX is a device container (D-prefix).
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_device_container(fx)
    if not fx then return false end
    local ok, is_cont = pcall(function() return fx:is_container() end)
    if not ok or not is_cont then return false end

    local ok2, name = pcall(function() return fx:get_name() end)
    if not ok2 or not name then return false end

    return naming.is_device_name(name)
end

--- Check if an FX is a chain container (R{n}_C{n} pattern).
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_chain_container(fx)
    if not fx then return false end
    local ok, is_cont = pcall(function() return fx:is_container() end)
    if not ok or not is_cont then return false end

    local ok2, name = pcall(function() return fx:get_name() end)
    if not ok2 or not name then return false end

    return naming.is_chain_name(name)
end

--- Check if an FX is a rack container (R-prefix, not a chain).
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_rack_container(fx)
    if not fx then return false end
    local ok, is_cont = pcall(function() return fx:is_container() end)
    if not ok or not is_cont then return false end

    local ok2, name = pcall(function() return fx:get_name() end)
    if not ok2 or not name then return false end

    return naming.is_rack_name(name)
end

--- Check if an FX is an internal mixer.
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_mixer_fx(fx)
    if not fx then return false end
    local ok, name = pcall(function() return fx:get_name() end)
    if not ok or not name then return false end
    return naming.is_mixer_name(name)
end

--------------------------------------------------------------------------------
-- Display Name Helpers
--------------------------------------------------------------------------------

--- Get display name for FX (checks custom display name first, then strips prefixes).
-- @param fx TrackFX ReaWrap FX object
-- @return string Clean display name
function M.get_display_name(fx)
    if not fx then return "Unknown" end

    -- Get GUID to check for custom display name
    local ok_guid, guid = pcall(function() return fx:get_guid() end)
    if ok_guid and guid then
        -- Lazy load state module to avoid circular dependency
        local state_module = require('lib.core.state')
        local state = state_module.state
        if state.display_names[guid] then
            return state.display_names[guid]
        end
    end

    -- Fall back to actual FX name (stripped of prefixes)
    local ok2, raw_name = pcall(function() return fx:get_name() end)
    local name = ok2 and raw_name or "Unknown"
    return naming.strip_sidefx_prefixes(name)
end

--- Get display name for chain (shows custom name + [R1_C1] format).
-- @param chain TrackFX Chain container FX object
-- @return string Display name with format: "Custom Name [R1_C1]" or just "R1_C1"
function M.get_chain_display_name(chain)
    if not chain then return "Unknown" end

    -- Get internal name to extract R1_C1 identifier
    local ok_name, raw_name = pcall(function() return chain:get_name() end)
    if not ok_name or not raw_name then return "Unknown" end

    -- Extract R1_C1 identifier (before colon if present)
    local chain_id = raw_name:match("^(R%d+_C%d+)")
    if not chain_id then
        -- Fallback: try to extract from any format
        chain_id = raw_name:match("R%d+_C%d+") or "Chain"
    end

    -- Check for custom display name
    local ok_guid, guid = pcall(function() return chain:get_guid() end)
    if ok_guid and guid then
        local state_module = require('lib.core.state')
        local state = state_module.state
        if state.display_names[guid] then
            -- Show custom name with identifier in brackets
            return state.display_names[guid] .. " [" .. chain_id .. "]"
        end
    end

    -- No custom name, just show identifier
    return chain_id
end

--- Get label name for chain row (shows only custom name, no [R1_C1]).
-- @param chain TrackFX Chain container FX object
-- @return string Display name: custom name if set, otherwise "R1_C1" identifier
function M.get_chain_label_name(chain)
    if not chain then return "Unknown" end

    -- Check for custom display name first
    local ok_guid, guid = pcall(function() return chain:get_guid() end)
    if ok_guid and guid then
        local state_module = require('lib.core.state')
        local state = state_module.state
        if state.display_names[guid] then
            -- Return just the custom name (no identifier)
            return state.display_names[guid]
        end
    end

    -- No custom name, get identifier from internal name
    local ok_name, raw_name = pcall(function() return chain:get_name() end)
    if not ok_name or not raw_name then return "Unknown" end

    -- Extract R1_C1 identifier (before colon if present)
    local chain_id = raw_name:match("^(R%d+_C%d+)")
    if not chain_id then
        -- Fallback: try to extract from any format
        chain_id = raw_name:match("R%d+_C%d+") or "Chain"
    end

    return chain_id
end

--- Get rack identifier (R1 format).
-- @param rack TrackFX Rack container FX object
-- @return string|nil Rack identifier like "R1" or nil
function M.get_rack_identifier(rack)
    if not rack then return nil end
    local ok_name, raw_name = pcall(function() return rack:get_name() end)
    if not ok_name or not raw_name then return nil end

    local rack_id = raw_name:match("^(R%d+)")
    if not rack_id then
        rack_id = raw_name:match("R%d+")
    end
    return rack_id
end

--- Get display name for rack header (shows custom name only, identifier shown separately).
-- @param rack TrackFX Rack container FX object
-- @return string Display name: custom name if set, otherwise "Rack"
function M.get_rack_display_name(rack)
    if not rack then return "Unknown" end

    -- Check for custom display name
    local ok_guid, guid = pcall(function() return rack:get_guid() end)
    if ok_guid and guid then
        local state_module = require('lib.core.state')
        local state = state_module.state
        if state.display_names[guid] then
            return state.display_names[guid]
        end
    end

    -- No custom name, return default
    return "Rack"
end

--- Get device identifier (R1_C1_D1 or D1 format).
-- @param device TrackFX Device container FX object
-- @return string|nil Device identifier like "R1_C1_D1" or "D1" or nil
function M.get_device_identifier(device)
    if not device then return nil end
    local ok_name, raw_name = pcall(function() return device:get_name() end)
    if not ok_name or not raw_name then return nil end

    local device_id = raw_name:match("^(R%d+_C%d+_D%d+)")
    if not device_id then
        device_id = raw_name:match("^(D%d+)")
        if not device_id then
            device_id = raw_name:match("R%d+_C%d+_D%d+") or raw_name:match("D%d+")
        end
    end
    return device_id
end

--- Get display name for device header (shows custom name only, identifier shown separately).
-- @param device TrackFX Device container FX object
-- @return string Display name: custom name if set, otherwise device identifier or "Device"
function M.get_device_display_name(device)
    if not device then return "Unknown" end

    -- Check for custom display name
    local ok_guid, guid = pcall(function() return device:get_guid() end)
    if ok_guid and guid then
        local state_module = require('lib.core.state')
        local state = state_module.state
        if state.display_names[guid] then
            return state.display_names[guid]
        end
    end

    -- No custom name, try to get identifier as fallback
    local device_id = M.get_device_identifier(device)
    return device_id or "Device"
end

--- Get internal name for FX (with SideFX prefix).
-- @param fx TrackFX ReaWrap FX object
-- @return string Internal name (may include prefix)
function M.get_internal_name(fx)
    if not fx then return "" end
    local ok, renamed = pcall(function() return fx:get_named_config_param("renamed_name") end)
    if ok and renamed and renamed ~= "" then
        return renamed
    end
    local ok2, name = pcall(function() return fx:get_name() end)
    return ok2 and name or ""
end

--- Rename an FX while preserving its internal prefix.
-- @param fx TrackFX ReaWrap FX object
-- @param new_display_name string New display name (without prefix)
-- @return boolean Success
function M.rename_fx(fx, new_display_name)
    if not fx or not new_display_name then return false end
    local internal_name = M.get_internal_name(fx)
    local prefix = naming.extract_prefix(internal_name)
    local new_internal_name = prefix .. new_display_name
    local ok = pcall(function()
        fx:set_named_config_param("renamed_name", new_internal_name)
    end)
    return ok
end

--------------------------------------------------------------------------------
-- Container Child Helpers
--------------------------------------------------------------------------------

--- Get the main FX from a D-container (first non-utility child).
-- @param container TrackFX Container FX object
-- @return TrackFX|nil Main FX or nil
function M.get_device_main_fx(container)
    if not container then return nil end
    for child in container:iter_container_children() do
        if not M.is_utility_fx(child) then
            return child
        end
    end
    return nil
end

--- Get the utility FX from a D-container.
-- @param container TrackFX Container FX object
-- @return TrackFX|nil Utility FX or nil
function M.get_device_utility(container)
    if not container then return nil end
    for child in container:iter_container_children() do
        if M.is_utility_fx(child) then
            return child
        end
    end
    return nil
end

--- Get the mixer FX from a rack container.
-- @param rack TrackFX Rack container FX object
-- @return TrackFX|nil Mixer FX or nil
function M.get_rack_mixer(rack)
    if not rack then return nil end
    for child in rack:iter_container_children() do
        if M.is_mixer_fx(child) then
            return child
        end
    end
    return nil
end

--- Find paired utility FX immediately after given FX (legacy support).
-- @param track Track ReaWrap Track object
-- @param fx TrackFX FX to find pair for
-- @return TrackFX|nil Paired utility or nil
function M.find_paired_utility(track, fx)
    if not track or not fx then return nil end

    local fx_idx = fx.pointer
    local next_idx = fx_idx + 1
    local total = track:get_track_fx_count()

    if next_idx < total then
        local next_fx = track:get_track_fx(next_idx)
        if next_fx and M.is_utility_fx(next_fx) then
            return next_fx
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Index Helpers
--------------------------------------------------------------------------------

--- Count D-containers at top level to get next index.
-- @param track Track ReaWrap Track object
-- @return number Next device index
function M.get_next_device_index(track)
    if not track then return 1 end
    local max_idx = 0
    for fx in track:iter_track_fx_chain() do
        local parent = fx:get_parent_container()
        if not parent then  -- Top level only
            local ok, name = pcall(function() return fx:get_name() end)
            if ok and name then
                local idx = naming.parse_device_index(name)
                if idx then
                    max_idx = math.max(max_idx, idx)
                end
            end
        end
    end
    return max_idx + 1
end

--- Get next rack index for R-naming.
-- @param track Track ReaWrap Track object
-- @return number Next rack index
function M.get_next_rack_index(track)
    if not track then return 1 end
    local max_idx = 0
    -- Use iter_all_fx_flat() to find ALL racks including nested ones
    for fx_info in track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local ok, name = pcall(function() return fx:get_name() end)
        if ok and name then
            -- Check for R-containers (racks can be at any depth)
            local r_idx = naming.parse_rack_index(name)
            if r_idx then
                max_idx = math.max(max_idx, r_idx)
            end
            -- Also count D-containers for overall numbering
            local d_idx = naming.parse_device_index(name)
            if d_idx then
                max_idx = math.max(max_idx, d_idx)
            end
        end
    end
    return max_idx + 1
end

--- Count devices in a chain container.
-- @param chain TrackFX Chain container
-- @return number Number of device containers
function M.count_devices_in_chain(chain)
    if not chain then return 0 end
    local count = 0
    for child in chain:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name then
            if name:match("_D%d+") or (not name:match("^_") and not naming.is_utility_name(name) and not naming.is_mixer_name(name)) then
                count = count + 1
            end
        end
    end
    return count
end

--- Count chains in a rack container (excluding mixer).
-- @param rack TrackFX Rack container
-- @return number Number of chain containers
function M.count_chains_in_rack(rack)
    if not rack then return 0 end
    local count = 0
    for child in rack:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name and not name:match("^_") and not naming.is_mixer_name(name) then
            count = count + 1
        end
    end
    return count
end

return M
