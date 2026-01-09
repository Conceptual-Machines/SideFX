--- Unit tests for SideFX state management (LuaUnit version).
-- Tests state module functionality including nested rack expansion state.
-- @module unit.test_state_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")

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
package.loaded['lib.core.state'] = nil
local state_module = require("lib.core.state")

TestState = {}

function TestState:setUp()
    -- Reset state before each test
    local state = state_module.state
    state.expanded_path = {}
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
end

function TestState:test_state_initialization()
    local state = state_module.state

    luaunit.assertNotIsNil(state, "State should exist")
    luaunit.assertEquals("table", type(state), "State should be a table")
    luaunit.assertEquals("table", type(state.expanded_path), "expanded_path should be a table")
    luaunit.assertEquals("table", type(state.expanded_racks), "expanded_racks should be a table")
end

function TestState:test_expanded_path_independence()
    local state = state_module.state
    state.expanded_path = {}
    state.expanded_racks = {}

    -- Set top-level expansion
    state.expanded_path = { "{rack-1-guid}" }

    -- Set nested rack expansion
    state.expanded_racks["{rack-2-guid}"] = true

    -- Verify they're independent
    luaunit.assertEquals(1, #state.expanded_path, "Top-level path should have 1 item")
    luaunit.assertTrue(state.expanded_racks["{rack-2-guid}"], "Nested rack should be expanded")

    -- Clear top-level
    state.expanded_path = {}
    luaunit.assertTrue(state.expanded_racks["{rack-2-guid}"], "Nested rack state should persist after clearing top-level")
end

function TestState:test_multiple_nested_racks_independence()
    local state = state_module.state
    state.expanded_racks = {}

    -- Expand multiple nested racks
    state.expanded_racks["{rack-a}"] = true
    state.expanded_racks["{rack-b}"] = true
    state.expanded_racks["{rack-c}"] = false  -- Explicitly collapsed

    -- Verify independence
    luaunit.assertTrue(state.expanded_racks["{rack-a}"], "Rack A should be expanded")
    luaunit.assertTrue(state.expanded_racks["{rack-b}"], "Rack B should be expanded")
    luaunit.assertEquals(false, state.expanded_racks["{rack-c}"], "Rack C should be collapsed")

    -- Collapse one
    state.expanded_racks["{rack-a}"] = nil
    luaunit.assertIsNil(state.expanded_racks["{rack-a}"], "Rack A should be collapsed")
    luaunit.assertTrue(state.expanded_racks["{rack-b}"], "Rack B should still be expanded")
    luaunit.assertEquals(false, state.expanded_racks["{rack-c}"], "Rack C should still be collapsed")
end

function TestState:test_expanded_path_operations()
    local state = state_module.state
    state.expanded_path = {}

    -- Add to path
    table.insert(state.expanded_path, "{guid-1}")
    luaunit.assertEquals(1, #state.expanded_path, "Path should have 1 item")

    -- Add more
    table.insert(state.expanded_path, "{guid-2}")
    luaunit.assertEquals(2, #state.expanded_path, "Path should have 2 items")

    -- Clear
    state.expanded_path = {}
    luaunit.assertEquals(0, #state.expanded_path, "Path should be empty after clear")
end

function TestState:test_nested_rack_operations()
    local state = state_module.state
    state.expanded_racks = {}

    -- Expand a rack
    state.expanded_racks["{test-rack}"] = true
    luaunit.assertTrue(state.expanded_racks["{test-rack}"], "Rack should be expanded")

    -- Collapse it
    state.expanded_racks["{test-rack}"] = nil
    luaunit.assertIsNil(state.expanded_racks["{test-rack}"], "Rack should be collapsed")

    -- Toggle it
    if state.expanded_racks["{test-rack}"] then
        state.expanded_racks["{test-rack}"] = nil
    else
        state.expanded_racks["{test-rack}"] = true
    end
    luaunit.assertTrue(state.expanded_racks["{test-rack}"], "Rack should be expanded after toggle")
end

function TestState:test_state_isolation()
    local state = state_module.state
    state.expanded_path = {}
    state.expanded_racks = {}

    -- Set top-level path
    state.expanded_path = { "{top-rack}" }

    -- Set nested racks
    state.expanded_racks["{nested-1}"] = true
    state.expanded_racks["{nested-2}"] = true

    -- Verify isolation
    luaunit.assertEquals(1, #state.expanded_path, "Top-level path should be independent")
    luaunit.assertEquals("{top-rack}", state.expanded_path[1], "Top-level should contain correct GUID")

    luaunit.assertTrue(state.expanded_racks["{nested-1}"], "Nested 1 should be expanded")
    luaunit.assertTrue(state.expanded_racks["{nested-2}"], "Nested 2 should be expanded")
    luaunit.assertIsNil(state.expanded_racks["{top-rack}"], "Top-level GUID should not appear in nested state")
end

function TestState:test_multiple_top_level_racks_independence()
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
    luaunit.assertTrue(state.expanded_racks[rack1_guid], "Rack1 should be expanded")
    luaunit.assertTrue(state.expanded_racks[rack2_guid], "Rack2 should be expanded")
    luaunit.assertIsNil(state.expanded_racks[rack3_guid], "Rack3 should be collapsed")

    -- Collapse rack1
    state.expanded_racks[rack1_guid] = nil
    luaunit.assertIsNil(state.expanded_racks[rack1_guid], "Rack1 should be collapsed")
    luaunit.assertTrue(state.expanded_racks[rack2_guid], "Rack2 should still be expanded")
    luaunit.assertIsNil(state.expanded_racks[rack3_guid], "Rack3 should still be collapsed")

    -- Expand rack3
    state.expanded_racks[rack3_guid] = true
    luaunit.assertIsNil(state.expanded_racks[rack1_guid], "Rack1 should still be collapsed")
    luaunit.assertTrue(state.expanded_racks[rack2_guid], "Rack2 should still be expanded")
    luaunit.assertTrue(state.expanded_racks[rack3_guid], "Rack3 should be expanded")
end

function TestState:test_top_level_rack_chain_selection_independence()
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
    luaunit.assertEquals(chain1_guid, state.expanded_nested_chains[rack1_guid], "Rack1 should have chain1 selected")
    luaunit.assertIsNil(state.expanded_nested_chains[rack2_guid], "Rack2 should have no chain selected")

    -- Select chain in rack2
    state.expanded_nested_chains[rack2_guid] = chain2_guid
    luaunit.assertEquals(chain1_guid, state.expanded_nested_chains[rack1_guid], "Rack1 should still have chain1 selected")
    luaunit.assertEquals(chain2_guid, state.expanded_nested_chains[rack2_guid], "Rack2 should have chain2 selected")

    -- Clear rack1's chain selection
    state.expanded_nested_chains[rack1_guid] = nil
    luaunit.assertIsNil(state.expanded_nested_chains[rack1_guid], "Rack1 should have no chain selected")
    luaunit.assertEquals(chain2_guid, state.expanded_nested_chains[rack2_guid], "Rack2 should still have chain2 selected")
end

function TestState:test_top_level_and_nested_rack_coexistence()
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
    luaunit.assertTrue(state.expanded_racks[top_rack_guid], "Top-level rack should be expanded")
    luaunit.assertTrue(state.expanded_racks[nested_rack_guid], "Nested rack should be expanded")

    -- Collapse top-level
    state.expanded_racks[top_rack_guid] = nil
    luaunit.assertIsNil(state.expanded_racks[top_rack_guid], "Top-level rack should be collapsed")
    luaunit.assertTrue(state.expanded_racks[nested_rack_guid], "Nested rack should still be expanded")

    -- Collapse nested
    state.expanded_racks[nested_rack_guid] = nil
    luaunit.assertIsNil(state.expanded_racks[top_rack_guid], "Top-level rack should still be collapsed")
    luaunit.assertIsNil(state.expanded_racks[nested_rack_guid], "Nested rack should be collapsed")
end

function TestState:test_save_expansion_state_with_deleted_track()
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

    luaunit.assertTrue(ok, "save_expansion_state should not error on deleted track")
    luaunit.assertIsNil(state.track, "state.track should be cleared when track is invalid")
end

function TestState:test_refresh_fx_list_with_deleted_track()
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

    luaunit.assertTrue(ok, "refresh_fx_list should not error on deleted track")
    luaunit.assertIsNil(state.track, "state.track should be cleared")
    luaunit.assertEquals(0, #state.top_level_fx, "top_level_fx should be cleared")
    luaunit.assertEquals(0, state.last_fx_count, "last_fx_count should be reset")
end

function TestState:test_check_fx_changes_with_deleted_track()
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

    luaunit.assertTrue(ok, "check_fx_changes should not error on deleted track")
    luaunit.assertIsNil(state.track, "state.track should be cleared")
    luaunit.assertEquals(0, #state.top_level_fx, "top_level_fx should be cleared")
    luaunit.assertEquals(0, state.last_fx_count, "last_fx_count should be reset")
end

function TestState:test_check_fx_changes_with_nil_track()
    local state = state_module.state

    state.track = nil
    state.top_level_fx = {{}, {}}
    state.last_fx_count = 5

    -- Should not error, should clear FX list
    local ok, err = pcall(function()
        state_module.check_fx_changes()
    end)

    luaunit.assertTrue(ok, "check_fx_changes should not error with nil track")
    luaunit.assertEquals(0, #state.top_level_fx, "top_level_fx should be cleared")
    luaunit.assertEquals(0, state.last_fx_count, "last_fx_count should be reset")
end
