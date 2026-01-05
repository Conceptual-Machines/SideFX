--- Integration tests for deeply nested rack structures.
-- Tests operations on racks nested 4+ levels deep, including state management,
-- device/chain operations, and edge cases specific to deep nesting.
--
-- To run: Load this script as a ReaScript action in REAPER
--
-- @module integration.test_deeply_nested
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
    r.GetSetMediaTrackInfo_String(track_ptr, "P_NAME", "_SideFX_DeepNested_Test", true)
    
    test_track = Track:new(track_ptr)
    
    -- Set up state for rack module
    state.track = test_track
    state.track_name = "_SideFX_DeepNested_Test"
    
    return test_track
end

local function cleanup_test_track()
    if test_track then
        r.DeleteTrack(test_track.pointer)
        test_track = nil
        state.track = nil
        state.track_name = ""
    end
    r.Undo_EndBlock("SideFX Deeply Nested Integration Test", -1)
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

local function find_rack_by_index(idx)
    return find_fx_by_name_pattern("^R" .. idx .. ":")
end

local function count_chains_in_rack(rack)
    if not rack then return 0 end
    -- Use fx_utils function which properly counts chains
    return fx_utils.count_chains_in_rack(rack)
end

--------------------------------------------------------------------------------
-- Tests: Deep Nesting (4+ levels)
--------------------------------------------------------------------------------

local function test_four_level_nesting()
    assert.section("Create 4-level nested rack structure")
    
    setup_test_track()
    clear_track_fx()
    
    -- Level 1: Top-level rack
    local rack1 = rack_module.add_rack_to_track(nil)
    assert.not_nil(rack1, "Rack1 should be created")
    
    -- Level 2: Nested in rack1
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    assert.not_nil(rack2, "Rack2 should be created")
    rack2 = find_rack_by_index(2)
    assert.not_nil(rack2, "Should find rack2")
    
    -- Level 3: Nested in rack2
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    assert.not_nil(rack3, "Rack3 should be created")
    rack3 = find_rack_by_index(3)
    assert.not_nil(rack3, "Should find rack3")
    
    -- Level 4: Nested in rack3
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    assert.not_nil(rack4, "Rack4 should be created")
    rack4 = find_rack_by_index(4)
    assert.not_nil(rack4, "Should find rack4")
    
    -- Verify all racks exist and have mixers
    rack1 = find_rack_by_index(1)
    rack2 = find_rack_by_index(2)
    rack3 = find_rack_by_index(3)
    rack4 = find_rack_by_index(4)
    
    assert.not_nil(rack1, "Rack1 should exist")
    assert.not_nil(rack2, "Rack2 should exist")
    assert.not_nil(rack3, "Rack3 should exist")
    assert.not_nil(rack4, "Rack4 should exist")
    
    local mixer1 = fx_utils.get_rack_mixer(rack1)
    local mixer2 = fx_utils.get_rack_mixer(rack2)
    local mixer3 = fx_utils.get_rack_mixer(rack3)
    local mixer4 = fx_utils.get_rack_mixer(rack4)
    
    assert.not_nil(mixer1, "Rack1 should have mixer")
    assert.not_nil(mixer2, "Rack2 should have mixer")
    assert.not_nil(mixer3, "Rack3 should have mixer")
    assert.not_nil(mixer4, "Rack4 should have mixer")
    
    cleanup_test_track()
end

