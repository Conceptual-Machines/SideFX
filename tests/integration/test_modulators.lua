--- Integration tests for SideFX modulator operations.
-- These tests run INSIDE REAPER and test actual modulator manipulation.
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_modulators
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
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_Modulator_Test", true)

    test_track = Track:new(track_ptr)

    -- Set up state for rack module
    state.track = test_track
    state.track_name = "_SideFX_Modulator_Test"

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
    r.Undo_EndBlock("SideFX Modulator Integration Test", -1)
end

local function clear_track_fx()
    if not test_track then return end
    while test_track:get_track_fx_count() > 0 do
        local fx = test_track:get_track_fx(0)
        if fx then fx:delete() end
    end
end

--- Add modulator to device container using the same pattern as device_panel.lua
local function add_modulator_to_device(device_container, modulator_jsfx_name, track)
    if not track or not device_container then return nil end
    if not device_container:is_container() then return nil end

    r.PreventUIRefresh(1)

    -- Get container GUID before operations
    local container_guid = device_container:get_guid()
    if not container_guid then
        r.PreventUIRefresh(-1)
        return nil
    end

    -- Add modulator JSFX at track level first
    local modulator = track:add_fx_by_name(modulator_jsfx_name, false, -1)
    if not modulator or modulator.pointer < 0 then
        r.PreventUIRefresh(-1)
        return nil
    end

    local mod_guid = modulator:get_guid()

    -- Refind container by GUID
    local fresh_container = track:find_fx_by_guid(container_guid)
    if not fresh_container then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        return nil
    end

    -- Refresh pointer for deeply nested containers
    if fresh_container.pointer and fresh_container.pointer >= 0x2000000 and fresh_container.refresh_pointer then
        fresh_container:refresh_pointer()
    end

    -- Refind modulator by GUID
    modulator = track:find_fx_by_guid(mod_guid)
    if not modulator then
        r.PreventUIRefresh(-1)
        return nil
    end

    -- Get insert position (append to end of container)
    local insert_pos = fresh_container:get_container_child_count()

    -- Move modulator into container
    local success = fresh_container:add_fx_to_container(modulator, insert_pos)

    if not success then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        return nil
    end

    -- Refind modulator after move
    local moved_modulator = track:find_fx_by_guid(mod_guid)

    r.PreventUIRefresh(-1)

    return moved_modulator
end

--- Get all modulators inside a device container
local function get_device_modulators(device_container)
    if not device_container or not device_container:is_container() then
        return {}
    end

    local modulators = {}
    local ok, iter = pcall(function() return device_container:iter_container_children() end)
    if not ok then return {} end

    for child in iter do
        if fx_utils.is_modulator_fx(child) then
            table.insert(modulators, child)
        end
    end

    return modulators
end

--------------------------------------------------------------------------------
-- Tests: Modulator Creation
--------------------------------------------------------------------------------

local function test_add_modulator_to_device()
    assert.section("Add modulator to device container")

    clear_track_fx()

    -- Create a device container with a plugin
    local device = test_track:add_fx_by_name("Container", false, -1)
    assert.truthy(device, "Should create device container")
    device:set_named_config_param("renamed_name", "D1: TestDevice")

    -- Add a plugin to the device
    local plugin = test_track:add_fx_by_name("ReaEQ", false, -1)
    assert.truthy(plugin, "Should create plugin")
    device:add_fx_to_container(plugin, 0)

    -- Add modulator to device
    local modulator = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)
    assert.truthy(modulator, "Should create and move modulator")

    -- Verify modulator is inside container
    local parent = modulator:get_parent_container()
    assert.truthy(parent, "Modulator should have parent container")
    assert.equals(device:get_guid(), parent:get_guid(), "Modulator parent should be device container")

    -- Verify modulator name
    local mod_name = modulator:get_name()
    assert.contains(mod_name, "SideFX Modulator", "Modulator should have correct name")
end

