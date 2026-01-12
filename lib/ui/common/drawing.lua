-- Drawing Utilities Module
-- Custom ImGui drawing functions for device UI

local M = {}
local r = reaper

--- Draw a UI icon (spanner/wrench emoji button)
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param width number Button width
-- @param height number Button height
-- @param icon_font ImGui font handle for emoji rendering (optional)
-- @return boolean True if clicked
function M.draw_ui_icon(ctx, label, width, height, icon_font)
    local imgui = require('imgui')
    local constants = require('lib.core.constants')
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
    local icon = constants.icon_text(emojimgui, constants.Icons.wrench)

    -- Push icon font if available (use 14pt for emoji icons to better match button size)
    if icon_font then
        ctx:push_font(icon_font, 14)
    end

    -- Adjust frame padding to center the emoji better
    ctx:push_style_var(imgui.StyleVar.FramePadding(), 2, 2)

    local clicked = ctx:button(icon .. label, width, height)

    ctx:pop_style_var()

    -- Pop icon font if we pushed it
    if icon_font then
        ctx:pop_font()
    end

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
function M.draw_on_off_circle(ctx, label, is_on, width, height, bg_color_on, bg_color_off)
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
    local bg_color = is_on and (bg_color_on or 0x2A5A2AFF) or (bg_color_off or 0x5A2A2AFF)
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
function M.draw_knob(ctx, label, value, size)
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
function M.draw_fader(ctx, label, value, min_val, max_val, width, height, format)
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
-- Fine Control Slider Functions (Shift key for precision)
--------------------------------------------------------------------------------

--- Check if Shift key is held
-- @param ctx ImGui context (raw or wrapper) - not used, kept for API compatibility
-- @return boolean True if Shift is held
function M.is_shift_held(ctx)
    -- Use REAPER's GetMouseState which returns modifier keys in the bitmask
    -- Bit 8 (value 8) = Shift key held
    local mouse_state = r.JS_Mouse_GetState and r.JS_Mouse_GetState(0) or 0
    if (mouse_state & 8) ~= 0 then
        return true
    end
    -- Fallback to ImGui detection
    local raw_ctx = ctx.ctx or ctx
    local left_shift = r.ImGui_IsKeyDown(raw_ctx, r.ImGui_Key_LeftShift())
    local right_shift = r.ImGui_IsKeyDown(raw_ctx, r.ImGui_Key_RightShift())
    return left_shift or right_shift
end

--- Horizontal slider with fine control and double-click reset
-- Features:
--   - Shift+drag for fine control (10% sensitivity)
--   - Double-click to reset to default value
--   - Ctrl/Cmd+click uses ImGui's built-in text input mode
-- @param ctx ImGui context wrapper
-- @param label string Slider label
-- @param value number Current value
-- @param min number Minimum value
-- @param max number Maximum value
-- @param format string Display format (optional)
-- @param fine_factor number Fine control multiplier (default 0.1)
-- @param display_mult number Multiplier for display value (e.g., 100 for percentage)
-- @param default_value number Default value for double-click reset (optional)
-- @return boolean changed, number new_value
function M.slider_double_fine(ctx, label, value, min, max, format, fine_factor, display_mult, default_value)
    fine_factor = fine_factor or 0.1
    display_mult = display_mult or 1
    local shift_held = M.is_shift_held(ctx)

    local changed = false
    local new_value = value

    -- If we have a display multiplier, scale the slider range for display
    local display_value = value * display_mult
    local display_min = min * display_mult
    local display_max = max * display_mult

    -- Use raw ImGui API with NoRoundToFormat flag for better precision
    local raw_ctx = ctx.ctx or ctx
    local flags = r.ImGui_SliderFlags_NoRoundToFormat()
    local slider_changed, new_display_value = r.ImGui_SliderDouble(raw_ctx, label, display_value, display_min, display_max, format or "%.3f", flags)

    local is_hovered = r.ImGui_IsItemHovered(raw_ctx)
    local mouse_double_clicked = r.ImGui_IsMouseDoubleClicked(raw_ctx, 0)

    -- Check for double-click to reset to default
    if is_hovered and mouse_double_clicked and default_value ~= nil then
        new_value = default_value
        changed = true
    -- Normal slider change with optional fine control
    elseif slider_changed then
        new_value = new_display_value / display_mult

        if shift_held then
            -- Apply fine control: reduce the delta
            local delta = new_value - value
            new_value = value + delta * fine_factor
        end
        -- Clamp to range
        new_value = math.max(min, math.min(max, new_value))
        changed = true
    end

    return changed, new_value
end