local function test_five_level_nesting()
    assert.section("Create 5-level nested rack structure")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 5 levels deep
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    local rack5 = rack_module.add_nested_rack_to_rack(rack4)
    
    -- Verify all levels exist
    rack1 = find_rack_by_index(1)
    rack2 = find_rack_by_index(2)
    rack3 = find_rack_by_index(3)
    rack4 = find_rack_by_index(4)
    rack5 = find_rack_by_index(5)
    
    assert.not_nil(rack1, "Rack1 should exist")
    assert.not_nil(rack2, "Rack2 should exist")
    assert.not_nil(rack3, "Rack3 should exist")
    assert.not_nil(rack4, "Rack4 should exist")
    assert.not_nil(rack5, "Rack5 should exist")
    
    -- Verify parent relationships
    local rack2_parent = rack2:get_parent_container()
    local rack3_parent = rack3:get_parent_container()
    local rack4_parent = rack4:get_parent_container()
    local rack5_parent = rack5:get_parent_container()
    
    assert.not_nil(rack2_parent, "Rack2 should have parent")
    assert.not_nil(rack3_parent, "Rack3 should have parent")
    assert.not_nil(rack4_parent, "Rack4 should have parent")
    assert.not_nil(rack5_parent, "Rack5 should have parent")
    
    cleanup_test_track()
end

