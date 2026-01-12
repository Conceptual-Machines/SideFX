--- Unit Detector Module
-- Detects parameter units from formatted value strings
-- @module utils.unit_detector
-- @author Nomad Monad
-- @license MIT

local M = {}

--- Unit definitions with format strings and display multipliers
-- use_plugin_format: if true, display the plugin's formatted value instead of computing
M.UNITS = {
    percent = { format = "%.1f%%", display_mult = 100, label = "Percent (%)", use_plugin_format = false },
    dB = { format = "%.1f dB", display_mult = 1, label = "Decibels (dB)", use_plugin_format = true },
    Hz = { format = "%.0f Hz", display_mult = 1, label = "Hertz (Hz)", use_plugin_format = true },
    kHz = { format = "%.2f kHz", display_mult = 1, label = "Kilohertz (kHz)", use_plugin_format = true },
    ms = { format = "%.0f ms", display_mult = 1, label = "Milliseconds (ms)", use_plugin_format = true },
    s = { format = "%.2f s", display_mult = 1, label = "Seconds (s)", use_plugin_format = true },
    linear = { format = "%.3f", display_mult = 1, label = "Linear (0-1)", use_plugin_format = false },
    linear100 = { format = "%.1f", display_mult = 100, label = "Linear (0-100)", use_plugin_format = false },
}

--- Unit options for dropdown (in display order)
M.UNIT_OPTIONS = {
    { id = "auto", label = "Auto" },
    { id = "percent", label = "Percent (%)" },
    { id = "dB", label = "Decibels (dB)" },
    { id = "Hz", label = "Hertz (Hz)" },
    { id = "kHz", label = "Kilohertz (kHz)" },
    { id = "ms", label = "Milliseconds (ms)" },
    { id = "s", label = "Seconds (s)" },
    { id = "linear", label = "Linear (0-1)" },
    { id = "linear100", label = "Linear (0-100)" },
}

--- Detect unit from formatted parameter value string
-- @param formatted_str string The plugin's formatted parameter value (e.g., "50.0%", "-12.0 dB")
-- @return table Unit info with {unit, format, display_mult}
function M.detect_unit(formatted_str)
    if not formatted_str or formatted_str == "" then
        return M.get_unit_info("percent")  -- Default to percent
    end

    -- Trim whitespace
    formatted_str = formatted_str:match("^%s*(.-)%s*$") or formatted_str

    -- Check for percentage (ends with %)
    if formatted_str:match("%%$") then
        return M.get_unit_info("percent")
    end

    -- Check for decibels (ends with dB, case insensitive)
    if formatted_str:match("[dD][bB]$") then
        return M.get_unit_info("dB")
    end

    -- Check for kilohertz (ends with kHz, case insensitive)
    if formatted_str:match("[kK][hH][zZ]$") then
        return M.get_unit_info("kHz")
    end

    -- Check for hertz (ends with Hz, case insensitive) - after kHz check
    if formatted_str:match("[hH][zZ]$") then
        return M.get_unit_info("Hz")
    end

    -- Check for milliseconds (ends with ms)
    if formatted_str:match("ms$") then
        return M.get_unit_info("ms")
    end

    -- Check for seconds (ends with s, but not ms) - must be careful
    if formatted_str:match("%d+%.?%d*%s*s$") and not formatted_str:match("ms$") then
        return M.get_unit_info("s")
    end

    -- Check for semitones (st)
    if formatted_str:match("st$") then
        return { unit = "st", format = "%.1f st", display_mult = 1, label = "Semitones" }
    end

    -- Check for cents (ct or cents)
    if formatted_str:match("ct$") or formatted_str:match("cents$") then
        return { unit = "ct", format = "%.0f ct", display_mult = 1, label = "Cents" }
    end

    -- Check for degrees
    if formatted_str:match("°$") or formatted_str:match("deg$") then
        return { unit = "deg", format = "%.1f°", display_mult = 1, label = "Degrees" }
    end

    -- Check if it's a plain number (integer or decimal)
    local num = tonumber(formatted_str)
    if num then
        -- If it looks like a 0-1 range value
        if num >= 0 and num <= 1 then
            return M.get_unit_info("linear")
        -- If it looks like a 0-100 range value
        elseif num >= 0 and num <= 100 then
            return M.get_unit_info("linear100")
        end
    end

    -- Default to percent for unknown formats
    return M.get_unit_info("percent")
end

--- Get unit info by unit ID
-- @param unit_id string The unit ID (e.g., "percent", "dB", "Hz")
-- @return table Unit info with {unit, format, display_mult, label}
function M.get_unit_info(unit_id)
    if not unit_id or unit_id == "auto" then
        return nil  -- Auto-detect mode
    end

    local unit = M.UNITS[unit_id]
    if unit then
        return {
            unit = unit_id,
            format = unit.format,
            display_mult = unit.display_mult,
            label = unit.label,
            use_plugin_format = unit.use_plugin_format or false
        }
    end

    -- Fallback to percent
    return {
        unit = "percent",
        format = M.UNITS.percent.format,
        display_mult = M.UNITS.percent.display_mult,
        label = M.UNITS.percent.label,
        use_plugin_format = false
    }
end

--- Get unit option index by ID (for dropdown selection)
-- @param unit_id string The unit ID or nil for auto
-- @return number Index in UNIT_OPTIONS (1-based)
function M.get_unit_option_index(unit_id)
    if not unit_id then
        return 1  -- "Auto" is first
    end
    for i, opt in ipairs(M.UNIT_OPTIONS) do
        if opt.id == unit_id then
            return i
        end
    end
    return 1  -- Default to Auto
end

--- Get unit ID by option index
-- @param index number Index in UNIT_OPTIONS (1-based)
-- @return string Unit ID or "auto"
function M.get_unit_id_by_index(index)
    local opt = M.UNIT_OPTIONS[index]
    if opt then
        return opt.id
    end
    return "auto"
end

return M
