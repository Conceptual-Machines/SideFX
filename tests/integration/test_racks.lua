--- Integration tests for SideFX rack operations.
-- These tests run INSIDE REAPER and test actual rack/chain manipulation.
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_racks
-- @author Nomad Monad
-- @license MIT

--------------------------------------------------------------------------------
-- Setup
--------------------------------------------------------------------------------

local info = debug.getinfo(1, "S")
local script_path = info.source:match("@?(.*[\\/])")
local root_path = script_path:match("^(.+/)tests/") or script_path .. "../../"

-- Add SideFX paths - need both for direct requires and lib.* requires
package.path = root_path .. "?.lua;" .. package.path           -- for require('lib.naming')
package.path = root_path .. "lib/?.lua;" .. package.path       -- for require('naming')
package.path = root_path .. "tests/?.lua;" .. package.path     -- for require('assertions')

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
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_Rack_Test", true)

    test_track = Track:new(track_ptr)

    -- Set up state for rack module
    state.track = test_track
    state.track_name = "_SideFX_Rack_Test"

    return test_track
end

local function cleanup_test_track()
    if test_track then
        -- Delete the test track
        r.DeleteTrack(test_track.pointer)
        test_track = nil
        state.track = nil
        state.track_name = ""
    end
    r.Undo_EndBlock("SideFX Rack Integration Test", -1)
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
    -- Search recursively through all FX including inside containers
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
-- Tests: Rack Creation
--------------------------------------------------------------------------------

local function test_add_rack_to_track()
    assert.section("Add rack to track")

    clear_track_fx()

    local rack = rack_module.add_rack_to_track()
    assert.not_nil(rack, "Rack should be created")

    local is_cont = rack:is_container()
    assert.truthy(is_cont, "Rack should be a container")

    local name = rack:get_name()
    assert.truthy(naming.is_rack_name(name), "Rack should have R prefix: " .. tostring(name))

    -- Check mixer was created inside
    local mixer = fx_utils.get_rack_mixer(rack)
    assert.not_nil(mixer, "Rack should contain mixer")

    if mixer then
        local mixer_name = mixer:get_name()
        assert.truthy(naming.is_mixer_name(mixer_name), "Mixer should have _R#_M name: " .. tostring(mixer_name))
    end
end

local function test_add_multiple_racks()
    assert.section("Add multiple racks")

    clear_track_fx()

    local rack1 = rack_module.add_rack_to_track()
    local rack2 = rack_module.add_rack_to_track()

    assert.not_nil(rack1, "Rack 1 should be created")
    assert.not_nil(rack2, "Rack 2 should be created")

    local name1 = rack1:get_name()
    local name2 = rack2:get_name()

    local idx1 = naming.parse_rack_index(name1)
    local idx2 = naming.parse_rack_index(name2)

    assert.equals(1, idx1, "First rack should be R1")
    assert.equals(2, idx2, "Second rack should be R2")
end

--------------------------------------------------------------------------------
-- Tests: Chain Operations
--------------------------------------------------------------------------------