local function test_add_chain_to_deeply_nested_rack()
    assert.section("Add chain to rack at level 4")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 4 levels deep
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    
    -- Add chain to deepest rack
    local plugin = { full_name = "VST: ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack4, plugin)
    
    assert.not_nil(chain, "Chain should be added to rack4")
    
    -- Verify chain exists in rack4
    rack4 = find_rack_by_index(4)
    local chain_count = count_chains_in_rack(rack4)
    assert.equals(1, chain_count, "Rack4 should have 1 chain")
    
    cleanup_test_track()
end

local function test_add_device_to_deeply_nested_chain()
    assert.section("Add device to chain in 4-level nested rack")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 4 levels deep with chain
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    
    -- Add chain to deepest rack
    local plugin1 = { full_name = "VST: ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack4, plugin1)
    assert.not_nil(chain, "Chain should be created")
    
    -- Re-find chain
    rack4 = find_rack_by_index(4)
    local chains = {}
    for child in rack4:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name and not name:match("^_") and not name:find("Mixer") then
            table.insert(chains, child)
        end
    end
    assert.equals(1, #chains, "Should have 1 chain")
    chain = chains[1]
    
    -- Add device to chain
    local plugin2 = { full_name = "VST: ReaEQ", name = "ReaEQ" }
    local device = rack_module.add_device_to_chain(chain, plugin2)
    
    assert.not_nil(device, "Device should be added to chain")
    
    cleanup_test_track()
end

local function test_multiple_chains_in_deeply_nested_rack()
    assert.section("Add multiple chains to deeply nested rack")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 4 levels deep
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    
    -- Add 3 chains to deepest rack
    local plugin1 = { full_name = "VST: ReaComp", name = "ReaComp" }
    local plugin2 = { full_name = "VST: ReaEQ", name = "ReaEQ" }
    local plugin3 = { full_name = "JS: Volume", name = "Volume" }
    
    rack_module.add_chain_to_rack(rack4, plugin1)
    rack_module.add_chain_to_rack(rack4, plugin2)
    rack_module.add_chain_to_rack(rack4, plugin3)
    
    -- Verify all chains exist
    rack4 = find_rack_by_index(4)
    local chain_count = count_chains_in_rack(rack4)
    assert.equals(3, chain_count, "Rack4 should have 3 chains")
    
    cleanup_test_track()
end

local function test_expansion_state_deeply_nested()
    assert.section("Expansion state in 5-level nested structure")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 5 levels deep
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    local rack5 = rack_module.add_nested_rack_to_rack(rack4)
    rack5 = find_rack_by_index(5)
    
    -- Get GUIDs
    local rack1_guid = rack1:get_guid()
    local rack2_guid = rack2:get_guid()
    local rack3_guid = rack3:get_guid()
    local rack4_guid = rack4:get_guid()
    local rack5_guid = rack5:get_guid()
    
    -- Set expansion state for different levels
    state.expanded_path[1] = rack1_guid  -- Top-level
    state.expanded_racks[rack2_guid] = true
    state.expanded_racks[rack3_guid] = true
    state.expanded_racks[rack4_guid] = false  -- Collapsed
    state.expanded_racks[rack5_guid] = true
    
    -- Verify state is independent
    assert.equals(rack1_guid, state.expanded_path[1], "Top-level should be expanded")
    assert.truthy(state.expanded_racks[rack2_guid], "Rack2 should be expanded")
    assert.truthy(state.expanded_racks[rack3_guid], "Rack3 should be expanded")
    assert.falsy(state.expanded_racks[rack4_guid], "Rack4 should be collapsed")
    assert.truthy(state.expanded_racks[rack5_guid], "Rack5 should be expanded")
    
    cleanup_test_track()
end

local function test_chain_expansion_in_deeply_nested()
    assert.section("Chain expansion state in deeply nested rack")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 4 levels deep with chain
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    
    -- Add chain to rack4
    local plugin = { full_name = "VST: ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack4, plugin)
    local chain_guid = chain:get_guid()
    local rack4_guid = rack4:get_guid()
    
    -- Set chain expansion state
    state.expanded_racks[rack4_guid] = true
    state.expanded_nested_chains[rack4_guid] = chain_guid
    
    -- Verify state
    assert.truthy(state.expanded_racks[rack4_guid], "Rack4 should be expanded")
    assert.equals(chain_guid, state.expanded_nested_chains[rack4_guid], "Chain should be selected")
    
    cleanup_test_track()
end

local function test_operations_at_different_nesting_levels()
    assert.section("Perform operations at different nesting levels simultaneously")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 4 levels deep and save GUIDs
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack1_guid = rack1:get_guid()
    
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    local rack2_guid = rack2:get_guid()
    
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    local rack3_guid = rack3:get_guid()
    
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    local rack4_guid = rack4:get_guid()
    
    -- Add chains at different levels
    local plugin1 = { full_name = "VST: ReaComp", name = "ReaComp" }
    local plugin2 = { full_name = "VST: ReaEQ", name = "ReaEQ" }
    local plugin3 = { full_name = "JS: Volume", name = "Volume" }
    
    -- Give REAPER time to process nested rack additions
    r.PreventUIRefresh(-1)
    r.PreventUIRefresh(1)
    
    -- Re-find racks by GUID before operations (fresh references)
    rack2 = test_track:find_fx_by_guid(rack2_guid)
    rack3 = test_track:find_fx_by_guid(rack3_guid)
    rack4 = test_track:find_fx_by_guid(rack4_guid)
    
    r.ShowConsoleMsg(string.format("\n=== Adding chains to nested racks ===\n"))
    r.ShowConsoleMsg(string.format("Rack2: %s (pointer: 0x%X)\n", rack2:get_name(), rack2.pointer))
    r.ShowConsoleMsg(string.format("Rack3: %s (pointer: 0x%X)\n", rack3:get_name(), rack3.pointer))
    r.ShowConsoleMsg(string.format("Rack4: %s (pointer: 0x%X)\n", rack4:get_name(), rack4.pointer))
    
    local chain1 = rack_module.add_chain_to_rack(rack2, plugin1)  -- Level 2
    r.ShowConsoleMsg(string.format("Chain added to Rack2: %s\n", chain1 and "SUCCESS" or "FAILED"))
    
    -- CRITICAL: After modifying Rack2, ALL nested containers get new pointers!
    -- Must re-find Rack3 and Rack4 by GUID
    rack3 = test_track:find_fx_by_guid(rack3_guid)
    rack4 = test_track:find_fx_by_guid(rack4_guid)
    r.ShowConsoleMsg(string.format("After Rack2 op - Rack3 pointer: 0x%X, Rack4 pointer: 0x%X\n", 
        rack3 and rack3.pointer or 0, rack4 and rack4.pointer or 0))
    
    local chain2 = rack_module.add_chain_to_rack(rack3, plugin2)  -- Level 3
    r.ShowConsoleMsg(string.format("Chain added to Rack3: %s\n", chain2 and "SUCCESS" or "FAILED"))
    
    -- CRITICAL: After modifying Rack3, Rack4 (nested inside it) gets a new pointer!
    rack4 = test_track:find_fx_by_guid(rack4_guid)
    r.ShowConsoleMsg(string.format("After Rack3 op - Rack4 pointer: 0x%X\n", rack4 and rack4.pointer or 0))
    
    local chain3 = rack_module.add_chain_to_rack(rack4, plugin3)  -- Level 4
    r.ShowConsoleMsg(string.format("Chain added to Rack4: %s\n", chain3 and "SUCCESS" or "FAILED"))
    
    -- Give REAPER time to process chain additions
    r.PreventUIRefresh(-1)
    r.PreventUIRefresh(1)
    
    -- Verify chains exist at each level
    -- Re-find all racks by GUID to get fresh references after operations
    rack1 = test_track:find_fx_by_guid(rack1_guid)
    rack2 = test_track:find_fx_by_guid(rack2_guid)
    rack3 = test_track:find_fx_by_guid(rack3_guid)
    rack4 = test_track:find_fx_by_guid(rack4_guid)
    
    r.ShowConsoleMsg(string.format("\n=== Verification ===\n"))
    
    if not rack2 or not rack3 or not rack4 then
        r.ShowConsoleMsg("CRITICAL ERROR: Could not re-find racks by GUID after operations!\n")
        if not rack2 then r.ShowConsoleMsg("  - Rack2 is nil\n") end
        if not rack3 then r.ShowConsoleMsg("  - Rack3 is nil\n") end
        if not rack4 then r.ShowConsoleMsg("  - Rack4 is nil\n") end
    end
    
    -- add_nested_rack_to_rack creates a chain containing the nested rack
    -- add_chain_to_rack creates another chain
    -- So rack2 should have: 1 chain with nested rack (rack3) + 1 chain with plugin1 = 2 chains
    local rack2_chains = rack2 and count_chains_in_rack(rack2) or 0
    r.ShowConsoleMsg(string.format("Rack2 has %d chains (expected: 2)\n", rack2_chains))
    assert.equals(2, rack2_chains, "Rack2 should have 2 chains (1 nested rack + 1 plugin) (got " .. rack2_chains .. ")")
    
    -- Rack3 should have: 1 chain with nested rack (rack4) + 1 chain with plugin2 = 2 chains
    local rack3_chains = rack3 and count_chains_in_rack(rack3) or 0
    r.ShowConsoleMsg(string.format("Rack3 has %d chains (expected: 2)\n", rack3_chains))
    assert.equals(2, rack3_chains, "Rack3 should have 2 chains (1 nested rack + 1 plugin) (got " .. rack3_chains .. ")")
    
    -- Rack4 should have: 1 chain with plugin3
    local rack4_chains = rack4 and count_chains_in_rack(rack4) or 0
    r.ShowConsoleMsg(string.format("Rack4 has %d chains (expected: 1)\n", rack4_chains))
    assert.equals(1, rack4_chains, "Rack4 should have 1 chain (got " .. rack4_chains .. ")")
    
    cleanup_test_track()
end

local function test_stale_pointer_recovery_deep_nesting()
    assert.section("Stale pointer recovery in deeply nested structure")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 5 levels deep
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    local rack5 = rack_module.add_nested_rack_to_rack(rack4)
    
    -- Get GUIDs before operations
    local rack5_guid = rack5:get_guid()
    
    -- Add chain to rack5 (this may cause pointer refresh)
    local plugin = { full_name = "VST: ReaComp", name = "ReaComp" }
    local chain = rack_module.add_chain_to_rack(rack5, plugin)
    
    -- Re-find rack5 by GUID (should work even if pointer was stale)
    rack5 = test_track:find_fx_by_guid(rack5_guid)
    assert.not_nil(rack5, "Should be able to re-find rack5 by GUID")
    
    -- Verify chain was added
    local chain_count = count_chains_in_rack(rack5)
    assert.equals(1, chain_count, "Rack5 should have 1 chain")
    
    cleanup_test_track()
end

local function test_mixer_volume_persistence_deep_nesting()
    assert.section("Mixer volume persistence in deeply nested racks")
    
    setup_test_track()
    clear_track_fx()
    
    -- Build 4 levels deep with chains
    local rack1 = rack_module.add_rack_to_track(nil)
    local rack2 = rack_module.add_nested_rack_to_rack(rack1)
    rack2 = find_rack_by_index(2)
    local rack3 = rack_module.add_nested_rack_to_rack(rack2)
    rack3 = find_rack_by_index(3)
    local rack4 = rack_module.add_nested_rack_to_rack(rack3)
    rack4 = find_rack_by_index(4)
    
    -- Add chains to rack4
    local plugin1 = { full_name = "VST: ReaComp", name = "ReaComp" }
    local plugin2 = { full_name = "VST: ReaEQ", name = "ReaEQ" }
    
    rack_module.add_chain_to_rack(rack4, plugin1)
    rack_module.add_chain_to_rack(rack4, plugin2)
    
    -- Verify mixer volumes are set correctly
    rack4 = find_rack_by_index(4)
    local mixer = fx_utils.get_rack_mixer(rack4)
    assert.not_nil(mixer, "Rack4 should have mixer")
    
    -- Check chain 1 volume (param 2)
    local vol_param1 = rack_module.get_mixer_chain_volume_param(1)
    local vol_norm1 = mixer:get_param_normalized(vol_param1)
    local expected_0db = 60 / 72  -- 0.833...
    -- Use tolerance for floating point comparison
    assert.truthy(math.abs(vol_norm1 - expected_0db) < 0.0001, 
        string.format("Chain 1 volume should be 0 dB (expected: %.6f, got: %.6f)", expected_0db, vol_norm1))
    
    -- Check chain 2 volume (param 3)
    local vol_param2 = rack_module.get_mixer_chain_volume_param(2)
    local vol_norm2 = mixer:get_param_normalized(vol_param2)
    assert.truthy(math.abs(vol_norm2 - expected_0db) < 0.0001,
        string.format("Chain 2 volume should be 0 dB (expected: %.6f, got: %.6f)", expected_0db, vol_norm2))
    
    cleanup_test_track()
end

--------------------------------------------------------------------------------
-- Test Runner
--------------------------------------------------------------------------------

local tests = {
    { name = "test_four_level_nesting", fn = test_four_level_nesting },
    { name = "test_five_level_nesting", fn = test_five_level_nesting },
    { name = "test_add_chain_to_deeply_nested_rack", fn = test_add_chain_to_deeply_nested_rack },
    { name = "test_add_device_to_deeply_nested_chain", fn = test_add_device_to_deeply_nested_chain },
    { name = "test_multiple_chains_in_deeply_nested_rack", fn = test_multiple_chains_in_deeply_nested_rack },
    { name = "test_expansion_state_deeply_nested", fn = test_expansion_state_deeply_nested },
    { name = "test_chain_expansion_in_deeply_nested", fn = test_chain_expansion_in_deeply_nested },
    { name = "test_operations_at_different_nesting_levels", fn = test_operations_at_different_nesting_levels },
    { name = "test_stale_pointer_recovery_deep_nesting", fn = test_stale_pointer_recovery_deep_nesting },
    { name = "test_mixer_volume_persistence_deep_nesting", fn = test_mixer_volume_persistence_deep_nesting },
}

-- Run all tests
for _, test in ipairs(tests) do
    local ok, err = pcall(test.fn)
    if not ok then
        r.ShowConsoleMsg("ERROR in " .. test.name .. ": " .. tostring(err) .. "\n")
    end
end

