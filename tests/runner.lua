--- Test runner for SideFX.
-- Runs unit tests that use mocked ReaWrap classes.
--
-- Usage (standalone):
--   cd SideFX
--   lua tests/runner.lua
--
-- @module runner
-- @author Nomad Monad
-- @license MIT

--------------------------------------------------------------------------------
-- Setup Paths
--------------------------------------------------------------------------------

local script_path
local root_path

-- Detect if running in REAPER or standalone
if reaper then
    -- Running in REAPER
    script_path = ({ reaper.get_action_context() })[2]:match('^.+[\\//]')
    root_path = script_path:match('^(.+/)tests/')
else
    -- Running standalone
    local info = debug.getinfo(1, "S")
    script_path = info.source:match("@?(.*[\\/])") or "./"
    root_path = script_path:match("^(.+/)tests/") or script_path .. "../"
end

-- Add paths
package.path = root_path .. "lib/?.lua;" .. package.path
package.path = root_path .. "lib/?/init.lua;" .. package.path
package.path = root_path .. "tests/?.lua;" .. package.path
package.path = root_path .. "tests/mock/?.lua;" .. package.path

--------------------------------------------------------------------------------
-- Output Helper
--------------------------------------------------------------------------------

local function output(msg)
    if reaper and reaper.ShowConsoleMsg then
        reaper.ShowConsoleMsg(msg .. "\n")
    else
        print(msg)
    end
end

--------------------------------------------------------------------------------
-- Test Discovery
--------------------------------------------------------------------------------

-- List of test modules to run
local test_modules = {
    "unit.test_naming",
    "unit.test_hierarchical_naming",
    "unit.test_patterns",
    "unit.test_rack",
    "unit.test_rack_recursive",
    "unit.test_state",
    "unit.test_track_detection",
}

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

local assert = require("assertions")

output("")
output("========================================")
output("SideFX Test Runner")
output("========================================")
output("")

if reaper then
    output("Mode: REAPER")
else
    output("Mode: Standalone (using mock ReaWrap)")
end
output("")

local all_passed = true
local total_passed = 0
local total_failed = 0

for _, module_name in ipairs(test_modules) do
    output("Running: " .. module_name)
    output("----------------------------------------")

    -- Reset state between test modules
    assert.reset()

    -- Clear cached module to allow re-running
    package.loaded[module_name] = nil

    local test_module = require(module_name)
    if type(test_module) == "table" and test_module.run then
        test_module.run()
    end

    local results = assert.get_results()
    total_passed = total_passed + results.passed
    total_failed = total_failed + results.failed

    if results.failed > 0 then
        all_passed = false
    end

    output("")
end

output("========================================")
output(string.format("Results: %d passed, %d failed", total_passed, total_failed))
if all_passed then
    output("All tests passed!")
else
    output("Some tests failed.")
end
output("========================================")

-- Return exit code for CI (fail if any tests failed or any errors occurred)
local exit_code = (all_passed and total_failed == 0) and 0 or 1
output(string.format("Exiting with code: %d (all_passed=%s, total_failed=%d)", exit_code, tostring(all_passed), total_failed))
if not reaper then
    os.exit(exit_code)
end