--- Vertical slider with fine control and double-click reset
-- Features:
--   - Shift+drag for fine control (10% sensitivity)
--   - Double-click to reset to default value
--   - Ctrl/Cmd+click uses ImGui's built-in text input mode
-- @param ctx ImGui context wrapper
-- @param label string Slider label
-- @param width number Slider width
-- @param height number Slider height
-- @param value number Current value
-- @param min number Minimum value
-- @param max number Maximum value
-- @param format string Display format (optional)
-- @param fine_factor number Fine control multiplier (default 0.1)
-- @param display_mult number Multiplier for display value (e.g., 100 for percentage)
-- @param default_value number Default value for double-click reset (optional)
-- @return boolean changed, number new_value
function M.v_slider_double_fine(ctx, label, width, height, value, min, max, format, fine_factor, display_mult, default_value)
    fine_factor = fine_factor or 0.1
    display_mult = display_mult or 1
    local shift_held = M.is_shift_held(ctx)

    local changed = false
    local new_value = value

    -- If we have a display multiplier, scale the slider range for display
    local display_value = value * display_mult
    local display_min = min * display_mult
    local display_max = max * display_mult

    -- Use raw ImGui API with NoRoundToFormat flag for better precision
    local raw_ctx = ctx.ctx or ctx
    local flags = r.ImGui_SliderFlags_NoRoundToFormat()
    local slider_changed, new_display_value = r.ImGui_VSliderDouble(raw_ctx, label, width, height, display_value, display_min, display_max, format or "%.3f", flags)

    local is_hovered = r.ImGui_IsItemHovered(raw_ctx)
    local mouse_double_clicked = r.ImGui_IsMouseDoubleClicked(raw_ctx, 0)

    -- Check for double-click to reset to default
    if is_hovered and mouse_double_clicked and default_value ~= nil then
        new_value = default_value
        changed = true
    -- Normal slider change with optional fine control
    elseif slider_changed then
        new_value = new_display_value / display_mult

        if shift_held then
            -- Apply fine control: reduce the delta
            local delta = new_value - value
            new_value = value + delta * fine_factor
        end
        -- Clamp to range
        new_value = math.max(min, math.min(max, new_value))
        changed = true
    end

    return changed, new_value
end

--------------------------------------------------------------------------------
-- Meter and Fader Drawing Functions
--------------------------------------------------------------------------------

--- Draw dB scale marks for vertical fader
-- @param ctx ImGui context
-- @param draw_list ImGui draw list
-- @param scale_x number X position of scale
-- @param screen_y number Top Y position
-- @param fader_h number Height of fader
-- @param scale_w number Width of scale
function M.draw_db_scale_marks(ctx, draw_list, scale_x, screen_y, fader_h, scale_w)
    local db_marks = {12, 6, 0, -6, -12, -18, -24}
    for _, db in ipairs(db_marks) do
        local mark_norm = (db + 24) / 36
        local mark_y = screen_y + fader_h - (fader_h * mark_norm)
        r.ImGui_DrawList_AddLine(draw_list, scale_x + scale_w - 6, mark_y, scale_x + scale_w, mark_y, 0x666666FF, 1)
        if db == 0 or db == -12 or db == 12 then
            local label = db == 0 and "0" or tostring(db)
            r.ImGui_DrawList_AddText(draw_list, scale_x, mark_y - 5, 0x888888FF, label)
        end
    end
end

--- Draw vertical fader visualization (background, fill, border, 0dB line)
-- @param ctx ImGui context
-- @param draw_list ImGui draw list
-- @param fader_x number X position
-- @param screen_y number Top Y position
-- @param fader_w number Width
-- @param fader_h number Height
-- @param gain_norm number Normalized gain (0-1)
function M.draw_fader_visualization(ctx, draw_list, fader_x, screen_y, fader_w, fader_h, gain_norm)
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
    -- 0dB line
    local zero_db_norm = 24 / 36
    local zero_y = screen_y + fader_h - (fader_h * zero_db_norm)
    r.ImGui_DrawList_AddLine(draw_list, fader_x, zero_y, fader_x + fader_w, zero_y, 0xFFFFFF44, 1)
end

--- Draw stereo meter visualization (backgrounds and borders)
-- @param ctx ImGui context
-- @param draw_list ImGui draw list
-- @param meter_x number X position
-- @param screen_y number Top Y position
-- @param meter_w number Total width (both channels)
-- @param fader_h number Height
function M.draw_stereo_meters_visualization(ctx, draw_list, meter_x, screen_y, meter_w, fader_h)
    local meter_l_x = meter_x
    local meter_r_x = meter_x + meter_w / 2 + 1
    local half_meter_w = meter_w / 2 - 1
    -- Meter backgrounds
    r.ImGui_DrawList_AddRectFilled(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)
    r.ImGui_DrawList_AddRectFilled(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)
    -- Meter borders
    r.ImGui_DrawList_AddRect(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)
    r.ImGui_DrawList_AddRect(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)
end

--- Draw peak meter bars (left and right) with color coding
-- @param ctx ImGui context
-- @param draw_list ImGui draw list
-- @param meter_l_x number Left meter X position
-- @param meter_r_x number Right meter X position
-- @param screen_y number Top Y position
-- @param fader_h number Height
-- @param half_meter_w number Width of each meter
-- @param peak_l number Left peak value (0-1)
-- @param peak_r number Right peak value (0-1)
function M.draw_peak_meters(ctx, draw_list, meter_l_x, meter_r_x, screen_y, fader_h, half_meter_w, peak_l, peak_r)
    local function draw_meter_bar(x, w, peak)
        if peak > 0 then
            local peak_db = 20 * math.log(peak, 10)
            peak_db = math.max(-60, math.min(12, peak_db))
            local peak_norm = (peak_db + 60) / 72
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

return M
