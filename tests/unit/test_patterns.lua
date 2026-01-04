--- Unit tests for SideFX pattern matching utilities.
-- Tests the lib/naming.lua module pattern functions.
-- @module unit.test_patterns
-- @author Nomad Monad
-- @license MIT

local assert = require("assertions")
local naming = require("naming")

local M = {}

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

function M.run()
    assert.section("is_device_name")
    
    assert.truthy(naming.is_device_name("D1: ReaComp"), "matches D1: prefix")
    assert.truthy(naming.is_device_name("D12: ReaEQ"), "matches D12: prefix")
    assert.truthy(naming.is_device_name("D1_FX: ReaComp"), "matches D1_FX: prefix")
    assert.falsy(naming.is_device_name("ReaComp"), "rejects no prefix")
    assert.falsy(naming.is_device_name("R1: Rack"), "rejects R prefix")
    assert.falsy(naming.is_device_name(nil), "handles nil")
    
    assert.section("is_chain_name")
    
    assert.truthy(naming.is_chain_name("R1_C1"), "matches R1_C1")
    assert.truthy(naming.is_chain_name("R1_C1: ReaComp"), "matches R1_C1 with name")
    assert.truthy(naming.is_chain_name("R2_C3_D1: ReaComp"), "matches nested device in chain")
    assert.falsy(naming.is_chain_name("R1: Rack"), "rejects rack")
    assert.falsy(naming.is_chain_name("D1: ReaComp"), "rejects device")
    assert.falsy(naming.is_chain_name(nil), "handles nil")
    
    assert.section("is_rack_name")
    
    assert.truthy(naming.is_rack_name("R1: Rack"), "matches R1: Rack")
    assert.truthy(naming.is_rack_name("R12: My Rack"), "matches R12: with custom name")
    assert.falsy(naming.is_rack_name("R1_C1"), "rejects chain (no colon)")
    assert.falsy(naming.is_rack_name("R1_C1: ReaComp"), "rejects chain with colon")
    assert.falsy(naming.is_rack_name("D1: ReaComp"), "rejects device")
    assert.falsy(naming.is_rack_name(nil), "handles nil")
    
    assert.section("is_internal_name")
    
    assert.truthy(naming.is_internal_name("_R1_M"), "matches mixer")
    assert.truthy(naming.is_internal_name("_hidden"), "matches any underscore prefix")
    assert.falsy(naming.is_internal_name("R1: Rack"), "rejects rack")
    assert.falsy(naming.is_internal_name("D1: ReaComp"), "rejects device")
    assert.falsy(naming.is_internal_name(nil), "handles nil")
    
    assert.section("is_mixer_name")
    
    assert.truthy(naming.is_mixer_name("_R1_M"), "matches _R1_M")
    assert.truthy(naming.is_mixer_name("_R12_M"), "matches _R12_M")
    assert.truthy(naming.is_mixer_name("JS: SideFX/SideFX_Mixer"), "matches full JSFX path")
    assert.truthy(naming.is_mixer_name("SideFX Mixer"), "matches display name")
    assert.falsy(naming.is_mixer_name("R1: Rack"), "rejects rack")
    assert.falsy(naming.is_mixer_name("Mixer"), "rejects plain Mixer")
    assert.falsy(naming.is_mixer_name(nil), "handles nil")
    
    assert.section("parse_device_index")
    
    assert.equals(1, naming.parse_device_index("D1: ReaComp"), "parses D1")
    assert.equals(12, naming.parse_device_index("D12: ReaEQ"), "parses D12")
    assert.equals(1, naming.parse_device_index("D1_FX: ReaComp"), "parses D1_FX")
    assert.is_nil(naming.parse_device_index("R1: Rack"), "returns nil for rack")
    assert.is_nil(naming.parse_device_index("ReaComp"), "returns nil for no prefix")
    assert.is_nil(naming.parse_device_index(nil), "handles nil")
    
    assert.section("parse_rack_index")
    
    assert.equals(1, naming.parse_rack_index("R1: Rack"), "parses R1")
    assert.equals(12, naming.parse_rack_index("R12: My Rack"), "parses R12")
    assert.equals(1, naming.parse_rack_index("R1_C1"), "parses from chain")
    assert.is_nil(naming.parse_rack_index("D1: ReaComp"), "returns nil for device")
    assert.is_nil(naming.parse_rack_index(nil), "handles nil")
    
    assert.section("parse_chain_index")
    
    assert.equals(1, naming.parse_chain_index("R1_C1"), "parses C1")
    assert.equals(3, naming.parse_chain_index("R2_C3_D1: ReaComp"), "parses C3 from nested")
    assert.is_nil(naming.parse_chain_index("R1: Rack"), "returns nil for rack")
    assert.is_nil(naming.parse_chain_index("D1: ReaComp"), "returns nil for device")
    assert.is_nil(naming.parse_chain_index(nil), "handles nil")
    
    assert.section("build functions")
    
    assert.equals("D1: ReaComp", naming.build_device_name(1, "ReaComp"), "builds D1: ReaComp")
    assert.equals("D12: ReaEQ", naming.build_device_name(12, "ReaEQ"), "builds D12: ReaEQ")
    assert.equals("R1_C1", naming.build_chain_name(1, 1), "builds R1_C1")
    assert.equals("R2_C3", naming.build_chain_name(2, 3), "builds R2_C3")
    assert.equals("R1: Rack", naming.build_rack_name(1), "builds R1: Rack")
    assert.equals("R5: Rack", naming.build_rack_name(5), "builds R5: Rack")
    assert.equals("_R1_M", naming.build_mixer_name(1), "builds _R1_M")
    assert.equals("_R5_M", naming.build_mixer_name(5), "builds _R5_M")
    
    assert.section("truncate")
    
    assert.equals("Hello", naming.truncate("Hello", 10), "no truncation when short")
    assert.equals("Hello W..", naming.truncate("Hello World", 10), "truncates with ellipsis")
    assert.equals("", naming.truncate("", 10), "handles empty string")
    assert.equals("", naming.truncate(nil, 10), "handles nil")
end

return M

