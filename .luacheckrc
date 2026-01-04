-- Luacheck configuration for SideFX
-- https://luacheck.readthedocs.io/

-- Global objects defined by REAPER
globals = {
    "reaper",
}

-- Read-only globals
read_globals = {
    "reaper",
}

-- Ignore certain warnings
ignore = {
    "212",  -- Unused argument (common in callbacks)
    "213",  -- Unused loop variable
    "311",  -- Value assigned to variable is unused (common pattern)
    "631",  -- Line is too long (we have long UI code)
}

-- Max line length
max_line_length = 120

-- Allow unused self in methods
self = false

-- Exclude directories
exclude_files = {
    "extension/",
    "tests/mock/",
}

-- Files to check
files["SideFX.lua"] = {
    globals = {"reaper"},
}

files["lib/**/*.lua"] = {
    globals = {"reaper"},
}

files["tests/**/*.lua"] = {
    globals = {"reaper"},
}

