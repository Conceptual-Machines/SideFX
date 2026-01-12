--- Unit tests for SideFX container utility pattern matching (LuaUnit version).
-- Tests the pattern matching logic for container type detection used in
-- convert_chain_to_devices and convert_device_to_rack.
-- @module unit.test_container_utils_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local naming = require("lib.utils.naming")

TestContainerUtils = {}

--------------------------------------------------------------------------------
-- Tests: D-container (device) pattern detection
-- D-containers follow pattern: D{n}: {name}
--------------------------------------------------------------------------------

function TestContainerUtils:test_device_pattern_matches_device_containers()
    -- D-containers should match the pattern ^D%d+
    luaunit.assertTrue(("D1: ReaComp"):match("^D%d+") ~= nil, "D1: ReaComp matches D pattern")
    luaunit.assertTrue(("D12: Plugin"):match("^D%d+") ~= nil, "D12: Plugin matches D pattern")
    luaunit.assertTrue(("D99: Effect"):match("^D%d+") ~= nil, "D99: Effect matches D pattern")
end

function TestContainerUtils:test_device_pattern_rejects_non_devices()
    -- Non-device containers should NOT match
    luaunit.assertNil(("R1: Rack"):match("^D%d+"), "R1: Rack doesn't match D pattern")
    luaunit.assertNil(("R1_C1"):match("^D%d+"), "R1_C1 doesn't match D pattern")
    luaunit.assertNil(("Container"):match("^D%d+"), "Container doesn't match D pattern")
    luaunit.assertNil(("_R1_M"):match("^D%d+"), "Mixer doesn't match D pattern")
end

function TestContainerUtils:test_device_pattern_rejects_chain_devices()
    -- Chain device names have R prefix, not D
    luaunit.assertNil(("R1_C1_D1: ReaComp"):match("^D%d+"), "Chain device doesn't match D pattern")
end

--------------------------------------------------------------------------------
-- Tests: C-container (chain) pattern detection
-- C-containers follow pattern: R{n}_C{n}
--------------------------------------------------------------------------------

function TestContainerUtils:test_chain_pattern_matches_chain_containers()
    -- C-containers should match the pattern ^R%d+_C%d+
    luaunit.assertTrue(("R1_C1"):match("^R%d+_C%d+") ~= nil, "R1_C1 matches C pattern")
    luaunit.assertTrue(("R2_C3"):match("^R%d+_C%d+") ~= nil, "R2_C3 matches C pattern")
    luaunit.assertTrue(("R10_C15"):match("^R%d+_C%d+") ~= nil, "R10_C15 matches C pattern")
end

function TestContainerUtils:test_chain_pattern_rejects_non_chains()
    -- Non-chain containers should NOT match
    luaunit.assertNil(("R1: Rack"):match("^R%d+_C%d+"), "Rack doesn't match C pattern")
    luaunit.assertNil(("D1: ReaComp"):match("^R%d+_C%d+"), "Device doesn't match C pattern")
    luaunit.assertNil(("Container"):match("^R%d+_C%d+"), "Plain container doesn't match C pattern")
end

function TestContainerUtils:test_chain_pattern_matches_chain_with_suffix()
    -- Chain names with custom suffixes should still match
    luaunit.assertTrue(("R1_C1: My Chain"):match("^R%d+_C%d+") ~= nil, "R1_C1: My Chain matches")
    luaunit.assertTrue(("R2_C3_D1: ReaComp"):match("^R%d+_C%d+") ~= nil, "Chain device path matches")
end

--------------------------------------------------------------------------------
-- Tests: Rack container pattern detection
-- R-containers follow pattern: R{n}: {name}
--------------------------------------------------------------------------------

function TestContainerUtils:test_rack_pattern_matches_racks()
    -- Use naming module's is_rack_name function
    luaunit.assertTrue(naming.is_rack_name("R1: Rack"), "R1: Rack is a rack")
    luaunit.assertTrue(naming.is_rack_name("R2: My Rack"), "R2: My Rack is a rack")
    luaunit.assertTrue(naming.is_rack_name("R99: Custom"), "R99: Custom is a rack")
end

function TestContainerUtils:test_rack_pattern_rejects_chains()
    -- Chains have _C after R{n}, so they shouldn't be detected as racks
    luaunit.assertFalse(naming.is_rack_name("R1_C1"), "Chain is not a rack")
    luaunit.assertFalse(naming.is_rack_name("R2_C3"), "Chain is not a rack")
end

--------------------------------------------------------------------------------
-- Tests: Short name extraction from D-container names
-- Used in convert_device_to_rack to preserve FX name
--------------------------------------------------------------------------------

