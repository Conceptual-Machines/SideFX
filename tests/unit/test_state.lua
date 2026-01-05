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
end

return M

