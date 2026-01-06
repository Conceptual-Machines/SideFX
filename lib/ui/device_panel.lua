--- Device Panel UI Component
-- Renders a single FX as an Ableton-style device panel.
-- @module ui.device_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper
local widgets = require('lib.ui.widgets')
local fx_utils = require('lib.fx_utils')

local M = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

M.config = {
    column_width = 180,        -- Width per parameter column
    header_height = 32,
    param_height = 38,         -- Height per param row (label + slider)
    sidebar_width = 120,       -- Width for sidebar (controls on right)
    sidebar_padding = 12,      -- Extra padding for scrollbar
    padding = 8,               -- Padding around content
    border_radius = 6,
    fader_width = 28,          -- Fader width
    fader_height = 70,         -- Fader height
    knob_size = 48,            -- Knob diameter
    -- Modulator sidebar (left side of device)
    mod_sidebar_width = 240,   -- Width for modulator 2×4 grid
    mod_sidebar_collapsed_width = 24,  -- Collapsed width
    mod_slot_width = 60,
    mod_slot_height = 60,
    mod_slot_padding = 4,
}

-- Utility JSFX name for detection
M.UTILITY_JSFX = "SideFX_Utility"

-- Colors (RGBA as 0xRRGGBBAA)
M.colors = {
    panel_bg = 0x2A2A2AFF,
    panel_bg_hover = 0x333333FF,
    panel_border = 0x444444FF,
    header_bg = 0x383838FF,
    header_text = 0xDDDDDDFF,
    param_label = 0xAAAAAAFF,
    param_value = 0xCCCCCCFF,
    bypass_on = 0x44AA44FF,
    bypass_off = 0xAA4444FF,
    slider_bg = 0x1A1A1AFF,
    slider_fill = 0x5588CCFF,
    slider_grab = 0x77AAEEFF,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Track expanded state per FX (by GUID)
local expanded_state = {}

-- Track sidebar collapsed state per FX (by GUID)
local sidebar_collapsed = {}

-- Track panel collapsed state per FX (by GUID) - collapses the whole panel to just header
local panel_collapsed = {}

-- Track modulator sidebar collapsed state per device container (by GUID)
local mod_sidebar_collapsed = {}

-- Track which modulator slot is expanded per device container (by GUID)
local expanded_mod_slot = {}  -- {[device_guid] = slot_index} or nil

-- Rename state: which FX is being renamed and the edit buffer
local rename_active = {}    -- guid -> true if rename mode active
local rename_buffer = {}    -- guid -> current edit text

--------------------------------------------------------------------------------
-- Custom Widgets
--------------------------------------------------------------------------------

--- Draw a UI button icon (window/screen icon)
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param width number Button width
-- @param height number Button height
-- @return boolean True if clicked
local function draw_ui_icon(ctx, label, width, height)
    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local clicked = r.ImGui_IsItemClicked(ctx.ctx, 0)

    -- Get button bounds for drawing
    local item_min_x, item_min_y = r.ImGui_GetItemRectMin(ctx.ctx)
    local item_max_x, item_max_y = r.ImGui_GetItemRectMax(ctx.ctx)

    -- Draw window/screen icon using DrawList
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    local center_x = (item_min_x + item_max_x) / 2
    local center_y = (item_min_y + item_max_y) / 2
    local icon_size = 12
    local half_size = icon_size / 2

    -- Draw a simple window icon: rectangle with a line in the middle (like a window)
    local x1 = center_x - half_size
    local y1 = center_y - half_size
    local x2 = center_x + half_size
    local y2 = center_y + half_size

    -- Greyish color for the icon
    local icon_color = 0xAAAAAAFF
    -- Border color
    local border_color = 0x666666FF

    -- Draw border around the button
    r.ImGui_DrawList_AddRect(draw_list, item_min_x, item_min_y, item_max_x, item_max_y, border_color, 0, 0, 1.0)

    -- Outer rectangle (window frame) - signature: (draw_list, x1, y1, x2, y2, color, rounding, flags, thickness)
    r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, icon_color, 0, 0, 2)
    -- Inner line (window pane divider)
    r.ImGui_DrawList_AddLine(draw_list, center_x, y1, center_x, y2, icon_color, 1.5)

    return clicked
end

--- Draw an ON/OFF circle indicator with colored background
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param is_on boolean Whether the state is ON
-- @param width number Button width
-- @param height number Button height
-- @param bg_color_on number RGBA color for ON background
-- @param bg_color_off number RGBA color for OFF background
-- @return boolean True if clicked
local function draw_on_off_circle(ctx, label, is_on, width, height, bg_color_on, bg_color_off)
    -- Get cursor position for drawing
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local center_x = cursor_x + width / 2
    local center_y = cursor_y + height / 2
    local radius = 6  -- Small circle radius

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local clicked = r.ImGui_IsItemClicked(ctx.ctx, 0)
    local is_hovered = r.ImGui_IsItemHovered(ctx.ctx)

    -- Draw background and circle
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    -- Draw background rectangle
    local bg_color = is_on and (bg_color_on or colors.bypass_on) or (bg_color_off or colors.bypass_off)
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + width, cursor_y + height, bg_color, 0)

    if is_on then
        -- Filled circle for ON state
        r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, 0xFFFFFFFF, 12)
    else
        -- Empty circle (outline only) for OFF state
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radius, 0xFFFFFFFF, 12, 2)
    end

    return clicked
end

--- Draw a knob control
-- @param ctx ImGui context
-- @param label string Label for the knob
-- @param value number Current value (0-1)
-- @param size number Diameter of the knob
-- @return boolean changed, number new_value
local function draw_knob(ctx, label, value, size)
    local changed = false
    local new_value = value

    size = size or 32
    local radius = size / 2

    -- Get cursor position for drawing
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local center_x = cursor_x + radius
    local center_y = cursor_y + radius

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, size, size)
    local is_active = r.ImGui_IsItemActive(ctx.ctx)
    local is_hovered = r.ImGui_IsItemHovered(ctx.ctx)

    -- Handle dragging
    if is_active then
        local delta_y = r.ImGui_GetMouseDragDelta(ctx.ctx, 0, 0, 0)
        if delta_y ~= 0 then
            local _, dy = r.ImGui_GetMouseDragDelta(ctx.ctx, 0, 0, 0)
            new_value = math.max(0, math.min(1, value - dy * 0.005))
            r.ImGui_ResetMouseDragDelta(ctx.ctx, 0)
            if new_value ~= value then
                changed = true
            end
        end
    end

    -- Draw knob
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    -- Background circle
    local bg_color = is_hovered and 0x444444FF or 0x333333FF
    r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius - 2, bg_color)

    -- Border
    local border_color = is_active and 0x88AACCFF or 0x666666FF
    r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radius - 2, border_color, 0, 2)

    -- Value arc (270 degree range, starting from bottom-left)
    local start_angle = 0.75 * math.pi  -- 135 degrees (bottom-left)
    local end_angle = 2.25 * math.pi    -- 405 degrees (bottom-right)
    local value_angle = start_angle + (end_angle - start_angle) * new_value

    -- Draw filled arc for value
    if new_value > 0.01 then
        local arc_radius = radius - 5
        local segments = 24
        local step = (value_angle - start_angle) / segments
        for i = 0, segments - 1 do
            local a1 = start_angle + step * i
            local a2 = start_angle + step * (i + 1)
            local x1 = center_x + math.cos(a1) * arc_radius
            local y1 = center_y + math.sin(a1) * arc_radius
            local x2 = center_x + math.cos(a2) * arc_radius
            local y2 = center_y + math.sin(a2) * arc_radius
            r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, 0x88AACCFF, 3)
        end
    end

    -- Indicator line
    local ind_inner = radius * 0.3
    local ind_outer = radius * 0.7
    local ind_x1 = center_x + math.cos(value_angle) * ind_inner
    local ind_y1 = center_y + math.sin(value_angle) * ind_inner
    local ind_x2 = center_x + math.cos(value_angle) * ind_outer
    local ind_y2 = center_y + math.sin(value_angle) * ind_outer
    r.ImGui_DrawList_AddLine(draw_list, ind_x1, ind_y1, ind_x2, ind_y2, 0xFFFFFFFF, 2)

    return changed, new_value
end

--- Draw a fader control (vertical slider with fill)
-- @param ctx ImGui context
-- @param label string Label for the fader
-- @param value number Current value
-- @param min_val number Minimum value
-- @param max_val number Maximum value
-- @param width number Width of fader
-- @param height number Height of fader
-- @param format string Display format
-- @return boolean changed, number new_value
local function draw_fader(ctx, label, value, min_val, max_val, width, height, format)
    local changed = false
    local new_value = value

    -- Get cursor position for drawing
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)

    -- Calculate fill height based on value
    local normalized = (value - min_val) / (max_val - min_val)
    local fill_height = height * normalized

    -- Draw background
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + width, cursor_y + height, 0x1A1A1AFF, 3)

    -- Draw fill from bottom
    if fill_height > 0 then
        local fill_top = cursor_y + height - fill_height
        -- Gradient-like effect with multiple colors
        local fill_color = 0x5588AACC
        r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x + 2, fill_top, cursor_x + width - 2, cursor_y + height - 2, fill_color, 2)
    end

    -- Border
    r.ImGui_DrawList_AddRect(draw_list, cursor_x, cursor_y, cursor_x + width, cursor_y + height, 0x555555FF, 3)

    -- Invisible slider on top for interaction
    r.ImGui_SetCursorScreenPos(ctx.ctx, cursor_x, cursor_y)
    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_FrameBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_FrameBgHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_FrameBgActive(), 0x00000000)
    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_SliderGrab(), 0xAAAAAAFF)
    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_SliderGrabActive(), 0xFFFFFFFF)
    r.ImGui_PushStyleVar(ctx.ctx, r.ImGui_StyleVar_GrabMinSize(), 8)

    changed, new_value = r.ImGui_VSliderDouble(ctx.ctx, label, width, height, value, min_val, max_val, format)

    r.ImGui_PopStyleVar(ctx.ctx)
    r.ImGui_PopStyleColor(ctx.ctx, 5)

    return changed, new_value
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Get the internal REAPER name (with prefix)
local function get_internal_name(fx)
    if not fx then return "" end
    local ok, renamed = pcall(function() return fx:get_named_config_param("renamed_name") end)
    if ok and renamed and renamed ~= "" then
        return renamed
    end
    local ok2, name = pcall(function() return fx:get_name() end)
    return ok2 and name or ""
