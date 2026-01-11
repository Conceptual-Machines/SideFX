--- Test runner for SideFX using LuaUnit.
-- Runs unit tests that use mocked ReaWrap classes.
--
-- Usage (standalone):
--   cd SideFX
--   lua tests/runner_luaunit.lua
--
-- @module runner_luaunit
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
-- Load LuaUnit
--------------------------------------------------------------------------------

local luaunit = require("luaunit")

--------------------------------------------------------------------------------
-- Test Discovery
--------------------------------------------------------------------------------

-- List of test modules to run (LuaUnit format)
local test_modules = {
    "unit.test_naming_luaunit",
    "unit.test_hierarchical_naming_luaunit",
    "unit.test_patterns_luaunit",
    "unit.test_rack_luaunit",
    "unit.test_rack_recursive_luaunit",
    "unit.test_state_luaunit",
    "unit.test_track_detection_luaunit",
    "unit.test_modulation_math_luaunit",
}

--------------------------------------------------------------------------------
-- Run Tests
--------------------------------------------------------------------------------

print("")
print("========================================")
print("SideFX Test Runner (LuaUnit)")
print("========================================")
print("")

if reaper then
    print("Mode: REAPER")
else
    print("Mode: Standalone (using mock ReaWrap)")
end
print("")

-- Load all test modules (LuaUnit auto-discovers Test* classes)
for _, module_name in ipairs(test_modules) do
    -- Clear cached module to allow re-running
    package.loaded[module_name] = nil
    require(module_name)
end

-- Run LuaUnit (default output is text, which is fine for CI)
local result = luaunit.LuaUnit.run()

-- Exit with proper code for CI
if not reaper then
    os.exit(result)
end