local function test_add_chain_to_rack()
    assert.section("Add chain to rack")

    clear_track_fx()

    local rack = rack_module.add_rack_to_track()
    assert.not_nil(rack, "Rack should be created")

    local plugin = { full_name = "ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack, plugin)

    assert.not_nil(chain, "Chain should be created")

    -- Re-fetch rack to get updated children
    rack = find_fx_by_name_pattern("^R1:")
    assert.not_nil(rack, "Should find rack after adding chain")

    -- Count chains
    local chain_count = fx_utils.count_chains_in_rack(rack)
    assert.equals(1, chain_count, "Rack should have 1 chain")
end

local function test_add_multiple_chains()
    assert.section("Add multiple chains to rack")

    clear_track_fx()

    local rack = rack_module.add_rack_to_track()

    local plugin1 = { full_name = "ReaComp", name = "ReaComp" }
    local plugin2 = { full_name = "ReaEQ", name = "ReaEQ" }
    local plugin3 = { full_name = "ReaDelay", name = "ReaDelay" }

    rack_module.add_chain_to_rack(rack, plugin1)
    rack_module.add_chain_to_rack(rack, plugin2)
    rack_module.add_chain_to_rack(rack, plugin3)

    -- Re-fetch rack
    rack = find_fx_by_name_pattern("^R1:")
    assert.not_nil(rack, "Should find rack")

    local chain_count = fx_utils.count_chains_in_rack(rack)
    assert.equals(3, chain_count, "Rack should have 3 chains")

    -- Verify chain naming
    local found_c1 = false
    local found_c2 = false
    local found_c3 = false

    for child in rack:iter_container_children() do
        local name = child:get_name()
        if name:match("^R1_C1") then found_c1 = true end
        if name:match("^R1_C2") then found_c2 = true end
        if name:match("^R1_C3") then found_c3 = true end
    end

    assert.truthy(found_c1, "Should find chain R1_C1")
    assert.truthy(found_c2, "Should find chain R1_C2")
    assert.truthy(found_c3, "Should find chain R1_C3")
end

local function test_add_device_to_chain()
    assert.section("Add device to chain")

    clear_track_fx()

    local rack = rack_module.add_rack_to_track()
    local plugin1 = { full_name = "ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack, plugin1)

    assert.not_nil(chain, "Chain should be created")

    -- Re-fetch chain
    rack = find_fx_by_name_pattern("^R1:")
    local chain_inside = nil
    for child in rack:iter_container_children() do
        local name = child:get_name()
        if name:match("^R1_C1") then
            chain_inside = child
            break
        end
    end

    assert.not_nil(chain_inside, "Should find chain inside rack")

    -- Add another device to chain
    local plugin2 = { full_name = "ReaEQ", name = "ReaEQ" }
    local device = rack_module.add_device_to_chain(chain_inside, plugin2)

    assert.not_nil(device, "Device should be added to chain")

    -- Count devices in chain
    local device_count = fx_utils.count_devices_in_chain(chain_inside)
    assert.equals(2, device_count, "Chain should have 2 devices")
end

--------------------------------------------------------------------------------
-- Tests: Nested Racks
--------------------------------------------------------------------------------

local function test_nested_rack()
    assert.section("Create nested rack")

    clear_track_fx()

    -- Create parent rack
    local parent_rack = rack_module.add_rack_to_track()
    assert.not_nil(parent_rack, "Parent rack should be created")

    local parent_name = parent_rack:get_name()
    assert.equals(1, naming.parse_rack_index(parent_name), "Parent should be R1")

    -- Create nested rack inside parent
    local nested_rack = rack_module.add_nested_rack_to_rack(parent_rack)
    assert.not_nil(nested_rack, "Nested rack should be created")

    local nested_name = nested_rack:get_name()
    assert.truthy(naming.is_rack_name(nested_name), "Nested rack should have R prefix: " .. tostring(nested_name))

    -- Nested rack should be R2
    local nested_idx = naming.parse_rack_index(nested_name)
    assert.equals(2, nested_idx, "Nested rack should be R2")

    -- Check parent has a chain containing the nested rack
    parent_rack = find_fx_by_name_pattern("^R1:")
    assert.not_nil(parent_rack, "Should find parent rack")

    local chain_count = fx_utils.count_chains_in_rack(parent_rack)
    assert.equals(1, chain_count, "Parent rack should have 1 chain containing nested rack")

    -- Check nested rack has its own mixer
    nested_rack = find_fx_by_name_pattern("^R2:")
    assert.not_nil(nested_rack, "Should find nested rack")

    local nested_mixer = fx_utils.get_rack_mixer(nested_rack)
    assert.not_nil(nested_mixer, "Nested rack should have its own mixer")
end

local function test_deeply_nested_racks()
    assert.section("Create deeply nested racks (3 levels)")

    clear_track_fx()

    -- Level 1: Create parent rack
    local rack1 = rack_module.add_rack_to_track()
    assert.not_nil(rack1, "Level 1 rack should be created")

    -- Level 2: Create nested rack inside rack1
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    assert.not_nil(rack2, "Level 2 rack should be created")

    -- Re-find rack2 before adding to it (reference may be stale after move)
    rack2 = find_fx_by_name_pattern("^R2:")
    assert.not_nil(rack2, "Should find R2 before nesting")

    -- Level 3: Create nested rack inside rack2
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    assert.not_nil(rack3, "Level 3 rack should be created")

    -- Verify all racks exist with correct indices
    rack1 = find_fx_by_name_pattern("^R1:")
    rack2 = find_fx_by_name_pattern("^R2:")
    rack3 = find_fx_by_name_pattern("^R3:")

    assert.not_nil(rack1, "Should find R1")
    assert.not_nil(rack2, "Should find R2")
    assert.not_nil(rack3, "Should find R3")

    -- Each nested rack should have its own mixer
    local mixer1 = fx_utils.get_rack_mixer(rack1)
    local mixer2 = fx_utils.get_rack_mixer(rack2)
    local mixer3 = fx_utils.get_rack_mixer(rack3)

    assert.not_nil(mixer1, "R1 should have mixer")
    assert.not_nil(mixer2, "R2 should have mixer")
    assert.not_nil(mixer3, "R3 should have mixer")

    -- Verify mixer names
    if mixer1 then
        assert.equals("_R1_M", mixer1:get_name(), "R1 mixer name")
    end
    if mixer2 then
        assert.equals("_R2_M", mixer2:get_name(), "R2 mixer name")
    end
    if mixer3 then
        assert.equals("_R3_M", mixer3:get_name(), "R3 mixer name")
    end
end

local function test_nested_rack_with_chains()
    assert.section("Nested rack with chains")

    clear_track_fx()

    -- Create parent rack with a regular chain
    local parent_rack = rack_module.add_rack_to_track()
    local plugin1 = { full_name = "ReaComp", name = "ReaComp" }
    rack_module.add_chain_to_rack(parent_rack, plugin1)

    -- Add nested rack
    parent_rack = find_fx_by_name_pattern("^R1:")
    local nested_rack = rack_module.add_nested_rack_to_rack(parent_rack)

    -- Add another regular chain to parent
    parent_rack = find_fx_by_name_pattern("^R1:")
    local plugin2 = { full_name = "ReaEQ", name = "ReaEQ" }
    rack_module.add_chain_to_rack(parent_rack, plugin2)

    -- Verify parent has 3 chains (1 plugin + 1 nested rack + 1 plugin)
    parent_rack = find_fx_by_name_pattern("^R1:")
    local chain_count = fx_utils.count_chains_in_rack(parent_rack)
    assert.equals(3, chain_count, "Parent should have 3 chains")

    -- Add chain to nested rack
    nested_rack = find_fx_by_name_pattern("^R2:")
    local plugin3 = { full_name = "ReaDelay", name = "ReaDelay" }
    rack_module.add_chain_to_rack(nested_rack, plugin3)

    -- Verify nested rack has 1 chain
    nested_rack = find_fx_by_name_pattern("^R2:")
    local nested_chain_count = fx_utils.count_chains_in_rack(nested_rack)
    assert.equals(1, nested_chain_count, "Nested rack should have 1 chain")
end

--------------------------------------------------------------------------------
-- Tests: Rack Detection
--------------------------------------------------------------------------------

local function test_rack_detection()
    assert.section("Rack and chain detection")

    clear_track_fx()

    -- Create rack with chain
    local rack = rack_module.add_rack_to_track()
    local plugin = { full_name = "ReaComp", name = "ReaComp" }
    rack_module.add_chain_to_rack(rack, plugin)

    rack = find_fx_by_name_pattern("^R1:")
    assert.not_nil(rack, "Should find rack")

    -- Test is_rack_container
    assert.truthy(fx_utils.is_rack_container(rack), "Rack should be detected as rack container")

    -- Test is_chain_container
    local chain = nil
    for child in rack:iter_container_children() do
        local name = child:get_name()
        if naming.is_chain_name(name) then
            chain = child
            break
        end
    end

    assert.not_nil(chain, "Should find chain")
    if chain then
        assert.truthy(fx_utils.is_chain_container(chain), "Chain should be detected as chain container")
        assert.falsy(fx_utils.is_rack_container(chain), "Chain should not be detected as rack")
    end

    -- Test get_rack_mixer
    local mixer = fx_utils.get_rack_mixer(rack)
    assert.not_nil(mixer, "Should find mixer in rack")
end

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

local function run_all_tests()
    assert.reset()

    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("SideFX Rack Integration Tests\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("\n")

    -- Setup
    setup_test_track()

    -- Run tests
    local tests = {
        { name = "test_add_rack_to_track", fn = test_add_rack_to_track },
        { name = "test_add_multiple_racks", fn = test_add_multiple_racks },
        { name = "test_add_chain_to_rack", fn = test_add_chain_to_rack },
        { name = "test_add_multiple_chains", fn = test_add_multiple_chains },
        { name = "test_add_device_to_chain", fn = test_add_device_to_chain },
        { name = "test_nested_rack", fn = test_nested_rack },
        { name = "test_deeply_nested_racks", fn = test_deeply_nested_racks },
        { name = "test_nested_rack_with_chains", fn = test_nested_rack_with_chains },
        { name = "test_rack_detection", fn = test_rack_detection },
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
    end
    r.ShowConsoleMsg("========================================\n")
end

-- Run if executed directly
run_all_tests()