end

-- Extract the SideFX prefix from a name (R1_C1:, D1:, R1:)
local function extract_prefix(name)
    local prefix = name:match("^(R%d+_C%d+:%s*)")
    if prefix then return prefix end
    prefix = name:match("^(D%d+:%s*)")
    if prefix then return prefix end
    prefix = name:match("^(R%d+:%s*)")
    if prefix then return prefix end
    return ""
end

local function get_display_name(fx)
    if not fx then return "Unknown" end

    -- Check for custom display name first (SideFX-only renaming)
    local ok_guid, guid = pcall(function() return fx:get_guid() end)
    if ok_guid and guid then
        local state_module = require('lib.state')
        local state = state_module.state
        if state.display_names[guid] then
            return state.display_names[guid]
        end
    end

    -- Fall back to internal name with prefixes stripped
    local name = get_internal_name(fx)

    -- Strip SideFX internal prefixes for clean UI display
    -- Patterns from most specific to least specific
    name = name:gsub("^R%d+_C%d+_D%d+_FX:%s*", "")  -- R1_C1_D1_FX: prefix
    name = name:gsub("^R%d+_C%d+_D%d+:%s*", "")     -- R1_C1_D1: prefix
    name = name:gsub("^R%d+_C%d+:%s*", "")          -- R1_C1: prefix
    name = name:gsub("^D%d+_FX:%s*", "")            -- D1_FX: prefix
    name = name:gsub("^D%d+:%s*", "")               -- D1: prefix
    name = name:gsub("^R%d+:%s*", "")               -- R1: prefix

    -- Strip common plugin format prefixes
    name = name:gsub("^VST3?: ", "")
    name = name:gsub("^AU: ", "")
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAP: ", "")

    return name
end

-- Rename an FX while preserving its internal prefix
local function rename_fx(fx, new_display_name)
    if not fx or not new_display_name then return false end
    local internal_name = get_internal_name(fx)
    local prefix = extract_prefix(internal_name)
    local new_internal_name = prefix .. new_display_name
    local ok = pcall(function()
        fx:set_named_config_param("renamed_name", new_internal_name)
    end)
    return ok
end

local function truncate(str, max_len)
    if #str <= max_len then return str end
    return str:sub(1, max_len - 2) .. ".."
end

-- Debug logging for parameter detection (only logs once per FX+param combo)
local DEBUG_PARAMS = false  -- Set to true to enable logging
local logged_params = {}   -- Cache to prevent repeated logging

--- Detect if a parameter is a switch (discrete) vs continuous
-- @param fx FX object
-- @param param_idx Parameter index
-- @return boolean true if switch, false if continuous
local function is_switch_param(fx, param_idx)
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

-- Call this to reset logging (e.g., when FX changes)
local function reset_param_logging()
    logged_params = {}
end

--------------------------------------------------------------------------------
-- Modulator Support
--------------------------------------------------------------------------------

-- Available modulator types
local MODULATOR_TYPES = {
    {id = "bezier_lfo", name = "Bezier LFO", jsfx = "JS:SideFX/SideFX_Modulator"},
    -- Future: Classic LFO, ADSR, etc.
}

--- Get all modulators inside a device container
-- @param device_container TrackFX D-container
-- @return table Array of modulator FX objects
local function get_device_modulators(device_container)
    if not device_container or not device_container:is_container() then
        return {}
    end

    local modulators = {}
    local ok, iter = pcall(function() return device_container:iter_container_children() end)
    if not ok then return {} end

    for child in iter do
        if fx_utils.is_modulator_fx(child) then
            table.insert(modulators, child)
        end
    end

    return modulators
end

--- Add a modulator to a device container
-- @param device_container TrackFX D-container
-- @param modulator_type table Modulator type definition
-- @param track Track object
-- @return TrackFX|nil Modulator FX object or nil on failure
local function add_modulator_to_device(device_container, modulator_type, track)
    if not track or not device_container then return nil end
    if not device_container:is_container() then return nil end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get container GUID before operations (GUID is stable)
    local container_guid = device_container:get_guid()
    if not container_guid then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (failed)", -1)
        return nil
    end

    -- Add modulator JSFX at track level first
    local modulator = track:add_fx_by_name(modulator_type.jsfx, false, -1)
    if not modulator or modulator.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (failed)", -1)
        return nil
    end

    local mod_guid = modulator:get_guid()

    -- Refind container by GUID (important for nested containers)
    local fresh_container = track:find_fx_by_guid(container_guid)
    if not fresh_container then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (container lost)", -1)
        return nil
    end

    -- Refresh pointer for deeply nested containers
    if fresh_container.pointer and fresh_container.pointer >= 0x2000000 and fresh_container.refresh_pointer then
        fresh_container:refresh_pointer()
    end

    -- Refind modulator by GUID
    modulator = track:find_fx_by_guid(mod_guid)
    if not modulator then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (modulator lost)", -1)
        return nil
    end

    -- Get insert position (append to end of container)
    local insert_pos = fresh_container:get_container_child_count()

    -- Move modulator into container
    local success = fresh_container:add_fx_to_container(modulator, insert_pos)

    if not success then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (move failed)", -1)
        return nil
    end

    -- Refind modulator after move (pointer changed)
    local moved_modulator = track:find_fx_by_guid(mod_guid)

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Modulator to Device", -1)

    return moved_modulator
end

--------------------------------------------------------------------------------
-- Device Panel Component
--------------------------------------------------------------------------------

