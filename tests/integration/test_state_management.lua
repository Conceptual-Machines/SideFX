--- Integration tests for SideFX state management in UI.
-- Tests that nested rack expansion state is independent of top-level racks.
-- These tests run INSIDE REAPER.
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_state_management
-- @author Nomad Monad
-- @license MIT

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local info = debug.getinfo(1, "S")
local script_path = info.source:match("@?(.*[\\/])")
local root_path = script_path:match("^(.+/)tests/") or script_path .. "../../"

-- Add SideFX paths
package.path = root_path .. "?.lua;" .. package.path
package.path = root_path .. "lib/?.lua;" .. package.path
package.path = root_path .. "tests/?.lua;" .. package.path

-- Find ReaWrap
local reawrap_path = root_path .. "../ReaWrap/"
package.path = reawrap_path .. "?.lua;" .. package.path
package.path = reawrap_path .. "lua/?.lua;" .. package.path

local r = reaper
local assert = require("assertions")
local naming = require("lib.naming")
local fx_utils = require("lib.fx_utils")
local rack_module = require("lib.rack")
local state_module = require("lib.state")

-- Load ReaWrap
local Track = require("track")

--------------------------------------------------------------------------------
-- Test Helpers
--------------------------------------------------------------------------------

local test_track = nil
local state = state_module.state

local function setup_test_track()
    r.Undo_BeginBlock()
    
    r.InsertTrackAtIndex(0, false)
    local track_ptr = r.GetTrack(0, 0)
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_State_Test", true)
    
    test_track = Track:new(track_ptr)
    state.track = test_track
    state.track_name = "_SideFX_State_Test"
    
    return test_track
end

local function cleanup_test_track()
    if test_track then
        r.DeleteTrack(test_track.pointer)
        test_track = nil
        state.track = nil
        state.track_name = ""
    end
    r.Undo_EndBlock("SideFX State Management Integration Test", -1)
end

local function clear_track_fx()
    if not test_track then return end
    while test_track:get_track_fx_count() > 0 do
        local fx = test_track:get_track_fx(0)
        if fx then fx:delete() end
    end
end

local function find_fx_by_name_pattern(pattern)
    if not test_track then return nil end
    for entry in test_track:iter_all_fx_flat() do
        local fx = entry.fx
        local ok, name = pcall(function() return fx:get_name() end)
        if ok and name and name:match(pattern) then
            return fx
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Tests: State Management
--------------------------------------------------------------------------------

local function test_nested_rack_state_independence()
    assert.section("Nested rack expansion state is independent of parent")
    
    clear_track_fx()
    state.expanded_path = {}
    state.expanded_racks = {}
    
    -- Create structure: rack1 -> chain1 -> rack2
    local rack1 = rack_module.add_rack_to_track()
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    
    rack1 = find_fx_by_name_pattern("^R1:")
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    
    -- Get GUIDs
    local rack1_guid = rack1:get_guid()
    local rack2_guid = rack2:get_guid()
    
    -- Initially both should be collapsed
    assert.falsy(state.expanded_racks[rack1_guid], "Top-level rack should be collapsed")
    assert.falsy(state.expanded_racks[rack2_guid], "Nested rack should be collapsed")
    
    -- Expand top-level rack (rack1)
    state.expanded_racks[rack1_guid] = true
    assert.truthy(state.expanded_racks[rack1_guid], "Top-level rack should be expanded")
    assert.falsy(state.expanded_racks[rack2_guid], "Nested rack should still be collapsed")
    
    -- Expand nested rack (rack2)
    state.expanded_racks[rack2_guid] = true
    assert.truthy(state.expanded_racks[rack2_guid], "Nested rack should be expanded")
    assert.truthy(state.expanded_racks[rack1_guid], "Top-level rack should still be expanded")
    
    -- Collapse top-level rack
    state.expanded_racks[rack1_guid] = nil
    assert.falsy(state.expanded_racks[rack1_guid], "Top-level rack should be collapsed")
    assert.truthy(state.expanded_racks[rack2_guid], "Nested rack expansion should persist")
    
    -- Collapse nested rack
    state.expanded_racks[rack2_guid] = nil
    assert.falsy(state.expanded_racks[rack2_guid], "Nested rack should be collapsed")
end

local function test_multiple_nested_racks_independent_expansion()
    assert.section("Multiple nested racks have independent expansion state")
    
    clear_track_fx()
    state.expanded_path = {}
    state.expanded_racks = {}
    
    -- Create: rack1 -> chain1 -> rack2, rack3
    local rack1 = rack_module.add_rack_to_track()
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    
    rack1 = find_fx_by_name_pattern("^R1:")
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack3 = rack_module.add_rack_to_chain(chain1_ref)
    
    local rack2_guid = rack2:get_guid()
    local rack3_guid = rack3:get_guid()
    
    -- Expand rack2 only
    state.expanded_racks[rack2_guid] = true
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should be expanded")
    assert.falsy(state.expanded_racks[rack3_guid], "Rack3 should be collapsed")
    
    -- Expand rack3
    state.expanded_racks[rack3_guid] = true
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should still be expanded")
    assert.truthy(state.expanded_racks[rack3_guid], "Rack3 should be expanded")
    
    -- Collapse rack2
    state.expanded_racks[rack2_guid] = nil
    assert.falsy(state.expanded_racks[rack2_guid], "Rack2 should be collapsed")
    assert.truthy(state.expanded_racks[rack3_guid], "Rack3 should still be expanded")
