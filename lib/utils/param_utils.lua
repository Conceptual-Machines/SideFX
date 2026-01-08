-- Parameter Utilities Module
-- Functions for analyzing and working with FX parameters

local M = {}
local r = reaper

-- Debug logging for parameter detection (only logs once per FX+param combo)
local DEBUG_PARAMS = false  -- Set to true to enable logging
local logged_params = {}   -- Cache to prevent repeated logging

--- Detect if a parameter is a switch (discrete) vs continuous
-- @param fx FX object
-- @param param_idx Parameter index
-- @return boolean true if switch, false if continuous
function M.is_switch_param(fx, param_idx)
    -- Get parameter step sizes from REAPER API
    -- Returns: retval, step, smallstep, largestep, istoggle
    local retval_step, step, smallstep, largestep, is_toggle = r.TrackFX_GetParameterStepSizes(fx.track.pointer, fx.pointer, param_idx)

    -- Get the parameter's value range
    local retval_range, minval, maxval, midval = r.TrackFX_GetParamEx(fx.track.pointer, fx.pointer, param_idx)

    -- Get param name
    local param_name = "?"
    pcall(function() param_name = fx:get_param_name(param_idx) end)

    -- Create unique key for logging
    local log_key = tostring(fx.pointer) .. "_" .. param_idx

    local result = false
    local reason = "default"

    -- 1. API says it's explicitly a toggle
    if is_toggle == true then
        result = true
        reason = "API is_toggle"
    -- 2. API provides step info and step covers most of range (2 values)
    elseif retval_step and step and step > 0 and retval_range and maxval and minval then
        local range = maxval - minval
        if range > 0 and step >= range * 0.5 then
            result = true
            reason = string.format("step=%s >= range/2", step)
        end
    end

    -- 3. Fallback: check param name for common switch keywords
    -- Only if API didn't provide info (retval_step=false)
    if not result and not retval_step and param_name then
        local lower = param_name:lower()
        -- Common switch/toggle parameter names
        if lower == "bypass" or lower == "on" or lower == "off" or
           lower == "enabled" or lower == "enable" or lower == "mute" or
           lower == "solo" or lower == "delta" or
           lower:find("on/off") or lower:find("mode$") then
            result = true
            reason = "name match: " .. lower
        end
    end

    -- Log only once per param
    if DEBUG_PARAMS and not logged_params[log_key] then
        logged_params[log_key] = true
        r.ShowConsoleMsg(string.format(
            "[%d] '%s': retval=%s, step=%s, is_toggle=%s -> %s (%s)\n",
            param_idx,
            param_name or "nil",
            tostring(retval_step),
            tostring(step),
            tostring(is_toggle),
            result and "SWITCH" or "CONTINUOUS",
            reason
        ))
    end

    return result
end

--- Reset parameter logging cache
function M.reset_param_logging()
    logged_params = {}
end

return M