--- Draw a single device panel.
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param opts table Options {on_delete, on_open_ui, on_drag, avail_height, ...}
-- @return boolean True if panel was interacted with
function M.draw(ctx, fx, opts)
    opts = opts or {}
    local cfg = M.config
    local colors = M.colors

    -- Get icon font for UI button
    local icon_font = opts.icon_font
    local constants = require('lib.constants')
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
    local ui_icon = constants.icon_text(emojimgui, constants.Icons.window)

    if not fx then return false end

    -- Safety check: FX might have been deleted
    local ok, guid = pcall(function() return fx:get_guid() end)
    if not ok or not guid then return false end

    -- Skip rendering modulators - they're handled by modulator_grid_panel
    local is_modulator = fx_utils.is_modulator_fx(fx)
    if is_modulator then
        return false
    end

    -- Use container GUID for drag/drop if we have a container
    local container = opts.container
    local drag_guid = container and container:get_guid() or guid

    -- Get device name and identifier separately
    local fx_utils = require('lib.fx_utils')
    local name = "Unknown"
    local device_id = nil
    if container then
        -- Get actual FX name (plugin name, not hierarchical) and identifier separately
        local ok_name, fx_name = pcall(function() return fx_utils.get_display_name(fx) end)
        if ok_name then name = fx_name end
        local ok_id, id = pcall(function() return fx_utils.get_device_identifier(container) end)
        if ok_id then device_id = id end
    else
        -- No container, use regular display name
        local ok2, fx_name = pcall(function() return get_display_name(fx) end)
        if ok2 then name = fx_name end
    end

    local ok3, enabled = pcall(function() return fx:get_enabled() end)
    if not ok3 then enabled = false end

    local ok4, param_count = pcall(function() return fx:get_num_params() end)
    if not ok4 then param_count = 0 end

    -- Build list of visible params (exclude sidebar controls: wet, delta, bypass)
    local visible_params = {}
    for i = 0, param_count - 1 do
        local ok_pn, pname = pcall(function() return fx:get_param_name(i) end)
        local skip = false
        if ok_pn and pname then
            local lower = pname:lower()
            if lower == "wet" or lower == "delta" or lower == "bypass" then
                skip = true
            end
        end
        if not skip then
            table.insert(visible_params, i)
        end
    end
    local visible_count = #visible_params

    -- Use available height passed in opts, or default
    local avail_height = opts.avail_height or 600

    -- Use drag_guid for state (container GUID if applicable)
    local state_guid = drag_guid

    -- Check if panel is collapsed (just header bar)
    local is_panel_collapsed = panel_collapsed[state_guid] or false

    -- Check if sidebar is collapsed
    local is_sidebar_collapsed = sidebar_collapsed[state_guid] or false
    local collapsed_sidebar_w = 8  -- Minimal width when collapsed (button is in header)

    -- Check modulator sidebar state early for panel width calculation
    if mod_sidebar_collapsed[state_guid] == nil then
        mod_sidebar_collapsed[state_guid] = true
    end
    local is_mod_sidebar_collapsed = mod_sidebar_collapsed[state_guid]

    -- Check if a modulator is expanded to make sidebar wider
    local expanded_slot_idx = expanded_mod_slot[state_guid]
    local mod_sidebar_expanded_w = 380  -- Wider width when modulator controls are shown

    local mod_sidebar_w
    if is_mod_sidebar_collapsed then
        mod_sidebar_w = cfg.mod_sidebar_collapsed_width
    elseif expanded_slot_idx ~= nil then
        mod_sidebar_w = mod_sidebar_expanded_w
    else
        mod_sidebar_w = cfg.mod_sidebar_width
    end

    -- Calculate dimensions based on collapsed state
    local panel_height, panel_width, content_width, num_columns, params_per_column

    if is_panel_collapsed then
        -- Collapsed: full height but narrow width
        panel_height = avail_height
        panel_width = 140  -- Minimal width for collapsed panel
        content_width = 0
        num_columns = 0
        params_per_column = 0
    else
        -- Expanded: full panel
        panel_height = avail_height

        -- Calculate how many params fit per column based on available height
        local usable_height = panel_height - cfg.header_height - cfg.padding * 2
        params_per_column = math.floor(usable_height / cfg.param_height)
        params_per_column = math.max(1, params_per_column)

        -- Calculate columns needed to show visible params only
        num_columns = math.ceil(visible_count / params_per_column)
        num_columns = math.max(1, num_columns)

        -- Calculate panel width: columns + sidebar (if visible) + modulator sidebar + padding
        content_width = cfg.column_width * num_columns
        local sidebar_w = is_sidebar_collapsed and collapsed_sidebar_w or (cfg.sidebar_width + cfg.sidebar_padding)

        panel_width = content_width + sidebar_w + mod_sidebar_w + cfg.padding * 2
    end

    local interacted = false

    ctx:push_id(guid)

    -- Panel background
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    -- Draw panel frame
    r.ImGui_DrawList_AddRectFilled(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_bg, cfg.border_radius)
    r.ImGui_DrawList_AddRect(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_border, cfg.border_radius, 0, 1)

    -- Begin child for panel content
    if ctx:begin_child("panel_" .. guid, panel_width, panel_height, 0) then

        -- Wrapper table: [Modulator Sidebar | Main Content]
        -- (mod_sidebar_w already calculated above for panel width)
        if r.ImGui_BeginTable(ctx.ctx, "device_wrapper_" .. guid, 2, r.ImGui_TableFlags_BordersInnerV()) then
            r.ImGui_TableSetupColumn(ctx.ctx, "modulators", r.ImGui_TableColumnFlags_WidthFixed(), mod_sidebar_w)
            r.ImGui_TableSetupColumn(ctx.ctx, "content", r.ImGui_TableColumnFlags_WidthStretch())

            r.ImGui_TableNextRow(ctx.ctx)

            -- === MODULATOR SIDEBAR ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)

            -- TODO: Draw modulator sidebar here
            if is_mod_sidebar_collapsed then
                -- Collapsed: show expand button
                if ctx:button("▶##expand_mod_" .. guid, 20, 30) then
                    mod_sidebar_collapsed[state_guid] = false
                    interacted = true
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Expand Modulators")
                end
            else
                -- Expanded: show grid
                if ctx:button("◀##collapse_mod_" .. guid, 24, 20) then
                    mod_sidebar_collapsed[state_guid] = true
                    interacted = true
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Collapse Modulators")
                end
                ctx:same_line()
                ctx:text("Modulators")
                ctx:separator()

                -- Get modulators for this device
                local modulators = get_device_modulators(container)
                local expanded_slot_idx = expanded_mod_slot[state_guid]

                -- Require imgui for Col constants
                local imgui = require('imgui')

                -- Require state module for modulator UI state
                local state_module = require('lib.state')
                local state = state_module.state

                -- Calculate slot dimensions to use available width
                local avail_width = ctx:get_content_region_avail()
                local slot_padding = 4  -- Padding between slots
                local slot_width = (avail_width - slot_padding) / 2  -- 2 columns
                local slot_height = cfg.mod_slot_height

                -- 2×4 grid of modulator slots
                for row = 0, 3 do
                    for col = 0, 1 do
                        local slot_idx = row * 2 + col
                        local modulator = modulators[slot_idx + 1]  -- Lua 1-based

                        if col > 0 then
                            ctx:same_line()
                        end

                        -- Draw slot
                        local slot_id = "slot_" .. slot_idx .. "_" .. guid
                        if modulator then
                            -- Slot has modulator - show short name (LFO1, LFO2, etc.)
                            local display_name = "LFO" .. (slot_idx + 1)

                            local is_expanded = (expanded_slot_idx == slot_idx)
                            if is_expanded then
                                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                            end

                            if ctx:button(display_name .. "##" .. slot_id, slot_width, slot_height) then
                                -- Toggle expansion
                                if expanded_mod_slot[state_guid] == slot_idx then
                                    expanded_mod_slot[state_guid] = nil
                                else
                                    expanded_mod_slot[state_guid] = slot_idx
                                end
                                interacted = true
                            end

                            -- Right-click context menu for modulator
                            if ctx:begin_popup_context_item("mod_ctx_" .. slot_id) then
                                if ctx:selectable("Delete Modulator") then
                                    -- Delete modulator
                                    local ok_del = pcall(function()
                                        modulator:delete()
                                    end)
                                    if ok_del then
                                        -- Clear expansion state for this slot
                                        expanded_mod_slot[state_guid] = nil
                                        -- Refresh FX list
                                        if opts.refresh_fx_list then
                                            opts.refresh_fx_list()
                                        end
                                        interacted = true
                                    end
                                end
                                ctx:end_popup()
                            end

                            if is_expanded then
                                ctx:pop_style_color()
                            end
                        else
                            -- Empty slot - show + button
                            if ctx:button("+##" .. slot_id, slot_width, slot_height) then
                                -- Show modulator type dropdown (simplified for now - just add Bezier LFO)
                                local track = opts.track or state.track
                                if track and container then
                                    local new_mod = add_modulator_to_device(container, MODULATOR_TYPES[1], track)
                                    if new_mod and opts.refresh_fx_list then
                                        opts.refresh_fx_list()
                                    end
                                end
                                interacted = true
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Add Modulator")
                            end
                        end
                    end
                end

                -- Show expanded modulator parameters
                if expanded_slot_idx ~= nil then
                    local expanded_modulator = modulators[expanded_slot_idx + 1]
                    if expanded_modulator then
                        -- Get parameter values safely (ReaWrap uses get_num_params, not get_param_count)
                        local ok, param_count = pcall(function() return expanded_modulator:get_num_params() end)
                        if ok and param_count and param_count > 0 then
                            ctx:separator()
                            ctx:spacing()
                            -- Get available width for controls
                            local control_width = ctx:get_content_region_avail() - 8  -- Small padding

                            -- Rate section
                            ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                            ctx:text("RATE")
                            ctx:pop_style_color()
                            ctx:spacing()

                            -- Tempo Mode: Free/Sync (slider1)
                            local ok_tempo, tempo_mode = pcall(function() return expanded_modulator:get_param_normalized(0) end)
                            if ok_tempo then
                                if ctx:radio_button("Free##tempo_" .. guid, tempo_mode < 0.5) then
                                    expanded_modulator:set_param_normalized(0, 0)
                                    interacted = true
                                end
                                ctx:same_line()
                                if ctx:radio_button("Sync##tempo_" .. guid, tempo_mode >= 0.5) then
                                    expanded_modulator:set_param_normalized(0, 1)
                                    interacted = true
                                end
                            end

                            -- Show Hz slider when Free mode, Sync Rate dropdown when Sync mode
                            if ok_tempo and tempo_mode < 0.5 then
                                -- Free mode - show Hz slider (slider2)
                                local ok_rate, rate_hz = pcall(function() return expanded_modulator:get_param_normalized(1) end)
                                if ok_rate then
                                    ctx:set_next_item_width(control_width)
                                    local changed, new_rate = ctx:slider_double("Hz##rate_" .. guid, rate_hz, 0.01, 20, "%.2f")
                                    if changed then
                                        expanded_modulator:set_param_normalized(1, new_rate)
                                        interacted = true
                                    end
                                end
                            else
                                -- Sync mode - show sync rate dropdown (slider3)
                                local ok_sync, sync_rate_idx = pcall(function() return expanded_modulator:get_param_normalized(2) end)
                                if ok_sync then
                                    local sync_rates = {"8 bars", "4 bars", "2 bars", "1 bar", "1/2", "1/4", "1/4T", "1/4.", "1/8", "1/8T", "1/8.", "1/16", "1/16T", "1/16.", "1/32", "1/32T", "1/32.", "1/64"}
                                    local current_idx = math.floor(sync_rate_idx * 17 + 0.5)
                                    ctx:set_next_item_width(control_width)
                                    if ctx:begin_combo("##sync_rate_" .. guid, sync_rates[current_idx + 1] or "1/4") then
                                        for i, rate_name in ipairs(sync_rates) do
                                            if ctx:selectable(rate_name, i - 1 == current_idx) then
                                                expanded_modulator:set_param_normalized(2, (i - 1) / 17)
                                                interacted = true
                                            end
                                        end
                                        ctx:end_combo()
                                    end
                                end
                            end

                            ctx:spacing()

                            -- Phase (slider5)
                            local ok_phase, phase = pcall(function() return expanded_modulator:get_param_normalized(4) end)
                            if ok_phase then
                                ctx:set_next_item_width(control_width)
                                local phase_deg = phase * 360
                                local changed, new_phase_deg = ctx:slider_double("Phase##phase_" .. guid, phase_deg, 0, 360, "%.0f°")
                                if changed then
                                    expanded_modulator:set_param_normalized(4, new_phase_deg / 360)
                                    interacted = true
                                end
                            end

                            -- Depth (slider6)
                            local ok_depth, depth = pcall(function() return expanded_modulator:get_param_normalized(5) end)
                            if ok_depth then
                                ctx:set_next_item_width(control_width)
                                local depth_pct = depth * 100
                                local changed, new_depth_pct = ctx:slider_double("Depth##depth_" .. guid, depth_pct, 0, 100, "%.0f%%")
                                if changed then
                                    expanded_modulator:set_param_normalized(5, new_depth_pct / 100)
                                    interacted = true
                                end
                            end

                            ctx:spacing()

                            -- Trigger Mode section
                            ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                            ctx:text("TRIGGER")
                            ctx:pop_style_color()
                            ctx:spacing()

                            -- Trigger Mode dropdown (slider20)
                            local ok_trig, trigger_mode_val = pcall(function() return expanded_modulator:get_param_normalized(19) end)
                            if ok_trig then
                                local trigger_modes = {"Free", "Transport", "MIDI", "Audio"}
                                local trig_idx = math.floor(trigger_mode_val * 3 + 0.5)
                                ctx:set_next_item_width(control_width)
                                if ctx:begin_combo("##trigger_mode_" .. guid, trigger_modes[trig_idx + 1] or "Free") then
                                    for i, mode_name in ipairs(trigger_modes) do
                                        if ctx:selectable(mode_name, i - 1 == trig_idx) then
                                            expanded_modulator:set_param_normalized(19, (i - 1) / 3)
                                            interacted = true
                                        end
                                    end
                                    ctx:end_combo()
                                end
                            end

                            ctx:spacing()

                            -- LFO Mode section
                            ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                            ctx:text("MODE")
                            ctx:pop_style_color()
                            ctx:spacing()

                            -- LFO Mode: Loop/One Shot (slider28)
                            local ok_lfo_mode, lfo_mode = pcall(function() return expanded_modulator:get_param_normalized(27) end)
                            if ok_lfo_mode then
                                if ctx:radio_button("Loop##lfo_" .. guid, lfo_mode < 0.5) then
                                    expanded_modulator:set_param_normalized(27, 0)
                                    interacted = true
                                end
                                ctx:same_line()
                                if ctx:radio_button("One Shot##lfo_" .. guid, lfo_mode >= 0.5) then
                                    expanded_modulator:set_param_normalized(27, 1)
                                    interacted = true
                                end
                            end

                            ctx:spacing()

                            -- Advanced section (collapsible)
                            local advanced_key = "mod_advanced_" .. guid .. "_" .. expanded_slot_idx
                            local is_advanced_open = state.modulator_advanced[advanced_key] or false

                            if ctx:tree_node("Advanced##adv_" .. guid) then
                                state.modulator_advanced[advanced_key] = true

                                -- Show additional params based on trigger mode
                                if ok_trig and trig_idx == 2 then
                                    -- MIDI trigger mode
                                    -- MIDI Source (slider21)
                                    local ok_midi_src, midi_src = pcall(function() return expanded_modulator:get_param_normalized(20) end)
                                    if ok_midi_src then
                                        if ctx:radio_button("This Track##midi_src_" .. guid, midi_src < 0.5) then
                                            expanded_modulator:set_param_normalized(20, 0)
                                            interacted = true
                                        end
                                        ctx:same_line()
                                        if ctx:radio_button("MIDI Bus##midi_src_" .. guid, midi_src >= 0.5) then
                                            expanded_modulator:set_param_normalized(20, 1)
                                            interacted = true
                                        end
                                    end

                                    -- MIDI Note (slider22)
                                    local ok_note, midi_note = pcall(function() return expanded_modulator:get_param_normalized(21) end)
                                    if ok_note then
                                        ctx:set_next_item_width(control_width)
                                        local note_val = math.floor(midi_note * 127 + 0.5)
                                        local changed, new_note_val = ctx:slider_int("MIDI Note##note_" .. guid, note_val, 0, 127, note_val == 0 and "Any" or tostring(note_val))
                                        if changed then
                                            expanded_modulator:set_param_normalized(21, new_note_val / 127)
                                            interacted = true
                                        end
                                    end
                                elseif ok_trig and trig_idx == 3 then
                                    -- Audio trigger mode
                                    -- Audio Threshold (slider23)
                                    local ok_thresh, audio_thresh = pcall(function() return expanded_modulator:get_param_normalized(22) end)
                                    if ok_thresh then
                                        ctx:set_next_item_width(control_width)
                                        local changed, new_thresh = ctx:slider_double("Threshold##thresh_" .. guid, audio_thresh, 0, 1, "%.2f")
                                        if changed then
                                            expanded_modulator:set_param_normalized(22, new_thresh)
                                            interacted = true
                                        end
                                    end
                                end

                                -- Attack/Release (always show in advanced)
                                if ok_trig and trig_idx > 0 then
                                    -- Attack (slider24)
                                    local ok_atk, attack_ms = pcall(function() return expanded_modulator:get_param_normalized(23) end)
                                    if ok_atk then
                                        local atk_val = attack_ms * 1999 + 1  -- 1-2000ms
                                        ctx:set_next_item_width(control_width)
                                        local changed, new_atk_val = ctx:slider_double("Attack##atk_" .. guid, atk_val, 1, 2000, "%.0f ms")
                                        if changed then
                                            expanded_modulator:set_param_normalized(23, (new_atk_val - 1) / 1999)
                                            interacted = true
                                        end
                                    end

                                    -- Release (slider25)
                                    local ok_rel, release_ms = pcall(function() return expanded_modulator:get_param_normalized(24) end)
                                    if ok_rel then
                                        local rel_val = release_ms * 4999 + 1  -- 1-5000ms
                                        ctx:set_next_item_width(control_width)
                                        local changed, new_rel_val = ctx:slider_double("Release##rel_" .. guid, rel_val, 1, 5000, "%.0f ms")
                                        if changed then
                                            expanded_modulator:set_param_normalized(24, (new_rel_val - 1) / 4999)
                                            interacted = true
                                        end
                                    end
                                end

                                ctx:tree_pop()
                            else
                                state.modulator_advanced[advanced_key] = false
                            end

                            ctx:spacing()
                            ctx:separator()
                            ctx:spacing()

                            -- Parameter Links section
                            ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                            ctx:text("PARAMETER LINKS")
                            ctx:pop_style_color()
                            ctx:spacing()

                            -- Get modulator GUID for tracking links
                            local mod_guid = expanded_modulator:get_guid()

                            -- Find existing links for this modulator
                            local existing_links = {}
                            local mod_fx_idx = expanded_modulator.pointer
                            if container and container:is_container() then
                                for child in container:iter_container_children() do
                                    local ok_check, is_mod = pcall(function() return fx_utils.is_modulator_fx(child) end)
                                    if not (ok_check and is_mod) then
                                        -- Check each parameter of this device
                                        local ok_params, param_count = pcall(function() return child:get_num_params() end)
                                        if ok_params and param_count then
                                            for param_idx = 0, param_count - 1 do
                                                -- Query if this param is linked to our modulator
                                                local ok_query, link_fx_str = pcall(function()
                                                    local plink_str = string.format("param.%d.plink.active", param_idx)
                                                    return child:get_named_config_param(plink_str)
                                                end)
                                                if ok_query and link_fx_str then
                                                    local link_fx_idx = tonumber(link_fx_str)
                                                    if link_fx_idx == mod_fx_idx then
                                                        -- This parameter is linked to our modulator
                                                        local ok_pname, param_name = pcall(function() return child:get_param_name(param_idx) end)
                                                        local ok_fname, fx_name = pcall(function() return child:get_name() end)
                                                        if ok_pname and ok_fname then
                                                            table.insert(existing_links, {
                                                                fx = child,
                                                                fx_name = fx_name,
                                                                param_idx = param_idx,
                                                                param_name = param_name
                                                            })
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end

                            -- Show existing links
                            if #existing_links > 0 then
                                ctx:push_style_color(imgui.Col.Text(), 0x88FF88FF)
                                ctx:text(string.format("Active Links: %d", #existing_links))
                                ctx:pop_style_color()
                                ctx:spacing()

                                for i, link in ipairs(existing_links) do
                                    local link_label = string.format("%s → %s", link.fx_name, link.param_name)
                                    ctx:text("• " .. link_label)
                                    ctx:same_line()
                                    if ctx:button("X##remove_link_" .. i .. "_" .. guid, 20, 0) then
                                        -- Remove this link
                                        local ok_remove = pcall(function()
                                            local plink_str = string.format("param.%d.plink.active", link.param_idx)
                                            link.fx:set_named_config_param(plink_str, "-1")  -- -1 disables the link
                                        end)
                                        if ok_remove then
                                            interacted = true
                                        end
                                    end
                                    if ctx:is_item_hovered() then
                                        ctx:set_tooltip("Remove link")
                                    end
                                end

                                ctx:spacing()
                                ctx:separator()
                                ctx:spacing()
                            end

                            -- Link selection state (device + parameter)
                            local link_state_key = "mod_link_" .. guid .. "_" .. expanded_slot_idx
                            state.mod_selected_target[link_state_key] = state.mod_selected_target[link_state_key] or {}
                            local link_state = state.mod_selected_target[link_state_key]

                            -- Get all devices in this container (excluding modulators)
                            local target_devices = {}
                            if container and container:is_container() then
                                for child in container:iter_container_children() do
                                    local ok_check, is_mod = pcall(function() return fx_utils.is_modulator_fx(child) end)
                                    if not (ok_check and is_mod) then
                                        local ok_name, child_name = pcall(function() return child:get_name() end)
                                        if ok_name and child_name then
                                            table.insert(target_devices, {fx = child, name = child_name})
                                        end
                                    end
                                end
                            end

                            -- Device selector
                            if #target_devices > 0 then
                                local current_device_name = link_state.device_name or "Select Device..."
                                ctx:set_next_item_width(control_width)
                                if ctx:begin_combo("##link_device_" .. guid, current_device_name) then
                                    for i, dev_info in ipairs(target_devices) do
                                        if ctx:selectable(dev_info.name, link_state.device_name == dev_info.name) then
                                            link_state.device_fx = dev_info.fx
                                            link_state.device_name = dev_info.name
                                            link_state.param_idx = nil  -- Reset parameter selection
                                            link_state.param_name = nil
                                            interacted = true
                                        end
                                    end
                                    ctx:end_combo()
                                end

                                -- Parameter selector (if device selected)
                                if link_state.device_fx then
                                    local ok_params, param_count = pcall(function() return link_state.device_fx:get_num_params() end)
                                    if ok_params and param_count and param_count > 0 then
                                        local current_param_name = link_state.param_name or "Select Parameter..."
                                        ctx:set_next_item_width(control_width)
                                        if ctx:begin_combo("##link_param_" .. guid, current_param_name) then
                                            for param_idx = 0, param_count - 1 do
                                                local ok_pname, param_name = pcall(function() return link_state.device_fx:get_param_name(param_idx) end)
                                                if ok_pname and param_name then
                                                    if ctx:selectable(param_name, link_state.param_idx == param_idx) then
                                                        link_state.param_idx = param_idx
                                                        link_state.param_name = param_name
                                                        interacted = true
                                                    end
                                                end
                                            end
                                            ctx:end_combo()
                                        end

                                        -- Add Link button
                                        if link_state.param_idx ~= nil then
                                            if ctx:button("Add Link##" .. guid, control_width, 0) then
                                                -- Create modulation link using REAPER's param.X.plink API
                                                local target_fx = link_state.device_fx
                                                local target_param = link_state.param_idx

                                                -- Get FX indices for both modulator and target
                                                local track = opts.track or state.track
                                                if track then
                                                    local ok_link = pcall(function()
                                                        -- Use REAPER's parameter modulation API
                                                        -- Format: param.X.plink.active=Y where X is target param, Y is modulator FX
                                                        local mod_fx_idx = expanded_modulator.pointer
                                                        local target_fx_idx = target_fx.pointer

                                                        -- Enable parameter link from modulator output (slider4=param 3) to target parameter
                                                        local plink_str = string.format("param.%d.plink.active", target_param)
                                                        target_fx:set_named_config_param(plink_str, tostring(mod_fx_idx))

                                                        -- Set modulator link params
                                                        local plink_param_str = string.format("param.%d.plink.param", target_param)
                                                        target_fx:set_named_config_param(plink_param_str, "3")  -- slider4 (Output) is param index 3

                                                        -- Set modulation amount to 100%
                                                        local plink_scale_str = string.format("param.%d.plink.scale", target_param)
                                                        target_fx:set_named_config_param(plink_scale_str, "1.0")
                                                    end)

                                                    if ok_link then
                                                        -- Clear selection after adding link
                                                        link_state.device_fx = nil
                                                        link_state.device_name = nil
                                                        link_state.param_idx = nil
                                                        link_state.param_name = nil
                                                        interacted = true
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            else
                                ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                                ctx:text("No devices in container")
                                ctx:pop_style_color()
                            end
                        end
                    end
                end
            end

            -- === MAIN CONTENT ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)

        -- Header row using table for proper alignment
        if is_panel_collapsed then
            -- Collapsed header: collapse button | path
            if r.ImGui_BeginTable(ctx.ctx, "header_collapsed_" .. guid, 2, 0) then
                r.ImGui_TableSetupColumn(ctx.ctx, "collapse", r.ImGui_TableColumnFlags_WidthFixed(), 24)
                r.ImGui_TableSetupColumn(ctx.ctx, "path", r.ImGui_TableColumnFlags_WidthStretch())

                r.ImGui_TableNextRow(ctx.ctx)

                -- Collapse button
                r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
                ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
                ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
                if ctx:button("▶##collapse_" .. state_guid, 20, 20) then
                    panel_collapsed[state_guid] = false
                    interacted = true
                end
                ctx:pop_style_color(3)
                if r.ImGui_IsItemHovered(ctx.ctx) then
                    ctx:set_tooltip("Expand panel")
                end

                -- Path identifier
                r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
                if device_id then
                    ctx:push_style_color(r.ImGui_Col_Text(), 0x888888FF)
                    ctx:text("[" .. device_id .. "]")
                    ctx:pop_style_color()
                end

                r.ImGui_EndTable(ctx.ctx)
            end
        else
            -- Expanded header: drag | name (50%) | path (15%) | ui | on | x | collapse (buttons fixed width)
            local imgui = require('imgui')
            local table_flags = imgui.TableFlags.SizingStretchProp()
            if ctx:begin_table("header_" .. guid, 7, table_flags) then
                ctx:table_setup_column("drag", imgui.TableColumnFlags.WidthFixed(), 24)
                ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch(), 50)  -- 50%
                ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 15)  -- 15%
                ctx:table_setup_column("ui", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed
                ctx:table_setup_column("on", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed
                ctx:table_setup_column("x", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed
                ctx:table_setup_column("collapse", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed

                ctx:table_next_row()

            -- Drag handle / collapse toggle
            ctx:table_set_column_index(0)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
            ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
            local collapse_icon = is_panel_collapsed and "▶" or "≡"
            if ctx:button(collapse_icon .. "##drag", 20, 20) then
                -- Toggle panel collapse on click
                panel_collapsed[state_guid] = not is_panel_collapsed
                interacted = true
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(is_panel_collapsed and "Expand panel" or "Collapse panel (drag to reorder)")
            end

            if ctx:begin_drag_drop_source() then
                ctx:set_drag_drop_payload("FX_GUID", drag_guid)
                ctx:text("Moving: " .. truncate(name, 20))
                ctx:end_drag_drop_source()
            end

            if ctx:begin_drag_drop_target() then
                -- Accept FX reorder drops
                local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
                if accepted and payload and payload ~= drag_guid then
                    if opts.on_drop then
                        opts.on_drop(payload, drag_guid)
                    end
                    interacted = true
                end

                -- Accept plugin drops (insert before this FX/container)
                local accepted_plugin, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                if accepted_plugin and plugin_name then
                    if opts.on_plugin_drop then
                        opts.on_plugin_drop(plugin_name, fx.pointer)
                    end
                    interacted = true
                end

                -- Accept rack drops (insert before this FX/container)
                local accepted_rack = ctx:accept_drag_drop_payload("RACK_ADD")
                if accepted_rack then
                    if opts.on_rack_drop then
                        opts.on_rack_drop(fx.pointer)
                    end
                    interacted = true
                end

                ctx:end_drag_drop_target()
            end

            -- Device name (double-click to rename)
            ctx:table_set_column_index(1)

            -- Check if this device/container is being renamed (use SideFX state system)
            -- Use FX GUID for renaming since we display the FX name, not the container name
            local state_module = require('lib.state')
            local sidefx_state = state_module.state
            local rename_guid = guid  -- Use FX GUID for renaming
            local is_renaming = (sidefx_state.renaming_fx == rename_guid)

            if is_renaming then
                -- Rename mode: show input text (just the name)
                ctx:set_next_item_width(-1)

                -- Initialize rename text if needed (use just the name, not the identifier)
                if not sidefx_state.rename_text or sidefx_state.rename_text == "" then
                    sidefx_state.rename_text = name  -- Just the name, no identifier
                    r.ImGui_SetKeyboardFocusHere(ctx.ctx)
                end

                local changed, new_text = r.ImGui_InputText(ctx.ctx, "##rename_" .. state_guid, sidefx_state.rename_text, r.ImGui_InputTextFlags_EnterReturnsTrue())
                sidefx_state.rename_text = new_text

                -- Commit on Enter
                if changed then
                    if sidefx_state.rename_text ~= "" then
                        -- Store custom display name in state (SideFX-only, doesn't change REAPER name)
                        sidefx_state.display_names[rename_guid] = sidefx_state.rename_text
                    else
                        -- Clear custom name if empty
                        sidefx_state.display_names[rename_guid] = nil
                    end
                    state_module.save_display_names()
                    sidefx_state.renaming_fx = nil
                    sidefx_state.rename_text = ""
                    interacted = true
                end

                -- Cancel on Escape or click elsewhere
                if r.ImGui_IsKeyPressed(ctx.ctx, r.ImGui_Key_Escape()) then
                    sidefx_state.renaming_fx = nil
                    sidefx_state.rename_text = ""
                elseif not r.ImGui_IsItemActive(ctx.ctx) and not r.ImGui_IsItemFocused(ctx.ctx) and r.ImGui_IsMouseClicked(ctx.ctx, 0) then
                    -- Lost focus - commit if text changed
                    if sidefx_state.rename_text ~= "" then
                        sidefx_state.display_names[rename_guid] = sidefx_state.rename_text
                    else
                        sidefx_state.display_names[rename_guid] = nil
                    end
                    state_module.save_display_names()
                    sidefx_state.renaming_fx = nil
                    sidefx_state.rename_text = ""
                end
            else
                -- Normal mode: show text, double-click to rename
                local display_name = truncate(name, 50)  -- Reasonable max length
                if not enabled then
                    ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                end

                -- Selectable for double-click detection (name only) - use 0 width to fill column
                if r.ImGui_Selectable(ctx.ctx, display_name .. "##name_" .. state_guid, false, r.ImGui_SelectableFlags_AllowDoubleClick(), 0, 0) then
                    if r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
                        sidefx_state.renaming_fx = rename_guid
                        sidefx_state.rename_text = name  -- Just the name, no identifier
                        interacted = true
                    end
                end
                if r.ImGui_IsItemHovered(ctx.ctx) then
                    ctx:set_tooltip("Double-click to rename")
                end

                if not enabled then
                    ctx:pop_style_color()
                end
            end

            -- Path identifier (15%)
            ctx:table_set_column_index(2)
            if device_id then
                ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                ctx:text("[" .. device_id .. "]")
                ctx:pop_style_color()
            end

            -- UI button
            ctx:table_set_column_index(3)
            local ui_col_w = ctx:get_content_region_avail()
            if ui_col_w > 0 then
                if draw_ui_icon(ctx, "##ui_header_" .. state_guid, math.min(24, ui_col_w), 20) then
                    fx:show(3)
                    interacted = true
                end
                if r.ImGui_IsItemHovered(ctx.ctx) then
                    ctx:set_tooltip("Open native FX window")
                end
            end

            -- ON/OFF toggle
            ctx:table_set_column_index(4)
            local on_col_w = ctx:get_content_region_avail()
            if on_col_w > 0 then
                if draw_on_off_circle(ctx, "##on_off_header_" .. state_guid, enabled, math.min(24, on_col_w), 20, colors.bypass_on, colors.bypass_off) then
                    fx:set_enabled(not enabled)
                    interacted = true
                end
            end

            -- Close button
            ctx:table_set_column_index(5)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x664444FF)
            if ctx:button("×", 24, 20) then
                if opts.on_delete then
                    opts.on_delete(fx)
                else
                    fx:delete()
                end
                interacted = true
            end
            ctx:pop_style_color()

            -- Sidebar collapse/expand button (rightmost) - only show when panel is expanded
            ctx:table_set_column_index(6)
            if not is_panel_collapsed then
                ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
                if is_sidebar_collapsed then
                    if ctx:button("▶##sidebar_" .. state_guid, 24, 20) then
                        sidebar_collapsed[state_guid] = false
                    end
                    if r.ImGui_IsItemHovered(ctx.ctx) then
                        ctx:set_tooltip("Expand sidebar")
                    end
                else
                    if ctx:button("◀##sidebar_" .. state_guid, 24, 20) then
                        sidebar_collapsed[state_guid] = true
                    end
                    if r.ImGui_IsItemHovered(ctx.ctx) then
                        ctx:set_tooltip("Collapse sidebar")
                    end
                end
                ctx:pop_style_color(2)
            end

            ctx:end_table()
            end  -- end expanded header
        end  -- end if is_panel_collapsed check for header

        -- Render collapsed panel content
        if is_panel_collapsed then
            ctx:separator()

            -- Collapsed view table layout
            -- Row 1: ui | on | x
            -- Row 2: name
            if r.ImGui_BeginTable(ctx.ctx, "controls_" .. guid, 3, r.ImGui_TableFlags_SizingStretchSame()) then
                r.ImGui_TableSetupColumn(ctx.ctx, "ui", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx.ctx, "on", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableSetupColumn(ctx.ctx, "x", r.ImGui_TableColumnFlags_WidthStretch())

                r.ImGui_TableNextRow(ctx.ctx)

                -- UI button
                r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
                -- Draw custom UI icon (border is drawn inside the function)
                local ui_avail_w = ctx:get_content_region_avail()
                if ui_avail_w > 0 and draw_ui_icon(ctx, "##ui_" .. state_guid, ui_avail_w, 24) then
                    fx:show(3)
                    interacted = true
                end
                if r.ImGui_IsItemHovered(ctx.ctx) then
                    ctx:set_tooltip("Open " .. name)
                end

                -- ON/OFF toggle
                r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
                -- Draw custom circle indicator with colored background
                local avail_w, avail_h = ctx:get_content_region_avail()
                if avail_w > 0 and draw_on_off_circle(ctx, "##on_off_" .. state_guid, enabled, avail_w, 24, colors.bypass_on, colors.bypass_off) then
                    fx:set_enabled(not enabled)
                    interacted = true
                end

                -- Close button
                r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
                ctx:push_style_color(r.ImGui_Col_Button(), 0x663333FF)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x444444FF)
                if ctx:button("×", -1, 24) then
                    if opts.on_delete then
                        opts.on_delete(fx)
                    else
                        fx:delete()
                    end
                    interacted = true
                end
                ctx:pop_style_color(2)

                r.ImGui_EndTable(ctx.ctx)
            end

            -- Row 2: name
            ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAAAAFF)
            ctx:text(name)
            ctx:pop_style_color()

            ctx:end_child()  -- end panel
            ctx:pop_id()
            return interacted
        end

        ctx:separator()

        -- Main content area: use a table for params (left) + sidebar (right)
        local content_h = panel_height - cfg.header_height - 10
        local sidebar_actual_w = is_sidebar_collapsed and 8 or cfg.sidebar_width
        local btn_h = 22

        if r.ImGui_BeginTable(ctx.ctx, "device_layout_" .. guid, 2, r.ImGui_TableFlags_BordersInnerV()) then
            r.ImGui_TableSetupColumn(ctx.ctx, "params", r.ImGui_TableColumnFlags_WidthFixed(), content_width)
            r.ImGui_TableSetupColumn(ctx.ctx, "sidebar", r.ImGui_TableColumnFlags_WidthStretch())  -- Stretch to fill remaining space

            r.ImGui_TableNextRow(ctx.ctx)

            -- === PARAMS COLUMN ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)

            if visible_count > 0 then
                -- Use nested table for parameter columns
                if r.ImGui_BeginTable(ctx.ctx, "params_" .. guid, num_columns, r.ImGui_TableFlags_SizingStretchSame()) then

                    for col = 0, num_columns - 1 do
                        r.ImGui_TableSetupColumn(ctx.ctx, "col" .. col, r.ImGui_TableColumnFlags_WidthStretch())
                    end

                    -- Draw parameters row by row across columns (using pre-filtered visible_params)
                    for row = 0, params_per_column - 1 do
                        r.ImGui_TableNextRow(ctx.ctx)

                        for col = 0, num_columns - 1 do
                            local visible_idx = col * params_per_column + row + 1  -- +1 for Lua 1-based

                            r.ImGui_TableSetColumnIndex(ctx.ctx, col)

                            if visible_idx <= visible_count then
                                local param_idx = visible_params[visible_idx]

                                -- Safely get param info (FX might have been deleted)
                                local ok_name, param_name = pcall(function() return fx:get_param_name(param_idx) end)
                                local ok_val, param_val = pcall(function() return fx:get_param_normalized(param_idx) end)

                                if ok_name and ok_val then
                                    param_val = param_val or 0
                                    local display_label = (param_name and param_name ~= "") and truncate(param_name, 14) or ("P" .. (param_idx + 1))

                                    ctx:push_id(param_idx)

                                    -- Parameter label
                                    ctx:push_style_color(r.ImGui_Col_Text(), colors.param_label)
                                    ctx:text(display_label)
                                    ctx:pop_style_color()

                                    -- Smart detection: switch vs continuous
                                    local is_switch = is_switch_param(fx, param_idx)

                                    if is_switch then
                                        -- Draw as toggle button
                                        local is_on = param_val > 0.5
                                        if is_on then
                                            ctx:push_style_color(r.ImGui_Col_Button(), 0x5588AAFF)
                                        else
                                            ctx:push_style_color(r.ImGui_Col_Button(), 0x333333FF)
                                        end
                                        if ctx:button(is_on and "ON" or "OFF", -cfg.padding, 0) then
                                            pcall(function() fx:set_param_normalized(param_idx, is_on and 0 or 1) end)
                                            interacted = true
                                        end
                                        ctx:pop_style_color()
                                    else
                                        -- Draw as slider
                                        ctx:set_next_item_width(-cfg.padding)
                                        local changed, new_val = ctx:slider_double("##p", param_val, 0, 1, "%.2f")
                                        if changed then
                                            pcall(function() fx:set_param_normalized(param_idx, new_val) end)
                                            interacted = true
                                        end
                                    end

                                    ctx:pop_id()
                                end
                            end
                        end
                    end

                    r.ImGui_EndTable(ctx.ctx)
                end
            else
                ctx:text_disabled("No parameters")
            end

            -- === SIDEBAR COLUMN ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)

            -- Get column starting X position for centering calculations
            local col_start_x = r.ImGui_GetCursorPosX(ctx.ctx)
            local sidebar_w = sidebar_actual_w

            -- Helper to center an item of given width within sidebar
            local function center_item(item_w)
                local offset = (sidebar_w - item_w) / 2
                if offset > 0 then
                    r.ImGui_SetCursorPosX(ctx.ctx, col_start_x + offset)
                end
            end

            if is_sidebar_collapsed then
                -- Collapsed: just empty space (expand button is in header)
                -- Nothing to render
            else
                -- Expanded sidebar
                local ctrl_w = cfg.sidebar_width - cfg.padding * 2  -- Full width controls
                local btn_w = 70  -- Narrower buttons (for pan slider)

                -- Mix and Delta on the same line using a table with bottom border
                local container = opts.container
                local has_mix = false
                local mix_val, mix_idx
                if container then
                    local ok_mix
                    ok_mix, mix_idx = pcall(function() return container:get_param_from_ident(":wet") end)
                    if ok_mix and mix_idx and mix_idx >= 0 then
                        local ok_mv
                        ok_mv, mix_val = pcall(function() return container:get_param_normalized(mix_idx) end)
                        has_mix = ok_mv and mix_val
                    end
                end

                local has_delta = false
                local delta_val, delta_idx
                local ok_delta
                ok_delta, delta_idx = pcall(function() return fx:get_param_from_ident(":delta") end)
                if ok_delta and delta_idx and delta_idx >= 0 then
                    local ok_dv
                    ok_dv, delta_val = pcall(function() return fx:get_param_normalized(delta_idx) end)
                    has_delta = ok_dv and delta_val
                end

                -- Only show table if we have mix or delta
                if has_mix or has_delta then
                    local imgui = require('imgui')
                    local table_flags = imgui.TableFlags.BordersH()
                    if ctx:begin_table("mix_delta_" .. state_guid, 2, table_flags) then
                        ctx:table_setup_column("mix", imgui.TableColumnFlags.WidthStretch())
                        ctx:table_setup_column("delta", imgui.TableColumnFlags.WidthStretch())

                        ctx:table_next_row()

                        -- Mix column
                        ctx:table_set_column_index(0)
                        if has_mix then
                            -- "Mix" label (centered)
                            local mix_text = "Mix"
                            local mix_text_w = r.ImGui_CalcTextSize(ctx.ctx, mix_text)
                            local col_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - mix_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xCC88FFFF)  -- Purple for container
                            ctx:text(mix_text)
                            ctx:pop_style_color()

                            -- Smaller knob (30px)
                            local mix_knob_size = 30
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - mix_knob_size) / 2)
                            local mix_changed, new_mix = draw_knob(ctx, "##mix_knob", mix_val, mix_knob_size)
                            if mix_changed then
                                pcall(function() container:set_param_normalized(mix_idx, new_mix) end)
                                interacted = true
                            end

                            -- Value below knob (centered)
                            local mix_val_text = string.format("%.0f%%", mix_val * 100)
                            local mix_val_text_w = r.ImGui_CalcTextSize(ctx.ctx, mix_val_text)
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - mix_val_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAAAAFF)
                            ctx:text(mix_val_text)
                            ctx:pop_style_color()

                            if r.ImGui_IsItemHovered(ctx.ctx) then
                                ctx:set_tooltip(string.format("Device Mix: %.0f%% (parallel blend)", mix_val * 100))
                            end
                        end

                        -- Delta column
                        ctx:table_set_column_index(1)
                        if has_delta then
                            -- "Delta" label (centered horizontally)
                            local delta_text = "Delta"
                            local delta_text_w = r.ImGui_CalcTextSize(ctx.ctx, delta_text)
                            local col_start_x = r.ImGui_GetCursorPosX(ctx.ctx)
                            local col_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, col_start_x + (col_w - delta_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAACCFF)
                            ctx:text(delta_text)
                            ctx:pop_style_color()

                            -- Center button vertically with mix knob
                            -- Mix column: label (~20px) + spacing (~5px) + knob (30px) + spacing (~5px) + value (~20px) = ~80px total
                            -- Knob center is at: label (20px) + spacing (5px) + knob_radius (15px) = ~40px from top
                            -- Delta column: label (~20px) + button (18px) = ~38px minimum
                            -- To center button with knob: button center should be at ~40px
                            -- Button center is 9px from button top, so button top should be at 40 - 9 = 31px
                            -- After label (~20px), we need 31 - 20 = 11px spacing
                            ctx:spacing()  -- Small spacing after label
                            r.ImGui_Dummy(ctx.ctx, 0, 6)  -- Additional spacing to align with knob center

                            local delta_on = delta_val > 0.5
                            if delta_on then
                                ctx:push_style_color(r.ImGui_Col_Button(), 0x6666CCFF)
                            else
                                ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                            end

                            -- Delta button (centered horizontally)
                            local delta_btn_w = 36
                            local delta_btn_h = 18
                            local col_w_btn = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, col_start_x + (col_w_btn - delta_btn_w) / 2)
                            if ctx:button(delta_on and "∆" or "—", delta_btn_w, delta_btn_h) then
                                pcall(function() fx:set_param_normalized(delta_idx, delta_on and 0 or 1) end)
                                interacted = true
                            end
                            ctx:pop_style_color()

                            if r.ImGui_IsItemHovered(ctx.ctx) then
                                ctx:set_tooltip(delta_on and "Delta Solo: ON (wet - dry)" or "Delta Solo: OFF")
                            end
                        end

                        ctx:end_table()
                    end
                end

                -- Gain control as FADER (from paired utility)
                local utility = opts.utility
                if utility then
                    local ok_g, gain_val = pcall(function() return utility:get_param_normalized(0) end)
                    local ok_p, pan_val = pcall(function() return utility:get_param_normalized(1) end)

                    -- Pan slider first (above fader)
                    if ok_p then
                        pan_val = pan_val or 0.5
                        local pan_pct = (pan_val - 0.5) * 200

                        ctx:spacing()

                        -- Use collapsed rack pan slider (with label underneath)
                        local avail_w, _ = ctx:get_content_region_avail()
                        local pan_w = math.min(avail_w - 4, 80)
                        local pan_offset = math.max(0, (avail_w - pan_w) / 2)
                        ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + pan_offset)
                        local pan_changed, new_pan = widgets.draw_pan_slider(ctx, "##utility_pan", pan_pct, pan_w)
                        if pan_changed then
                            local new_norm = (new_pan + 100) / 200
                            pcall(function() utility:set_param_normalized(1, new_norm) end)
                            interacted = true
                        end
                    end

                    if ok_g then
                        gain_val = gain_val or 0.5
                        local gain_norm = gain_val
                        local gain_db = (gain_val - 0.5) * 48

                        ctx:spacing()

                        -- Fader with meter and scale (same as collapsed rack)
                        local fader_w = 32
                        local meter_w = 12
                        local scale_w = 20

                        -- Calculate fader height (accounting for pan slider above)
                        local _, remaining_h = ctx:get_content_region_avail()
                        local fader_h = remaining_h - 22  -- Leave room for dB label
                        fader_h = math.max(50, fader_h)  -- Minimum 50px, but can extend

                        local avail_w, _ = ctx:get_content_region_avail()
                        local total_w = scale_w + fader_w + meter_w + 4
                        local offset_x = math.max(0, (avail_w - total_w) / 2)

                        ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + offset_x)

                        local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                        local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

                        local scale_x = screen_x
                        local fader_x = screen_x + scale_w + 2
                        local meter_x = fader_x + fader_w + 2

                        -- dB scale
                        local db_marks = {24, 12, 0, -12, -24}
                        for _, db in ipairs(db_marks) do
                            local mark_norm = (db + 24) / 48
                            local mark_y = screen_y + fader_h - (fader_h * mark_norm)
                            r.ImGui_DrawList_AddLine(draw_list, scale_x + scale_w - 6, mark_y, scale_x + scale_w, mark_y, 0x666666FF, 1)
                            if db == 0 or db == -12 or db == 12 or db == 24 then
                                local label = db == 0 and "0" or tostring(db)
                                r.ImGui_DrawList_AddText(draw_list, scale_x, mark_y - 5, 0x888888FF, label)
                            end
                        end

                        -- Fader background
                        r.ImGui_DrawList_AddRectFilled(draw_list, fader_x, screen_y, fader_x + fader_w, screen_y + fader_h, 0x1A1A1AFF, 3)
                        -- Fader fill
                        local fill_h = fader_h * gain_norm
                        if fill_h > 2 then
                            local fill_top = screen_y + fader_h - fill_h
                            r.ImGui_DrawList_AddRectFilled(draw_list, fader_x + 2, fill_top, fader_x + fader_w - 2, screen_y + fader_h - 2, 0x5588AACC, 2)
                        end
                        -- Fader border
                        r.ImGui_DrawList_AddRect(draw_list, fader_x, screen_y, fader_x + fader_w, screen_y + fader_h, 0x555555FF, 3)
                        -- 0dB line (at center since range is -24 to +24)
                        local zero_db_norm = 24 / 48
                        local zero_y = screen_y + fader_h - (fader_h * zero_db_norm)
                        r.ImGui_DrawList_AddLine(draw_list, fader_x, zero_y, fader_x + fader_w, zero_y, 0xFFFFFF44, 1)

                        -- Stereo meters
                        local meter_l_x = meter_x
                        local meter_r_x = meter_x + meter_w / 2 + 1
                        local half_meter_w = meter_w / 2 - 1
                        r.ImGui_DrawList_AddRectFilled(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)
                        r.ImGui_DrawList_AddRectFilled(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)

                        -- Get track for meters (if available)
                        local state_module = require('lib.state')
                        local sidefx_state = state_module.state
                        if sidefx_state.track and sidefx_state.track.pointer then
                            local peak_l = r.Track_GetPeakInfo(sidefx_state.track.pointer, 0)
                            local peak_r = r.Track_GetPeakInfo(sidefx_state.track.pointer, 1)
                            local function draw_meter_bar(x, w, peak)
                                if peak > 0 then
                                    local peak_db = 20 * math.log(peak, 10)
                                    peak_db = math.max(-60, math.min(24, peak_db))
                                    local peak_norm = (peak_db + 60) / 84
                                    local meter_fill_h = fader_h * peak_norm
                                    if meter_fill_h > 1 then
                                        local meter_top = screen_y + fader_h - meter_fill_h
                                        local meter_color
                                        if peak_db > 0 then meter_color = 0xFF4444FF
                                        elseif peak_db > -6 then meter_color = 0xFFAA44FF
                                        elseif peak_db > -18 then meter_color = 0x44FF44FF
                                        else meter_color = 0x44AA44FF end
                                        r.ImGui_DrawList_AddRectFilled(draw_list, x, meter_top, x + w, screen_y + fader_h - 1, meter_color, 0)
                                    end
                                end
                            end
                            draw_meter_bar(meter_l_x + 1, half_meter_w - 1, peak_l)
                            draw_meter_bar(meter_r_x + 1, half_meter_w - 1, peak_r)
                        end

                        r.ImGui_DrawList_AddRect(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)
                        r.ImGui_DrawList_AddRect(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)

                        -- Invisible slider for fader interaction
                        r.ImGui_SetCursorScreenPos(ctx.ctx, fader_x, screen_y)
                        local imgui = require('imgui')
                        ctx:push_style_color(imgui.Col.FrameBg(), 0x00000000)
                        ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x00000000)
                        ctx:push_style_color(imgui.Col.FrameBgActive(), 0x00000000)
                        ctx:push_style_color(imgui.Col.SliderGrab(), 0xAAAAAAFF)
                        ctx:push_style_color(imgui.Col.SliderGrabActive(), 0xFFFFFFFF)
                        local gain_changed, new_gain_db = ctx:v_slider_double("##gain_fader_v", fader_w, fader_h, gain_db, -24, 24, "")
                        if gain_changed then
                            local new_norm = (new_gain_db + 24) / 48
                            pcall(function() utility:set_param_normalized(0, new_norm) end)
                            interacted = true
                        end
                        if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                            pcall(function() utility:set_param_normalized(0, 0.5) end)  -- Reset to 0dB
                            interacted = true
                        end
                        ctx:pop_style_color(5)

                        -- dB label below fader (with double-click editing)
                        local label_h = 16
                        local label_y = screen_y + fader_h + 2
                        local label_x = fader_x
                        r.ImGui_DrawList_AddRectFilled(draw_list, label_x, label_y, label_x + fader_w, label_y + label_h, 0x222222FF, 2)
                        local db_label = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.0f", gain_db) or string.format("%.0f", gain_db))
                        local text_w = r.ImGui_CalcTextSize(ctx.ctx, db_label)
                        r.ImGui_DrawList_AddText(draw_list, label_x + (fader_w - text_w) / 2, label_y + 1, 0xCCCCCCFF, db_label)

                        -- Invisible button for dB label (for double-click editing)
                        r.ImGui_SetCursorScreenPos(ctx.ctx, label_x, label_y)
                        ctx:invisible_button("##gain_db_label", fader_w, label_h)

                        -- Double-click on dB label to edit value
                        if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                            ctx:open_popup("##gain_edit_popup")
                        end

                        -- Edit popup for gain
                        if ctx:begin_popup("##gain_edit_popup") then
                            local imgui = require('imgui')
                            ctx:set_next_item_width(60)
                            ctx:set_keyboard_focus_here()
                            local input_changed, input_val = ctx:input_double("##gain_input", gain_db, 0, 0, "%.1f")
                            if input_changed then
                                local new_norm = (math.max(-24, math.min(24, input_val)) + 24) / 48
                                pcall(function() utility:set_param_normalized(0, new_norm) end)
                                interacted = true
                            end
                            if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
                                ctx:close_current_popup()
                            end
                            ctx:end_popup()
                        end

                        -- Advance cursor past fader
                        r.ImGui_SetCursorScreenPos(ctx.ctx, screen_x, label_y + label_h)
                    end

                    -- Phase Invert controls
                    local ok_phase_l, phase_l = pcall(function() return utility:get_param_normalized(2) end)
                    local ok_phase_r, phase_r = pcall(function() return utility:get_param_normalized(3) end)

                    if ok_phase_l and ok_phase_r then
                        ctx:spacing()

                        -- Center "Phase" label
                        local phase_text = "Phase"
                        local phase_text_w = r.ImGui_CalcTextSize(ctx.ctx, phase_text)
                        center_item(phase_text_w)
                        ctx:push_style_color(r.ImGui_Col_Text(), 0xCC8888FF)
                        ctx:text(phase_text)
                        ctx:pop_style_color()

                        local phase_btn_w = 28
                        local phase_gap = 4
                        local phase_total_w = phase_btn_w * 2 + phase_gap

                        -- Center the pair of phase buttons
                        center_item(phase_total_w)

                        -- Phase L button
                        local phase_l_on = phase_l > 0.5
                        if phase_l_on then
                            ctx:push_style_color(r.ImGui_Col_Button(), 0xCC6666FF)
                        else
                            ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                        end
                        if ctx:button(phase_l_on and "ØL" or "L", phase_btn_w, 20) then
                            pcall(function() utility:set_param_normalized(2, phase_l_on and 0 or 1) end)
                            interacted = true
                        end
                        ctx:pop_style_color()
                        if r.ImGui_IsItemHovered(ctx.ctx) then
                            ctx:set_tooltip(phase_l_on and "Left Phase: Inverted" or "Left Phase: Normal")
                        end

                        ctx:same_line(0, phase_gap)

                        -- Phase R button
                        local phase_r_on = phase_r > 0.5
                        if phase_r_on then
                            ctx:push_style_color(r.ImGui_Col_Button(), 0xCC6666FF)
                        else
                            ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                        end
                        if ctx:button(phase_r_on and "ØR" or "R", phase_btn_w, 20) then
                            pcall(function() utility:set_param_normalized(3, phase_r_on and 0 or 1) end)
                            interacted = true
                        end
                        ctx:pop_style_color()
                        if r.ImGui_IsItemHovered(ctx.ctx) then
                            ctx:set_tooltip(phase_r_on and "Right Phase: Inverted" or "Right Phase: Normal")
                        end
                    end
                end
            end  -- end expanded sidebar

            r.ImGui_EndTable(ctx.ctx)
        end  -- end device_layout table

            ctx:end_table()  -- end device_wrapper table
        end

        ctx:end_child()  -- end panel
    end

    -- Right-click context menu
    if ctx:begin_popup_context_item("device_menu_" .. guid) then
        if ctx:menu_item("Open FX Window") then
            fx:show(3)
        end
        if ctx:menu_item(enabled and "Bypass" or "Enable") then
            fx:set_enabled(not enabled)
        end
        ctx:separator()
        if ctx:menu_item("Rename...") then
            if opts.on_rename then
                opts.on_rename(fx)
            else
                -- Fallback: use SideFX state system directly
                -- Use FX GUID for renaming since we display the FX name
                local state_module = require('lib.state')
                local sidefx_state = state_module.state
                sidefx_state.renaming_fx = guid  -- Use FX GUID
                sidefx_state.rename_text = name
            end
        end
        ctx:separator()
        if ctx:menu_item("Delete") then
            if opts.on_delete then
                opts.on_delete(fx)
            else
                fx:delete()
            end
        end
        ctx:end_popup()
    end

    ctx:pop_id()

    return interacted
