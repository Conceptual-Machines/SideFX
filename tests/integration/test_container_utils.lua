--- Integration tests for SideFX container utility operations.
-- These tests run INSIDE REAPER and test actual container manipulation.
--
-- Tests:
--   - convert_chain_to_devices: Extract all devices from chain to track level
--   - convert_device_to_rack: Wrap a device in a new rack
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_container_utils
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

-- Load ReaWrap
local Track = require("track")

-- Load SideFX modules
local container_module = require("lib.device.container")
local device_module = require("lib.device.device")
local rack_module = require("lib.rack.rack")
local fx_utils = require("lib.fx.fx_utils")
local naming = require("lib.utils.naming")
local state_module = require("lib.core.state")

--------------------------------------------------------------------------------
-- Test Helpers
--------------------------------------------------------------------------------

local test_track = nil

local function setup_test_track()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Insert a new test track
    r.InsertTrackAtIndex(0, false)
    local track_ptr = r.GetTrack(0, 0)
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_Container_Utils_Test", true)

    test_track = Track:new(track_ptr)

    -- Set as current track in state
    state_module.state.track = test_track

    return test_track
end

local function cleanup_test_track()
    r.PreventUIRefresh(-1)
    if test_track then
        -- Delete the test track
        r.DeleteTrack(test_track.pointer)
        test_track = nil
        state_module.state.track = nil
    end
    r.Undo_EndBlock("SideFX Container Utils Integration Test", -1)
end

local function clear_track_fx()
    if not test_track then return end
    while test_track:get_track_fx_count() > 0 do
        local fx = test_track:get_track_fx(0)
        fx:delete()
    end
end

local function add_device_to_track(plugin_name)
    if not test_track then return nil end
    local plugin = { full_name = plugin_name, name = plugin_name }
    return device_module.add_plugin_to_track(plugin)
end

--------------------------------------------------------------------------------
-- Tests: convert_chain_to_devices
--------------------------------------------------------------------------------