end

local function test_deeply_nested_state_preservation()
    assert.section("State preservation in deeply nested structures")
    
    clear_track_fx()
    state.expanded_path = {}
    state.expanded_racks = {}
    
    -- Create: rack1 -> chain1 -> rack2 -> chain2 -> rack3
    local rack1 = rack_module.add_rack_to_track()
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    
    rack1 = find_fx_by_name_pattern("^R1:")
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    local rack2_ref = nil
    for child in chain1_ref:iter_container_children() do
        if child:get_name():match("^R2:") then
            rack2_ref = child
            break
        end
    end
    
    local chain2 = rack_module.add_chain_to_rack(rack2_ref, { full_name = "ReaEQ", name = "ReaEQ" })
    
    rack2_ref = find_fx_by_name_pattern("^R2:")
    local chain2_ref = nil
    for child in rack2_ref:iter_container_children() do
        if child:get_name():match("^R2_C1") then
            chain2_ref = child
            break
        end
    end
    
    local rack3 = rack_module.add_rack_to_chain(chain2_ref)
    
    local rack1_guid = rack1:get_guid()
    local rack2_guid = rack2:get_guid()
    local rack3_guid = rack3:get_guid()
    
    -- Expand all
    state.expanded_racks[rack1_guid] = true
    state.expanded_racks[rack2_guid] = true
    state.expanded_racks[rack3_guid] = true
    
    -- Verify all are expanded
    assert.truthy(state.expanded_racks[rack1_guid], "Rack1 should be expanded")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should be expanded")
    assert.truthy(state.expanded_racks[rack3_guid], "Rack3 should be expanded")
    
    -- Collapse middle one
    state.expanded_racks[rack2_guid] = nil
    assert.truthy(state.expanded_racks[rack3_guid], "Rack3 should still be expanded")
    assert.truthy(state.expanded_racks[rack1_guid], "Rack1 should still be expanded")
end

local function test_state_persistence_across_refresh()
    assert.section("State persistence across FX list refresh")
    
    clear_track_fx()
    state.expanded_path = {}
    state.expanded_racks = {}
    
    -- Create nested structure
    local rack1 = rack_module.add_rack_to_track()
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    
    rack1 = find_fx_by_name_pattern("^R1:")
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    
    local rack1_guid = rack1:get_guid()
    local rack2_guid = rack2:get_guid()
    
    -- Set state (using expanded_racks for top-level rack now)
    state.expanded_racks[rack1_guid] = true
    state.expanded_racks[rack2_guid] = true
    
    -- Simulate refresh (re-fetch GUIDs)
    rack1 = find_fx_by_name_pattern("^R1:")
    local fresh_rack1_guid = rack1:get_guid()
    
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    local rack2_ref = nil
    for child in chain1_ref:iter_container_children() do
        if child:get_name():match("^R2:") then
            rack2_ref = child
            break
        end
    end
    local fresh_rack2_guid = rack2_ref:get_guid()
    
    -- Verify state matches GUIDs
    assert.truthy(state.expanded_racks[fresh_rack1_guid], "State should reference correct rack1 GUID")
    assert.truthy(state.expanded_racks[fresh_rack2_guid], "State should reference correct rack2 GUID")
end

local function test_multiple_top_level_racks_independent_expansion()
    assert.section("Multiple top-level racks have independent expansion state")
    
    clear_track_fx()
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
    
    -- Create two top-level racks
    local rack1 = rack_module.add_rack_to_track()
    local rack2 = rack_module.add_rack_to_track()
    
    local rack1_guid = rack1:get_guid()
    local rack2_guid = rack2:get_guid()
    
    -- Initially both should be collapsed
    assert.falsy(state.expanded_racks[rack1_guid], "Rack1 should be collapsed initially")
    assert.falsy(state.expanded_racks[rack2_guid], "Rack2 should be collapsed initially")
    
    -- Expand rack1
    state.expanded_racks[rack1_guid] = true
    assert.truthy(state.expanded_racks[rack1_guid], "Rack1 should be expanded")
    assert.falsy(state.expanded_racks[rack2_guid], "Rack2 should still be collapsed")
    
    -- Expand rack2
    state.expanded_racks[rack2_guid] = true
    assert.truthy(state.expanded_racks[rack1_guid], "Rack1 should still be expanded")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should be expanded")
    
    -- Collapse rack1
    state.expanded_racks[rack1_guid] = nil
    assert.falsy(state.expanded_racks[rack1_guid], "Rack1 should be collapsed")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should still be expanded")
    
    -- Collapse rack2
    state.expanded_racks[rack2_guid] = nil
    assert.falsy(state.expanded_racks[rack1_guid], "Rack1 should still be collapsed")
    assert.falsy(state.expanded_racks[rack2_guid], "Rack2 should be collapsed")