end

--------------------------------------------------------------------------------
-- Compact Device Panel (for chains inside racks)
--------------------------------------------------------------------------------

--- Draw a compact device panel for chain view.
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param opts table Options
-- @return boolean True if interacted
function M.draw_compact(ctx, fx, opts)
    opts = opts or {}
    local cfg = M.config

    if not fx then return false end

    local guid = fx:get_guid()
    local name = get_display_name(fx)
    local enabled = fx:get_enabled()

    local interacted = false
    local compact_width = 120
    local compact_height = 24

    ctx:push_id("compact_" .. guid)

    -- Simple button-like appearance
    local btn_color = enabled and 0x3A3A3AFF or 0x2A2A2AFF
    ctx:push_style_color(r.ImGui_Col_Button(), btn_color)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x4A4A4AFF)

    if ctx:button(truncate(name, 14), compact_width, compact_height) then
        -- Click opens FX detail or native UI
        if opts.on_click then
            opts.on_click(fx)
        else
            fx:show(3)
        end
        interacted = true
    end

    ctx:pop_style_color(2)

    -- Drag source
    if ctx:begin_drag_drop_source() then
        ctx:set_drag_drop_payload("FX_GUID", guid)
        ctx:text("Moving: " .. truncate(name, 20))
        ctx:end_drag_drop_source()
    end

    -- Drop target
    if ctx:begin_drag_drop_target() then
        local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
        if accepted and payload and payload ~= guid then
            if opts.on_drop then
                opts.on_drop(payload, guid)
            end
            interacted = true
        end
        ctx:end_drag_drop_target()
    end

    -- Tooltip with full name
    if ctx:is_item_hovered() then
        ctx:set_tooltip(name)
    end

    ctx:pop_id()

    return interacted
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

