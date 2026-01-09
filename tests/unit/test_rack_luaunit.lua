--- Unit tests for SideFX rack utilities (LuaUnit version).
-- Tests rack-related naming and helper functions.
-- @module unit.test_rack_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local naming = require("lib.utils.naming")

TestRack = {}

function TestRack:test_build_rack_name()
    luaunit.assertEquals("R1: Rack", naming.build_rack_name(1), "builds rack 1 name")
    luaunit.assertEquals("R2: Rack", naming.build_rack_name(2), "builds rack 2 name")
    luaunit.assertEquals("R10: Rack", naming.build_rack_name(10), "builds rack 10 name")
end

function TestRack:test_build_chain_name()
    luaunit.assertEquals("R1_C1", naming.build_chain_name(1, 1), "builds chain R1_C1")
    luaunit.assertEquals("R1_C2", naming.build_chain_name(1, 2), "builds chain R1_C2")
    luaunit.assertEquals("R2_C3", naming.build_chain_name(2, 3), "builds chain R2_C3")
end

function TestRack:test_build_mixer_name()
    luaunit.assertEquals("_R1_M", naming.build_mixer_name(1), "builds mixer name R1")
    luaunit.assertEquals("_R2_M", naming.build_mixer_name(2), "builds mixer name R2")
end

function TestRack:test_build_chain_device_name()
    luaunit.assertEquals("R1_C1_D1: ReaComp", naming.build_chain_device_name(1, 1, 1, "ReaComp"), "builds chain device name")
    luaunit.assertEquals("R2_C3_D2: ReaEQ", naming.build_chain_device_name(2, 3, 2, "ReaEQ"), "builds chain device with higher indices")
end

function TestRack:test_build_chain_device_fx_name()
    luaunit.assertEquals("R1_C1_D1_FX: ReaComp", naming.build_chain_device_fx_name(1, 1, 1, "ReaComp"), "builds chain device FX name")
end

function TestRack:test_build_chain_device_util_name()
    luaunit.assertEquals("R1_C1_D1_Util", naming.build_chain_device_util_name(1, 1, 1), "builds chain device util name")
    luaunit.assertEquals("R2_C3_D2_Util", naming.build_chain_device_util_name(2, 3, 2), "builds chain device util with higher indices")
end

function TestRack:test_is_rack_name()
    luaunit.assertTrue(naming.is_rack_name("R1: Rack"), "detects R1: Rack")
    luaunit.assertTrue(naming.is_rack_name("R2: My Rack"), "detects R2: My Rack")
    luaunit.assertTrue(naming.is_rack_name("R10: Rack"), "detects R10: Rack")
    luaunit.assertFalse(naming.is_rack_name("D1: ReaComp"), "rejects D1: prefix")
    luaunit.assertFalse(naming.is_rack_name("R1_C1"), "rejects chain name")
    luaunit.assertFalse(naming.is_rack_name("Container"), "rejects plain Container")
    luaunit.assertFalse(naming.is_rack_name(nil), "handles nil")
end

function TestRack:test_is_chain_name()
    luaunit.assertTrue(naming.is_chain_name("R1_C1"), "detects R1_C1")
    luaunit.assertTrue(naming.is_chain_name("R2_C3"), "detects R2_C3")
    luaunit.assertTrue(naming.is_chain_name("R10_C15"), "detects R10_C15")
    luaunit.assertFalse(naming.is_chain_name("R1: Rack"), "rejects rack name")
    luaunit.assertFalse(naming.is_chain_name("D1: ReaComp"), "rejects device name")
    luaunit.assertFalse(naming.is_chain_name("R1_C1_D1: ReaComp"), "rejects chain device name")
    luaunit.assertFalse(naming.is_chain_name(nil), "handles nil")
end

function TestRack:test_is_mixer_name()
    luaunit.assertTrue(naming.is_mixer_name("_R1_M"), "detects _R1_M")
    luaunit.assertTrue(naming.is_mixer_name("_R2_M"), "detects _R2_M")
    luaunit.assertTrue(naming.is_mixer_name("_R10_M"), "detects _R10_M")
    luaunit.assertFalse(naming.is_mixer_name("R1_M"), "rejects without underscore")
    luaunit.assertFalse(naming.is_mixer_name("R1: Rack"), "rejects rack name")
    luaunit.assertFalse(naming.is_mixer_name(nil), "handles nil")
end

function TestRack:test_parse_rack_index()
    luaunit.assertEquals(1, naming.parse_rack_index("R1: Rack"), "parses R1 index")
    luaunit.assertEquals(2, naming.parse_rack_index("R2: Rack"), "parses R2 index")
    luaunit.assertEquals(10, naming.parse_rack_index("R10: Rack"), "parses R10 index")
    luaunit.assertEquals(1, naming.parse_rack_index("R1_C1"), "parses from chain name")
    luaunit.assertEquals(2, naming.parse_rack_index("R2_C3_D1: ReaComp"), "parses from chain device name")
    luaunit.assertIsNil(naming.parse_rack_index("D1: ReaComp"), "returns nil for non-rack")
    luaunit.assertIsNil(naming.parse_rack_index(nil), "handles nil")
end

function TestRack:test_parse_chain_index()
    luaunit.assertEquals(1, naming.parse_chain_index("R1_C1"), "parses C1 index")
    luaunit.assertEquals(3, naming.parse_chain_index("R2_C3"), "parses C3 index")
    luaunit.assertEquals(15, naming.parse_chain_index("R1_C15"), "parses C15 index")
    luaunit.assertEquals(2, naming.parse_chain_index("R1_C2_D1: ReaComp"), "parses from chain device name")
    luaunit.assertIsNil(naming.parse_chain_index("R1: Rack"), "returns nil for rack")
    luaunit.assertIsNil(naming.parse_chain_index(nil), "handles nil")
end

function TestRack:test_parse_hierarchy_for_racks()
    local h1 = naming.parse_hierarchy("R1: Rack")
    luaunit.assertEquals(1, h1.rack_idx, "parses rack_idx from rack name")
    luaunit.assertIsNil(h1.chain_idx, "no chain_idx in rack name")
    luaunit.assertIsNil(h1.device_idx, "no device_idx in rack name")

    local h2 = naming.parse_hierarchy("R2_C3")
    luaunit.assertEquals(2, h2.rack_idx, "parses rack_idx from chain name")
    luaunit.assertEquals(3, h2.chain_idx, "parses chain_idx from chain name")
    luaunit.assertIsNil(h2.device_idx, "no device_idx in chain name")

    local h3 = naming.parse_hierarchy("R1_C2_D3: ReaComp")
    luaunit.assertEquals(1, h3.rack_idx, "parses rack_idx from chain device")
    luaunit.assertEquals(2, h3.chain_idx, "parses chain_idx from chain device")
    luaunit.assertEquals(3, h3.device_idx, "parses device_idx from chain device")
    luaunit.assertEquals("ReaComp", h3.fx_name, "parses fx_name from chain device")
end

function TestRack:test_strip_sidefx_prefixes_for_rack_names()
    luaunit.assertEquals("Rack", naming.strip_sidefx_prefixes("R1: Rack"), "strips R1: prefix")
    luaunit.assertEquals("My Rack", naming.strip_sidefx_prefixes("R2: My Rack"), "strips R2: prefix with name")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1: ReaComp"), "strips full chain device prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1_FX: ReaComp"), "strips chain device FX prefix")
end
