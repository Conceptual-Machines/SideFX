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
    st = { format = "%+.1f st", display_mult = 48, label = "Semitones (st)", use_plugin_format = false, is_bipolar = true },
    ct = { format = "%+.0f ct", display_mult = 100, label = "Cents (ct)", use_plugin_format = false, is_bipolar = true },
    linear = { format = "%.3f", display_mult = 1, label = "Linear (0-1)", use_plugin_format = false },
    linear100 = { format = "%.1f", display_mult = 100, label = "Linear (0-100)", use_plugin_format = false },
    bipolar = { format = "%+.0f", display_mult = 100, label = "Bipolar (-50/+50)", use_plugin_format = false, is_bipolar = true },
    switch = { format = "", display_mult = 1, label = "Switch (On/Off)", use_plugin_format = false, is_switch = true },
    plugin = { format = " ", display_mult = 1, label = "Plugin Format", use_plugin_format = true, hide_label = true },
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
    { id = "st", label = "Semitones (st)" },
    { id = "ct", label = "Cents (ct)" },
    { id = "linear", label = "Linear (0-1)" },
    { id = "linear100", label = "Linear (0-100)" },
    { id = "bipolar", label = "Bipolar (-50/+50)" },
    { id = "switch", label = "Switch (On/Off)" },
    { id = "plugin", label = "Plugin Format" },
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
    if formatted_str:match("st$") or formatted_str:match("semi") then
        return M.get_unit_info("st")
    end

    -- Check for cents (ct or cents)
    if formatted_str:match("ct$") or formatted_str:match("cents$") then
        return M.get_unit_info("ct")
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
-- @param custom_min number|nil Custom minimum value (overrides default)
-- @param custom_max number|nil Custom maximum value (overrides default)
-- @return table Unit info with {unit, format, display_mult, label, min, max}
function M.get_unit_info(unit_id, custom_min, custom_max)
    if not unit_id or unit_id == "auto" then
        return nil  -- Auto-detect mode
    end

    local unit = M.UNITS[unit_id]
    if unit then
        local info = {
            unit = unit_id,
            format = unit.format,
            display_mult = unit.display_mult,
            label = unit.label,
            use_plugin_format = unit.use_plugin_format or false,
            is_bipolar = unit.is_bipolar or false,
            is_switch = unit.is_switch or false,
            hide_label = unit.hide_label or false,
        }

        -- Apply custom range if provided
        if custom_min and custom_max then
            info.min = custom_min
            info.max = custom_max
            info.has_custom_range = true
            -- Calculate display_mult from range (for bipolar: total range, for unipolar: max)
            if info.is_bipolar then
                info.display_mult = custom_max - custom_min
            else
                info.display_mult = custom_max - custom_min
            end
        end

        return info
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

--- Get default min/max for a unit type
-- @param unit_id string The unit ID
-- @return number min, number max
function M.get_unit_default_range(unit_id)
    local unit = M.UNITS[unit_id]
    if not unit then return 0, 100 end

    if unit.is_bipolar then
        -- Bipolar: range is symmetric around 0
        local half = unit.display_mult / 2
        return -half, half
    else
        -- Unipolar: 0 to display_mult
        return 0, unit.display_mult
    end
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
