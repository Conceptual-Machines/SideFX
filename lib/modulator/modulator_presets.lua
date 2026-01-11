--- Modulator Preset Management
-- Save and load modulator shapes as presets
-- @module modulator.modulator_presets
-- @author Nomad Monad
-- @license MIT

local r = reaper
local PARAM = require('lib.modulator.modulator_constants')

local M = {}

--------------------------------------------------------------------------------
-- Base64 Encoding (Lua implementation)
--------------------------------------------------------------------------------

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64_encode(data)
    return ((data:gsub('.', function(x)
        local bits, b = '', x:byte()
        for i = 8, 1, -1 do
            bits = bits .. (b % 2^i - b % 2^(i-1) > 0 and '1' or '0')
        end
        return bits
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do
            c = c + (x:sub(i, i) == '1' and 2^(6-i) or 0)
        end
        return b64chars:sub(c+1, c+1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

--------------------------------------------------------------------------------
-- Read Modulator State
--------------------------------------------------------------------------------

--- Read the current shape from a modulator FX
-- @param track MediaTrack pointer
-- @param fx_idx number FX index
-- @return table Shape data {num_points, points, curves}
function M.read_shape(track, fx_idx)
    local num_points = math.floor(r.TrackFX_GetParam(track, fx_idx, PARAM.PARAM_NUM_POINTS) + 0.5)

    local points = {}
    for i = 0, 15 do
        local x = r.TrackFX_GetParam(track, fx_idx, PARAM.PARAM_POINT_START + i * 2)
        local y = r.TrackFX_GetParam(track, fx_idx, PARAM.PARAM_POINT_START + i * 2 + 1)
        points[i + 1] = {x = x, y = y}
    end

    local curves = {}
    for i = 0, 14 do
        local curve = r.TrackFX_GetParam(track, fx_idx, PARAM.PARAM_SEGMENT_CURVE_START + i)
        curves[i + 1] = curve
    end

    return {
        num_points = num_points,
        points = points,
        curves = curves
    }
end

--------------------------------------------------------------------------------
-- Preset Encoding
--------------------------------------------------------------------------------

--- Encode a shape as a JSFX preset string (base64)
-- @param name string Preset name
-- @param shape table Shape data from read_shape()
-- @return string Base64-encoded preset data
function M.encode_preset(name, shape)
    -- Build the 86-value array (before name insertion)
    local values = {}
    for i = 1, 86 do
        values[i] = "-"
    end

    -- Rate section (positions 1-6, indices 0-5)
    values[1] = "0"   -- Tempo mode
    values[2] = "1"   -- Rate Hz
    values[3] = "5"   -- Sync rate
    values[4] = "0"   -- Output
    values[5] = "0"   -- Phase
    values[6] = "1"   -- Depth

    -- Trigger section (positions 20-25, indices 19-24)
    values[20] = "0"     -- Trigger mode
    values[21] = "0"     -- MIDI source
    values[22] = "0"     -- MIDI note
    values[23] = "0.5"   -- Audio threshold
    values[24] = "100"   -- Attack
    values[25] = "500"   -- Release

    -- Editor section (positions 26-30, indices 25-29)
    values[26] = "2"   -- Grid
    values[27] = "1"   -- Snap
    values[28] = "0"   -- LFO mode
    values[29] = "0"   -- Curve shape
    values[30] = tostring(shape.num_points)  -- Num points

    -- Points (positions 40-71, indices 39-70)
    for i = 1, 16 do
        local point = shape.points[i] or {x = 0.5, y = 0.5}
        values[40 + (i-1) * 2] = string.format("%.6g", point.x)
        values[40 + (i-1) * 2 + 1] = string.format("%.6g", point.y)
    end

    -- Insert name at position 65 (index 64, after point data)
    table.insert(values, 65, '"' .. name .. '"')

    -- Curves (positions 73-87, indices 72-86 after insert)
    local has_curves = false
    for i = 1, 15 do
        local curve = shape.curves[i] or 0
        if math.abs(curve) > 0.001 then
            has_curves = true
        end
    end

    for i = 1, 15 do
        local curve = shape.curves[i] or 0
        if has_curves and math.abs(curve) > 0.001 then
            values[72 + i] = string.format("%.6g", curve)
        else
            values[72 + i] = "0"
        end
    end

    -- Join and encode
    local full = table.concat(values, " ")
    return base64_encode(full)
end

--- Format encoded preset data with line breaks (80 chars per line)
-- @param encoded string Base64-encoded data
-- @return string Formatted with line breaks
function M.format_preset_data(encoded)
    local lines = {}
    for i = 1, #encoded, 80 do
        table.insert(lines, encoded:sub(i, i + 79))
    end
    return table.concat(lines, "\n    ")
end

--------------------------------------------------------------------------------
-- Preset File Operations
--------------------------------------------------------------------------------

-- Cached root path (set during first use)
local cached_root_path = nil

--- Get the SideFX root directory
-- @return string Root path with trailing slash
local function get_root_path()
    if cached_root_path then
        return cached_root_path
    end

    -- Try to get path from debug info
    local info = debug.getinfo(1, "S")
    if info and info.source then
        local script_path = info.source:match("@?(.*)")
        if script_path then
            -- This file is in lib/modulator/, so go up two levels
            local root = script_path:match("(.*/lib/modulator/)"):gsub("/lib/modulator/$", "/")
            if root then
                cached_root_path = root
                return root
            end
        end
    end

    -- Fallback: search in common locations
    local resource_path = r.GetResourcePath()
    local possible_paths = {
        resource_path .. "/Scripts/SideFX/",
        resource_path .. "/Scripts/ReaTeam Scripts/SideFX/",
    }

    for _, path in ipairs(possible_paths) do
        local test_file = io.open(path .. "SideFX.lua", "r")
        if test_file then
            test_file:close()
            cached_root_path = path
            return path
        end
    end

    -- Last resort: use resource path
    cached_root_path = resource_path .. "/Scripts/SideFX/"
    return cached_root_path
end

--- Get the path to the modulator preset library file
-- @return string Path to .rpl file
function M.get_preset_library_path()
    return get_root_path() .. "jsfx/SideFX_Modulator.jsfx.rpl"
end

--- Read the current preset library
-- @return string|nil File contents or nil on error
function M.read_preset_library()
    local path = M.get_preset_library_path()
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

--- Save a new preset to the library
-- @param name string Preset name
-- @param shape table Shape data from read_shape()
-- @return boolean, string Success and error message
function M.save_preset_to_library(name, shape)
    local path = M.get_preset_library_path()

    -- Read existing content
    local content = M.read_preset_library()
    if not content then
        -- Create new library
        content = '<REAPER_PRESET_LIBRARY "JS: SideFX Modulator"\n>\n'
    end

    -- Encode new preset
    local encoded = M.encode_preset(name, shape)
    local formatted = M.format_preset_data(encoded)

    -- Create preset block
    local preset_block = string.format('  <PRESET `%s`\n    %s\n  >', name, formatted)

    -- Insert before closing >
    -- Try multiple patterns
    local new_content
    if content:match("\n>%s*$") then
        new_content = content:gsub("\n>%s*$", "\n" .. preset_block .. "\n>")
    elseif content:match(">%s*$") then
        new_content = content:gsub(">%s*$", preset_block .. "\n>")
    else
        -- Append at end
        new_content = content .. "\n" .. preset_block .. "\n>"
    end

    -- Write back
    local file, err = io.open(path, "w")
    if not file then
        return false, "Cannot open file for writing: " .. (err or path)
    end
    file:write(new_content)
    file:close()

    return true, nil
end

--- Save current modulator shape as a preset
-- @param track MediaTrack pointer
-- @param fx_idx number FX index
-- @param name string Preset name
-- @return boolean, string Success and error message
function M.save_current_shape(track, fx_idx, name)
    local shape = M.read_shape(track, fx_idx)
    return M.save_preset_to_library(name, shape)
end

--- Debug: Get current paths
-- @return string Path info for debugging
function M.debug_paths()
    local root = get_root_path()
    local rpl_path = M.get_preset_library_path()
    local exists = io.open(rpl_path, "r") ~= nil
    return string.format("Root: %s\nRPL: %s\nExists: %s", root, rpl_path, tostring(exists))
end

return M
