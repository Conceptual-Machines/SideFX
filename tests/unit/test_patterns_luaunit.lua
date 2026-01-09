--- Unit tests for SideFX pattern matching utilities (LuaUnit version).
-- Tests the lib/utils/naming.lua module pattern functions.
-- @module unit.test_patterns_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local naming = require("lib.utils.naming")

TestPatterns = {}

function TestPatterns:test_is_device_name()
    luaunit.assertTrue(naming.is_device_name("D1: ReaComp"), "matches D1: prefix")
    luaunit.assertTrue(naming.is_device_name("D12: ReaEQ"), "matches D12: prefix")
    luaunit.assertTrue(naming.is_device_name("D1_FX: ReaComp"), "matches D1_FX: prefix")
    luaunit.assertFalse(naming.is_device_name("ReaComp"), "rejects no prefix")
    luaunit.assertFalse(naming.is_device_name("R1: Rack"), "rejects R prefix")
    luaunit.assertFalse(naming.is_device_name(nil), "handles nil")
end

function TestPatterns:test_is_chain_name()
    luaunit.assertTrue(naming.is_chain_name("R1_C1"), "matches R1_C1")
    luaunit.assertTrue(naming.is_chain_name("R1_C1: ReaComp"), "matches R1_C1 with name")
    luaunit.assertFalse(naming.is_chain_name("R2_C3_D1: ReaComp"), "rejects device inside chain (has _D)")
    luaunit.assertFalse(naming.is_chain_name("R1: Rack"), "rejects rack")
    luaunit.assertFalse(naming.is_chain_name("D1: ReaComp"), "rejects device")
    luaunit.assertFalse(naming.is_chain_name(nil), "handles nil")
end

function TestPatterns:test_is_rack_name()
    luaunit.assertTrue(naming.is_rack_name("R1: Rack"), "matches R1: Rack")
    luaunit.assertTrue(naming.is_rack_name("R12: My Rack"), "matches R12: with custom name")
    luaunit.assertFalse(naming.is_rack_name("R1_C1"), "rejects chain (no colon)")
    luaunit.assertFalse(naming.is_rack_name("R1_C1: ReaComp"), "rejects chain with colon")
    luaunit.assertFalse(naming.is_rack_name("D1: ReaComp"), "rejects device")
    luaunit.assertFalse(naming.is_rack_name(nil), "handles nil")
end

function TestPatterns:test_is_internal_name()
    luaunit.assertTrue(naming.is_internal_name("_R1_M"), "matches mixer")
    luaunit.assertTrue(naming.is_internal_name("_hidden"), "matches any underscore prefix")
    luaunit.assertFalse(naming.is_internal_name("R1: Rack"), "rejects rack")
    luaunit.assertFalse(naming.is_internal_name("D1: ReaComp"), "rejects device")
    luaunit.assertFalse(naming.is_internal_name(nil), "handles nil")
end

function TestPatterns:test_is_mixer_name()
    luaunit.assertTrue(naming.is_mixer_name("_R1_M"), "matches _R1_M")
    luaunit.assertTrue(naming.is_mixer_name("_R12_M"), "matches _R12_M")
    luaunit.assertTrue(naming.is_mixer_name("JS: SideFX/SideFX_Mixer"), "matches full JSFX path")
    luaunit.assertTrue(naming.is_mixer_name("SideFX Mixer"), "matches display name")
    luaunit.assertFalse(naming.is_mixer_name("R1: Rack"), "rejects rack")
    luaunit.assertFalse(naming.is_mixer_name("Mixer"), "rejects plain Mixer")
    luaunit.assertFalse(naming.is_mixer_name(nil), "handles nil")
end

function TestPatterns:test_parse_device_index()
    luaunit.assertEquals(1, naming.parse_device_index("D1: ReaComp"), "parses D1")
    luaunit.assertEquals(12, naming.parse_device_index("D12: ReaEQ"), "parses D12")
    luaunit.assertEquals(1, naming.parse_device_index("D1_FX: ReaComp"), "parses D1_FX")
    luaunit.assertIsNil(naming.parse_device_index("R1: Rack"), "returns nil for rack")
    luaunit.assertIsNil(naming.parse_device_index("ReaComp"), "returns nil for no prefix")
    luaunit.assertIsNil(naming.parse_device_index(nil), "handles nil")
end

function TestPatterns:test_parse_rack_index()
    luaunit.assertEquals(1, naming.parse_rack_index("R1: Rack"), "parses R1")
    luaunit.assertEquals(12, naming.parse_rack_index("R12: My Rack"), "parses R12")
    luaunit.assertEquals(1, naming.parse_rack_index("R1_C1"), "parses from chain")
    luaunit.assertIsNil(naming.parse_rack_index("D1: ReaComp"), "returns nil for device")
    luaunit.assertIsNil(naming.parse_rack_index(nil), "handles nil")
end

function TestPatterns:test_parse_chain_index()
    luaunit.assertEquals(1, naming.parse_chain_index("R1_C1"), "parses C1")
    luaunit.assertEquals(3, naming.parse_chain_index("R2_C3_D1: ReaComp"), "parses C3 from nested")
    luaunit.assertIsNil(naming.parse_chain_index("R1: Rack"), "returns nil for rack")
    luaunit.assertIsNil(naming.parse_chain_index("D1: ReaComp"), "returns nil for device")
    luaunit.assertIsNil(naming.parse_chain_index(nil), "handles nil")
end

function TestPatterns:test_build_functions()
    luaunit.assertEquals("D1: ReaComp", naming.build_device_name(1, "ReaComp"), "builds D1: ReaComp")
    luaunit.assertEquals("D12: ReaEQ", naming.build_device_name(12, "ReaEQ"), "builds D12: ReaEQ")
    luaunit.assertEquals("R1_C1", naming.build_chain_name(1, 1), "builds R1_C1")
    luaunit.assertEquals("R2_C3", naming.build_chain_name(2, 3), "builds R2_C3")
    luaunit.assertEquals("R1: Rack", naming.build_rack_name(1), "builds R1: Rack")
    luaunit.assertEquals("R5: Rack", naming.build_rack_name(5), "builds R5: Rack")
    luaunit.assertEquals("_R1_M", naming.build_mixer_name(1), "builds _R1_M")
    luaunit.assertEquals("_R5_M", naming.build_mixer_name(5), "builds _R5_M")
end

function TestPatterns:test_truncate()
    luaunit.assertEquals("Hello", naming.truncate("Hello", 10), "no truncation when short")
    luaunit.assertEquals("Hello Wo..", naming.truncate("Hello World", 10), "truncates with ellipsis")
    luaunit.assertEquals("", naming.truncate("", 10), "handles empty string")
    luaunit.assertEquals("", naming.truncate(nil, 10), "handles nil")
end
