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

-- Build reverse lookup table for base64 decode
local b64lookup = {}
for i = 1, #b64chars do
    b64lookup[b64chars:sub(i, i)] = i - 1
end

local function base64_decode(data)
    -- Remove padding and whitespace
    data = data:gsub('%s', ''):gsub('=', '')
    local result = {}
    local bits = ''

    for i = 1, #data do
        local char = data:sub(i, i)
        local val = b64lookup[char]
        if val then
            -- Convert to 6-bit binary string
            for j = 5, 0, -1 do
                bits = bits .. (math.floor(val / 2^j) % 2)
            end
        end
    end

    -- Convert bits to bytes
    for i = 1, #bits - 7, 8 do
        local byte = 0
        for j = 0, 7 do
            byte = byte + tonumber(bits:sub(i + j, i + j)) * 2^(7 - j)
        end
        table.insert(result, string.char(byte))
    end

    return table.concat(result)
end

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

--- Hex-encode a string (for .ini preset format)
-- @param data string Data to encode
-- @return string Hex-encoded string
local function hex_encode(data)
    return (data:gsub('.', function(c)
        return string.format('%02X', string.byte(c))
    end))
end

--- Calculate checksum for REAPER preset (last byte of hex string)
-- @param hex_data string Hex-encoded preset data
-- @return string Two-character hex checksum
local function calc_checksum(hex_data)
    local sum = 0
    for i = 1, #hex_data, 2 do
        local byte = tonumber(hex_data:sub(i, i+1), 16)
        if byte then
            sum = sum + byte
        end
    end
    return string.format("%02X", sum % 256)
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

--- Get the path to the factory preset library file
-- @return string Path to factory .rpl file
function M.get_preset_library_path()
    return get_root_path() .. "jsfx/SideFX_Modulator.jsfx.rpl"
end

--- Get the path to the user preset library file
-- @return string Path to user .rpl file
function M.get_user_preset_path()
    local resource_path = r.GetResourcePath()
    return resource_path .. "/presets/SideFX_Modulator_User.rpl"
end

--- Read the factory preset library
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

--- Read the user preset library
-- @return string|nil File contents or nil on error
function M.read_user_preset_library()
    local path = M.get_user_preset_path()
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

--- Get all preset names from both factory and user .rpl libraries
-- @return table Array of preset names (1-indexed), table Array of sources ("factory" or "user")
function M.get_preset_names()
    local names = {}
    local sources = {}

    -- Read factory presets first
    local factory_content = M.read_preset_library()
    if factory_content then
        for name in factory_content:gmatch("<PRESET [`\"]([^`\"]+)[`\"]") do
            table.insert(names, name)
            table.insert(sources, "factory")
        end
    end

    -- Then read user presets
    local user_content = M.read_user_preset_library()
    if user_content then
        for name in user_content:gmatch("<PRESET [`\"]([^`\"]+)[`\"]") do
            table.insert(names, name)
            table.insert(sources, "user")
        end
    end

    return names, sources
end

--- Get only user preset names
-- @return table Array of user preset names (1-indexed)
function M.get_user_preset_names()
    local content = M.read_user_preset_library()
    if not content then
        return {}
    end

    local names = {}
    for name in content:gmatch("<PRESET [`\"]([^`\"]+)[`\"]") do
        table.insert(names, name)
    end

    return names
end

--- Check if a preset name already exists in user presets
-- @param name string Preset name to check
-- @return boolean True if preset exists in user presets
function M.preset_exists(name)
    local names = M.get_user_preset_names()
    for _, existing_name in ipairs(names) do
        if existing_name == name then
            return true
        end
    end
    return false
end

--- Delete a preset from the user library by name
-- @param name string Preset name to delete
-- @return boolean Success
function M.delete_preset(name)
    local content = M.read_user_preset_library()
    if not content then
        return false
    end

    -- Escape special pattern characters in preset name
    local escaped_name = name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

    -- Remove the preset block (try both backtick and quote formats)
    local pattern1 = "%s*<PRESET `" .. escaped_name .. "`%s*\n.->"
    local pattern2 = '%s*<PRESET "' .. escaped_name .. '"%s*\n.->'

    local new_content = content:gsub(pattern1, "")
    new_content = new_content:gsub(pattern2, "")

    if new_content == content then
        return false  -- Nothing was deleted
    end

    -- Write back to user file
    local path = M.get_user_preset_path()
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(new_content)
    file:close()

    return true
end