local function test_convert_chain_to_devices_extracts_all()
    assert.section("convert_chain_to_devices extracts all devices")

    clear_track_fx()

    -- Create a rack first
    local rack = rack_module.add_rack_to_track()
    assert.not_nil(rack, "Rack should be created")

    -- Add a chain with a plugin
    local plugin = { full_name = "ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack, plugin)
    assert.not_nil(chain, "Chain should be created")

    local chain_guid = chain:get_guid()
    local chain_name = chain:get_name()
    assert.truthy(chain_name:match("^R%d+_C%d+"), "Chain name should match C pattern")

    -- Count devices in chain before conversion
    local device_count = 0
    for _ in chain:iter_container_children() do
        device_count = device_count + 1
    end
    assert.truthy(device_count > 0, "Chain should have at least one device")

    -- Convert chain to devices
    local extracted = container_module.convert_chain_to_devices(chain)
    assert.truthy(#extracted > 0, "Should extract at least one device")

    -- Chain should no longer exist
    local chain_after = test_track:find_fx_by_guid(chain_guid)
    assert.is_nil(chain_after, "Chain should be deleted after conversion")
end

local function test_convert_chain_to_devices_handles_empty_chain()
    assert.section("convert_chain_to_devices handles empty chain")

    clear_track_fx()

    -- Create a rack
    local rack = rack_module.add_rack_to_track()
    assert.not_nil(rack, "Rack should be created")

    -- Add an empty chain
    local chain = rack_module.add_empty_chain_to_rack(rack)
    assert.not_nil(chain, "Empty chain should be created")

    local chain_guid = chain:get_guid()

    -- Convert empty chain
    local extracted = container_module.convert_chain_to_devices(chain)
    assert.equals(0, #extracted, "Should extract 0 devices from empty chain")

    -- Chain should be deleted
    local chain_after = test_track:find_fx_by_guid(chain_guid)
    assert.is_nil(chain_after, "Empty chain should be deleted after conversion")
end

local function test_convert_chain_to_devices_rejects_non_chain()
    assert.section("convert_chain_to_devices rejects non-chain containers")

    clear_track_fx()

    -- Add a device container (not a chain)
    local device = add_device_to_track("ReaComp")
    assert.not_nil(device, "Device should be created")

    -- Try to convert it - should return empty table
    local result = container_module.convert_chain_to_devices(device)
    assert.equals(0, #result, "Should return empty table for non-chain")
end

--------------------------------------------------------------------------------
-- Tests: convert_device_to_rack
--------------------------------------------------------------------------------

local function test_convert_device_to_rack_creates_rack()
    assert.section("convert_device_to_rack creates rack")

    clear_track_fx()

    -- Add a device
    local device = add_device_to_track("ReaComp")
    assert.not_nil(device, "Device should be created")

    local device_guid = device:get_guid()

    -- Convert to rack
    local rack = container_module.convert_device_to_rack(device)
    assert.not_nil(rack, "Rack should be created")

    local rack_name = rack:get_name()
    assert.truthy(rack_name:match("^R%d+"), "Rack name should match R pattern")

    -- Rack should contain a chain
    local chain_count = 0
    local first_chain = nil
    for child in rack:iter_container_children() do
        local name = child:get_name()
        if name:match("^R%d+_C%d+") then
            chain_count = chain_count + 1
            first_chain = child
        end
    end
    assert.equals(1, chain_count, "Rack should have exactly 1 chain")

    -- Chain should contain the device
    if first_chain then
        local device_in_chain = nil
        for child in first_chain:iter_container_children() do
            local name = child:get_name()
            if name:match("D%d+") then
                device_in_chain = child
                break
            end
        end
        assert.not_nil(device_in_chain, "Device should be in the chain")
    end
end

local function test_convert_device_to_rack_rejects_non_device()
    assert.section("convert_device_to_rack rejects non-device containers")

    clear_track_fx()

    -- Add a plain container
    local container = test_track:add_fx_by_name("Container", false, -1)
    assert.not_nil(container, "Container should be created")

    -- Try to convert it - should return nil
    local result = container_module.convert_device_to_rack(container)
    assert.is_nil(result, "convert_device_to_rack should return nil for non-device")
end

local function test_convert_device_to_rack_preserves_fx_name()
    assert.section("convert_device_to_rack preserves FX name")

    clear_track_fx()

    -- Add a device
    local device = add_device_to_track("ReaComp")
    assert.not_nil(device, "Device should be created")

    -- Convert to rack
    local rack = container_module.convert_device_to_rack(device)
    assert.not_nil(rack, "Rack should be created")

    -- Find the device inside the chain
    for child in rack:iter_container_children() do
        local name = child:get_name()
        if name:match("^R%d+_C%d+") then
            for device_child in child:iter_container_children() do
                local device_name = device_child:get_name()
                if device_name:match("D%d+") then
                    -- Device name should contain ReaComp
                    assert.contains(device_name, "ReaComp", "Device name should contain ReaComp")
                    break
                end
            end
            break
        end
    end
end

--------------------------------------------------------------------------------
-- Run All Tests
--------------------------------------------------------------------------------

local function run_all_tests()
    assert.reset()

    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("SideFX Container Utils Integration Tests\n")
    r.ShowConsoleMsg("========================================\n")
    r.ShowConsoleMsg("\n")

    -- Setup
    setup_test_track()

    -- Run tests
    local ok, err

    -- convert_chain_to_devices tests
    ok, err = pcall(test_convert_chain_to_devices_extracts_all)
    if not ok then r.ShowConsoleMsg("ERROR: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_convert_chain_to_devices_handles_empty_chain)
    if not ok then r.ShowConsoleMsg("ERROR: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_convert_chain_to_devices_rejects_non_chain)
    if not ok then r.ShowConsoleMsg("ERROR: " .. tostring(err) .. "\n") end

    -- convert_device_to_rack tests
    ok, err = pcall(test_convert_device_to_rack_creates_rack)
    if not ok then r.ShowConsoleMsg("ERROR: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_convert_device_to_rack_rejects_non_device)
    if not ok then r.ShowConsoleMsg("ERROR: " .. tostring(err) .. "\n") end

    ok, err = pcall(test_convert_device_to_rack_preserves_fx_name)
    if not ok then r.ShowConsoleMsg("ERROR: " .. tostring(err) .. "\n") end

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
