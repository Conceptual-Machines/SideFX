-- Drawing Utilities Module
-- Custom ImGui drawing functions for device UI

local M = {}
local r = reaper

-- Track when a slider is being dragged with fine control (Shift held)
-- This is used by curve_editor to avoid Shift key conflicts
M.slider_fine_active = false

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

    -- Track if this slider is actively being dragged with Shift (for curve_editor conflict avoidance)
    local is_active = r.ImGui_IsItemActive(raw_ctx)
    if is_active and shift_held then
        M.slider_fine_active = true
    elseif not is_active then
        -- Only clear when no slider is active (will be set again if another slider is active)
        M.slider_fine_active = false
    end

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

    -- Track if this slider is actively being dragged with Shift (for curve_editor conflict avoidance)
    local is_active = r.ImGui_IsItemActive(raw_ctx)
    if is_active and shift_held then
        M.slider_fine_active = true
    elseif not is_active then
        M.slider_fine_active = false
    end

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

--------------------------------------------------------------------------------
-- Oscilloscope and Spectrum Analyzer Drawing Functions
--------------------------------------------------------------------------------

--- Draw oscilloscope waveform from GMEM buffer (stereo display)
-- Based on Cockos gfxscope DSP
-- GMEM layout per slot (base = 2000 + slot * 2100):
--   [0-1023]    = left channel samples
--   [1024-2047] = right channel samples
--   [2048]      = num samples written
--   [2049]      = view_msec
--   [2050]      = view_maxdb
--   [2051]      = sample_rate
--   [2052]      = update timestamp
--   [2053]      = num_samples
-- @param ctx ImGui context wrapper
-- @param label string Unique label for the widget
-- @param width number Widget width
-- @param height number Widget height
-- @param slot number GMEM slot (0-15)
-- @return boolean True if hovered
function M.draw_oscilloscope(ctx, label, width, height, slot)
    slot = slot or 0
    local scope_slot_size = 2100
    local scope_base = 2000 + slot * scope_slot_size

    -- Read metadata from GMEM
    local num_samples = r.gmem_read(scope_base + 2048) or 0
    local view_msec = r.gmem_read(scope_base + 2049) or 100
    local view_maxdb = r.gmem_read(scope_base + 2050) or 0

    -- Use num_samples or default buffer size
    local buffer_size = num_samples > 0 and math.floor(num_samples) or 1024

    local x, y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    local grid_color = 0x333333FF
    local label_color = 0x888888FF
    local color_l = 0x80FF80FF  -- Light green for left
    local color_r = 0xFF80FFFF  -- Light magenta for right

    -- Background
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x1A1A1AFF, 4)

    -- Center line
    local center_y = y + height/2
    r.ImGui_DrawList_AddLine(draw_list, x, center_y, x + width, center_y, 0x666666FF, 1)

    -- Y-axis grid (dB levels based on view_maxdb)
    -- Draw some horizontal reference lines
    local db_marks = {0, -6, -12, -18, -24}
    if view_maxdb < 0 then
        -- Zoom range from center
        local zoom_scale = math.exp(-view_maxdb * (math.log(10)/20))
        for _, db in ipairs(db_marks) do
            local amp = math.exp(db * (math.log(10)/20))  -- dB to linear
            local offset = amp * zoom_scale * (height/2 - 4)
            if offset < height/2 - 4 then
                -- Upper and lower lines
                r.ImGui_DrawList_AddLine(draw_list, x, center_y - offset, x + width, center_y - offset, grid_color, 1)
                r.ImGui_DrawList_AddLine(draw_list, x, center_y + offset, x + width, center_y + offset, grid_color, 1)
                -- Labels
                local label_text = string.format("%ddB", db)
                r.ImGui_DrawList_AddText(draw_list, x + 2, center_y - offset - 10, label_color, label_text)
            end
        end
    else
        -- Standard amplitude grid
        local y_levels = {1, 0.5, 0, -0.5, -1}
        local y_labels = {"+1", "+.5", "0", "-.5", "-1"}
        for i, level in ipairs(y_levels) do
            local line_y = center_y - level * (height/2 - 4)
            r.ImGui_DrawList_AddLine(draw_list, x, line_y, x + width, line_y, grid_color, 1)
            r.ImGui_DrawList_AddText(draw_list, x + 2, line_y - 6, label_color, y_labels[i])
        end
    end

    -- X-axis grid (time divisions)
    local num_x_divs = 4
    for i = 1, num_x_divs - 1 do
        local line_x = x + (width * i / num_x_divs)
        r.ImGui_DrawList_AddLine(draw_list, line_x, y, line_x, y + height, grid_color, 1)
        -- Time label
        local t = view_msec * (1 - i / num_x_divs)  -- Time ago from right
        local label_text
        if t < 1 then
            label_text = string.format("%.1fms", t)
        elseif t >= 1000 then
            label_text = string.format("%.1fs", t/1000)
        else
            label_text = string.format("%.0fms", t)
        end
        r.ImGui_DrawList_AddText(draw_list, line_x + 2, y + height - 12, label_color, label_text)
    end

    -- Draw both channels if we have samples
    if buffer_size > 0 then
        -- Draw left channel
        local prev_px_l, prev_py_l
        local prev_px_r, prev_py_r

        for i = 0, width - 1 do
            local buf_idx = math.floor(i * buffer_size / width)
            if buf_idx < buffer_size then
                local sample_l = r.gmem_read(scope_base + buf_idx) or 0
                local sample_r = r.gmem_read(scope_base + 1024 + buf_idx) or 0

                -- Clamp samples
                sample_l = math.max(-1, math.min(1, sample_l))
                sample_r = math.max(-1, math.min(1, sample_r))

                local px = x + i
                local py_l = center_y - sample_l * (height/2 - 4)
                local py_r = center_y - sample_r * (height/2 - 4)

                -- Draw left channel line (green)
                if prev_px_l then
                    r.ImGui_DrawList_AddLine(draw_list, prev_px_l, prev_py_l, px, py_l, color_l, 1.5)
                end

                -- Draw right channel line (magenta) with slight transparency
                if prev_px_r then
                    r.ImGui_DrawList_AddLine(draw_list, prev_px_r, prev_py_r, px, py_r, color_r, 1.0)
                end

                prev_px_l, prev_py_l = px, py_l
                prev_px_r, prev_py_r = px, py_r
            end
        end
    end

    -- Channel legend
    r.ImGui_DrawList_AddText(draw_list, x + width - 50, y + 4, color_l, "L")
    r.ImGui_DrawList_AddText(draw_list, x + width - 35, y + 4, color_r, "R")

    -- Border
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, 0x444444FF, 4, 0, 1)

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local hovered = r.ImGui_IsItemHovered(ctx.ctx)

    return hovered
