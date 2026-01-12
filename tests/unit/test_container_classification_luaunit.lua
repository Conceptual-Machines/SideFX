--- Unit tests for container classification logic (LuaUnit version).
-- Tests the pattern matching that distinguishes R-containers (racks) from D-containers (devices).
-- This was added after a bug where renumber_device_chain incorrectly renamed racks as devices.
-- @module unit.test_container_classification_luaunit
-- @author Nomad Monad
-- @license MIT

local luaunit = require("luaunit")
local naming = require("lib.utils.naming")

TestContainerClassification = {}

--------------------------------------------------------------------------------
-- Tests: Rack vs Device pattern distinction
-- The bug was that containers matching R{n} pattern were being processed as devices
--------------------------------------------------------------------------------

function TestContainerClassification:test_rack_pattern_matches_racks()
    -- The pattern ^R%d+ should match rack container names
    luaunit.assertTrue(("R1: Rack"):match("^R%d+") ~= nil, "R1: Rack matches ^R%d+")
    luaunit.assertTrue(("R12: My Rack"):match("^R%d+") ~= nil, "R12: My Rack matches ^R%d+")
    luaunit.assertTrue(("R99: Rack"):match("^R%d+") ~= nil, "R99: Rack matches ^R%d+")
end

function TestContainerClassification:test_rack_pattern_does_not_match_devices()
    -- The pattern ^R%d+ should NOT match device container names
    luaunit.assertNil(("D1: ReaComp"):match("^R%d+"), "D1: ReaComp does not match ^R%d+")
    luaunit.assertNil(("D12: Plugin"):match("^R%d+"), "D12: Plugin does not match ^R%d+")
end

function TestContainerClassification:test_rack_pattern_does_not_match_chains()
    -- The pattern ^R%d+ should match chain names (they start with R{n}_C{n})
    -- But chains have _C after the number, so they are distinguishable
    luaunit.assertTrue(("R1_C1"):match("^R%d+") ~= nil, "R1_C1 matches ^R%d+ (but is a chain)")
    luaunit.assertTrue(("R1_C1: Chain"):match("^R%d+") ~= nil, "R1_C1: Chain matches ^R%d+")
end

function TestContainerClassification:test_device_pattern_matches_devices()
    -- The pattern ^D(%d+): should match device container names
    luaunit.assertTrue(("D1: ReaComp"):match("^D(%d+): (.+)$") ~= nil, "D1: ReaComp matches D pattern")
    luaunit.assertTrue(("D12: Plugin"):match("^D(%d+): (.+)$") ~= nil, "D12: Plugin matches D pattern")
end

function TestContainerClassification:test_device_pattern_does_not_match_racks()
    -- The pattern ^D(%d+): should NOT match rack container names
    luaunit.assertNil(("R1: Rack"):match("^D(%d+): (.+)$"), "R1: Rack does not match D pattern")
    luaunit.assertNil(("R12: My Rack"):match("^D(%d+): (.+)$"), "R12: My Rack does not match D pattern")
end

--------------------------------------------------------------------------------
-- Tests: naming module classification functions
-- These test the actual functions used for container classification
--------------------------------------------------------------------------------

function TestContainerClassification:test_is_rack_name_identifies_racks()
    luaunit.assertTrue(naming.is_rack_name("R1: Rack"), "R1: Rack is a rack")
    luaunit.assertTrue(naming.is_rack_name("R99: Custom Rack"), "R99: Custom Rack is a rack")
end

function TestContainerClassification:test_is_rack_name_rejects_devices()
    luaunit.assertFalse(naming.is_rack_name("D1: ReaComp"), "D1: ReaComp is not a rack")
    luaunit.assertFalse(naming.is_rack_name("D1: SideFX Chain Mixer"), "D1: SideFX Chain Mixer is not a rack")
end

function TestContainerClassification:test_is_device_name_identifies_devices()
    luaunit.assertTrue(naming.is_device_name("D1: ReaComp"), "D1: ReaComp is a device")
    luaunit.assertTrue(naming.is_device_name("D99: Plugin"), "D99: Plugin is a device")
end

function TestContainerClassification:test_is_device_name_rejects_racks()
    luaunit.assertFalse(naming.is_device_name("R1: Rack"), "R1: Rack is not a device")
    luaunit.assertFalse(naming.is_device_name("R12: My Rack"), "R12: My Rack is not a device")
end

--------------------------------------------------------------------------------
-- Tests: Mixer name classification
-- The mixer should not be classified as a device container
--------------------------------------------------------------------------------

function TestContainerClassification:test_mixer_name_is_not_device()
    luaunit.assertFalse(naming.is_device_name("JS: SideFX Chain Mixer"), "Mixer JSFX is not a device")
    luaunit.assertFalse(naming.is_device_name("SideFX Chain Mixer"), "Mixer display name is not a device")
    luaunit.assertFalse(naming.is_device_name("_R1_M"), "Mixer internal name is not a device")
end

function TestContainerClassification:test_mixer_not_classified_as_rack()
    -- Mixer names should not match the rack pattern
    luaunit.assertFalse(naming.is_rack_name("_R1_M"), "Mixer is not a rack")
    luaunit.assertFalse(naming.is_rack_name("SideFX Chain Mixer"), "Mixer display name is not a rack")
end

--------------------------------------------------------------------------------
-- Tests: Renumber exclusion logic
-- Simulates the condition that should skip R-containers in renumber_device_chain
--------------------------------------------------------------------------------

function TestContainerClassification:test_renumber_should_skip_racks()
    -- Simulates the fix: elseif is_container and not name:match("^R%d+") then
    -- For racks, the condition should be FALSE (skip processing)
    local rack_names = {"R1: Rack", "R12: Rack", "R99: Custom"}
    for _, name in ipairs(rack_names) do
        local should_process = not name:match("^R%d+")
        luaunit.assertFalse(should_process, "Should skip " .. name .. " in renumber")
    end
end

function TestContainerClassification:test_renumber_should_process_unnamed_containers()
    -- For containers without D{n} or R{n} prefix, renumber should process them
    -- (to restore their proper names)
    local container_names = {"Container", "My Container", "ReaComp Container"}
    for _, name in ipairs(container_names) do
        local should_process = not name:match("^R%d+")
        luaunit.assertTrue(should_process, "Should process " .. name .. " in renumber")
    end
end

function TestContainerClassification:test_renumber_should_not_reprocess_devices()
    -- D-containers are handled by a different branch (matching ^D(%d+):)
    -- They should match the D pattern and NOT reach the "unnamed container" branch
    local device_names = {"D1: ReaComp", "D12: Plugin", "D99: Effect"}
    for _, name in ipairs(device_names) do
        local matches_d_pattern = name:match("^D(%d+): (.+)$") ~= nil
        luaunit.assertTrue(matches_d_pattern, name .. " matches D pattern")
    end
end

return TestContainerClassification
