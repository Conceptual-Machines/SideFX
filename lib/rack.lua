--- SideFX Rack Operations.
-- Functions for creating and managing R-containers (racks) and C-containers (chains).
-- @module rack
-- @author Nomad Monad
-- @license MIT

local r = reaper

local naming = require('lib.naming')
local fx_utils = require('lib.fx_utils')
local state_module = require('lib.state')

local M = {}

-- Local reference to state singleton
local state = state_module.state

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

M.MIXER_JSFX = "JS:SideFX/SideFX_Mixer"
M.UTILITY_JSFX = "JS:SideFX/SideFX_Utility"

--------------------------------------------------------------------------------
-- Mixer Parameter Helpers
--------------------------------------------------------------------------------

--- Get the parameter index for chain volume in the mixer.
-- Parameter index is based on DECLARATION ORDER in JSFX, not slider number!
-- slider1 (Master Gain) = param 0
-- slider2 (Master Pan) = param 1
-- slider10-25 (Chain 1-16 Vol) = param 2-17
-- @param chain_index number Chain index (1-based)
-- @return number Parameter index
function M.get_mixer_chain_volume_param(chain_index)
    return 1 + chain_index  -- Chain 1 = param 2, Chain 2 = param 3, etc.
end

--- Get the parameter index for chain pan in the mixer.
-- @param chain_index number Chain index (1-based)
-- @return number Parameter index
function M.get_mixer_chain_pan_param(chain_index)
    return 17 + chain_index  -- Chain 1 Pan = param 18, Chain 2 Pan = param 19, etc.
end

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Find an FX by name pattern (searches recursively through all containers).
-- @param name_pattern string Lua pattern to match against FX name
-- @return TrackFX|nil FX object or nil if not found
local function find_fx_by_name_pattern(name_pattern)
    if not state.track then return nil end
    for entry in state.track:iter_all_fx_flat() do
        local fx = entry.fx
        local ok, name = pcall(function() return fx:get_name() end)
        if ok and name and name:match(name_pattern) then
            return fx
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Rack Creation
--------------------------------------------------------------------------------

--- Create a rack container with mixer (internal helper).
-- @param rack_idx number Rack index
-- @param position number|nil Position for track-level rack (nil = end)
-- @return TrackFX|nil Rack container or nil on failure
local function create_rack_container(rack_idx, position)
    if not state.track then return nil end

    local rack_name = naming.build_rack_name(rack_idx)

    -- Position for the container (only used when adding to track)
    local container_position = position and (-1000 - position) or -1

    -- Create the rack container at track level
    local rack = state.track:add_fx_by_name("Container", false, container_position)
    if not rack or rack.pointer < 0 then
        return nil
    end

        -- Rename the rack
        rack:set_named_config_param("renamed_name", rack_name)

        -- Set up for parallel routing (64 channels for up to 32 stereo chains)
        rack:set_container_channels(64)

        -- Add the mixer JSFX at track level, then move into rack
        local mixer_fx = state.track:add_fx_by_name(M.MIXER_JSFX, false, -1)
        if mixer_fx and mixer_fx.pointer >= 0 then
            -- Move mixer into rack
            rack:add_fx_to_container(mixer_fx, 0)

            -- Rename mixer
            local mixer_inside = nil
            for child in rack:iter_container_children() do
                local ok, name = pcall(function() return child:get_name() end)
                if ok and name and ((name:find("SideFX") and name:find("Mixer")) or name:match("^_R%d+_M$")) then
                    mixer_inside = child
                    break
                end
            end
            if mixer_inside then
                mixer_inside:set_named_config_param("renamed_name", naming.build_mixer_name(rack_idx))

                -- Initialize master and chain params
                local master_0db_norm = (0 + 24) / 36  -- 0.667
                local pan_center_norm = 0.5
                local vol_0db_norm = (0 + 60) / 72  -- 0.833

                pcall(function() mixer_inside:set_param_normalized(0, master_0db_norm) end)
                pcall(function() mixer_inside:set_param_normalized(1, pan_center_norm) end)

                for i = 1, 16 do
                    pcall(function() mixer_inside:set_param_normalized(1 + i, vol_0db_norm) end)
                    pcall(function() mixer_inside:set_param_normalized(17 + i, pan_center_norm) end)
                end
            end
        else
            r.ShowConsoleMsg("SideFX: Could not add mixer JSFX. Make sure SideFX_Mixer.jsfx is installed.\n")
        return nil
    end

    return rack
