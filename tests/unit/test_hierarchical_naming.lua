--- Unit tests for hierarchical naming functions.
-- Tests the general hierarchical path and name building functions.
-- @module test_hierarchical_naming
-- @author Nomad Monad
-- @license MIT

local assert = require("assertions")
local naming = require("lib.utils.naming")

local M = {}

--------------------------------------------------------------------------------
-- Path String Building
--------------------------------------------------------------------------------

local function test_build_hierarchical_path_string()
    assert.section("Build hierarchical path string")

    -- Standalone device
    local path = {device_idx = 1}
    assert.equals("D1", naming.build_hierarchical_path_string(path), "Standalone device path")

    -- Rack
    path = {rack_idx = 1}
    assert.equals("R1", naming.build_hierarchical_path_string(path), "Rack path")

    -- Chain
    path = {rack_idx = 1, chain_idx = 2}
    assert.equals("R1_C2", naming.build_hierarchical_path_string(path), "Chain path")

    -- Device in chain
    path = {rack_idx = 1, chain_idx = 2, device_idx = 3}
    assert.equals("R1_C2_D3", naming.build_hierarchical_path_string(path), "Device in chain path")

    -- Empty path
    path = {}
    assert.equals("", naming.build_hierarchical_path_string(path), "Empty path")

    -- Nil path
    assert.equals("", naming.build_hierarchical_path_string(nil), "Nil path")
end

--------------------------------------------------------------------------------
-- Extract Path from Name
--------------------------------------------------------------------------------

local function test_extract_path_from_name()
    assert.section("Extract path from name")

    -- Device in chain
    assert.equals("R1_C2_D3", naming.extract_path_from_name("R1_C2_D3: ReaComp"), "Device in chain")
    assert.equals("R1_C2_D3", naming.extract_path_from_name("R1_C2_D3_M1: Modulator"), "Modulator in chain device")
    assert.equals("R1_C2_D3", naming.extract_path_from_name("R1_C2_D3_Util"), "Utility in chain device")

    -- Chain
    assert.equals("R1_C2", naming.extract_path_from_name("R1_C2"), "Chain")
    assert.equals("R1_C2", naming.extract_path_from_name("R1_C2: Some Name"), "Chain with name")

    -- Rack
    assert.equals("R1", naming.extract_path_from_name("R1: Rack"), "Rack")

    -- Standalone device
    assert.equals("D1", naming.extract_path_from_name("D1: ReaComp"), "Standalone device")
    assert.equals("D1", naming.extract_path_from_name("D1_M2: Modulator"), "Modulator in standalone device")

    -- No path
    assert.is_nil(naming.extract_path_from_name("ReaComp"), "No hierarchical path")
    assert.is_nil(naming.extract_path_from_name("VST: ReaComp"), "Plugin without path")
    assert.is_nil(naming.extract_path_from_name(nil), "Nil name")
end

--------------------------------------------------------------------------------
-- Build Hierarchical Names
--------------------------------------------------------------------------------

local function test_build_hierarchical_name()
    assert.section("Build hierarchical name")

    -- Device names
    assert.equals("D1: ReaComp", naming.build_hierarchical_name("D1", "device", nil, "ReaComp"), "Standalone device")
    assert.equals("R1_C2_D3: ReaEQ", naming.build_hierarchical_name("R1_C2_D3", "device", nil, "ReaEQ"), "Chain device")

    -- FX names
    assert.equals("D1_FX: ReaComp", naming.build_hierarchical_name("D1", "fx", nil, "ReaComp"), "Standalone device FX")
    assert.equals("R1_C2_D3_FX: ReaEQ", naming.build_hierarchical_name("R1_C2_D3", "fx", nil, "ReaEQ"), "Chain device FX")

    -- Utility names
    assert.equals("D1_Util", naming.build_hierarchical_name("D1", "util"), "Standalone device utility")
    assert.equals("R1_C2_D3_Util", naming.build_hierarchical_name("R1_C2_D3", "util"), "Chain device utility")

    -- Modulator names
    assert.equals("D1_M1: SideFX Modulator", naming.build_hierarchical_name("D1", "modulator", 1, "SideFX Modulator"), "First modulator in standalone device")
    assert.equals("D1_M2: SideFX Modulator", naming.build_hierarchical_name("D1", "modulator", 2, "SideFX Modulator"), "Second modulator in standalone device")
    assert.equals("R1_C2_D3_M1: SideFX Modulator", naming.build_hierarchical_name("R1_C2_D3", "modulator", 1, "SideFX Modulator"), "Modulator in chain device")

    -- Mixer names
    assert.equals("_R1_M", naming.build_hierarchical_name("R1", "mixer"), "Rack mixer")

    -- Rack names
    assert.equals("R1: Rack", naming.build_hierarchical_name("R1", "rack", nil, "Rack"), "Rack")
    assert.equals("R1: My Rack", naming.build_hierarchical_name("R1", "rack", nil, "My Rack"), "Rack with custom name")

    -- Chain names
    assert.equals("R1_C2", naming.build_hierarchical_name("R1_C2", "chain"), "Chain")

    -- Using path table instead of string
    local path = {rack_idx = 1, chain_idx = 2, device_idx = 3}
    assert.equals("R1_C2_D3_M1: SideFX Modulator", naming.build_hierarchical_name(path, "modulator", 1, "SideFX Modulator"), "Modulator using path table")
end

--------------------------------------------------------------------------------
-- Integration: Extract and Build
--------------------------------------------------------------------------------

local function test_extract_and_rebuild_name()
    assert.section("Extract path and rebuild name")

    -- Extract path from existing name and build new component name
    local device_name = "R1_C2_D3: ReaComp"
    local device_path = naming.extract_path_from_name(device_name)
    assert.equals("R1_C2_D3", device_path, "Extracted path")

    -- Build modulator name using extracted path
    local mod_name = naming.build_hierarchical_name(device_path, "modulator", 1, "SideFX Modulator")
    assert.equals("R1_C2_D3_M1: SideFX Modulator", mod_name, "Modulator name from extracted path")

    -- Build utility name using extracted path
    local util_name = naming.build_hierarchical_name(device_path, "util")
    assert.equals("R1_C2_D3_Util", util_name, "Utility name from extracted path")
end

--------------------------------------------------------------------------------
-- Test Runner
--------------------------------------------------------------------------------

function M.run()
    test_build_hierarchical_path_string()
    test_extract_path_from_name()
    test_build_hierarchical_name()
    test_extract_and_rebuild_name()
end

return M
