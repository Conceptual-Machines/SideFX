--- SideFX Rack Operations.
-- Functions for creating and managing R-containers (racks) and C-containers (chains).
-- @module rack
-- @author Nomad Monad
-- @license MIT

local r = reaper

local naming = require('lib.naming')
local fx_utils = require('lib.fx_utils')

local M = {}

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
-- Rack Creation
--------------------------------------------------------------------------------

--- Add a new rack (R-container) to a track.
-- @param track Track ReaWrap Track object
-- @param position number|nil Insert position (nil = end of chain)
-- @param on_complete function|nil Callback after creation (e.g., refresh_fx_list)
-- @return TrackFX|nil Rack container or nil on failure
function M.add_rack_to_track(track, position, on_complete)
    if not track then return nil end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get next index
    local rack_idx = fx_utils.get_next_rack_index(track)
    local rack_name = naming.build_rack_name(rack_idx)
    
    -- Position for the container
    local container_position = position and (-1000 - position) or -1
    
    -- Create the rack container
    local rack = track:add_fx_by_name("Container", false, container_position)
    
    if rack and rack.pointer >= 0 then
        -- Rename the rack
        rack:set_named_config_param("renamed_name", rack_name)
        
        -- Set up for parallel routing (64 channels for up to 32 stereo chains)
        rack:set_container_channels(64)
        
        -- Add the mixer JSFX at track level, then move into rack
        local mixer_fx = track:add_fx_by_name(M.MIXER_JSFX, false, -1)
        
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
        end
        
        if on_complete then on_complete() end
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Rack", -1)
    
    return rack
end

--------------------------------------------------------------------------------
-- Chain Operations
--------------------------------------------------------------------------------

--- Add a chain (C-container) to an existing rack.
-- @param track Track ReaWrap Track object
-- @param rack TrackFX Rack container
-- @param plugin table Plugin info {full_name, name}
-- @param on_complete function|nil Callback after creation
-- @return TrackFX|nil Chain container or nil on failure
function M.add_chain_to_rack(track, rack, plugin, on_complete)
    if not track or not rack or not plugin then return nil end
    if not fx_utils.is_rack_container(rack) then return nil end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get rack name for prefix
    local rack_name = rack:get_name()
    local rack_prefix = rack_name:match("^(R%d+)") or "R1"
    local rack_idx = naming.parse_rack_index(rack_name) or 1
    
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
    local device = track:add_fx_by_name("Container", false, -1)
    if not device or device.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Chain (failed)", -1)
        return nil
    end
    device:set_named_config_param("renamed_name", device_name)
    
    -- Step 2: Add FX to device container
    local main_fx = track:add_fx_by_name(plugin.full_name, false, -1)
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
    local util_fx = track:add_fx_by_name(M.UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        device:add_fx_to_container(util_fx, 1)
        
        local util_inside = fx_utils.get_device_utility(device)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", util_name)
        end
    end
    
    -- Step 4: Create chain container
    local chain = track:add_fx_by_name("Container", false, -1)
    if chain and chain.pointer >= 0 then
        chain:set_named_config_param("renamed_name", chain_name)
        chain:add_fx_to_container(device, 0)
        
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
        
        rack:add_fx_to_container(chain, mixer_pos)
        
        -- Re-find chain inside rack
        local chain_inside = nil
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
        
        if on_complete then on_complete() end
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Chain to Rack", -1)
    
    return chain
end

--- Add a device to an existing chain.
-- @param track Track ReaWrap Track object
-- @param chain TrackFX Chain container
-- @param plugin table Plugin info {full_name, name}
-- @param on_complete function|nil Callback after creation
-- @return TrackFX|nil Device container or nil on failure
function M.add_device_to_chain(track, chain, plugin, on_complete)
    if not track or not chain or not plugin then return nil end
    if not fx_utils.is_chain_container(chain) then return nil end
    
    local chain_guid = chain:get_guid()
    if not chain_guid then return nil end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get chain name to extract prefix
    local chain_name = chain:get_name()
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
    local device = track:add_fx_by_name("Container", false, -1)
    if not device or device.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (failed)", -1)
        return nil
    end
    device:set_named_config_param("renamed_name", device_name)
    
    -- Add FX to device
    local main_fx = track:add_fx_by_name(plugin.full_name, false, -1)
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
    local util_fx = track:add_fx_by_name(M.UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        device:add_fx_to_container(util_fx, 1)
        
        local util_inside = fx_utils.get_device_utility(device)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", util_name)
        end
    end
    
    -- Move device into chain
    local device_guid = device:get_guid()
    local fresh_chain = track:find_fx_by_guid(chain_guid)
    
    if not fresh_chain then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (chain lost)", -1)
        return nil
    end
    
    local rack = fresh_chain:get_parent_container()
    if rack then
        -- Chain is nested - move it OUT to track level first
        local rack_guid = rack:get_guid()
        
        local chain_pos_in_rack = 0
        for child in rack:iter_container_children() do
            if child:get_guid() == chain_guid then break end
            chain_pos_in_rack = chain_pos_in_rack + 1
        end
        
        fresh_chain:move_out_of_container()
        fresh_chain = track:find_fx_by_guid(chain_guid)
        device = track:find_fx_by_guid(device_guid)
        
        if fresh_chain and device then
            local insert_pos = fresh_chain:get_container_child_count()
            fresh_chain:add_fx_to_container(device, insert_pos)
            
            fresh_chain = track:find_fx_by_guid(chain_guid)
            local fresh_rack = track:find_fx_by_guid(rack_guid)
            
            if fresh_chain and fresh_rack then
                fresh_rack:add_fx_to_container(fresh_chain, chain_pos_in_rack)
            end
        end
    else
        -- Chain is top-level
        local insert_pos = fresh_chain:get_container_child_count()
        fresh_chain:add_fx_to_container(device, insert_pos)
    end
    
    if on_complete then on_complete() end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Device to Chain", -1)
    
    return device
end

--------------------------------------------------------------------------------
-- Chain Reordering
--------------------------------------------------------------------------------

--- Reorder a chain within a rack.
-- @param track Track ReaWrap Track object
-- @param rack TrackFX Rack container
-- @param chain_guid string GUID of chain to move
-- @param target_chain_guid string|nil GUID to move before (nil = end)
-- @param on_complete function|nil Callback after reorder
-- @return boolean Success
function M.reorder_chain_in_rack(track, rack, chain_guid, target_chain_guid, on_complete)
    if not track or not rack or not chain_guid then return false end
    if not fx_utils.is_rack_container(rack) then return false end
    
    local chain = track:find_fx_by_guid(chain_guid)
    if not chain then return false end
    
    local parent = chain:get_parent_container()
    if not parent or parent:get_guid() ~= rack:get_guid() then return false end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
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
    
    chain = track:find_fx_by_guid(chain_guid)
    rack = track:find_fx_by_guid(rack:get_guid())
    
    if chain and rack then
        rack:add_fx_to_container(chain, dest_pos)
        M.renumber_chains_in_rack(rack)
    end
    
    if on_complete then on_complete() end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Reorder Chain", -1)
    
    return true
end

--- Renumber chains within a rack after reordering.
-- @param rack TrackFX Rack container
function M.renumber_chains_in_rack(rack)
    if not rack then return end
    
    local rack_name = rack:get_name()
    local rack_idx = naming.parse_rack_index(rack_name) or 1
    
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