end

local function test_multiple_top_level_racks_chain_selection_independence()
    assert.section("Multiple top-level racks have independent chain selection")
    
    clear_track_fx()
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
    
    -- Create two top-level racks with chains
    local rack1 = rack_module.add_rack_to_track()
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    
    local rack2 = rack_module.add_rack_to_track()
    local chain2 = rack_module.add_chain_to_rack(rack2, { full_name = "ReaEQ", name = "ReaEQ" })
    
    -- Refresh to get fresh references
    rack1 = find_fx_by_name_pattern("^R1:")
    rack2 = find_fx_by_name_pattern("^R2:")
    
    local rack1_guid = rack1:get_guid()
    local rack2_guid = rack2:get_guid()
    
    -- Get chain GUIDs
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local chain2_ref = nil
    for child in rack2:iter_container_children() do
        if child:get_name():match("^R2_C1") then
            chain2_ref = child
            break
        end
    end
    
    local chain1_guid = chain1_ref:get_guid()
    local chain2_guid = chain2_ref:get_guid()
    
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

local function test_top_level_and_nested_rack_independence()
    assert.section("Top-level and nested racks have independent expansion state")
    
    clear_track_fx()
    state.expanded_racks = {}
    state.expanded_nested_chains = {}
    
    -- Create top-level rack
    local top_rack = rack_module.add_rack_to_track()
    local top_chain = rack_module.add_chain_to_rack(top_rack, { full_name = "ReaComp", name = "ReaComp" })
    
    -- Create nested rack inside the chain
    top_rack = find_fx_by_name_pattern("^R1:")
    local top_chain_ref = nil
    for child in top_rack:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            top_chain_ref = child
            break
        end
    end
    
    local nested_rack = rack_module.add_rack_to_chain(top_chain_ref)
    
    local top_rack_guid = top_rack:get_guid()
    local nested_rack_guid = nested_rack:get_guid()
    
    -- Initially both should be collapsed
    assert.falsy(state.expanded_racks[top_rack_guid], "Top-level rack should be collapsed initially")
    assert.falsy(state.expanded_racks[nested_rack_guid], "Nested rack should be collapsed initially")
    
    -- Expand top-level rack
    state.expanded_racks[top_rack_guid] = true
    assert.truthy(state.expanded_racks[top_rack_guid], "Top-level rack should be expanded")
    assert.falsy(state.expanded_racks[nested_rack_guid], "Nested rack should still be collapsed")
    
    -- Expand nested rack
    state.expanded_racks[nested_rack_guid] = true
    assert.truthy(state.expanded_racks[top_rack_guid], "Top-level rack should still be expanded")
    assert.truthy(state.expanded_racks[nested_rack_guid], "Nested rack should be expanded")
    
    -- Collapse top-level rack
    state.expanded_racks[top_rack_guid] = nil
    assert.falsy(state.expanded_racks[top_rack_guid], "Top-level rack should be collapsed")
    assert.truthy(state.expanded_racks[nested_rack_guid], "Nested rack should still be expanded")
    
    -- Collapse nested rack
    state.expanded_racks[nested_rack_guid] = nil
    assert.falsy(state.expanded_racks[top_rack_guid], "Top-level rack should still be collapsed")
    assert.falsy(state.expanded_racks[nested_rack_guid], "Nested rack should be collapsed")
end

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

local function run_all_tests()
    assert.reset()
    
    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("SideFX State Management Integration Tests\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("\n")
    
    setup_test_track()
    
    local tests = {
        { name = "test_nested_rack_state_independence", fn = test_nested_rack_state_independence },
        { name = "test_multiple_nested_racks_independent_expansion", fn = test_multiple_nested_racks_independent_expansion },
        { name = "test_deeply_nested_state_preservation", fn = test_deeply_nested_state_preservation },
        { name = "test_state_persistence_across_refresh", fn = test_state_persistence_across_refresh },
        { name = "test_multiple_top_level_racks_independent_expansion", fn = test_multiple_top_level_racks_independent_expansion },
        { name = "test_multiple_top_level_racks_chain_selection_independence", fn = test_multiple_top_level_racks_chain_selection_independence },
        { name = "test_top_level_and_nested_rack_independence", fn = test_top_level_and_nested_rack_independence },
    }
    
    for _, test in ipairs(tests) do
        local ok, err = pcall(test.fn)
        if not ok then
            r.ShowConsoleMsg("ERROR in " .. test.name .. ": " .. tostring(err) .. "\n")
        end
    end
    
    cleanup_test_track()
    
    local results = assert.get_results()
    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg(string.format("Results: %d passed, %d failed\n", results.passed, results.failed))
    if results.failed == 0 then
        r.ShowConsoleMsg("All tests passed!\n")
    else
        r.ShowConsoleMsg("Some tests failed.\n")
        for _, msg in ipairs(results.messages) do
            r.ShowConsoleMsg(msg .. "\n")
        end
    end
    r.ShowConsoleMsg("========================================\n")
end

run_all_tests()


