--- Integration tests for SideFX container operations.
-- These tests run INSIDE REAPER and test actual FX manipulation.
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_containers
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
local naming = require("naming")
local fx_utils = require("fx_utils")

-- Load ReaWrap
local Project = require("project")
local Track = require("track")
local TrackFX = require("track_fx")

--------------------------------------------------------------------------------
-- Test Helpers
--------------------------------------------------------------------------------

local test_track = nil

local function setup_test_track()
    r.Undo_BeginBlock()

    -- Insert a new test track
    r.InsertTrackAtIndex(0, false)
    local track_ptr = r.GetTrack(0, 0)
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_Test_Track", true)

    test_track = Track:new(track_ptr)
    return test_track
end

local function cleanup_test_track()
    if test_track then
        -- Delete the test track
        r.DeleteTrack(test_track.pointer)
        test_track = nil
    end
    r.Undo_EndBlock("SideFX Integration Test", -1)
end

local function add_test_fx(name)
    if not test_track then return nil end
    local fx = test_track:add_fx_by_name(name or "ReaComp", false, -1)
    return fx
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local function test_add_fx()
    assert.section("Add FX to track")

    local fx = add_test_fx("ReaComp")
    assert.not_nil(fx, "FX should be created")

    local name = fx:get_name()
    assert.contains(name, "ReaComp", "FX name should contain ReaComp")

    local count = test_track:get_track_fx_count()
    assert.equals(1, count, "Track should have 1 FX")
end

local function test_create_container()
    assert.section("Create container")

    -- Add container
    local container = test_track:add_fx_by_name("Container", false, -1)
    assert.not_nil(container, "Container should be created")

    local is_cont = container:is_container()
    assert.truthy(is_cont, "FX should be a container")

    local child_count = container:get_container_child_count()
    assert.equals(0, child_count, "Empty container should have 0 children")
end

local function test_move_fx_to_container()
    assert.section("Move FX into container")

    -- Clear track first
    while test_track:get_track_fx_count() > 0 do
        local fx = test_track:get_track_fx(0)
        fx:delete()
    end

    -- Add FX
    local fx1 = add_test_fx("ReaComp")
    local fx2 = add_test_fx("ReaEQ")

    -- Add container
    local container = test_track:add_fx_by_name("Container", false, -1)

    -- Move FX into container
    container:add_fx_to_container(fx1)

    -- Check
    local child_count = container:get_container_child_count()
    assert.equals(1, child_count, "Container should have 1 child after move")
end

local function test_naming_functions()
    assert.section("Naming utilities")

    -- Test device naming
    local device_name = naming.build_device_name(1, "ReaComp")
    assert.equals("D1: ReaComp", device_name, "Should build device name")

    assert.truthy(naming.is_device_name(device_name), "Should detect device name")
    assert.falsy(naming.is_rack_name(device_name), "Should not detect as rack")

    -- Test rack naming
    local rack_name = naming.build_rack_name(2, "My Rack")
    assert.equals("R2: My Rack", rack_name, "Should build rack name")

    assert.truthy(naming.is_rack_name(rack_name), "Should detect rack name")
    assert.falsy(naming.is_device_name(rack_name), "Should not detect as device")

    -- Test parsing
    local parsed = naming.parse_hierarchy("R1_C2_D3: ReaComp")
    assert.equals(1, parsed.rack_idx, "Should parse rack index")
    assert.equals(2, parsed.chain_idx, "Should parse chain index")
    assert.equals(3, parsed.device_idx, "Should parse device index")
end

local function test_fx_utils()
    assert.section("FX utilities")

    -- Clear track
    while test_track:get_track_fx_count() > 0 do
        local fx = test_track:get_track_fx(0)
        fx:delete()
    end

    -- Add FX
    local fx = add_test_fx("ReaComp")

    -- Test display name
    local display = fx_utils.get_display_name(fx)
    assert.not_nil(display, "Should get display name")
    assert.contains(display, "ReaComp", "Display name should contain FX name")

    -- Test type detection (should not be a container)
    local is_cont = fx_utils.is_device_container(fx)
    assert.falsy(is_cont, "ReaComp should not be a device container")

    -- Add container
    local container = test_track:add_fx_by_name("Container", false, -1)
    container:set_named_config_param("renamed_name", "D1: Test Device")

    -- Re-fetch to get updated name
    container = test_track:get_track_fx(1)
    local is_device = fx_utils.is_device_container(container)
    assert.truthy(is_device, "Named container should be detected as device container")
end

local function test_container_iteration()
    assert.section("Container iteration")

    -- Clear track
    while test_track:get_track_fx_count() > 0 do
        local fx = test_track:get_track_fx(0)
        fx:delete()
    end

    -- Create container with children
    local container = test_track:add_fx_by_name("Container", false, -1)

    -- Add FX to container
    local fx1 = test_track:add_fx_by_name("ReaComp", false, -1)
    container:add_fx_to_container(fx1)

    local fx2 = test_track:add_fx_by_name("ReaEQ", false, -1)
    container:add_fx_to_container(fx2)

    -- Test iteration
    local count = 0
    for child in container:iter_container_children() do
        count = count + 1
        assert.not_nil(child, "Child should not be nil")
    end

    assert.equals(2, count, "Should iterate over 2 children")
end

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

local function run_all_tests()
    assert.reset()

    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("SideFX Integration Tests\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("\n")

    -- Setup
    setup_test_track()

    -- Run tests
    local ok, err

    ok, err = pcall(test_add_fx)
    if not ok then r.ShowConsoleMsg("ERROR in test_add_fx: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_create_container)
    if not ok then r.ShowConsoleMsg("ERROR in test_create_container: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_move_fx_to_container)
    if not ok then r.ShowConsoleMsg("ERROR in test_move_fx_to_container: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_naming_functions)
    if not ok then r.ShowConsoleMsg("ERROR in test_naming_functions: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_fx_utils)
    if not ok then r.ShowConsoleMsg("ERROR in test_fx_utils: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_container_iteration)
    if not ok then r.ShowConsoleMsg("ERROR in test_container_iteration: " .. tostring(err) .. "\n") end

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
