--- Device Panel UI Component
-- Renders a single FX as an Ableton-style device panel.
-- @module ui.device_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper

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

        -- Calculate panel width: columns + sidebar (if visible) + padding
        content_width = cfg.column_width * num_columns
        local sidebar_w = is_sidebar_collapsed and collapsed_sidebar_w or (cfg.sidebar_width + cfg.sidebar_padding)
        panel_width = content_width + sidebar_w + cfg.padding * 2
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
            if draw_ui_icon(ctx, "##ui_header_" .. state_guid, 24, 20) then
                fx:show(3)
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Open native FX window")
            end

            -- ON/OFF toggle
            ctx:table_set_column_index(4)
            if draw_on_off_circle(ctx, "##on_off_header_" .. state_guid, enabled, 24, 20, colors.bypass_on, colors.bypass_off) then
                fx:set_enabled(not enabled)
                interacted = true
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
                if draw_ui_icon(ctx, "##ui_" .. state_guid, -1, 24) then
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
                if draw_on_off_circle(ctx, "##on_off_" .. state_guid, enabled, avail_w, 24, colors.bypass_on, colors.bypass_off) then
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
            r.ImGui_TableSetupColumn(ctx.ctx, "sidebar", r.ImGui_TableColumnFlags_WidthFixed(), sidebar_actual_w)

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

                            -- Smaller knob (40px instead of 60px)
                            local mix_knob_size = 40
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
                            -- "Delta" label (centered)
                            local delta_text = "Delta"
                            local delta_text_w = r.ImGui_CalcTextSize(ctx.ctx, delta_text)
                            local col_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - delta_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAACCFF)
                            ctx:text(delta_text)
                            ctx:pop_style_color()

                            local delta_on = delta_val > 0.5
                            if delta_on then
                                ctx:push_style_color(r.ImGui_Col_Button(), 0x6666CCFF)
                            else
                                ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                            end

                            -- Delta button (centered)
                            local delta_btn_w = 36
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - delta_btn_w) / 2)
                            if ctx:button(delta_on and "∆" or "—", delta_btn_w, 18) then
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

                    if ok_g then
                        gain_val = gain_val or 0.5
                        local gain_db = (gain_val - 0.5) * 48

                        ctx:spacing()

                        -- Center "Gain" label
                        local gain_text = "Gain"
                        local gain_text_w = r.ImGui_CalcTextSize(ctx.ctx, gain_text)
                        center_item(gain_text_w)
                        ctx:push_style_color(r.ImGui_Col_Text(), 0xAACC88FF)
                        ctx:text(gain_text)
                        ctx:pop_style_color()

                        -- Center the fader
                        center_item(cfg.fader_width)
                        local gain_format = gain_db >= 0 and "+%.0f" or "%.0f"
                        local gain_changed, new_gain_db = draw_fader(ctx, "##gain_fader", gain_db, -24, 24, cfg.fader_width, cfg.fader_height, gain_format)
                        if gain_changed then
                            local new_norm = (new_gain_db + 24) / 48
                            pcall(function() utility:set_param_normalized(0, new_norm) end)
                            interacted = true
                        end
                        if r.ImGui_IsItemHovered(ctx.ctx) then
                            ctx:set_tooltip(string.format("Gain: %+.1f dB", gain_db))
                        end
                    end

                    if ok_p then
                        pan_val = pan_val or 0.5
                        local pan_pct = (pan_val - 0.5) * 200

                        ctx:spacing()

                        -- Center "Pan" label
                        local pan_text = "Pan"
                        local pan_text_w = r.ImGui_CalcTextSize(ctx.ctx, pan_text)
                        center_item(pan_text_w)
                        ctx:push_style_color(r.ImGui_Col_Text(), 0xCCAA88FF)
                        ctx:text(pan_text)
                        ctx:pop_style_color()

                        local pan_str
                        if pan_pct < -1 then
                            pan_str = string.format("%.0fL", -pan_pct)
                        elseif pan_pct > 1 then
                            pan_str = string.format("%.0fR", pan_pct)
                        else
                            pan_str = "C"
                        end

                        -- Center the pan slider (narrower)
                        center_item(btn_w)
                        ctx:set_next_item_width(btn_w)
                        local pan_changed, new_pan_pct = ctx:slider_double("##pan", pan_pct, -100, 100, pan_str)
                        if pan_changed then
                            local new_norm = (new_pan_pct / 200) + 0.5
                            pcall(function() utility:set_param_normalized(1, new_norm) end)
                            interacted = true
                        end
                        if r.ImGui_IsItemHovered(ctx.ctx) then
                            ctx:set_tooltip("Pan: " .. pan_str)
                        end
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
