--- Rack Backend Operations
-- Wrapper functions for rack operations with state management and UI refresh.
-- Bridges rack_module (business logic) with UI state and refresh.
-- @module rack_backend
-- @author Nomad Monad
-- @license MIT

local M = {}

-- Dependencies injected by caller
local rack_module
local state_module
local refresh_fx_list

--- Initialize backend with required dependencies
-- @param rack_mod table Rack module
-- @param state_mod table State module
-- @param refresh_fn function Refresh function
function M.init(rack_mod, state_mod, refresh_fn)
    rack_module = rack_mod
    state_module = state_mod
    refresh_fx_list = refresh_fn
end

--------------------------------------------------------------------------------
-- Rack Operations
--------------------------------------------------------------------------------

--- Add a rack to the track
-- @param position number|nil Position to insert rack
-- @return TrackFX|nil Rack FX or nil on failure
function M.add_rack_to_track(position)
    local rack = rack_module.add_rack_to_track(position)
    if rack then
        -- Use expanded_racks for top-level racks (consistent with nested racks)
        local state = state_module.state
        state.expanded_racks[rack:get_guid()] = true
        refresh_fx_list()
        -- Update snapshot after SideFX operation to prevent false warnings
        state_module.capture_fx_chain_snapshot()
    end
    return rack
end

--- Add a chain to a rack
-- @param rack TrackFX Rack container
-- @param plugin table Plugin info {full_name, name}
-- @return TrackFX|nil Chain FX or nil on failure
function M.add_chain_to_rack(rack, plugin)
    -- Get rack info before adding chain (while reference is still valid)
    local rack_guid = rack:get_guid()
    local rack_parent = rack:get_parent_container()
    local is_nested = (rack_parent ~= nil)

    local chain = rack_module.add_chain_to_rack(rack, plugin)
    if chain then
        -- Get chain GUID (stable identifier)
        local chain_guid = chain:get_guid()
        if chain_guid then
            local state = state_module.state
            -- Force the chain to be expanded/selected so user can see it
            if rack_guid then
                -- Ensure rack is expanded (works for both top-level and nested)
                state.expanded_racks[rack_guid] = true
                -- Track which chain is selected (works for both top-level and nested)
                state.expanded_nested_chains[rack_guid] = chain_guid
            end
            state_module.save_expansion_state()
        end
        refresh_fx_list()
        -- Update snapshot after SideFX operation to prevent false warnings
        state_module.capture_fx_chain_snapshot()
    end
    return chain
end

--- Add an empty chain to a rack (no plugin)
-- @param rack TrackFX Rack container
-- @return TrackFX|nil Chain FX or nil on failure
function M.add_empty_chain_to_rack(rack)
    local chain = rack_module.add_empty_chain_to_rack(rack)
    if chain then
        refresh_fx_list()
        -- Update snapshot after SideFX operation to prevent false warnings
        state_module.capture_fx_chain_snapshot()
    end
    return chain
end

--- Add a nested rack to an existing rack
-- @param parent_rack TrackFX Parent rack container
-- @return TrackFX|nil Nested rack FX or nil on failure
function M.add_nested_rack_to_rack(parent_rack)
    -- Get parent rack info before adding nested rack
    local parent_rack_guid = parent_rack:get_guid()
    local parent_rack_parent = parent_rack:get_parent_container()
    local is_parent_nested = (parent_rack_parent ~= nil)

    local nested_rack = rack_module.add_nested_rack_to_rack(parent_rack)
    if nested_rack then
        -- Get nested rack GUID (stable identifier)
        local nested_rack_guid = nested_rack:get_guid()
        if nested_rack_guid then
            local state = state_module.state
            -- Find the chain that contains this nested rack
            local chain_container = nested_rack:get_parent_container()
            local chain_guid = chain_container and chain_container:get_guid()

            -- Force the nested rack to be expanded so user can see it
            state.expanded_racks[nested_rack_guid] = true

            -- Also select the chain that contains the nested rack
            if chain_guid then
                if parent_rack_guid then
                    -- Ensure parent rack is expanded (works for both top-level and nested)
                    state.expanded_racks[parent_rack_guid] = true
                    -- Track which chain is selected (works for both top-level and nested)
                    state.expanded_nested_chains[parent_rack_guid] = chain_guid
                end
            end
            state_module.save_expansion_state()
        end
        refresh_fx_list()
    end
    return nested_rack
end

--- Add a device to a chain
-- @param chain TrackFX Chain container
-- @param plugin table Plugin info {full_name, name}
-- @return TrackFX|nil Device FX or nil on failure
function M.add_device_to_chain(chain, plugin)
    -- Get chain GUID before adding device (GUIDs are stable)
    local chain_guid = chain:get_guid()
    if not chain_guid then
        return nil
    end

    -- Determine expansion state BEFORE adding device (while chain reference is still valid)
    local parent_rack = chain:get_parent_container()
    local is_nested = false
    local rack_guid = nil
    if parent_rack then
        rack_guid = parent_rack:get_guid()
        local rack_parent = parent_rack:get_parent_container()
        is_nested = (rack_parent ~= nil)
    end

    local device = rack_module.add_device_to_chain(chain, plugin)
    if device then
        local state = state_module.state
        -- Force the chain to be expanded/selected so user can see the device that was just added
        if rack_guid then
            -- Ensure rack is expanded (works for both top-level and nested)
            state.expanded_racks[rack_guid] = true
            -- Track which chain is selected (works for both top-level and nested)
            state.expanded_nested_chains[rack_guid] = chain_guid
        end
        state_module.save_expansion_state()
        refresh_fx_list()
    end
    return device
end

--- Add a rack to a chain
-- @param chain TrackFX Chain container
-- @return TrackFX|nil Rack FX or nil on failure
function M.add_rack_to_chain(chain)
    local rack = rack_module.add_rack_to_chain(chain)
    if rack then refresh_fx_list() end
    return rack
end

--- Reorder a chain within a rack
-- @param rack TrackFX Rack container
-- @param chain_guid string GUID of chain to move
-- @param target_chain_guid string GUID of target position
-- @return boolean True if successful
function M.reorder_chain_in_rack(rack, chain_guid, target_chain_guid)
    local result = rack_module.reorder_chain_in_rack(rack, chain_guid, target_chain_guid)
    if result then refresh_fx_list() end
    return result
end

--- Move a chain from one rack to another
-- @param source_rack TrackFX Source rack container
-- @param target_rack TrackFX Target rack container
-- @param chain_guid string Chain GUID to move
-- @param target_chain_guid string|nil Target chain GUID (nil = end)
-- @return boolean True if successful
function M.move_chain_between_racks(source_rack, target_rack, chain_guid, target_chain_guid)
    local result = rack_module.move_chain_between_racks(source_rack, target_rack, chain_guid, target_chain_guid)
    if result then refresh_fx_list() end
    return result
end

--- Renumber chains in a rack after reordering
-- @param rack TrackFX Rack container
function M.renumber_chains_in_rack(rack)
    return rack_module.renumber_chains_in_rack(rack)
end

return M
