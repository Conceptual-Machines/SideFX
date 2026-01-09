--- Unit tests for SideFX naming utilities.
-- Tests the lib/naming.lua module functions.
-- @module unit.test_naming
-- @author Nomad Monad
-- @license MIT

local assert = require("assertions")
local naming = require("lib.utils.naming")

local M = {}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function M.run()
    assert.section("get_short_plugin_name")
    
    assert.equals("ReaComp", naming.get_short_plugin_name("VST: ReaComp"), "strips VST: prefix")
    assert.equals("ReaComp", naming.get_short_plugin_name("VST3: ReaComp"), "strips VST3: prefix")
    assert.equals("Compressor", naming.get_short_plugin_name("AU: Compressor"), "strips AU: prefix")
    assert.equals("utility", naming.get_short_plugin_name("JS: utility"), "strips JS: prefix")
    assert.equals("Compressor", naming.get_short_plugin_name("CLAP: Compressor"), "strips CLAP: prefix")
    assert.equals("Kontakt", naming.get_short_plugin_name("VSTi: Kontakt"), "strips VSTi: prefix")
    assert.equals("SideFX_Utility", naming.get_short_plugin_name("JS: SideFX/SideFX_Utility"), "strips JS path")
    assert.equals("ReaComp", naming.get_short_plugin_name("ReaComp"), "no prefix unchanged")
    
    assert.section("strip_sidefx_prefixes")
    
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("D1: ReaComp"), "strips D1: prefix")
    assert.equals("ReaEQ", naming.strip_sidefx_prefixes("D2: ReaEQ"), "strips D2: prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("R1: ReaComp"), "strips R1: prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("R1_C1: ReaComp"), "strips R1_C1: prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1: ReaComp"), "strips R1_C1_D1: prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1_FX: ReaComp"), "strips R1_C1_D1_FX: prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("D1_FX: ReaComp"), "strips D1_FX: prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("ReaComp"), "no prefix unchanged")
    -- Note: strip_sidefx_prefixes also strips VST: etc. now for consistency
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("VST: ReaComp"), "strips VST: prefix too")
    
    assert.section("extract_prefix")
    
    assert.equals("D1: ", naming.extract_prefix("D1: ReaComp"), "extracts D1: prefix")
    assert.equals("D12: ", naming.extract_prefix("D12: ReaComp"), "extracts D12: prefix")
    assert.equals("R1: ", naming.extract_prefix("R1: Rack"), "extracts R1: prefix")
    assert.equals("R1_C1: ", naming.extract_prefix("R1_C1: ReaComp"), "extracts R1_C1: prefix")
    assert.equals("", naming.extract_prefix("ReaComp"), "returns empty for no prefix")
    assert.equals("", naming.extract_prefix("VST: ReaComp"), "returns empty for non-SideFX prefix")
    
    assert.section("is_utility_name")
    
    assert.truthy(naming.is_utility_name("SideFX_Utility"), "detects SideFX_Utility")
    assert.truthy(naming.is_utility_name("SideFX Utility"), "detects SideFX Utility (space)")
    assert.truthy(naming.is_utility_name("JS: SideFX/SideFX_Utility"), "detects full path")
    assert.truthy(naming.is_utility_name("D1_Util"), "detects D1_Util")
    assert.truthy(naming.is_utility_name("R1_C1_D1_Util"), "detects R1_C1_D1_Util")
    assert.falsy(naming.is_utility_name("ReaComp"), "rejects ReaComp")
    assert.falsy(naming.is_utility_name("Utility"), "rejects plain Utility")
    assert.falsy(naming.is_utility_name(nil), "handles nil")
    
    assert.section("build functions")
    
    assert.equals("D1: ReaComp", naming.build_device_name(1, "ReaComp"), "builds device name")
    assert.equals("D1_FX: ReaComp", naming.build_device_fx_name(1, "ReaComp"), "builds device FX name")
    assert.equals("D1_Util", naming.build_device_util_name(1), "builds device util name")
    assert.equals("R1_C1", naming.build_chain_name(1, 1), "builds chain name")
    assert.equals("R1: Rack", naming.build_rack_name(1), "builds rack name")
    assert.equals("_R1_M", naming.build_mixer_name(1), "builds mixer name")
    
    assert.section("parse_hierarchy")
    
    local h1 = naming.parse_hierarchy("R1_C2_D3: ReaComp")
    assert.equals(1, h1.rack_idx, "parses rack_idx from full hierarchy")
    assert.equals(2, h1.chain_idx, "parses chain_idx from full hierarchy")
    assert.equals(3, h1.device_idx, "parses device_idx from full hierarchy")
    assert.equals("ReaComp", h1.fx_name, "parses fx_name from full hierarchy")
    
    local h2 = naming.parse_hierarchy("D5: ReaEQ")
    assert.equals(5, h2.device_idx, "parses device_idx from D-prefix")
    assert.equals("ReaEQ", h2.fx_name, "parses fx_name from D-prefix")
end

return M

