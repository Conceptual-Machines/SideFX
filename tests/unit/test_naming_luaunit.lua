--- Unit tests for SideFX naming utilities (LuaUnit version).
-- Tests the lib/utils/naming.lua module functions.
-- @module unit.test_naming_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local naming = require("lib.utils.naming")

TestNaming = {}

function TestNaming:test_get_short_plugin_name()
    luaunit.assertEquals("ReaComp", naming.get_short_plugin_name("VST: ReaComp"), "strips VST: prefix")
    luaunit.assertEquals("ReaComp", naming.get_short_plugin_name("VST3: ReaComp"), "strips VST3: prefix")
    luaunit.assertEquals("Compressor", naming.get_short_plugin_name("AU: Compressor"), "strips AU: prefix")
    luaunit.assertEquals("utility", naming.get_short_plugin_name("JS: utility"), "strips JS: prefix")
    luaunit.assertEquals("Compressor", naming.get_short_plugin_name("CLAP: Compressor"), "strips CLAP: prefix")
    luaunit.assertEquals("Kontakt", naming.get_short_plugin_name("VSTi: Kontakt"), "strips VSTi: prefix")
    luaunit.assertEquals("SideFX_Utility", naming.get_short_plugin_name("JS: SideFX/SideFX_Utility"), "strips JS path")
    luaunit.assertEquals("ReaComp", naming.get_short_plugin_name("ReaComp"), "no prefix unchanged")
end

function TestNaming:test_get_short_plugin_name_windows_paths()
    -- Windows backslash paths should be handled the same as Unix forward slash paths
    luaunit.assertEquals("SideFX_Utility", naming.get_short_plugin_name("JS: SideFX\\SideFX_Utility"), "strips JS path with backslash")
    luaunit.assertEquals("plugin.jsfx", naming.get_short_plugin_name("JS: path\\to\\plugin.jsfx"), "strips deep backslash path")
    luaunit.assertEquals("plugin.jsfx", naming.get_short_plugin_name("JS: C:\\Users\\Name\\Scripts\\plugin.jsfx"), "strips full Windows path")
    -- Mixed separators (shouldn't happen but handle gracefully)
    luaunit.assertEquals("plugin.jsfx", naming.get_short_plugin_name("JS: path/to\\plugin.jsfx"), "strips mixed separator path")
end

function TestNaming:test_strip_sidefx_prefixes()
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("D1: ReaComp"), "strips D1: prefix")
    luaunit.assertEquals("ReaEQ", naming.strip_sidefx_prefixes("D2: ReaEQ"), "strips D2: prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("R1: ReaComp"), "strips R1: prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("R1_C1: ReaComp"), "strips R1_C1: prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1: ReaComp"), "strips R1_C1_D1: prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1_FX: ReaComp"), "strips R1_C1_D1_FX: prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("D1_FX: ReaComp"), "strips D1_FX: prefix")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("ReaComp"), "no prefix unchanged")
    luaunit.assertEquals("ReaComp", naming.strip_sidefx_prefixes("VST: ReaComp"), "strips VST: prefix too")
end

function TestNaming:test_extract_prefix()
    luaunit.assertEquals("D1: ", naming.extract_prefix("D1: ReaComp"), "extracts D1: prefix")
    luaunit.assertEquals("D12: ", naming.extract_prefix("D12: ReaComp"), "extracts D12: prefix")
    luaunit.assertEquals("R1: ", naming.extract_prefix("R1: Rack"), "extracts R1: prefix")
    luaunit.assertEquals("R1_C1: ", naming.extract_prefix("R1_C1: ReaComp"), "extracts R1_C1: prefix")
    luaunit.assertEquals("", naming.extract_prefix("ReaComp"), "returns empty for no prefix")
    luaunit.assertEquals("", naming.extract_prefix("VST: ReaComp"), "returns empty for non-SideFX prefix")
end

function TestNaming:test_is_utility_name()
    luaunit.assertTrue(naming.is_utility_name("SideFX_Utility"), "detects SideFX_Utility")
    luaunit.assertTrue(naming.is_utility_name("SideFX Utility"), "detects SideFX Utility (space)")
    luaunit.assertTrue(naming.is_utility_name("JS: SideFX/SideFX_Utility"), "detects full path")
    luaunit.assertTrue(naming.is_utility_name("D1_Util"), "detects D1_Util")
    luaunit.assertTrue(naming.is_utility_name("R1_C1_D1_Util"), "detects R1_C1_D1_Util")
    luaunit.assertFalse(naming.is_utility_name("ReaComp"), "rejects ReaComp")
    luaunit.assertFalse(naming.is_utility_name("Utility"), "rejects plain Utility")
    luaunit.assertFalse(naming.is_utility_name(nil), "handles nil")
end

function TestNaming:test_build_functions()
    luaunit.assertEquals("D1: ReaComp", naming.build_device_name(1, "ReaComp"), "builds device name")
    luaunit.assertEquals("D1_FX: ReaComp", naming.build_device_fx_name(1, "ReaComp"), "builds device FX name")
    luaunit.assertEquals("D1_Util", naming.build_device_util_name(1), "builds device util name")
    luaunit.assertEquals("R1_C1", naming.build_chain_name(1, 1), "builds chain name")
    luaunit.assertEquals("R1: Rack", naming.build_rack_name(1), "builds rack name")
    luaunit.assertEquals("_R1_M", naming.build_mixer_name(1), "builds mixer name")
end

function TestNaming:test_parse_hierarchy()
    local h1 = naming.parse_hierarchy("R1_C2_D3: ReaComp")
    luaunit.assertEquals(1, h1.rack_idx, "parses rack_idx from full hierarchy")
    luaunit.assertEquals(2, h1.chain_idx, "parses chain_idx from full hierarchy")
    luaunit.assertEquals(3, h1.device_idx, "parses device_idx from full hierarchy")
    luaunit.assertEquals("ReaComp", h1.fx_name, "parses fx_name from full hierarchy")
    
    local h2 = naming.parse_hierarchy("D5: ReaEQ")
    luaunit.assertEquals(5, h2.device_idx, "parses device_idx from D-prefix")
    luaunit.assertEquals("ReaEQ", h2.fx_name, "parses fx_name from D-prefix")
end
