--- Integration tests for SideFX edge cases and weird scenarios.
-- Tests unusual scenarios, error recovery, and boundary conditions.
-- These tests run INSIDE REAPER.
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_edge_cases
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
    
    -- Insert a new test track
    r.InsertTrackAtIndex(0, false)
    local track_ptr = r.GetTrack(0, 0)
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_EdgeCase_Test", true)
    
    test_track = Track:new(track_ptr)
    
    -- Set up state for rack module
    state.track = test_track
    state.track_name = "_SideFX_EdgeCase_Test"
    
    return test_track
end

local function cleanup_test_track()
    if test_track then
        r.DeleteTrack(test_track.pointer)
        test_track = nil
        state.track = nil
        state.track_name = ""
    end
    r.Undo_EndBlock("SideFX Edge Case Integration Test", -1)
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

local function count_all_containers()
    local count = 0
    for entry in test_track:iter_all_fx_flat() do
        local fx = entry.fx
        if fx:is_container() then
            count = count + 1
        end
    end
    return count
end

local function verify_hierarchy_integrity()
    -- Verify no circular references and all parent-child relationships are consistent
    local visited = {}
    
    local function check_container(fx_data, depth, path)
        path = path or {}
        
        if depth > 20 then
            return false, "Maximum depth exceeded (circular reference?)"
        end
        
        if visited[fx_data] then
            return false, "Circular reference detected"
        end
        visited[fx_data] = true
        
        table.insert(path, fx_data.guid or "unknown")
        
        if fx_data.children then
            for _, child_data in ipairs(fx_data.children) do
                if child_data.parent ~= fx_data then
                    return false, "Parent-child mismatch"
                end
                local ok, err = check_container(child_data, depth + 1, path)
                if not ok then
                    return false, err .. " in path: " .. table.concat(path, " -> ")
                end
            end
        end
        
        table.remove(path)
        return true
    end
    
    for entry in test_track:iter_all_fx_flat() do
        if entry.depth == 0 then
            local fx = entry.fx
            local ok, err = pcall(function()
                local fx_data = fx._data or {}
                return check_container(fx_data, 0, {})
            end)
            if not ok then
                return false, "Error checking hierarchy: " .. tostring(err)
            end
        end
    end
    
    return true
end

--------------------------------------------------------------------------------
-- Edge Case Tests
--------------------------------------------------------------------------------

local function test_add_device_to_empty_nested_rack()
    assert.section("Add device to empty nested rack (regression test)")
    
    clear_track_fx()
    
    -- Create outer rack
    local rack1 = rack_module.add_rack_to_track()
    assert.not_nil(rack1, "Outer rack should be created")
    
    -- Create chain in rack1
    local plugin1 = { full_name = "ReaComp", name = "ReaComp" }
    local chain1 = rack_module.add_chain_to_rack(rack1, plugin1)
    assert.not_nil(chain1, "Chain should be created")
    
    -- Re-fetch to get fresh references
    rack1 = find_fx_by_name_pattern("^R1:")
    assert.not_nil(rack1, "Should find rack1")
    
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    assert.not_nil(chain1_ref, "Should find chain1")
    
    -- Add empty rack to chain1
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    assert.not_nil(rack2, "Nested rack should be created")
    
    -- Verify rack2 is in chain1
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
    assert.not_nil(rack2_ref, "Rack2 should be in chain1")
    
    -- Verify chain1 is still in rack1 (critical!)
    local chain1_parent = chain1_ref:get_parent_container()
    assert.not_nil(chain1_parent, "Chain1 should have parent")
    assert.equals(rack1:get_guid(), chain1_parent:get_guid(), "Chain1's parent should still be rack1")
    
    -- Now add a device to rack2's chain (this was causing the pop-out bug)
    local rack2_chain = nil
    for child in rack2_ref:iter_container_children() do
        if child:get_name():match("^R2_C1") then
            rack2_chain = child
            break
        end
    end
    
    if rack2_chain then
        local plugin2 = { full_name = "ReaEQ", name = "ReaEQ" }
        local device = rack_module.add_device_to_chain(rack2_chain, plugin2)
        assert.not_nil(device, "Device should be added")
        
        -- CRITICAL: Verify the entire hierarchy is still intact
        rack1 = find_fx_by_name_pattern("^R1:")
        chain1_ref = nil
        for child in rack1:iter_container_children() do
            if child:get_name():match("^R1_C1") then
                chain1_ref = child
                break
            end
        end
        
        local chain1_parent_after = chain1_ref:get_parent_container()
        assert.not_nil(chain1_parent_after, "Chain1 should still have parent after adding device")
        assert.equals(rack1:get_guid(), chain1_parent_after:get_guid(), "Chain1 should NOT pop out - parent should still be rack1")
        
        -- Verify rack2 is still in chain1
        local rack2_found = false
        for child in chain1_ref:iter_container_children() do
            if child:get_name():match("^R2:") then
                rack2_found = true
                break
            end
        end
        assert.truthy(rack2_found, "Rack2 should still be in chain1 after adding device")
    end
    
    -- Verify overall hierarchy integrity
    local ok, err = verify_hierarchy_integrity()
    assert.truthy(ok, "Hierarchy integrity check: " .. tostring(err))