end

--- Draw spectrum analyzer from GMEM FFT output (logarithmic frequency scale)
-- Based on Cockos gfxanalyzer DSP
-- GMEM layout per slot (base = 10000 + slot * 520):
--   [0-255]   = magnitude bins (normalized 0-1)
--   [512]     = num bins
--   [513]     = floor_db
--   [514]     = sample_rate
--   [515]     = update timestamp
--   [516]     = fft_size (actual FFT size)
-- @param ctx ImGui context wrapper
-- @param label string Unique label for the widget
-- @param width number Widget width
-- @param height number Widget height
-- @param slot number GMEM slot (0-15)
-- @return boolean True if hovered
function M.draw_spectrum(ctx, label, width, height, slot)
    slot = slot or 0
    local fft_slot_size = 520
    local fft_base = 10000 + slot * fft_slot_size

    -- Read metadata from GMEM
    local num_bins = r.gmem_read(fft_base + 512) or 256
    local floor_db = r.gmem_read(fft_base + 513) or -120
    local sample_rate = r.gmem_read(fft_base + 514) or 44100
    local fft_size = r.gmem_read(fft_base + 516) or 512

    num_bins = math.max(1, math.floor(num_bins))
    if sample_rate <= 0 then sample_rate = 44100 end

    local x, y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    local grid_color = 0x333333FF
    local label_color = 0x888888FF
    local hz_per_bin = sample_rate / fft_size

    -- Frequency range for log scale (20Hz to Nyquist)
    local min_freq = 20
    local max_freq = sample_rate / 2  -- Nyquist frequency
    local log_min = math.log(min_freq)
    local log_max = math.log(max_freq)
    local log_range = log_max - log_min

    -- Helper: convert frequency to x position (logarithmic)
    local function freq_to_x(freq)
        if freq <= min_freq then return x end
        if freq >= max_freq then return x + width end
        local log_freq = math.log(freq)
        return x + ((log_freq - log_min) / log_range) * width
    end

    -- Background
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x1A1A1AFF, 4)

    -- Y-axis grid (dB levels) - adapt to floor setting
    local db_levels = {0, -12, -24, -36, -48, -60, -72, -84, -96, -108, -120}
    for _, db in ipairs(db_levels) do
        if db >= floor_db then
            local norm = (db - floor_db) / (-floor_db)
            local line_y = y + height - norm * height
            r.ImGui_DrawList_AddLine(draw_list, x, line_y, x + width, line_y, grid_color, 1)
            r.ImGui_DrawList_AddText(draw_list, x + 2, line_y - 10, label_color, string.format("%ddB", db))
        end
    end

    -- X-axis grid (frequency markers - logarithmic positions)
    local freq_markers = {30, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000}
    for _, hz in ipairs(freq_markers) do
        if hz >= min_freq and hz <= max_freq then
            local line_x = freq_to_x(hz)
            if line_x > x + 5 and line_x < x + width - 5 then
                r.ImGui_DrawList_AddLine(draw_list, line_x, y, line_x, y + height, grid_color, 1)
                local label_text = hz >= 1000 and string.format("%.0fk", hz/1000) or string.format("%.0f", hz)
                r.ImGui_DrawList_AddText(draw_list, line_x + 2, y + 2, label_color, label_text)
            end
        end
    end

    -- Draw spectrum - iterate over bins and interpolate for smooth appearance
    -- Build array of (x_pos, magnitude) points
    local points = {}
    for bin = 1, num_bins - 1 do  -- Skip bin 0 (DC)
        local freq = bin * hz_per_bin
        if freq >= min_freq and freq <= max_freq then
            local bin_x = freq_to_x(freq)
            local mag = r.gmem_read(fft_base + bin) or 0
            mag = math.max(0, math.min(1, mag))
            table.insert(points, {x = bin_x, mag = mag})
        end
    end

    -- Draw filled spectrum by interpolating between points
    local bottom_y = y + height - 1
    for px = 0, width - 1 do
        local px_x = x + px

        -- Find surrounding points for interpolation
        local mag = 0
        local found = false

        for i = 1, #points - 1 do
            if points[i].x <= px_x and points[i+1].x >= px_x then
                -- Linear interpolation between bins
                local t = (px_x - points[i].x) / (points[i+1].x - points[i].x + 0.001)
                mag = points[i].mag * (1 - t) + points[i+1].mag * t
                found = true
                break
            end
        end

        -- Handle edges
        if not found and #points > 0 then
            if px_x < points[1].x then
                mag = points[1].mag
            elseif px_x > points[#points].x then
                mag = points[#points].mag
            end
        end

        mag = math.max(0, math.min(1, mag))
        local bar_height = mag * (height - 2)
        local bar_y = bottom_y - bar_height

        if bar_height > 0 then
            -- Color gradient based on magnitude (yellow spectrum style)
            local bar_color
            if mag > 0.8 then
                bar_color = 0xFFFF00FF  -- Bright yellow
            elseif mag > 0.5 then
                bar_color = 0xFFCC00FF  -- Yellow
            else
                bar_color = 0xCC9900FF  -- Darker yellow/orange
            end

            r.ImGui_DrawList_AddLine(draw_list, px_x, bar_y, px_x, bottom_y, bar_color, 1)
        end
    end

    -- Border
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, 0x444444FF, 4, 0, 1)

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local hovered = r.ImGui_IsItemHovered(ctx.ctx)

    return hovered
end

return M