function TestContainerUtils:test_extract_short_name_from_device()
    -- Pattern: ^D%d+:%s*(.+)$
    local name1 = "D1: ProQ 3"
    local short1 = name1:match("^D%d+:%s*(.+)$")
    luaunit.assertEquals("ProQ 3", short1, "Extracts ProQ 3")

    local name2 = "D12: ReaComp"
    local short2 = name2:match("^D%d+:%s*(.+)$")
    luaunit.assertEquals("ReaComp", short2, "Extracts ReaComp")

    local name3 = "D99: Very Long Plugin Name"
    local short3 = name3:match("^D%d+:%s*(.+)$")
    luaunit.assertEquals("Very Long Plugin Name", short3, "Extracts long name")
end

function TestContainerUtils:test_extract_short_name_handles_missing_space()
    -- Some names might not have a space after colon
    local name = "D1:NoSpace"
    local short = name:match("^D%d+:%s*(.+)$")
    luaunit.assertEquals("NoSpace", short, "Handles no space")
end

function TestContainerUtils:test_extract_short_name_fallback()
    -- Non-matching names should return nil
    local name = "Container"
    local short = name:match("^D%d+:%s*(.+)$")
    luaunit.assertNil(short, "Returns nil for non-device")
end

--------------------------------------------------------------------------------
-- Tests: Container type classification
-- These test the naming module's classification functions
--------------------------------------------------------------------------------

function TestContainerUtils:test_is_device_name()
    luaunit.assertTrue(naming.is_device_name("D1: ReaComp"), "D1: ReaComp is device")
    luaunit.assertTrue(naming.is_device_name("D99: Plugin"), "D99: Plugin is device")
    luaunit.assertFalse(naming.is_device_name("R1: Rack"), "Rack is not device")
    luaunit.assertFalse(naming.is_device_name("R1_C1"), "Chain is not device")
    luaunit.assertFalse(naming.is_device_name(nil), "nil is not device")
end

function TestContainerUtils:test_is_chain_name()
    luaunit.assertTrue(naming.is_chain_name("R1_C1"), "R1_C1 is chain")
    luaunit.assertTrue(naming.is_chain_name("R2_C3"), "R2_C3 is chain")
    luaunit.assertFalse(naming.is_chain_name("D1: ReaComp"), "Device is not chain")
    luaunit.assertFalse(naming.is_chain_name("R1: Rack"), "Rack is not chain")
    luaunit.assertFalse(naming.is_chain_name(nil), "nil is not chain")
end

--------------------------------------------------------------------------------
-- Tests: Naming functions used by convert_device_to_rack
--------------------------------------------------------------------------------

function TestContainerUtils:test_build_chain_device_name()
    luaunit.assertEquals("R1_C1_D1: ReaComp",
        naming.build_chain_device_name(1, 1, 1, "ReaComp"),
        "Builds chain device name")
    luaunit.assertEquals("R2_C3_D2: ProQ",
        naming.build_chain_device_name(2, 3, 2, "ProQ"),
        "Builds chain device with higher indices")
end

function TestContainerUtils:test_build_chain_device_fx_name()
    luaunit.assertEquals("R1_C1_D1_FX: ReaComp",
        naming.build_chain_device_fx_name(1, 1, 1, "ReaComp"),
        "Builds chain device FX name")
end

function TestContainerUtils:test_build_chain_device_util_name()
    luaunit.assertEquals("R1_C1_D1_Util",
        naming.build_chain_device_util_name(1, 1, 1),
        "Builds chain device util name")
end

--------------------------------------------------------------------------------
-- Tests: Edge cases for container operations
--------------------------------------------------------------------------------

function TestContainerUtils:test_empty_name_handling()
    -- Empty strings should not match patterns
    luaunit.assertNil((""):match("^D%d+"), "Empty string doesn't match D pattern")
    luaunit.assertNil((""):match("^R%d+_C%d+"), "Empty string doesn't match C pattern")
end

function TestContainerUtils:test_whitespace_name_handling()
    -- Whitespace-only strings should not match
    luaunit.assertNil(("   "):match("^D%d+"), "Whitespace doesn't match D pattern")
    luaunit.assertNil(("   "):match("^R%d+_C%d+"), "Whitespace doesn't match C pattern")
end

function TestContainerUtils:test_mixed_case_handling()
    -- Patterns are case-sensitive
    luaunit.assertNil(("d1: ReaComp"):match("^D%d+"), "Lowercase d doesn't match")
    luaunit.assertNil(("r1_c1"):match("^R%d+_C%d+"), "Lowercase r_c doesn't match")
end

return TestContainerUtils
