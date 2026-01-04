--- Run all SideFX integration tests.
-- Load this script as a ReaScript action in REAPER to run all integration tests.
--
-- @module integration.run_all
-- @author Nomad Monad
-- @license MIT

local info = debug.getinfo(1, "S")
local script_path = info.source:match("@?(.*[\\/])")
local root_path = script_path:match("^(.+/)tests/") or script_path .. "../../"

-- Add SideFX paths
package.path = root_path .. "?.lua;" .. package.path
package.path = root_path .. "lib/?.lua;" .. package.path
package.path = root_path .. "tests/?.lua;" .. package.path

-- Find ReaWrap
local reawrap_path = root_path .. "../ReaWrap/"
package.path = reawrap_path .. "?.lua;" .. package.path
package.path = reawrap_path .. "lua/?.lua;" .. package.path

local r = reaper
local assert = require("assertions")

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

r.ShowConsoleMsg("\n")
r.ShowConsoleMsg("========================================\n")
r.ShowConsoleMsg("SideFX Integration Test Suite\n")
r.ShowConsoleMsg("========================================\n")
r.ShowConsoleMsg("\n")

local total_passed = 0
local total_failed = 0

-- Run container tests
r.ShowConsoleMsg("Running: Container Tests\n")
r.ShowConsoleMsg("----------------------------------------\n")
local ok, err = pcall(function()
    local test_containers = dofile(script_path .. "test_containers.lua")
end)
if not ok then
    r.ShowConsoleMsg("ERROR loading container tests: " .. tostring(err) .. "\n")
end
local results = assert.get_results()
total_passed = total_passed + results.passed
total_failed = total_failed + results.failed
r.ShowConsoleMsg("\n")

-- Reset for next test suite
assert.reset()

-- Run rack tests
r.ShowConsoleMsg("Running: Rack Tests\n")
r.ShowConsoleMsg("----------------------------------------\n")
ok, err = pcall(function()
    local test_racks = dofile(script_path .. "test_racks.lua")
end)
if not ok then
    r.ShowConsoleMsg("ERROR loading rack tests: " .. tostring(err) .. "\n")
end
results = assert.get_results()
total_passed = total_passed + results.passed
total_failed = total_failed + results.failed
r.ShowConsoleMsg("\n")

-- Final summary
r.ShowConsoleMsg("========================================\n")
r.ShowConsoleMsg(string.format("Total Results: %d passed, %d failed\n", total_passed, total_failed))
if total_failed == 0 then
    r.ShowConsoleMsg("All integration tests passed!\n")
else
    r.ShowConsoleMsg("Some integration tests failed.\n")
end
r.ShowConsoleMsg("========================================\n")