end

local function test_deep_nesting_5_levels()
    assert.section("Deep nesting - 5 levels (rack in chain in rack in chain in rack)")
    
    clear_track_fx()
    
    -- Level 1: Rack
    local rack1 = rack_module.add_rack_to_track()
    assert.not_nil(rack1, "Level 1 rack should be created")
    
    -- Level 2: Chain in rack1
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    assert.not_nil(chain1, "Level 2 chain should be created")
    
    -- Re-fetch
    rack1 = find_fx_by_name_pattern("^R1:")
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    -- Level 3: Rack in chain1
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    assert.not_nil(rack2, "Level 3 rack should be created")
    
    -- Re-fetch
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
    
    -- Level 4: Chain in rack2
    local chain2 = rack_module.add_chain_to_rack(rack2_ref, { full_name = "ReaEQ", name = "ReaEQ" })
    assert.not_nil(chain2, "Level 4 chain should be created")
    
    -- Re-fetch
    rack2_ref = find_fx_by_name_pattern("^R2:")
    local chain2_ref = nil
    for child in rack2_ref:iter_container_children() do
        if child:get_name():match("^R2_C1") then
            chain2_ref = child
            break
        end
    end
    
    -- Level 5: Rack in chain2
    local rack3 = rack_module.add_rack_to_chain(chain2_ref)
    assert.not_nil(rack3, "Level 5 rack should be created")
    
    -- Verify entire hierarchy
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    assert.not_nil(chain1_ref, "Chain1 should exist")
    assert.equals(rack1:get_guid(), chain1_ref:get_parent_container():get_guid(), "Chain1 parent should be rack1")
    
    rack2_ref = nil
    for child in chain1_ref:iter_container_children() do
        if child:get_name():match("^R2:") then
            rack2_ref = child
            break
        end
    end
    
    assert.not_nil(rack2_ref, "Rack2 should exist")
    assert.equals(chain1_ref:get_guid(), rack2_ref:get_parent_container():get_guid(), "Rack2 parent should be chain1")
    
    local ok, err = verify_hierarchy_integrity()
    assert.truthy(ok, "Deep hierarchy integrity: " .. tostring(err))
end