local function test_get_device_modulators()
    assert.section("Get modulators from device container")

    clear_track_fx()

    -- Create device container
    local device = test_track:add_fx_by_name("Container", false, -1)
    device:set_named_config_param("renamed_name", "D1: TestDevice")

    -- Add plugin
    local plugin = test_track:add_fx_by_name("ReaEQ", false, -1)
    device:add_fx_to_container(plugin, 0)

    -- Add multiple modulators
    local mod1 = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)
    local mod2 = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)
    local mod3 = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)

    assert.truthy(mod1, "Should create modulator 1")
    assert.truthy(mod2, "Should create modulator 2")
    assert.truthy(mod3, "Should create modulator 3")

    -- Get all modulators from container
    local modulators = get_device_modulators(device)

    assert.equals(3, #modulators, "Should find 3 modulators in device")

    -- Verify all are modulators
    for i, mod in ipairs(modulators) do
        local is_mod = fx_utils.is_modulator_fx(mod)
        assert.truthy(is_mod, "Child " .. i .. " should be modulator")
    end
end

local function test_modulator_not_at_track_level()
    assert.section("Modulator should not appear at track level")

    clear_track_fx()

    -- Create device
    local device = test_track:add_fx_by_name("Container", false, -1)
    device:set_named_config_param("renamed_name", "D1: TestDevice")

    -- Add plugin
    local plugin = test_track:add_fx_by_name("ReaEQ", false, -1)
    device:add_fx_to_container(plugin, 0)

    -- Track should have 1 FX (the device container)
    local track_fx_count_before = test_track:get_track_fx_count()
    assert.equals(1, track_fx_count_before, "Track should have 1 FX before adding modulator")

    -- Add modulator
    local modulator = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)
    assert.truthy(modulator, "Should create modulator")

    -- Track should still have 1 FX (modulator is inside container)
    local track_fx_count_after = test_track:get_track_fx_count()
    assert.equals(1, track_fx_count_after, "Track should still have 1 FX after adding modulator (inside container)")

    -- Device container should have 2 children (plugin + modulator)
    local device_child_count = device:get_container_child_count()
    assert.equals(2, device_child_count, "Device should have 2 children (plugin + modulator)")
end

local function test_delete_modulator()
    assert.section("Delete modulator from device")

    clear_track_fx()

    -- Create device with modulators
    local device = test_track:add_fx_by_name("Container", false, -1)
    device:set_named_config_param("renamed_name", "D1: TestDevice")

    local plugin = test_track:add_fx_by_name("ReaEQ", false, -1)
    device:add_fx_to_container(plugin, 0)

    local mod1 = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)
    local mod2 = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)

    assert.truthy(mod1, "Should create modulator 1")
    assert.truthy(mod2, "Should create modulator 2")

    -- Verify 2 modulators
    local mods_before = get_device_modulators(device)
    assert.equals(2, #mods_before, "Should have 2 modulators before delete")

    -- Delete first modulator
    mod1:delete()

    -- Refind device (GUIDs stable after delete)
    local device_guid = device:get_guid()
    device = test_track:find_fx_by_guid(device_guid)
    assert.truthy(device, "Should refind device after modulator delete")

    -- Verify 1 modulator remains
    local mods_after = get_device_modulators(device)
    assert.equals(1, #mods_after, "Should have 1 modulator after delete")
end

local function test_modulator_in_nested_device()
    assert.section("Add modulator to nested device (rack chain)")

    clear_track_fx()

    -- Create rack structure: Rack -> Chain -> Device
    local rack = rack_module.add_rack_to_track()
    assert.truthy(rack, "Should create rack")

    -- Add chain to rack with first device
    local plugin1 = { full_name = "ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack, plugin1)
    assert.truthy(chain, "Should create chain with first device")

    -- Add second device to chain
    local plugin2 = { full_name = "ReaEQ", name = "ReaEQ" }
    local device = rack_module.add_device_to_chain(chain, plugin2)
    assert.truthy(device, "Should add second device to chain")

    -- Add modulator to nested device
    local modulator = add_modulator_to_device(device, "JS:SideFX/SideFX_Modulator", test_track)
    assert.truthy(modulator, "Should add modulator to nested device")

    if not modulator then
        return  -- Skip rest of test if modulator creation failed
    end

    -- Verify modulator parent is device
    local parent = modulator:get_parent_container()
    assert.truthy(parent, "Modulator should have parent")

    if parent then
        assert.equals(device:get_guid(), parent:get_guid(), "Modulator parent should be nested device")
    end

    -- Verify modulator appears in device modulators list
    local modulators = get_device_modulators(device)
    assert.equals(1, #modulators, "Should find 1 modulator in nested device")
end

--------------------------------------------------------------------------------
-- Main Test Runner
--------------------------------------------------------------------------------

local function run_all_tests()
    r.ShowConsoleMsg("\n========================================\n")
    r.ShowConsoleMsg("SideFX Modulator Integration Tests\n")
    r.ShowConsoleMsg("========================================\n\n")

    setup_test_track()

    -- Run tests
    assert.reset()
    test_add_modulator_to_device()
    test_get_device_modulators()
    test_modulator_not_at_track_level()
    test_delete_modulator()
    test_modulator_in_nested_device()

    cleanup_test_track()

    -- Report results
    local results = assert.get_results()
    r.ShowConsoleMsg("\n----------------------------------------\n")
    r.ShowConsoleMsg(string.format("Tests run: %d\n", results.run))
    r.ShowConsoleMsg(string.format("Passed: %d\n", results.passed))
    r.ShowConsoleMsg(string.format("Failed: %d\n", results.failed))
    r.ShowConsoleMsg("----------------------------------------\n")

    if results.failed > 0 then
        r.ShowConsoleMsg("\nFAILURES:\n")
        for _, msg in ipairs(results.messages) do
            r.ShowConsoleMsg(msg .. "\n")
        end
    else
        r.ShowConsoleMsg("\nAll tests PASSED!\n")
    end
end

-- Run if executed directly
run_all_tests()