--- Get raw preset data (base64) by name from .rpl files (checks user first, then factory)
-- @param preset_name string Name of the preset
-- @return string|nil Base64-encoded preset data or nil if not found
function M.get_preset_data_by_name(preset_name)
    -- Escape special pattern characters in preset name
    local escaped_name = preset_name:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")

    -- Try both backtick and quote formats
    local pattern1 = "<PRESET `" .. escaped_name .. "`%s*\n(.-)%s*>"
    local pattern2 = '<PRESET "' .. escaped_name .. '"%s*\n(.-)%s*>'

    -- Check user presets first
    local user_content = M.read_user_preset_library()
    if user_content then
        local data = user_content:match(pattern1) or user_content:match(pattern2)
        if data then
            return data:gsub("%s+", "")
        end
    end

    -- Then check factory presets
    local factory_content = M.read_preset_library()
    if factory_content then
        local data = factory_content:match(pattern1) or factory_content:match(pattern2)
        if data then
            return data:gsub("%s+", "")
        end
    end

    return nil
end

--- Parse decoded preset string into shape data
-- @param decoded_str string Space-separated preset values
-- @return table|nil Shape data {num_points, points, curves} or nil on error
function M.parse_preset_string(decoded_str)
    local values = {}
    for val in decoded_str:gmatch("[^%s]+") do
        table.insert(values, val)
    end

    if #values < 72 then
        return nil  -- Not enough values
    end

    -- num_points is at position 30 (index 30 in 1-based)
    local num_points = tonumber(values[30]) or 2

    -- Points start at position 40 (index 40 in 1-based)
    local points = {}
    for i = 1, 16 do
        local x_idx = 40 + (i - 1) * 2 - 1 + 1  -- Convert to 1-based
        local y_idx = x_idx + 1
        local x = tonumber(values[x_idx]) or 0.5
        local y = tonumber(values[y_idx]) or 0.5
        points[i] = {x = x, y = y}
    end

    -- Curves start after position 72 (after the name which is at 65)
    -- In the decoded string, name is at position 65, so curves are at 73+
    local curves = {}
    for i = 1, 15 do
        local curve_idx = 72 + i  -- 1-based: 73, 74, ... 87
        local curve = tonumber(values[curve_idx]) or 0
        curves[i] = curve
    end

    return {
        num_points = num_points,
        points = points,
        curves = curves
    }
end

--- Apply shape data to a modulator FX
-- @param track MediaTrack pointer
-- @param fx_idx number FX index
-- @param shape table Shape data {num_points, points, curves}
function M.apply_shape(track, fx_idx, shape)
    -- Set number of points
    r.TrackFX_SetParam(track, fx_idx, PARAM.PARAM_NUM_POINTS, shape.num_points)

    -- Set points
    for i = 1, 16 do
        local point = shape.points[i] or {x = 0.5, y = 0.5}
        r.TrackFX_SetParam(track, fx_idx, PARAM.PARAM_POINT_START + (i - 1) * 2, point.x)
        r.TrackFX_SetParam(track, fx_idx, PARAM.PARAM_POINT_START + (i - 1) * 2 + 1, point.y)
    end

    -- Set curves
    for i = 1, 15 do
        local curve = shape.curves[i] or 0
        r.TrackFX_SetParam(track, fx_idx, PARAM.PARAM_SEGMENT_CURVE_START + (i - 1), curve)
    end
end

--- Load a preset by name from .rpl file and apply to modulator
-- This is used when REAPER's built-in preset system hasn't loaded the preset yet
-- @param track MediaTrack pointer
-- @param fx_idx number FX index
-- @param preset_name string Name of the preset
-- @return boolean Success
function M.load_preset_by_name(track, fx_idx, preset_name)
    local data = M.get_preset_data_by_name(preset_name)
    if not data then
        return false
    end

    local decoded = base64_decode(data)
    if not decoded or decoded == "" then
        return false
    end

    local shape = M.parse_preset_string(decoded)
    if not shape then
        return false
    end

    M.apply_shape(track, fx_idx, shape)
    return true
end

--- Save a new preset to the user library
-- @param name string Preset name
-- @param shape table Shape data from read_shape()
-- @return boolean, string Success and error message
function M.save_preset_to_library(name, shape)
    local path = M.get_user_preset_path()

    -- Ensure presets directory exists
    local resource_path = r.GetResourcePath()
    r.RecursiveCreateDirectory(resource_path .. "/presets", 0)

    -- Read existing user content
    local content = M.read_user_preset_library()
    if not content then
        -- Create new user library
        content = '<REAPER_PRESET_LIBRARY "JS: SideFX Modulator User"\n>\n'
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

    -- Write to user file
    local file, err = io.open(path, "w")
    if not file then
        return false, "Cannot open file for writing: " .. (err or path)
    end
    file:write(new_content)
    file:close()

    return true, nil
end