local function test_add_multiple_devices_to_nested_chain()
    assert.section("Add multiple devices to deeply nested chain")
    
    clear_track_fx()
    
    -- Create nested structure: rack -> chain -> rack -> chain
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
    
    -- Re-fetch chain2
    rack2_ref = find_fx_by_name_pattern("^R2:")
    local chain2_ref = nil
    for child in rack2_ref:iter_container_children() do
        if child:get_name():match("^R2_C1") then
            chain2_ref = child
            break
        end
    end
    
    -- Add 3 devices to chain2
    local plugins = {
        { full_name = "JS: Volume", name = "Volume" },
        { full_name = "JS: Delay", name = "Delay" },
        { full_name = "JS: Reverb", name = "Reverb" },
    }
    
    for i, plugin in ipairs(plugins) do
        -- Re-fetch chain2 before each addition
        rack2_ref = find_fx_by_name_pattern("^R2:")
        chain2_ref = nil
        for child in rack2_ref:iter_container_children() do
            if child:get_name():match("^R2_C1") then
                chain2_ref = child
                break
            end
        end
        
        local device = rack_module.add_device_to_chain(chain2_ref, plugin)
        assert.not_nil(device, "Device " .. i .. " should be added")
        
        -- Verify hierarchy after each addition
        rack1 = find_fx_by_name_pattern("^R1:")
        chain1_ref = nil
        for child in rack1:iter_container_children() do
            if child:get_name():match("^R1_C1") then
                chain1_ref = child
                break
            end
        end
        
        local chain1_parent = chain1_ref:get_parent_container()
        assert.equals(rack1:get_guid(), chain1_parent:get_guid(), "Chain1 should remain in rack1 after device " .. i)
    end
    
    local ok, err = verify_hierarchy_integrity()
    assert.truthy(ok, "Hierarchy integrity after multiple additions: " .. tostring(err))
end

local function test_add_rack_to_chain_with_existing_devices()
    assert.section("Add rack to chain that already has devices")
    
    clear_track_fx()
    
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
    
    -- Add two devices first
    rack_module.add_device_to_chain(chain1_ref, { full_name = "ReaEQ", name = "ReaEQ" })
    rack_module.add_device_to_chain(chain1_ref, { full_name = "JS: Volume", name = "Volume" })
    
    -- Now add a rack
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local device_count_before = fx_utils.count_devices_in_chain(chain1_ref)
    assert.equals(2, device_count_before, "Should have 2 devices before adding rack")
    
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    assert.not_nil(rack2, "Rack should be added")
    
    -- Verify devices are still there
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local device_count_after = fx_utils.count_devices_in_chain(chain1_ref)
    assert.equals(2, device_count_after, "Should still have 2 devices after adding rack")
    
    -- Verify rack2 is in chain
    local rack2_found = false
    for child in chain1_ref:iter_container_children() do
        if child:get_name():match("^R2:") then
            rack2_found = true
            break
        end
    end
    assert.truthy(rack2_found, "Rack2 should be in chain1")
    
    -- Verify chain1 is still in rack1
    local chain1_parent = chain1_ref:get_parent_container()
    assert.equals(rack1:get_guid(), chain1_parent:get_guid(), "Chain1 should remain in rack1")
end

local function test_concurrent_additions_same_level()
    assert.section("Add multiple racks to same chain concurrently (simulated)")
    
    clear_track_fx()
    
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
    
    -- Add 3 racks sequentially
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)
    assert.not_nil(rack2, "First rack should be added")
    
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack3 = rack_module.add_rack_to_chain(chain1_ref)
    assert.not_nil(rack3, "Second rack should be added")
    
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack4 = rack_module.add_rack_to_chain(chain1_ref)
    assert.not_nil(rack4, "Third rack should be added")
    
    -- Verify all racks are in chain
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack_count = 0
    for child in chain1_ref:iter_container_children() do
        if child:get_name():match("^R%d+:") then
            rack_count = rack_count + 1
        end
    end
    
    assert.equals(3, rack_count, "Should have 3 racks in chain")
    
    -- Verify chain is still in rack1
    local chain1_parent = chain1_ref:get_parent_container()
    assert.equals(rack1:get_guid(), chain1_parent:get_guid(), "Chain1 should remain in rack1")
end

