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
        -- Get GUID and name before re-finding (these are stable)
        local parent_guid = parent_rack:get_guid()
        local parent_name = parent_rack:get_name()
        local parent_idx = naming.parse_rack_index(parent_name) or 1
        
        -- Re-find parent rack by GUID FIRST (most reliable, works even if nested)
        -- We need to re-find before checking parent, because the original reference might be stale
        -- and get_parent_container() only works on fresh references
        if parent_guid then
            parent_rack = state.track:find_fx_by_guid(parent_guid)
        end

        -- Verify we found a valid rack container (use fx_utils which is more reliable)
        if not parent_rack or not fx_utils.is_rack_container(parent_rack) then
            -- Fallback: try to find by name pattern
            local parent_name_pattern = "^R" .. parent_idx .. ":"
            parent_rack = find_fx_by_name_pattern(parent_name_pattern)
        end

        if not parent_rack or not fx_utils.is_rack_container(parent_rack) then
            r.ShowConsoleMsg("SideFX: Could not find valid parent rack R" .. parent_idx .. "\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

        -- NOW check parent after re-finding (parent relationship should be correct)
        local parent_rack_parent = parent_rack:get_parent_container()
        local parent_rack_parent_guid = parent_rack_parent and parent_rack_parent:get_guid() or nil

        r.ShowConsoleMsg(string.format("SideFX: [add_rack] Initial check - parent_name=%s, parent_has_parent=%s\n",
            parent_name, tostring(parent_rack_parent ~= nil)))

        -- Create the rack container (position not used for nested racks)
        local rack = create_rack_container(rack_idx, nil)
        if not rack then
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
            return nil
        end

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
        if chain and chain.pointer >= 0 then
            chain:set_named_config_param("renamed_name", chain_name)
            chain:add_fx_to_container(rack, 0)

            local chain_guid = chain:get_guid()
            local rack_guid = rack:get_guid()

            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Starting - parent_idx=%d, rack_idx=%d, chain_name=%s\n", parent_idx, rack_idx, chain_name))
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] parent_guid=%s, chain_guid=%s, rack_guid=%s\n", tostring(parent_guid), tostring(chain_guid), tostring(rack_guid)))
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] parent_rack_parent_guid=%s (from initial check)\n", tostring(parent_rack_parent_guid)))

            -- Check if parent rack is itself nested (inside another container)
            -- Use the parent_rack_parent_guid we got BEFORE re-finding
            local parent_rack_pos = 0
            local needs_pop = false
            local chain_parent_rack_guid_stored = nil  -- For two-step put-back when rack is in chain
            local chain_pos_in_rack_stored = 0

            if parent_rack_parent_guid then
                -- Re-find the parent container to get fresh reference
                parent_rack_parent = state.track:find_fx_by_guid(parent_rack_parent_guid)
                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Re-found parent container: %s\n", tostring(parent_rack_parent ~= nil)))
            end

            if parent_rack_parent then
                -- Parent rack is nested - need to pop it out first (like add_device_to_chain does)
                needs_pop = true
                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Parent rack R%d is nested, will pop out\n", parent_idx))

                -- Check if parent is inside a chain (which is inside a rack)
                local parent_is_in_chain = fx_utils.is_chain_container(parent_rack_parent)
                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Parent container is chain: %s\n", tostring(parent_is_in_chain)))

                -- Remember parent rack's position in its container
                local pos = 0
                for child in parent_rack_parent:iter_container_children() do
                    if child:get_guid() == parent_guid then
                        parent_rack_pos = pos
                        break
                    end
                    pos = pos + 1
                end
                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Parent rack position in container: %d\n", parent_rack_pos))

                -- If parent is in a chain, we need to move the chain out first, then the rack
                if parent_is_in_chain then
                    local chain_guid_before = parent_rack_parent:get_guid()
                    local chain_parent = parent_rack_parent:get_parent_container()
                    local chain_parent_rack_guid = chain_parent and chain_parent:get_guid() or nil
                    local chain_pos_in_rack = 0

                    if chain_parent then
                        pos = 0
                        for child in chain_parent:iter_container_children() do
                            if child:get_guid() == chain_guid_before then
                                chain_pos_in_rack = pos
                                break
                            end
                            pos = pos + 1
                        end
                        r.ShowConsoleMsg(string.format("SideFX: [add_rack] Chain is at position %d in rack\n", chain_pos_in_rack))

                        -- Re-find the chain before moving (reference might be stale)
                        parent_rack_parent = state.track:find_fx_by_guid(chain_guid_before)
                        if not parent_rack_parent then
                            r.ShowConsoleMsg("SideFX: Failed to re-find chain before move\n")
                            if chain then chain:delete() end
                            if rack then rack:delete() end
                            r.PreventUIRefresh(-1)
                            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                            return nil
                        end

                        -- Verify chain is valid before calling move_out_of_container
                        local chain_is_cont = false
                        local chain_has_parent = false
                        pcall(function()
                            chain_is_cont = parent_rack_parent:is_container()
                            local cp = parent_rack_parent:get_parent_container()
                            chain_has_parent = (cp ~= nil)
                        end)
                        r.ShowConsoleMsg(string.format("SideFX: [add_rack] Chain before move - is_container=%s, has_parent=%s\n", 
                            tostring(chain_is_cont), tostring(chain_has_parent)))

                        -- Move chain out first
                        r.ShowConsoleMsg("SideFX: [add_rack] Moving chain out first...\n")
                        local chain_pop_success = nil
                        local ok, result = pcall(function() 
                            return parent_rack_parent:move_out_of_container()
                        end)
                        if ok then
                            chain_pop_success = result
                        else
                            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Error calling move_out_of_container: %s\n", tostring(result)))
                        end
                        r.ShowConsoleMsg(string.format("SideFX: [add_rack] Chain move_out_of_container() returned: %s\n", tostring(chain_pop_success)))
                        if not chain_pop_success then
                            r.ShowConsoleMsg("SideFX: Failed to move chain out\n")
                            if chain then chain:delete() end
                            if rack then rack:delete() end
                            r.PreventUIRefresh(-1)
                            r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                            return nil
                        end
                        r.PreventUIRefresh(-1)
                        r.PreventUIRefresh(1)
                        parent_rack_parent = state.track:find_fx_by_guid(chain_guid_before)
                        parent_rack = state.track:find_fx_by_guid(parent_guid)
                    end

                    -- Now move rack out of chain
                    r.ShowConsoleMsg("SideFX: [add_rack] Moving rack out of chain...\n")
                    local pop_success = parent_rack:move_out_of_container()
                    r.ShowConsoleMsg(string.format("SideFX: [add_rack] Rack move_out_of_container() returned: %s\n", tostring(pop_success)))

                    if not pop_success then
                        r.ShowConsoleMsg("SideFX: Failed to move rack out of chain\n")
                        if chain then chain:delete() end
                        if rack then rack:delete() end
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                        return nil
                    end

                    -- Store chain info for putting back (rack goes back into chain, chain goes back into its rack)
                    parent_rack_parent_guid = chain_guid_before  -- Rack's parent is the chain
                    -- parent_rack_pos already set above (rack's position in chain)
                    -- Store chain's parent info separately for two-step put-back
                    chain_parent_rack_guid_stored = chain_parent_rack_guid
                    chain_pos_in_rack_stored = chain_pos_in_rack
                else
                    -- Pop parent rack out to track level directly
                    r.ShowConsoleMsg("SideFX: [add_rack] Calling move_out_of_container()\n")
                    local pop_success = parent_rack:move_out_of_container()
                    r.ShowConsoleMsg(string.format("SideFX: [add_rack] move_out_of_container() returned: %s\n", tostring(pop_success)))

                    if not pop_success then
                        r.ShowConsoleMsg("SideFX: Failed to move rack out of container\n")
                        if chain then chain:delete() end
                        if rack then rack:delete() end
                        r.PreventUIRefresh(-1)
                        r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                        return nil
                    end
                end

                -- Refresh and re-find
                r.PreventUIRefresh(-1)
                r.PreventUIRefresh(1)
                r.ShowConsoleMsg("SideFX: [add_rack] Re-finding after pop...\n")

                parent_rack = state.track:find_fx_by_guid(parent_guid)
                chain = state.track:find_fx_by_guid(chain_guid)
                rack = state.track:find_fx_by_guid(rack_guid)

                r.ShowConsoleMsg(string.format("SideFX: [add_rack] After pop - parent_rack=%s, chain=%s, rack=%s\n",
                    tostring(parent_rack ~= nil), tostring(chain ~= nil), tostring(rack ~= nil)))

                if not parent_rack or not chain or not rack then
                    r.ShowConsoleMsg("SideFX: Failed to pop parent rack R" .. parent_idx .. " out\n")
                    if chain then chain:delete() end
                    if rack then rack:delete() end
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                    return nil
                end

                -- Verify parent rack is now at track level (no parent)
                local still_has_parent = parent_rack:get_parent_container()
                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Parent rack still_has_parent after pop: %s\n", tostring(still_has_parent ~= nil)))
                if still_has_parent then
                    r.ShowConsoleMsg("SideFX: Parent rack R" .. parent_idx .. " still has parent after pop\n")
                    if chain then chain:delete() end
                    if rack then rack:delete() end
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                    return nil
                end
            else
                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Parent rack R%d is at track level, no pop needed\n", parent_idx))
            end

            -- Find mixer position in parent rack (after pop if needed)
            r.ShowConsoleMsg("SideFX: [add_rack] Finding mixer position...\n")
            local mixer_pos = 0
            local pos = 0
            local child_count = 0
            for child in parent_rack:iter_container_children() do
                child_count = child_count + 1
                local ok, name = pcall(function() return child:get_name() end)
                if ok and name and (name:match("^_") or name:find("Mixer")) then
                    mixer_pos = pos
                    r.ShowConsoleMsg(string.format("SideFX: [add_rack] Found mixer at position %d (name=%s)\n", pos, name))
                    break
                end
                pos = pos + 1
            end
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Parent rack has %d children, mixer_pos=%d\n", child_count, mixer_pos))

            -- Verify chain has no parent (is at track level)
            local chain_parent = chain:get_parent_container()
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Chain has parent: %s\n", tostring(chain_parent ~= nil)))
            if chain_parent then
                r.ShowConsoleMsg("SideFX: Chain already has parent before add\n")
                if chain_guid then
                    local orphan_chain = state.track:find_fx_by_guid(chain_guid)
                    if orphan_chain then orphan_chain:delete() end
                end
                if rack_guid then
                    local orphan_rack = state.track:find_fx_by_guid(rack_guid)
                    if orphan_rack then orphan_rack:delete() end
                end
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                return nil
            end

            -- Get parent rack info before adding
            local parent_name_before = ""
            local parent_is_cont_before = false
            pcall(function()
                parent_name_before = parent_rack:get_name() or ""
                parent_is_cont_before = parent_rack:is_container()
            end)
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Before add - parent_name=%s, parent_is_container=%s\n", parent_name_before, tostring(parent_is_cont_before)))

            -- Add chain to parent rack (now at track level if it was nested)
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Calling add_fx_to_container(chain, %d)...\n", mixer_pos))
            local add_success = parent_rack:add_fx_to_container(chain, mixer_pos)
            r.ShowConsoleMsg(string.format("SideFX: [add_rack] add_fx_to_container returned: %s\n", tostring(add_success)))
            if not add_success then
                -- Get detailed diagnostic info
                r.ShowConsoleMsg("SideFX: [add_rack] add_fx_to_container FAILED, gathering diagnostics...\n")
                local parent_is_cont = false
                local parent_name_check = ""
                local parent_guid_check = ""
                local chain_has_parent_after = false
                local chain_parent_guid = ""

                pcall(function()
                    parent_is_cont = parent_rack:is_container()
                    local ok, name = pcall(function() return parent_rack:get_name() end)
                    if ok then parent_name_check = name or "" end
                    parent_guid_check = parent_rack:get_guid() or ""
                end)

                pcall(function()
                    local cp = chain:get_parent_container()
                    chain_has_parent_after = (cp ~= nil)
                    if cp then chain_parent_guid = cp:get_guid() or "" end
                end)

                r.ShowConsoleMsg(string.format("SideFX: Failed to add chain to parent rack R%d\n", parent_idx))
                r.ShowConsoleMsg(string.format("  parent_name=%s\n", parent_name_check))
                r.ShowConsoleMsg(string.format("  parent_guid=%s\n", parent_guid_check))
                r.ShowConsoleMsg(string.format("  parent_is_container=%s\n", tostring(parent_is_cont)))
                r.ShowConsoleMsg(string.format("  chain_guid=%s\n", tostring(chain_guid)))
                r.ShowConsoleMsg(string.format("  chain_has_parent=%s\n", tostring(chain_has_parent_after)))
                r.ShowConsoleMsg(string.format("  chain_parent_guid=%s\n", chain_parent_guid))
                r.ShowConsoleMsg(string.format("  mixer_pos=%d\n", mixer_pos))
                -- Clean up
                if chain_guid then
                    local orphan_chain = state.track:find_fx_by_guid(chain_guid)
                    if orphan_chain then orphan_chain:delete() end
                end
                if rack_guid then
                    local orphan_rack = state.track:find_fx_by_guid(rack_guid)
                    if orphan_rack then orphan_rack:delete() end
                end
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock("SideFX: Add Rack (failed)", -1)
                return nil
            end

            -- Put parent rack back if we popped it out (like add_device_to_chain does)
            if needs_pop and parent_rack_parent_guid then
                r.ShowConsoleMsg("SideFX: [add_rack] Putting parent rack back into container...\n")
                -- Re-find everything after add
                chain = state.track:find_fx_by_guid(chain_guid)
                parent_rack = state.track:find_fx_by_guid(parent_guid)
                local fresh_parent_container = state.track:find_fx_by_guid(parent_rack_parent_guid)

                r.ShowConsoleMsg(string.format("SideFX: [add_rack] Re-found - chain=%s, parent_rack=%s, parent_container=%s\n",
                    tostring(chain ~= nil), tostring(parent_rack ~= nil), tostring(fresh_parent_container ~= nil)))

                if fresh_parent_container and parent_rack then
                    -- Step 1: Put rack back into chain
                    r.ShowConsoleMsg(string.format("SideFX: [add_rack] Step 1: Putting rack back into chain at position %d\n", parent_rack_pos))
                    local put_back_success = fresh_parent_container:add_fx_to_container(parent_rack, parent_rack_pos)
                    r.ShowConsoleMsg(string.format("SideFX: [add_rack] put_back returned: %s\n", tostring(put_back_success)))

                    if not put_back_success then
                        r.ShowConsoleMsg("SideFX: Failed to put rack back into chain\n")
                    end

                    -- Step 2: If chain was also popped, put chain back into its rack
                    if chain_parent_rack_guid_stored then
                        r.PreventUIRefresh(-1)
                        r.PreventUIRefresh(1)
                        fresh_parent_container = state.track:find_fx_by_guid(parent_rack_parent_guid)  -- Re-find chain
                        local chain_parent_rack = state.track:find_fx_by_guid(chain_parent_rack_guid_stored)

                        if chain_parent_rack and fresh_parent_container then
                            r.ShowConsoleMsg(string.format("SideFX: [add_rack] Step 2: Putting chain back into rack at position %d\n", chain_pos_in_rack_stored))
                            local chain_put_back_success = chain_parent_rack:add_fx_to_container(fresh_parent_container, chain_pos_in_rack_stored)
                            r.ShowConsoleMsg(string.format("SideFX: [add_rack] chain put_back returned: %s\n", tostring(chain_put_back_success)))

                            if not chain_put_back_success then
                                r.ShowConsoleMsg("SideFX: Failed to put chain back into rack\n")
                            end
                        end
                    end

                    -- Refresh and re-find after move back
                    r.PreventUIRefresh(-1)
                    r.PreventUIRefresh(1)
                    parent_rack = state.track:find_fx_by_guid(parent_guid)
                    chain = state.track:find_fx_by_guid(chain_guid)
                    r.ShowConsoleMsg(string.format("SideFX: [add_rack] After put_back - parent_rack=%s, chain=%s\n",
                        tostring(parent_rack ~= nil), tostring(chain ~= nil)))
                else
                    r.ShowConsoleMsg("SideFX: [add_rack] WARNING - Could not put parent rack back!\n")
                end
            end

            -- Set up routing for the chain
            local chain_inside = nil
            if chain_guid then
                chain_inside = state.track:find_fx_by_guid(chain_guid)
            end
            if not chain_inside and parent_rack then
                for child in parent_rack:iter_container_children() do
                    local ok, name = pcall(function() return child:get_name() end)
                    if ok and name == chain_name then
                        chain_inside = child
                        break
                    end
                end
            end

            if not chain_inside then
                r.ShowConsoleMsg("SideFX: Warning - Chain " .. chain_name .. " not found in parent rack R" .. parent_idx .. " after adding\n")
                -- Try to find it by GUID as fallback
                local chain_guid = chain:get_guid()
                if chain_guid then
                    chain_inside = state.track:find_fx_by_guid(chain_guid)
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
            else
                r.ShowConsoleMsg("SideFX: Error - Could not set up routing for chain " .. chain_name .. "\n")
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
        end

        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Rack", -1)

        -- Re-find the rack after it's been moved (reference is stale)
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

    -- Check if rack is nested (inside a chain)
    local rack_parent = rack:get_parent_container()
    local rack_parent_guid = rack_parent and rack_parent:get_guid() or nil
    local needs_pop = false
    local rack_pos_in_parent = 0
    local parent_is_chain = false

    if rack_parent then
        -- Rack is nested - need to pop it out first (like add_device_to_chain does)
        needs_pop = true
        parent_is_chain = fx_utils.is_chain_container(rack_parent)
        
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] Rack is nested, popping out...\n"))
        
        -- Remember rack's position in its container
        local pos = 0
        for child in rack_parent:iter_container_children() do
            if child:get_guid() == rack_guid then
                rack_pos_in_parent = pos
                break
            end
            pos = pos + 1
        end

        -- Pop rack out to track level (may need multiple moves if deeply nested)
        local pop_success = true
        local depth = 0
        local max_depth = 10  -- Safety limit
        while rack:get_parent_container() and depth < max_depth do
            pop_success = rack:move_out_of_container()
            if not pop_success then
                r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] move_out_of_container failed at depth %d\n", depth))
                break
            end
            r.PreventUIRefresh(-1)
            r.PreventUIRefresh(1)
            rack = state.track:find_fx_by_guid(rack_guid)
            if not rack then
                r.ShowConsoleMsg("SideFX: [add_chain_to_rack] Lost rack during pop\n")
                pop_success = false
                break
            end
            depth = depth + 1
        end
        
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] Moved rack out %d levels\n", depth))
        
        if not pop_success or not rack then
            r.ShowConsoleMsg("SideFX: Failed to pop rack out\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
            return nil
        end
        
        -- Verify rack is at track level and is a container
        local rack_has_parent = rack:get_parent_container() ~= nil
        local rack_is_cont = rack:is_container()
        local rack_child_count = rack:get_container_child_count()
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] After pop - has_parent=%s, is_container=%s, child_count=%d\n",
            tostring(rack_has_parent), tostring(rack_is_cont), rack_child_count))
        
        if rack_has_parent then
            r.ShowConsoleMsg("SideFX: [add_chain_to_rack] WARNING: Rack still has parent after pop!\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
            return nil
        end
        
        if not rack_is_cont then
            r.ShowConsoleMsg("SideFX: [add_chain_to_rack] WARNING: Rack is not a container after pop!\n")
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
            return nil
        end
        
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] Rack popped out successfully\n"))
    else
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] Rack is at track level, no pop needed\n"))
    end

    -- Get rack name again (in case it changed)
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
        
        -- Verify rack state before adding
        local rack_child_count_before = rack:get_container_child_count()
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] Before add - rack_child_count=%d, mixer_pos=%d\n",
            rack_child_count_before, mixer_pos))

        local add_success = rack:add_fx_to_container(chain, mixer_pos)
        r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] add_fx_to_container returned: %s\n", tostring(add_success)))
        
        if not add_success then
            local rack_child_count_after = rack:get_container_child_count()
            r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] After failed add - rack_child_count=%d (was %d)\n",
                rack_child_count_after, rack_child_count_before))
        end
        
        if not add_success then
            r.ShowConsoleMsg("SideFX: [add_chain_to_rack] Failed to add chain to rack\n")
        end

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
        -- Mixer slider range: -60 to +12 dB (72 dB range)
        -- Normalized 0dB = (0 - (-60)) / (12 - (-60)) = 60/72 = 0.833...
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

    -- Put rack back if we popped it out (like add_device_to_chain does)
    if needs_pop and rack_parent_guid then
        r.ShowConsoleMsg("SideFX: [add_chain_to_rack] Putting rack back into container...\n")
        -- Re-find everything after add
        rack = state.track:find_fx_by_guid(rack_guid)
        local fresh_parent_container = state.track:find_fx_by_guid(rack_parent_guid)
        
        if fresh_parent_container and rack then
            local put_back_success = fresh_parent_container:add_fx_to_container(rack, rack_pos_in_parent)
            r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] put_back returned: %s\n", tostring(put_back_success)))
            
            -- Refresh and re-find after move back
            r.PreventUIRefresh(-1)
            r.PreventUIRefresh(1)
            rack = state.track:find_fx_by_guid(rack_guid)
            
            if rack then
                -- Verify chain count after put back
                local chain_count_after = fx_utils.count_chains_in_rack(rack)
                r.ShowConsoleMsg(string.format("SideFX: [add_chain_to_rack] Chain count after put_back: %d\n", chain_count_after))
            end
        else
            r.ShowConsoleMsg("SideFX: [add_chain_to_rack] Failed to re-find rack or parent container\n")
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

    -- Move device into chain
    local device_guid = device:get_guid()
    local fresh_chain = state.track:find_fx_by_guid(chain_guid)

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
        fresh_chain = state.track:find_fx_by_guid(chain_guid)
        device = state.track:find_fx_by_guid(device_guid)

        if fresh_chain and device then
            local insert_pos = fresh_chain:get_container_child_count()
            fresh_chain:add_fx_to_container(device, insert_pos)

            fresh_chain = state.track:find_fx_by_guid(chain_guid)
            local fresh_rack = state.track:find_fx_by_guid(rack_guid)

            if fresh_chain and fresh_rack then
                fresh_rack:add_fx_to_container(fresh_chain, chain_pos_in_rack)
            end
        end
    else
        -- Chain is top-level
        local insert_pos = fresh_chain:get_container_child_count()
        fresh_chain:add_fx_to_container(device, insert_pos)
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Device to Chain", -1)

    -- Re-find the device after it's been moved (reference is stale)
    if device_guid then
        return state.track:find_fx_by_guid(device_guid)
    end
    return device
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
