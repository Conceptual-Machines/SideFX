--- Assertion utilities for SideFX tests.
-- Works both standalone and in REAPER.
-- @module assertions
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local assertions_run = 0
local assertions_passed = 0
local assertions_failed = 0
local failure_messages = {}
local current_section = ""

--------------------------------------------------------------------------------
-- Output
--------------------------------------------------------------------------------

local function output(msg)
    if reaper and reaper.ShowConsoleMsg then
        reaper.ShowConsoleMsg(msg .. "\n")
    else
        print(msg)
    end
end

--------------------------------------------------------------------------------
-- Core Functions
--------------------------------------------------------------------------------

--- Reset assertion counters between test modules.
function M.reset()
    assertions_run = 0
    assertions_passed = 0
    assertions_failed = 0
    failure_messages = {}
    current_section = ""
end

--- Mark a new test section.
-- @param name string Section name
function M.section(name)
    current_section = name
    output("  " .. name)
end

--- Get test results.
-- @return table {run, passed, failed, messages}
function M.get_results()
    return {
        run = assertions_run,
        passed = assertions_passed,
        failed = assertions_failed,
        messages = failure_messages
    }
end

--------------------------------------------------------------------------------
-- Assertion Helpers
--------------------------------------------------------------------------------

local function record_pass()
    assertions_run = assertions_run + 1
    assertions_passed = assertions_passed + 1
end

local function record_fail(message)
    assertions_run = assertions_run + 1
    assertions_failed = assertions_failed + 1
    local full_msg = string.format("    FAIL [%s]: %s", current_section, message)
    table.insert(failure_messages, full_msg)
    output(full_msg)
end

--------------------------------------------------------------------------------
-- Assertions
--------------------------------------------------------------------------------

--- Assert a condition is true.
-- @param condition boolean Condition to check
-- @param message string|nil Description
function M.truthy(condition, message)
    if condition then
        record_pass()
    else
        record_fail(message or "Expected truthy value")
    end
end

-- Alias for compatibility
M.assert_true = M.truthy

--- Assert a condition is false.
-- @param condition boolean Condition to check
-- @param message string|nil Description
function M.falsy(condition, message)
    if not condition then
        record_pass()
    else
        record_fail(message or "Expected falsy value")
    end
end

-- Alias for compatibility
M.assert_false = M.falsy

--- Assert two values are equal.
-- @param expected any Expected value
-- @param actual any Actual value
-- @param message string|nil Description
function M.equals(expected, actual, message)
    if expected == actual then
        record_pass()
    else
        record_fail(string.format(
            "%s (expected: %s, got: %s)",
            message or "Values not equal",
            tostring(expected),
            tostring(actual)
        ))
    end
end

-- Alias for compatibility
M.assert_equal = M.equals

--- Assert two values are not equal.
-- @param expected any Value to differ from
-- @param actual any Actual value
-- @param message string|nil Description
function M.not_equals(expected, actual, message)
    if expected ~= actual then
        record_pass()
    else
        record_fail(string.format(
            "%s (both are: %s)",
            message or "Values should differ",
            tostring(expected)
        ))
    end
end

-- Alias for compatibility
M.assert_not_equal = M.not_equals

--- Assert a value is nil.
-- @param value any Value to check
-- @param message string|nil Description
function M.is_nil(value, message)
    if value == nil then
        record_pass()
    else
        record_fail(string.format(
            "%s (got: %s)",
            message or "Expected nil",
            tostring(value)
        ))
    end
end

-- Alias for compatibility
M.assert_nil = M.is_nil

--- Assert a value is not nil.
-- @param value any Value to check
-- @param message string|nil Description
function M.not_nil(value, message)
    if value ~= nil then
        record_pass()
    else
        record_fail(message or "Expected non-nil value")
    end
end

-- Alias for compatibility
M.assert_not_nil = M.not_nil

--- Assert a value is of expected type.
-- @param expected_type string Expected type name
-- @param value any Value to check
-- @param message string|nil Description
function M.is_type(expected_type, value, message)
    local actual_type = type(value)
    if actual_type == expected_type then
        record_pass()
    else
        record_fail(string.format(
            "%s (expected type: %s, got: %s)",
            message or "Type mismatch",
            expected_type,
            actual_type
        ))
    end
end

--- Assert a string contains a substring.
-- @param str string String to search in
-- @param substring string Substring to find
-- @param message string|nil Description
function M.contains(str, substring, message)
    if str and str:find(substring, 1, true) then
        record_pass()
    else
        record_fail(string.format(
            "%s (looking for '%s' in '%s')",
            message or "String does not contain substring",
            substring,
            tostring(str)
        ))
    end
end

--- Assert a string matches a pattern.
-- @param str string String to match
-- @param pattern string Lua pattern
-- @param message string|nil Description
function M.matches(str, pattern, message)
    if str and str:match(pattern) then
        record_pass()
    else
        record_fail(string.format(
            "%s (pattern '%s' not found in '%s')",
            message or "Pattern not matched",
            pattern,
            tostring(str)
        ))
    end
end

--- Assert a table has expected length.
-- @param expected number Expected length
-- @param tbl table Table to check
-- @param message string|nil Description
function M.length(expected, tbl, message)
    local actual = tbl and #tbl or 0
    if actual == expected then
        record_pass()
    else
        record_fail(string.format(
            "%s (expected length: %d, got: %d)",
            message or "Length mismatch",
            expected,
            actual
        ))
    end
end

--- Assert a function throws an error.
-- @param fn function Function to call
-- @param message string|nil Description
function M.throws(fn, message)
    local ok = pcall(fn)
    if not ok then
        record_pass()
    else
        record_fail(message or "Expected function to throw")
    end
end

--- Assert a function does not throw.
-- @param fn function Function to call
-- @param message string|nil Description
function M.no_throw(fn, message)
    local ok, err = pcall(fn)
    if ok then
        record_pass()
    else
        record_fail(string.format(
            "%s (threw: %s)",
            message or "Function threw unexpectedly",
            tostring(err)
        ))
    end
end

return M