local function test_empty_chain_in_nested_rack()
    assert.section("Operations on empty chain in nested rack")
    
    clear_track_fx()
    
    -- Create nested structure with empty chain
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
    
    -- Create empty chain in rack2
    local chain2 = rack_module.add_chain_to_rack(rack2_ref, nil)
    
    -- Re-fetch chain2 (should be empty)
    rack2_ref = find_fx_by_name_pattern("^R2:")
    local chain2_ref = nil
    for child in rack2_ref:iter_container_children() do
        if child:get_name():match("^R2_C1") then
            chain2_ref = child
            break
        end
    end
    
    assert.not_nil(chain2_ref, "Empty chain should exist")
    assert.equals(0, fx_utils.count_devices_in_chain(chain2_ref), "Chain should be empty")
    
    -- Add device to empty chain
    local device = rack_module.add_device_to_chain(chain2_ref, { full_name = "ReaEQ", name = "ReaEQ" })
    assert.not_nil(device, "Device should be added to empty chain")
    
    -- Verify hierarchy is intact
    rack1 = find_fx_by_name_pattern("^R1:")
    chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local chain1_parent = chain1_ref:get_parent_container()
    assert.equals(rack1:get_guid(), chain1_parent:get_guid(), "Chain1 should remain in rack1")
    
    local ok, err = verify_hierarchy_integrity()
    assert.truthy(ok, "Hierarchy integrity with empty chain: " .. tostring(err))
end

local function test_rack_indexing_after_nested_additions()
    assert.section("Rack index generation after nested rack additions")
    
    clear_track_fx()
    
    -- Create racks at different nesting levels
    local rack1 = rack_module.add_rack_to_track()  -- R1
    local chain1 = rack_module.add_chain_to_rack(rack1, { full_name = "ReaComp", name = "ReaComp" })
    
    rack1 = find_fx_by_name_pattern("^R1:")
    local chain1_ref = nil
    for child in rack1:iter_container_children() do
        if child:get_name():match("^R1_C1") then
            chain1_ref = child
            break
        end
    end
    
    local rack2 = rack_module.add_rack_to_chain(chain1_ref)  -- R2 (nested)
    
    -- Add another rack at track level
    local rack3 = rack_module.add_rack_to_track()  -- Should be R3
    
    -- Verify indices
    rack1 = find_fx_by_name_pattern("^R1:")
    rack2 = find_fx_by_name_pattern("^R2:")
    rack3 = find_fx_by_name_pattern("^R3:")
    
    assert.not_nil(rack1, "Rack1 should exist")
    assert.not_nil(rack2, "Rack2 should exist")
    assert.not_nil(rack3, "Rack3 should exist")
    
    local idx1 = naming.parse_rack_index(rack1:get_name())
    local idx2 = naming.parse_rack_index(rack2:get_name())
    local idx3 = naming.parse_rack_index(rack3:get_name())
    
    assert.equals(1, idx1, "Rack1 should have index 1")
    assert.equals(2, idx2, "Rack2 should have index 2")
    assert.equals(3, idx3, "Rack3 should have index 3")
end

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

local function run_all_tests()
    assert.reset()
    
    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("SideFX Edge Cases Integration Tests\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("\n")
    
    -- Setup
    setup_test_track()
    
    -- Run tests
    local tests = {
        { name = "test_add_device_to_empty_nested_rack", fn = test_add_device_to_empty_nested_rack },
        { name = "test_deep_nesting_5_levels", fn = test_deep_nesting_5_levels },
        { name = "test_add_multiple_devices_to_nested_chain", fn = test_add_multiple_devices_to_nested_chain },
        { name = "test_add_rack_to_chain_with_existing_devices", fn = test_add_rack_to_chain_with_existing_devices },
        { name = "test_concurrent_additions_same_level", fn = test_concurrent_additions_same_level },
        { name = "test_empty_chain_in_nested_rack", fn = test_empty_chain_in_nested_rack },
        { name = "test_rack_indexing_after_nested_additions", fn = test_rack_indexing_after_nested_additions },
    }
    
    for _, test in ipairs(tests) do
        local ok, err = pcall(test.fn)
        if not ok then
            r.ShowConsoleMsg("ERROR in " .. test.name .. ": " .. tostring(err) .. "\n")
        end
    end
    
    -- Cleanup
    cleanup_test_track()
    
    -- Report
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

-- Run if executed directly
run_all_tests()

