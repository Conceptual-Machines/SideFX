--- Unit tests for SideFX state management.
-- Tests state module functionality including nested rack expansion state.
-- @module unit.test_state
-- @author Nomad Monad
-- @license MIT

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local assert = require("assertions")

-- Mock project module first
package.loaded['project'] = {
    new = function()
        return {
            has_selected_tracks = function() return false end,
            get_selected_track = function() return nil end,
        }
    end
}

-- Mock the state module
package.loaded['lib.state'] = nil
local state_module = require("lib.state")

local M = {}

--------------------------------------------------------------------------------
-- Tests: State Initialization
--------------------------------------------------------------------------------

local function test_state_initialization()
    assert.section("State initialization")
    
    local state = state_module.state
    
    assert.not_nil(state, "State should exist")
    assert.is_type("table", state, "State should be a table")
    assert.is_type("table", state.expanded_path, "expanded_path should be a table")
    assert.is_type("table", state.expanded_racks, "expanded_racks should be a table")
end

local function test_expanded_path_independence()
    assert.section("Expanded path independence from nested racks")
    
    local state = state_module.state
    state.expanded_path = {}
    state.expanded_racks = {}
    
    -- Set top-level expansion
    state.expanded_path = { "{rack-1-guid}" }
    
    -- Set nested rack expansion
    state.expanded_racks["{rack-2-guid}"] = true
    
    -- Verify they're independent
    assert.equals(1, #state.expanded_path, "Top-level path should have 1 item")
    assert.truthy(state.expanded_racks["{rack-2-guid}"], "Nested rack should be expanded")
    
    -- Clear top-level
    state.expanded_path = {}
    assert.falsy(state.expanded_racks["{rack-2-guid}"] == nil, "Nested rack state should persist")
    
    -- Actually, nested should still be true, let's fix the assertion
    assert.truthy(state.expanded_racks["{rack-2-guid}"], "Nested rack state should persist after clearing top-level")
end

local function test_multiple_nested_racks_independence()
    assert.section("Multiple nested racks have independent expansion state")
    
    local state = state_module.state
    state.expanded_racks = {}
    
    -- Expand multiple nested racks
    state.expanded_racks["{rack-a}"] = true
    state.expanded_racks["{rack-b}"] = true
    state.expanded_racks["{rack-c}"] = false  -- Explicitly collapsed
    
    -- Verify independence
    assert.truthy(state.expanded_racks["{rack-a}"], "Rack A should be expanded")
    assert.truthy(state.expanded_racks["{rack-b}"], "Rack B should be expanded")
    assert.falsy(state.expanded_racks["{rack-c}"], "Rack C should be collapsed")
    
    -- Collapse one
    state.expanded_racks["{rack-a}"] = nil
    assert.falsy(state.expanded_racks["{rack-a}"], "Rack A should be collapsed")
    assert.truthy(state.expanded_racks["{rack-b}"], "Rack B should still be expanded")
    assert.falsy(state.expanded_racks["{rack-c}"], "Rack C should still be collapsed")
end

local function test_expanded_path_operations()
    assert.section("Expanded path operations")
    
    local state = state_module.state
    state.expanded_path = {}
    
    -- Add to path
    table.insert(state.expanded_path, "{guid-1}")
    assert.equals(1, #state.expanded_path, "Path should have 1 item")
    
    -- Add more
    table.insert(state.expanded_path, "{guid-2}")
    assert.equals(2, #state.expanded_path, "Path should have 2 items")
    
    -- Clear
    state.expanded_path = {}
    assert.equals(0, #state.expanded_path, "Path should be empty after clear")
end

local function test_nested_rack_operations()
    assert.section("Nested rack expansion operations")
    
    local state = state_module.state
    state.expanded_racks = {}
    
    -- Expand a rack
    state.expanded_racks["{test-rack}"] = true
    assert.truthy(state.expanded_racks["{test-rack}"], "Rack should be expanded")
    
    -- Collapse it
    state.expanded_racks["{test-rack}"] = nil
    assert.falsy(state.expanded_racks["{test-rack}"], "Rack should be collapsed")
    
    -- Toggle it
    if state.expanded_racks["{test-rack}"] then
        state.expanded_racks["{test-rack}"] = nil
    else
        state.expanded_racks["{test-rack}"] = true
    end
    assert.truthy(state.expanded_racks["{test-rack}"], "Rack should be expanded after toggle")
end

local function test_state_isolation()
    assert.section("State isolation between different GUIDs")
    
    local state = state_module.state
    state.expanded_path = {}
    state.expanded_racks = {}
    
    -- Set top-level path
    state.expanded_path = { "{top-rack}" }
    
    -- Set nested racks
    state.expanded_racks["{nested-1}"] = true
    state.expanded_racks["{nested-2}"] = true
    
    -- Verify isolation
    assert.equals(1, #state.expanded_path, "Top-level path should be independent")
    assert.equals("{top-rack}", state.expanded_path[1], "Top-level should contain correct GUID")
    
    assert.truthy(state.expanded_racks["{nested-1}"], "Nested 1 should be expanded")
    assert.truthy(state.expanded_racks["{nested-2}"], "Nested 2 should be expanded")
    assert.falsy(state.expanded_racks["{top-rack}"], "Top-level GUID should not appear in nested state")
end

local function test_multiple_top_level_racks_independence()
    assert.section("Multiple top-level racks have independent expansion state")
    
    local state = state_module.state
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
    
    -- Create multiple top-level racks
    local rack1_guid = "{top-rack-1}"
    local rack2_guid = "{top-rack-2}"
    local rack3_guid = "{top-rack-3}"
    
    -- Expand rack1 and rack2
    state.expanded_racks[rack1_guid] = true
    state.expanded_racks[rack2_guid] = true
    
    -- Verify independence
    assert.truthy(state.expanded_racks[rack1_guid], "Rack1 should be expanded")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should be expanded")
    assert.falsy(state.expanded_racks[rack3_guid], "Rack3 should be collapsed")
    
    -- Collapse rack1
    state.expanded_racks[rack1_guid] = nil
    assert.falsy(state.expanded_racks[rack1_guid], "Rack1 should be collapsed")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should still be expanded")
    assert.falsy(state.expanded_racks[rack3_guid], "Rack3 should still be collapsed")
    
    -- Expand rack3
    state.expanded_racks[rack3_guid] = true
    assert.falsy(state.expanded_racks[rack1_guid], "Rack1 should still be collapsed")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should still be expanded")
    assert.truthy(state.expanded_racks[rack3_guid], "Rack3 should be expanded")
end

local function test_top_level_rack_chain_selection_independence()
    assert.section("Multiple top-level racks have independent chain selection")
    
    local state = state_module.state
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
    
    -- Create multiple top-level racks with chains
    local rack1_guid = "{top-rack-1}"
    local rack2_guid = "{top-rack-2}"
    local chain1_guid = "{chain-1}"
    local chain2_guid = "{chain-2}"
    
    -- Expand both racks
    state.expanded_racks[rack1_guid] = true
    state.expanded_racks[rack2_guid] = true
    
    -- Select chain in rack1
    state.expanded_nested_chains[rack1_guid] = chain1_guid
    assert.equals(chain1_guid, state.expanded_nested_chains[rack1_guid], "Rack1 should have chain1 selected")
    assert.falsy(state.expanded_nested_chains[rack2_guid], "Rack2 should have no chain selected")
    
    -- Select chain in rack2
    state.expanded_nested_chains[rack2_guid] = chain2_guid
    assert.equals(chain1_guid, state.expanded_nested_chains[rack1_guid], "Rack1 should still have chain1 selected")
    assert.equals(chain2_guid, state.expanded_nested_chains[rack2_guid], "Rack2 should have chain2 selected")
    
    -- Clear rack1's chain selection
    state.expanded_nested_chains[rack1_guid] = nil
    assert.falsy(state.expanded_nested_chains[rack1_guid], "Rack1 should have no chain selected")
    assert.equals(chain2_guid, state.expanded_nested_chains[rack2_guid], "Rack2 should still have chain2 selected")
end

local function test_top_level_and_nested_rack_coexistence()
    assert.section("Top-level and nested racks can coexist independently")
    
    local state = state_module.state
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
    
    -- Create top-level and nested racks
    local top_rack_guid = "{top-rack}"
    local nested_rack_guid = "{nested-rack}"
    
    -- Expand both
    state.expanded_racks[top_rack_guid] = true
    state.expanded_racks[nested_rack_guid] = true
    
    -- Verify both are expanded
    assert.truthy(state.expanded_racks[top_rack_guid], "Top-level rack should be expanded")
    assert.truthy(state.expanded_racks[nested_rack_guid], "Nested rack should be expanded")
    
    -- Collapse top-level
    state.expanded_racks[top_rack_guid] = nil
    assert.falsy(state.expanded_racks[top_rack_guid], "Top-level rack should be collapsed")
    assert.truthy(state.expanded_racks[nested_rack_guid], "Nested rack should still be expanded")
    
    -- Collapse nested
    state.expanded_racks[nested_rack_guid] = nil
    assert.falsy(state.expanded_racks[top_rack_guid], "Top-level rack should still be collapsed")
    assert.falsy(state.expanded_racks[nested_rack_guid], "Nested rack should be collapsed")
end

local function test_save_expansion_state_with_deleted_track()
    assert.section("save_expansion_state handles deleted tracks gracefully")
    
    local state = state_module.state
    
    -- Create a mock track that will fail when get_guid is called
    local mock_track = {
        get_guid = function()
            error("Track deleted")
        end
    }
    
    state.track = mock_track
    state.expanded_racks = {["{rack-1}"] = true}
    state.expanded_nested_chains = {["{rack-1}"] = "{chain-1}"}
    
    -- Should not error, should clear state.track
    local ok, err = pcall(function()
        state_module.save_expansion_state()
    end)
    
    assert.truthy(ok, "save_expansion_state should not error on deleted track")
    assert.is_nil(state.track, "state.track should be cleared when track is invalid")
end

local function test_refresh_fx_list_with_deleted_track()
    assert.section("refresh_fx_list handles deleted tracks gracefully")
    
    local state = state_module.state
    
    -- Create a mock track that will fail when accessed
    local mock_track = {
        iter_track_fx_chain = function()
            error("Track deleted")
        end
    }
    
    state.track = mock_track
    state.top_level_fx = {{}, {}}  -- Some fake FX objects
    
    -- Should not error, should clear state
    local ok, err = pcall(function()
        state_module.refresh_fx_list()
    end)
    
    assert.truthy(ok, "refresh_fx_list should not error on deleted track")
    assert.is_nil(state.track, "state.track should be cleared")
    assert.equals(0, #state.top_level_fx, "top_level_fx should be cleared")
    assert.equals(0, state.last_fx_count, "last_fx_count should be reset")
end

local function test_check_fx_changes_with_deleted_track()
    assert.section("check_fx_changes handles deleted tracks gracefully")
    
    local state = state_module.state
    
    -- Create a mock track that will fail when accessed
    local mock_track = {
        get_track_fx_count = function()
            error("Track deleted")
        end
    }
    
    state.track = mock_track
    state.top_level_fx = {{}, {}}
    state.last_fx_count = 5
    
    -- Should not error, should clear state
    local ok, err = pcall(function()
        state_module.check_fx_changes()
    end)
    
    assert.truthy(ok, "check_fx_changes should not error on deleted track")
    assert.is_nil(state.track, "state.track should be cleared")
    assert.equals(0, #state.top_level_fx, "top_level_fx should be cleared")
    assert.equals(0, state.last_fx_count, "last_fx_count should be reset")
end

local function test_check_fx_changes_with_nil_track()
    assert.section("check_fx_changes handles nil track gracefully")
    
    local state = state_module.state
    
    state.track = nil
    state.top_level_fx = {{}, {}}
    state.last_fx_count = 5
    
    -- Should not error, should clear FX list
    local ok, err = pcall(function()
        state_module.check_fx_changes()
    end)
    
    assert.truthy(ok, "check_fx_changes should not error with nil track")
    assert.equals(0, #state.top_level_fx, "top_level_fx should be cleared")
    assert.equals(0, state.last_fx_count, "last_fx_count should be reset")
end

--------------------------------------------------------------------------------
-- Test Runner
--------------------------------------------------------------------------------

function M.run()
    test_state_initialization()
    test_expanded_path_independence()
    test_multiple_nested_racks_independence()
    test_expanded_path_operations()
    test_nested_rack_operations()
    test_state_isolation()
    test_multiple_top_level_racks_independence()
    test_top_level_rack_chain_selection_independence()
    test_top_level_and_nested_rack_coexistence()
    test_save_expansion_state_with_deleted_track()
    test_refresh_fx_list_with_deleted_track()
    test_check_fx_changes_with_deleted_track()
    test_check_fx_changes_with_nil_track()
end

return M