--- Get possible paths to REAPER's preset .ini cache files for this JSFX
-- REAPER creates .ini files with various naming conventions depending on installation
-- @return table Array of possible .ini file paths
function M.get_ini_preset_paths()
    local resource_path = r.GetResourcePath()
    local presets_dir = resource_path .. "/presets/"

    -- Try multiple possible naming patterns
    return {
        presets_dir .. "jsfx-SideFX-SideFX_Modulator.ini",
        presets_dir .. "jsfx-Scripts-SideFX-jsfx-SideFX_Modulator.ini",
        presets_dir .. "js-SideFX_SideFX_Modulator.ini",
        presets_dir .. "jsfx-jsfx-SideFX_Modulator.ini",
    }
end

--- Get the path to REAPER's preset .ini file for this JSFX (legacy single path)
-- @return string Path to .ini file
function M.get_ini_preset_path()
    local paths = M.get_ini_preset_paths()
    -- Check which one exists
    for _, path in ipairs(paths) do
        local f = io.open(path, "r")
        if f then
            f:close()
            return path
        end
    end
    -- Return first path as default
    return paths[1]
end

--- Build preset data string (space-separated values)
-- @param name string Preset name
-- @param shape table Shape data
-- @return string Preset data string
local function build_preset_string(name, shape)
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
    for i = 1, 15 do
        local curve = shape.curves[i] or 0
        if math.abs(curve) > 0.001 then
            values[72 + i] = string.format("%.6g", curve)
        else
            values[72 + i] = "0"
        end
    end

    return table.concat(values, " ")
end

--- Save preset to REAPER's .ini file (user presets)
-- @param name string Preset name
-- @param shape table Shape data
-- @return boolean, string Success and error message
function M.save_to_ini(name, shape)
    local ini_path = M.get_ini_preset_path()

    -- Read existing ini file
    local existing_content = ""
    local num_presets = 0
    local file = io.open(ini_path, "r")
    if file then
        existing_content = file:read("*a")
        file:close()
        -- Find current number of presets
        local nb = existing_content:match("NbPresets=(%d+)")
        num_presets = tonumber(nb) or 0
    end

    -- Build preset data string and encode
    local preset_str = build_preset_string(name, shape)
    local hex_data = hex_encode(preset_str)
    local checksum = calc_checksum(hex_data)
    local full_hex = hex_data .. checksum

    -- Build new preset section
    local preset_idx = num_presets
    local preset_section = string.format("\n[Preset%d]\nData=%s\nLen=%d\nName=%s\n",
        preset_idx, full_hex, #preset_str, name)

    -- Update or create ini content
    local new_content
    if existing_content == "" then
        -- Create new file
        new_content = "[General]\nLastDefImpTime=0\nNbPresets=1\n" .. preset_section
    else
        -- Update existing file
        new_content = existing_content:gsub("NbPresets=%d+", "NbPresets=" .. (num_presets + 1))
        new_content = new_content .. preset_section
    end

    -- Write file
    file = io.open(ini_path, "w")
    if not file then
        return false, "Cannot write to: " .. ini_path
    end
    file:write(new_content)
    file:close()

    return true, nil
end

--- Delete all possible .ini preset cache files to force REAPER to re-read .rpl
-- @return boolean, string Success and list of deleted files
function M.delete_ini_cache()
    local paths = M.get_ini_preset_paths()
    local deleted = {}

    for _, path in ipairs(paths) do
        local f = io.open(path, "r")
        if f then
            f:close()
            os.remove(path)
            table.insert(deleted, path)
        end
    end

    if #deleted > 0 then
        return true, "Deleted: " .. table.concat(deleted, ", ")
    end
    return true, "No cache files found"
end

--- Save current modulator shape as a preset
-- @param track MediaTrack pointer
-- @param fx_idx number FX index
-- @param name string Preset name
-- @return boolean, string Success and error message
function M.save_current_shape(track, fx_idx, name)
    local shape = M.read_shape(track, fx_idx)
    -- Save to .rpl library
    local success, err = M.save_preset_to_library(name, shape)
    if success then
        -- Delete .ini cache so REAPER re-reads the .rpl
        M.delete_ini_cache()
        -- Note: We don't navigate presets here as that would change the current waveform
        -- Instead, the sidebar will use TrackFX_SetPreset with name for selection
    end
    return success, err
end

--- Debug: Get current paths
-- @return string Path info for debugging
function M.debug_paths()
    local rpl_path = M.get_preset_library_path()
    local rpl_file = io.open(rpl_path, "r")
    local rpl_exists = rpl_file ~= nil
    if rpl_file then rpl_file:close() end

    local lines = {
        "RPL: " .. rpl_path,
        "RPL exists: " .. tostring(rpl_exists),
        "",
        "Possible INI paths:"
    }

    for _, path in ipairs(M.get_ini_preset_paths()) do
        local f = io.open(path, "r")
        local exists = f ~= nil
        if f then f:close() end
        table.insert(lines, "  " .. (exists and "[EXISTS]" or "[     ]") .. " " .. path)
    end

    return table.concat(lines, "\n")
end

return M
