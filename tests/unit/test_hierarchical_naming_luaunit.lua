--- Unit tests for hierarchical naming functions (LuaUnit version).
-- Tests the general hierarchical path and name building functions.
-- @module unit.test_hierarchical_naming_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local naming = require("lib.utils.naming")

TestHierarchicalNaming = {}

function TestHierarchicalNaming:test_build_hierarchical_path_string()
    -- Standalone device
    local path = {device_idx = 1}
    luaunit.assertEquals("D1", naming.build_hierarchical_path_string(path), "Standalone device path")

    -- Rack
    path = {rack_idx = 1}
    luaunit.assertEquals("R1", naming.build_hierarchical_path_string(path), "Rack path")

    -- Chain
    path = {rack_idx = 1, chain_idx = 2}
    luaunit.assertEquals("R1_C2", naming.build_hierarchical_path_string(path), "Chain path")

    -- Device in chain
    path = {rack_idx = 1, chain_idx = 2, device_idx = 3}
    luaunit.assertEquals("R1_C2_D3", naming.build_hierarchical_path_string(path), "Device in chain path")

    -- Empty path
    path = {}
    luaunit.assertEquals("", naming.build_hierarchical_path_string(path), "Empty path")

    -- Nil path
    luaunit.assertEquals("", naming.build_hierarchical_path_string(nil), "Nil path")
end

function TestHierarchicalNaming:test_extract_path_from_name()
    -- Device in chain
    luaunit.assertEquals("R1_C2_D3", naming.extract_path_from_name("R1_C2_D3: ReaComp"), "Device in chain")
    luaunit.assertEquals("R1_C2_D3", naming.extract_path_from_name("R1_C2_D3_M1: Modulator"), "Modulator in chain device")
    luaunit.assertEquals("R1_C2_D3", naming.extract_path_from_name("R1_C2_D3_Util"), "Utility in chain device")

    -- Chain
    luaunit.assertEquals("R1_C2", naming.extract_path_from_name("R1_C2"), "Chain")
    luaunit.assertEquals("R1_C2", naming.extract_path_from_name("R1_C2: Some Name"), "Chain with name")

    -- Rack
    luaunit.assertEquals("R1", naming.extract_path_from_name("R1: Rack"), "Rack")

    -- Standalone device
    luaunit.assertEquals("D1", naming.extract_path_from_name("D1: ReaComp"), "Standalone device")
    luaunit.assertEquals("D1", naming.extract_path_from_name("D1_M2: Modulator"), "Modulator in standalone device")

    -- No path
    luaunit.assertIsNil(naming.extract_path_from_name("ReaComp"), "No hierarchical path")
    luaunit.assertIsNil(naming.extract_path_from_name("VST: ReaComp"), "Plugin without path")
    luaunit.assertIsNil(naming.extract_path_from_name(nil), "Nil name")
end

function TestHierarchicalNaming:test_build_hierarchical_name()
    -- Device names
    luaunit.assertEquals("D1: ReaComp", naming.build_hierarchical_name("D1", "device", nil, "ReaComp"), "Standalone device")
    luaunit.assertEquals("R1_C2_D3: ReaEQ", naming.build_hierarchical_name("R1_C2_D3", "device", nil, "ReaEQ"), "Chain device")

    -- FX names
    luaunit.assertEquals("D1_FX: ReaComp", naming.build_hierarchical_name("D1", "fx", nil, "ReaComp"), "Standalone device FX")
    luaunit.assertEquals("R1_C2_D3_FX: ReaEQ", naming.build_hierarchical_name("R1_C2_D3", "fx", nil, "ReaEQ"), "Chain device FX")

    -- Utility names
    luaunit.assertEquals("D1_Util", naming.build_hierarchical_name("D1", "util"), "Standalone device utility")
    luaunit.assertEquals("R1_C2_D3_Util", naming.build_hierarchical_name("R1_C2_D3", "util"), "Chain device utility")

    -- Modulator names
    luaunit.assertEquals("D1_M1: SideFX Modulator", naming.build_hierarchical_name("D1", "modulator", 1, "SideFX Modulator"), "First modulator in standalone device")
    luaunit.assertEquals("D1_M2: SideFX Modulator", naming.build_hierarchical_name("D1", "modulator", 2, "SideFX Modulator"), "Second modulator in standalone device")
    luaunit.assertEquals("R1_C2_D3_M1: SideFX Modulator", naming.build_hierarchical_name("R1_C2_D3", "modulator", 1, "SideFX Modulator"), "Modulator in chain device")

    -- Mixer names
    luaunit.assertEquals("_R1_M", naming.build_hierarchical_name("R1", "mixer"), "Rack mixer")

    -- Rack names
    luaunit.assertEquals("R1: Rack", naming.build_hierarchical_name("R1", "rack", nil, "Rack"), "Rack")
    luaunit.assertEquals("R1: My Rack", naming.build_hierarchical_name("R1", "rack", nil, "My Rack"), "Rack with custom name")

    -- Chain names
    luaunit.assertEquals("R1_C2", naming.build_hierarchical_name("R1_C2", "chain"), "Chain")

    -- Using path table instead of string
    local path = {rack_idx = 1, chain_idx = 2, device_idx = 3}
    luaunit.assertEquals("R1_C2_D3_M1: SideFX Modulator", naming.build_hierarchical_name(path, "modulator", 1, "SideFX Modulator"), "Modulator using path table")
end

function TestHierarchicalNaming:test_extract_and_rebuild_name()
    -- Extract path from existing name and build new component name
    local device_name = "R1_C2_D3: ReaComp"
    local device_path = naming.extract_path_from_name(device_name)
    luaunit.assertEquals("R1_C2_D3", device_path, "Extracted path")

    -- Build modulator name using extracted path
    local mod_name = naming.build_hierarchical_name(device_path, "modulator", 1, "SideFX Modulator")
    luaunit.assertEquals("R1_C2_D3_M1: SideFX Modulator", mod_name, "Modulator name from extracted path")

    -- Build utility name using extracted path
    local util_name = naming.build_hierarchical_name(device_path, "util")
    luaunit.assertEquals("R1_C2_D3_Util", util_name, "Utility name from extracted path")
end
