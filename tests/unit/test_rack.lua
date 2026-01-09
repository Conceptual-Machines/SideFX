--- Unit tests for SideFX rack utilities.
-- Tests rack-related naming and helper functions.
-- @module unit.test_rack
-- @author Nomad Monad
-- @license MIT

local assert = require("assertions")
local naming = require("lib.utils.naming")

local M = {}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function M.run()
    assert.section("build_rack_name")

    assert.equals("R1: Rack", naming.build_rack_name(1), "builds rack 1 name")
    assert.equals("R2: Rack", naming.build_rack_name(2), "builds rack 2 name")
    assert.equals("R10: Rack", naming.build_rack_name(10), "builds rack 10 name")

    assert.section("build_chain_name")

    assert.equals("R1_C1", naming.build_chain_name(1, 1), "builds chain R1_C1")
    assert.equals("R1_C2", naming.build_chain_name(1, 2), "builds chain R1_C2")
    assert.equals("R2_C3", naming.build_chain_name(2, 3), "builds chain R2_C3")

    assert.section("build_mixer_name")

    assert.equals("_R1_M", naming.build_mixer_name(1), "builds mixer name R1")
    assert.equals("_R2_M", naming.build_mixer_name(2), "builds mixer name R2")

    assert.section("build_chain_device_name")

    assert.equals("R1_C1_D1: ReaComp", naming.build_chain_device_name(1, 1, 1, "ReaComp"), "builds chain device name")
    assert.equals("R2_C3_D2: ReaEQ", naming.build_chain_device_name(2, 3, 2, "ReaEQ"), "builds chain device with higher indices")

    assert.section("build_chain_device_fx_name")

    assert.equals("R1_C1_D1_FX: ReaComp", naming.build_chain_device_fx_name(1, 1, 1, "ReaComp"), "builds chain device FX name")

    assert.section("build_chain_device_util_name")

    assert.equals("R1_C1_D1_Util", naming.build_chain_device_util_name(1, 1, 1), "builds chain device util name")
    assert.equals("R2_C3_D2_Util", naming.build_chain_device_util_name(2, 3, 2), "builds chain device util with higher indices")

    assert.section("is_rack_name")

    assert.truthy(naming.is_rack_name("R1: Rack"), "detects R1: Rack")
    assert.truthy(naming.is_rack_name("R2: My Rack"), "detects R2: My Rack")
    assert.truthy(naming.is_rack_name("R10: Rack"), "detects R10: Rack")
    assert.falsy(naming.is_rack_name("D1: ReaComp"), "rejects D1: prefix")
    assert.falsy(naming.is_rack_name("R1_C1"), "rejects chain name")
    assert.falsy(naming.is_rack_name("Container"), "rejects plain Container")
    assert.falsy(naming.is_rack_name(nil), "handles nil")

    assert.section("is_chain_name")

    assert.truthy(naming.is_chain_name("R1_C1"), "detects R1_C1")
    assert.truthy(naming.is_chain_name("R2_C3"), "detects R2_C3")
    assert.truthy(naming.is_chain_name("R10_C15"), "detects R10_C15")
    assert.falsy(naming.is_chain_name("R1: Rack"), "rejects rack name")
    assert.falsy(naming.is_chain_name("D1: ReaComp"), "rejects device name")
    assert.falsy(naming.is_chain_name("R1_C1_D1: ReaComp"), "rejects chain device name")
    assert.falsy(naming.is_chain_name(nil), "handles nil")

    assert.section("is_mixer_name")

    assert.truthy(naming.is_mixer_name("_R1_M"), "detects _R1_M")
    assert.truthy(naming.is_mixer_name("_R2_M"), "detects _R2_M")
    assert.truthy(naming.is_mixer_name("_R10_M"), "detects _R10_M")
    assert.falsy(naming.is_mixer_name("R1_M"), "rejects without underscore")
    assert.falsy(naming.is_mixer_name("R1: Rack"), "rejects rack name")
    assert.falsy(naming.is_mixer_name(nil), "handles nil")

    assert.section("parse_rack_index")

    assert.equals(1, naming.parse_rack_index("R1: Rack"), "parses R1 index")
    assert.equals(2, naming.parse_rack_index("R2: Rack"), "parses R2 index")
    assert.equals(10, naming.parse_rack_index("R10: Rack"), "parses R10 index")
    assert.equals(1, naming.parse_rack_index("R1_C1"), "parses from chain name")
    assert.equals(2, naming.parse_rack_index("R2_C3_D1: ReaComp"), "parses from chain device name")
    assert.is_nil(naming.parse_rack_index("D1: ReaComp"), "returns nil for non-rack")
    assert.is_nil(naming.parse_rack_index(nil), "handles nil")

    assert.section("parse_chain_index")

    assert.equals(1, naming.parse_chain_index("R1_C1"), "parses C1 index")
    assert.equals(3, naming.parse_chain_index("R2_C3"), "parses C3 index")
    assert.equals(15, naming.parse_chain_index("R1_C15"), "parses C15 index")
    assert.equals(2, naming.parse_chain_index("R1_C2_D1: ReaComp"), "parses from chain device name")
    assert.is_nil(naming.parse_chain_index("R1: Rack"), "returns nil for rack")
    assert.is_nil(naming.parse_chain_index(nil), "handles nil")

    assert.section("parse_hierarchy for racks")

    local h1 = naming.parse_hierarchy("R1: Rack")
    assert.equals(1, h1.rack_idx, "parses rack_idx from rack name")
    assert.is_nil(h1.chain_idx, "no chain_idx in rack name")
    assert.is_nil(h1.device_idx, "no device_idx in rack name")

    local h2 = naming.parse_hierarchy("R2_C3")
    assert.equals(2, h2.rack_idx, "parses rack_idx from chain name")
    assert.equals(3, h2.chain_idx, "parses chain_idx from chain name")
    assert.is_nil(h2.device_idx, "no device_idx in chain name")

    local h3 = naming.parse_hierarchy("R1_C2_D3: ReaComp")
    assert.equals(1, h3.rack_idx, "parses rack_idx from chain device")
    assert.equals(2, h3.chain_idx, "parses chain_idx from chain device")
    assert.equals(3, h3.device_idx, "parses device_idx from chain device")
    assert.equals("ReaComp", h3.fx_name, "parses fx_name from chain device")

    assert.section("strip_sidefx_prefixes for rack names")

    assert.equals("Rack", naming.strip_sidefx_prefixes("R1: Rack"), "strips R1: prefix")
    assert.equals("My Rack", naming.strip_sidefx_prefixes("R2: My Rack"), "strips R2: prefix with name")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1: ReaComp"), "strips full chain device prefix")
    assert.equals("ReaComp", naming.strip_sidefx_prefixes("R1_C1_D1_FX: ReaComp"), "strips chain device FX prefix")
end

return M