--- Reset all expanded states.
function M.reset_expanded()
    expanded_state = {}
end

--- Set expanded state for a specific FX.
-- @param guid string FX GUID
-- @param expanded boolean
function M.set_expanded(guid, expanded)
    expanded_state[guid] = expanded
end

--- Get expanded state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_expanded(guid)
    return expanded_state[guid] or false
end

--- Reset all sidebar collapsed states.
function M.reset_sidebar()
    sidebar_collapsed = {}
end

--- Set sidebar collapsed state for a specific FX.
-- @param guid string FX GUID
-- @param collapsed boolean
function M.set_sidebar_collapsed(guid, collapsed)
    sidebar_collapsed[guid] = collapsed
end

--- Get sidebar collapsed state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_sidebar_collapsed(guid)
    return sidebar_collapsed[guid] or false
end

--- Collapse all sidebars
function M.collapse_all_sidebars()
    for guid, _ in pairs(expanded_state) do
        sidebar_collapsed[guid] = true
    end
end

--- Expand all sidebars
function M.expand_all_sidebars()
    sidebar_collapsed = {}
end

--- Reset all panel collapsed states.
function M.reset_panel_collapsed()
    panel_collapsed = {}
end

--- Set panel collapsed state for a specific FX.
-- @param guid string FX GUID
-- @param collapsed boolean
function M.set_panel_collapsed(guid, collapsed)
    panel_collapsed[guid] = collapsed
end

--- Get panel collapsed state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_panel_collapsed(guid)
    return panel_collapsed[guid] or false
end

--- Collapse all panels
function M.collapse_all_panels()
    for guid, _ in pairs(expanded_state) do
        panel_collapsed[guid] = true
    end
end

--- Expand all panels
function M.expand_all_panels()
    panel_collapsed = {}
end

return M