end

--- Add a new rack (R-container) to the current track or inside another rack.
-- Recursive function that handles both top-level racks and nested racks.
-- @param parent_rack TrackFX|nil Parent rack container (nil = add to track)
-- @param position number|nil Insert position (nil = end of chain, only used when adding to track)
-- @return TrackFX|nil Rack container or nil on failure
function M.add_rack(parent_rack, position)
    if not state.track then return nil end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get next global rack index
    local rack_idx = fx_utils.get_next_rack_index(state.track)

    -- If parent is a rack, wrap in chain and add to parent
    if parent_rack and fx_utils.is_rack_container(parent_rack) then
        -- Get GUID and name
        local parent_guid = parent_rack:get_guid()
        local parent_name = parent_rack:get_name()
        local parent_idx = naming.parse_rack_index(parent_name) or 1
        
        -- Re-find parent rack to ensure fresh reference
        parent_rack = state.track:find_fx_by_guid(parent_guid)
        if not parent_rack or not fx_utils.is_rack_container(parent_rack) then
            r.ShowConsoleMsg("SideFX: Could not find valid parent rack R" .. parent_idx .. "\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

        -- Create the nested rack
        local rack = create_rack_container(rack_idx, nil)
        if not rack then
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

        local rack_guid = rack:get_guid()

        -- Count existing chains to determine chain index
        local chain_count = fx_utils.count_chains_in_rack(parent_rack)
        local chain_idx = chain_count + 1

        if chain_idx > 31 then
            r.ShowConsoleMsg("SideFX: Maximum 31 chains per rack\n")
            rack:delete()
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

        -- Build chain name
        local chain_name = naming.build_chain_name(parent_idx, chain_idx)

        -- Create chain container to hold the nested rack
        local chain = state.track:add_fx_by_name("Container", false, -1)
        if not chain or chain.pointer < 0 then
            rack:delete()
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end
        
        chain:set_named_config_param("renamed_name", chain_name)
        chain:add_fx_to_container(rack, 0)

        local chain_guid = chain:get_guid()

        -- Re-find parent rack
        parent_rack = state.track:find_fx_by_guid(parent_guid)
        if not parent_rack then
            r.ShowConsoleMsg("SideFX: Lost parent rack\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

        -- Find mixer position in parent rack
        local mixer_pos = 0
        local pos = 0
        for child in parent_rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and (name:match("^_") or name:find("Mixer")) then
                mixer_pos = pos
                break
            end
            pos = pos + 1
        end

        -- Add chain to parent rack using ReaWrap's fixed add_fx_to_container
        -- (handles nested racks automatically with pop-out-put-back)
        chain = state.track:find_fx_by_guid(chain_guid)
        parent_rack = state.track:find_fx_by_guid(parent_guid)
        
        if not chain or not parent_rack then
            r.ShowConsoleMsg("SideFX: Lost chain or parent rack\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end
        
        local add_success = parent_rack:add_fx_to_container(chain, mixer_pos)
        if not add_success then
            r.ShowConsoleMsg("SideFX: Failed to add chain to parent rack R" .. parent_idx .. "\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

        -- Re-find parent rack after add (pointer may have changed if rack was nested)
        parent_rack = state.track:find_fx_by_guid(parent_guid)

        -- Set up routing for the chain
        local chain_inside = nil
        for child in parent_rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name == chain_name then
                chain_inside = child
                break
            end
        end

        if chain_inside then
            chain_inside:set_container_channels(64)

            -- Set output channel routing
            local out_channel = chain_idx * 2
            local left_bits = math.floor(2 ^ out_channel)
            local right_bits = math.floor(2 ^ (out_channel + 1))

            chain_inside:set_pin_mappings(1, 0, left_bits, 0)
            chain_inside:set_pin_mappings(1, 1, right_bits, 0)
        end

        -- Set parent rack mixer volume for this chain to 0dB
        local parent_mixer = fx_utils.get_rack_mixer(parent_rack)
        if parent_mixer then
            local vol_param = M.get_mixer_chain_volume_param(chain_idx)
            local normalized_0db = 60 / 72  -- 0.833...
            
            parent_mixer:set_param_normalized(vol_param, normalized_0db)

            local pan_param = M.get_mixer_chain_pan_param(chain_idx)
            parent_mixer:set_param_normalized(pan_param, 0.5)
        end

        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack", -1)

        -- Re-find the rack to return
        local rack_name_pattern = "^R" .. rack_idx .. ":"
        return find_fx_by_name_pattern(rack_name_pattern)
    else
        -- Add to track at specified position
        local rack = create_rack_container(rack_idx, position)
        if not rack then
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Rack", -1)

        -- Re-find the rack to ensure we have a fresh reference
        local rack_name_pattern = "^R" .. rack_idx .. ":"
        return find_fx_by_name_pattern(rack_name_pattern)
    end
end

--- Add a new rack (R-container) to the current track.
-- @param position number|nil Insert position (nil = end of chain)
-- @return TrackFX|nil Rack container or nil on failure
function M.add_rack_to_track(position)
    return M.add_rack(nil, position)
end

--- Add a nested rack as a new chain inside an existing rack.
-- Creates a chain container with a fully functional rack inside it.
-- @param parent_rack TrackFX Parent rack container
-- @return TrackFX|nil Nested rack container or nil on failure
function M.add_nested_rack_to_rack(parent_rack)
    return M.add_rack(parent_rack, nil)
end

--------------------------------------------------------------------------------
-- Chain Operations
--------------------------------------------------------------------------------

--- Add a chain (C-container) to an existing rack.
-- @param rack TrackFX Rack container
-- @param plugin table Plugin info {full_name, name}
-- @return TrackFX|nil Chain container or nil on failure
function M.add_chain_to_rack(rack, plugin)
    if not state.track or not rack or not plugin then return nil end
    if not fx_utils.is_rack_container(rack) then return nil end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get GUID before re-finding (GUID is stable)
    local rack_guid = rack:get_guid()
    local rack_name = rack:get_name()
    local rack_idx = naming.parse_rack_index(rack_name) or 1
    local rack_name_pattern = "^R" .. rack_idx .. ":"
    rack = find_fx_by_name_pattern(rack_name_pattern)

    if not rack or not fx_utils.is_rack_container(rack) then
        r.ShowConsoleMsg("SideFX: Could not find rack R" .. rack_idx .. "\n")
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
        return nil
    end
    
    -- Re-save GUID in case rack changed (should be same, but be safe)
    rack_guid = rack:get_guid()
    rack_name = rack:get_name()
    local rack_prefix = rack_name:match("^(R%d+)") or "R1"

    -- Count existing chains
    local chain_count = fx_utils.count_chains_in_rack(rack)
    local chain_idx = chain_count + 1

    -- Max 31 chains
    if chain_idx > 31 then
        r.ShowConsoleMsg("SideFX: Maximum 31 chains per rack\n")
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
        return nil
    end

    -- Build names
    local short_name = naming.get_short_plugin_name(plugin.full_name)
    local chain_name = naming.build_chain_name(rack_idx, chain_idx)
    local device_name = naming.build_chain_device_name(rack_idx, chain_idx, 1, short_name)
    local fx_name = naming.build_chain_device_fx_name(rack_idx, chain_idx, 1, short_name)
    local util_name = naming.build_chain_device_util_name(rack_idx, chain_idx, 1)

    -- Step 1: Create device container at track level
    local device = state.track:add_fx_by_name("Container", false, -1)
    if not device or device.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Chain (failed)", -1)
        return nil
    end
    device:set_named_config_param("renamed_name", device_name)

    -- Step 2: Add FX to device container
    local main_fx = state.track:add_fx_by_name(plugin.full_name, false, -1)
    if main_fx and main_fx.pointer >= 0 then
        device:add_fx_to_container(main_fx, 0)

        local fx_inside = fx_utils.get_device_main_fx(device)
        if fx_inside then
            local wet_idx = fx_inside:get_param_from_ident(":wet")
            if wet_idx and wet_idx >= 0 then
                fx_inside:set_param_normalized(wet_idx, 1.0)
            end
            fx_inside:set_named_config_param("renamed_name", fx_name)
        end
    end

    -- Step 3: Add utility to device container
    local util_fx = state.track:add_fx_by_name(M.UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        device:add_fx_to_container(util_fx, 1)

        local util_inside = fx_utils.get_device_utility(device)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", util_name)
        end
    end

    -- Step 4: Create chain container
    local chain = state.track:add_fx_by_name("Container", false, -1)
    local chain_inside = nil  -- Declare outside block for use after
    if chain and chain.pointer >= 0 then
        chain:set_named_config_param("renamed_name", chain_name)
        chain:add_fx_to_container(device, 0)

        -- Force UI refresh before re-finding to ensure fresh pointers
        r.PreventUIRefresh(-1)
        r.PreventUIRefresh(1)
        
        -- Re-find rack to ensure fresh reference (may have become stale)
        rack = state.track:find_fx_by_guid(rack_guid)
        if not rack then
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
            return nil
        end
        
        -- Find mixer position
        local mixer_pos = 0
        local pos = 0
        for child in rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and (name:match("^_") or name:find("Mixer")) then
                mixer_pos = pos
                break
            end
            pos = pos + 1
        end
        
        -- Add chain to rack using ReaWrap's fixed add_fx_to_container
        -- (now handles nested racks automatically)
        local add_success = rack:add_fx_to_container(chain, mixer_pos)
        
        if not add_success then
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
            return nil
        end

        -- Re-find rack and chain after add (pointers may have changed if rack was nested)
        rack = state.track:find_fx_by_guid(rack_guid)
        
        -- Re-find chain inside rack
        for child in rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name == chain_name then
                chain_inside = child
                break
            end
        end

        if chain_inside then
            chain_inside:set_container_channels(64)

            -- Set output channel routing
            local out_channel = chain_idx * 2
            local left_bits = math.floor(2 ^ out_channel)
            local right_bits = math.floor(2 ^ (out_channel + 1))

            chain_inside:set_pin_mappings(1, 0, left_bits, 0)
            chain_inside:set_pin_mappings(1, 1, right_bits, 0)
        end

        -- Set mixer volume for this chain to 0dB
        local mixer = fx_utils.get_rack_mixer(rack)
        if mixer then
            local vol_param = M.get_mixer_chain_volume_param(chain_idx)
            local normalized_0db = 60 / 72  -- 0.833...
            mixer:set_param_normalized(vol_param, normalized_0db)

            -- Also set pan to center (normalized 0.5)
            local pan_param = M.get_mixer_chain_pan_param(chain_idx)
            mixer:set_param_normalized(pan_param, 0.5)
        end
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Chain to Rack", -1)

    -- Re-find the chain after it's been moved (reference is stale)
    -- Use the chain_inside if we found it, otherwise search by name pattern
    if chain_inside then
        return chain_inside
    else
        -- Fallback: search by name pattern (works for nested racks too)
        local chain_name_pattern = "^" .. chain_name .. "$"
        return find_fx_by_name_pattern(chain_name_pattern)
    end
end

--- Add a device to an existing chain.
-- @param chain TrackFX Chain container
-- @param plugin table Plugin info {full_name, name}
-- @return TrackFX|nil Device container or nil on failure
function M.add_device_to_chain(chain, plugin)
    if not state.track or not chain or not plugin then return nil end
    if not fx_utils.is_chain_container(chain) then return nil end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Re-find chain to ensure we have a fresh reference
    local chain_guid = chain:get_guid()
    if not chain_guid then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (failed)", -1)
        return nil
    end

    -- Get chain name first to build search pattern
    local chain_name = chain:get_name()
    local chain_name_pattern = "^" .. chain_name:gsub("%(", "%%("):gsub("%)", "%%)"):gsub("%.", "%%.") .. "$"
    chain = find_fx_by_name_pattern(chain_name_pattern)

    if not chain or not fx_utils.is_chain_container(chain) then
        r.ShowConsoleMsg("SideFX: Could not find chain: " .. tostring(chain_name) .. "\n")
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (failed)", -1)
        return nil
    end

    -- Get chain name again (in case it changed)
    chain_name = chain:get_name()
    local chain_prefix = chain_name:match("^(R%d+_C%d+)") or chain_name
    local hierarchy = naming.parse_hierarchy(chain_name)
    local rack_idx = hierarchy.rack_idx or 1
    local chain_idx = hierarchy.chain_idx or 1

    -- Count existing devices
    local device_count = fx_utils.count_devices_in_chain(chain)
    local device_idx = device_count + 1

    -- Build names
    local short_name = naming.get_short_plugin_name(plugin.full_name)
    local device_name = naming.build_chain_device_name(rack_idx, chain_idx, device_idx, short_name)
    local fx_name = naming.build_chain_device_fx_name(rack_idx, chain_idx, device_idx, short_name)
    local util_name = naming.build_chain_device_util_name(rack_idx, chain_idx, device_idx)

    -- Create device container at track level
    local device = state.track:add_fx_by_name("Container", false, -1)
    if not device or device.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (failed)", -1)
        return nil
    end
    device:set_named_config_param("renamed_name", device_name)

    -- Add FX to device
    local main_fx = state.track:add_fx_by_name(plugin.full_name, false, -1)
    if main_fx and main_fx.pointer >= 0 then
        device:add_fx_to_container(main_fx, 0)

        local fx_inside = fx_utils.get_device_main_fx(device)
        if fx_inside then
            local wet_idx = fx_inside:get_param_from_ident(":wet")
            if wet_idx and wet_idx >= 0 then
                fx_inside:set_param_normalized(wet_idx, 1.0)
            end
            fx_inside:set_named_config_param("renamed_name", fx_name)
        end
    end

    -- Add utility to device
    local util_fx = state.track:add_fx_by_name(M.UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        device:add_fx_to_container(util_fx, 1)

        local util_inside = fx_utils.get_device_utility(device)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", util_name)
        end
    end

    -- Move device into chain using ReaWrap's fixed add_fx_to_container
    -- (now handles nested containers properly)
    local device_guid = device:get_guid()
    local fresh_chain = state.track:find_fx_by_guid(chain_guid)

    if not fresh_chain then
        if device then device:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (chain lost)", -1)
        return nil
    end

    device = state.track:find_fx_by_guid(device_guid)
    if not device then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (device lost)", -1)
        return nil
    end

    local insert_pos = fresh_chain:get_container_child_count()
    local success = fresh_chain:add_fx_to_container(device, insert_pos)
    
    if not success then
        if device then device:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (failed)", -1)
        return nil
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Device to Chain", -1)

    -- Re-find the device after it's been moved (reference is stale)
    if device_guid then
        return state.track:find_fx_by_guid(device_guid)
    end
    return device
end

--- Add a rack (R-container) to an existing chain.
-- Creates a new empty rack and adds it to the chain.
-- @param chain TrackFX Chain container
-- @return TrackFX|nil Rack container or nil on failure
function M.add_rack_to_chain(chain)
    if not state.track or not chain then return nil end
    if not fx_utils.is_chain_container(chain) then return nil end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get chain GUID and name
    local chain_guid = chain:get_guid()
    if not chain_guid then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack to Chain (failed)", -1)
        return nil
    end

    local chain_name = chain:get_name()

    -- Get next rack index
    local rack_idx = fx_utils.get_next_rack_index(state.track)

    -- Create rack container with mixer at track level
    local rack = create_rack_container(rack_idx, nil)
    if not rack then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack to Chain (failed)", -1)
        return nil
    end

    local rack_guid = rack:get_guid()

    -- Re-find chain to ensure fresh reference
    chain = state.track:find_fx_by_guid(chain_guid)
    if not chain or not fx_utils.is_chain_container(chain) then
        if rack then rack:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack to Chain (chain lost)", -1)
        return nil
    end

    -- Re-find rack
    rack = state.track:find_fx_by_guid(rack_guid)
    if not rack then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack to Chain (rack lost)", -1)
        return nil
    end

    -- Add rack to chain using ReaWrap's fixed add_fx_to_container
    -- (which now handles nested containers properly via pop-out-put-back)
    local success = chain:add_fx_to_container(rack, nil)
    if not success then
        if rack then rack:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack to Chain (failed)", -1)
        return nil
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Rack to Chain", -1)

    -- Re-find the rack after it's been moved (reference is stale)
    if rack_guid then
        return state.track:find_fx_by_guid(rack_guid)
    end
    return rack
end

--------------------------------------------------------------------------------
-- Chain Reordering
--------------------------------------------------------------------------------

--- Reorder a chain within a rack.
-- @param rack TrackFX Rack container
-- @param chain_guid string GUID of chain to move
-- @param target_chain_guid string|nil GUID to move before (nil = end)
-- @return boolean Success
function M.reorder_chain_in_rack(rack, chain_guid, target_chain_guid)
    if not state.track or not rack or not chain_guid then return false end
    if not fx_utils.is_rack_container(rack) then return false end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Re-find rack to ensure we have a fresh reference
    local rack_name = rack:get_name()
    local rack_idx = naming.parse_rack_index(rack_name) or 1
    local rack_name_pattern = "^R" .. rack_idx .. ":"
    rack = find_fx_by_name_pattern(rack_name_pattern)

    if not rack or not fx_utils.is_rack_container(rack) then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain (failed)", -1)
        return false
    end

    local chain = state.track:find_fx_by_guid(chain_guid)
    if not chain then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain (failed)", -1)
        return false
    end

    local parent = chain:get_parent_container()
    if not parent or parent:get_guid() ~= rack:get_guid() then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain (failed)", -1)
        return false
    end

    -- Get children info
    local children = {}
    local chain_pos = nil
    local target_pos = nil
    local mixer_pos = nil
    local pos = 0

    for child in rack:iter_container_children() do
        local guid = child:get_guid()
        local ok, name = pcall(function() return child:get_name() end)

        children[#children + 1] = { guid = guid, fx = child }

        if guid == chain_guid then chain_pos = pos end
        if guid == target_chain_guid then target_pos = pos end
        if ok and name and (name:match("^_") or name:find("Mixer")) then
            mixer_pos = pos
        end

        pos = pos + 1
    end

    if chain_pos == nil then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain (failed)", -1)
        return false
    end

    -- Calculate destination
    local dest_pos
    if target_chain_guid == nil then
        dest_pos = mixer_pos or #children
    else
        dest_pos = target_pos or mixer_pos or #children
    end

    if dest_pos > chain_pos then
        dest_pos = dest_pos - 1
    end

    if dest_pos == chain_pos then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain", -1)
        return true
    end

    -- Perform the move
    chain:move_out_of_container()

    chain = state.track:find_fx_by_guid(chain_guid)
    rack = state.track:find_fx_by_guid(rack:get_guid())

    if chain and rack then
        rack:add_fx_to_container(chain, dest_pos)
        M.renumber_chains_in_rack(rack)
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Reorder Chain", -1)

    return true
end

--- Renumber chains within a rack after reordering.
-- @param rack TrackFX Rack container
function M.renumber_chains_in_rack(rack)
    if not rack then return end
    if not fx_utils.is_rack_container(rack) then return end

    -- Re-find rack to ensure we have a fresh reference
    local rack_name = rack:get_name()
    local rack_idx = naming.parse_rack_index(rack_name) or 1
    local rack_name_pattern = "^R" .. rack_idx .. ":"
    rack = find_fx_by_name_pattern(rack_name_pattern)

    if not rack or not fx_utils.is_rack_container(rack) then
        return
    end

    -- Get rack name again
    rack_name = rack:get_name()
    rack_idx = naming.parse_rack_index(rack_name) or 1

    local chain_idx = 0
    for child in rack:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name then
            if not name:match("^_") and not name:find("Mixer") then
                chain_idx = chain_idx + 1
                local old_prefix = name:match("^(R%d+_C%d+)")
                if old_prefix then
                    local new_prefix = naming.build_chain_name(rack_idx, chain_idx)
                    if old_prefix ~= new_prefix then
                        local new_name = name:gsub("^R%d+_C%d+", new_prefix)
                        child:set_named_config_param("renamed_name", new_name)

                        -- Rename devices inside chain
                        for device in child:iter_container_children() do
                            local ok_d, device_name = pcall(function() return device:get_name() end)
                            if ok_d and device_name then
                                local new_device_name = device_name:gsub("^R%d+_C%d+", new_prefix)
                                if new_device_name ~= device_name then
                                    device:set_named_config_param("renamed_name", new_device_name)

                                    -- Rename FX inside device
                                    for inner in device:iter_container_children() do
                                        local ok_i, inner_name = pcall(function() return inner:get_name() end)
                                        if ok_i and inner_name then
                                            local new_inner_name = inner_name:gsub("^R%d+_C%d+", new_prefix)
                                            if new_inner_name ~= inner_name then
                                                inner:set_named_config_param("renamed_name", new_inner_name)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

return M
