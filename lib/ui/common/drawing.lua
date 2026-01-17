-- Drawing Utilities Module
-- Custom ImGui drawing functions for device UI

local M = {}
local r = reaper

-- Track when a slider is being dragged with fine control (Alt held)
-- This is used by curve_editor to avoid key conflicts
M.slider_fine_active = false

-- Track text input state for sliders (keyed by label)
M.slider_text_input = {}
M.slider_text_input_buffer = {}

--- Draw a UI icon (wrench icon button)
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param width number Button width (unused, icon determines size)
-- @param height number Button height (unused, icon determines size)
-- @param icon_font ImGui font handle (unused, kept for API compatibility)
-- @return boolean True if clicked
function M.draw_ui_icon(ctx, label, width, height, icon_font)
    local icons = require('lib.ui.common.icons')
    return icons.button_bordered(ctx, "ui_icon" .. label, icons.Names.wrench, 18)
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
-- Fine Control Slider Functions (Alt key for precision)
--------------------------------------------------------------------------------

--- Check if Alt/Option key is held
-- @param ctx ImGui context (raw or wrapper)
-- @return boolean True if Alt is held
function M.is_alt_held(ctx)
    local raw_ctx = ctx.ctx or ctx
    local left_alt = r.ImGui_IsKeyDown(raw_ctx, r.ImGui_Key_LeftAlt())
    local right_alt = r.ImGui_IsKeyDown(raw_ctx, r.ImGui_Key_RightAlt())
    return left_alt or right_alt
end

--- Check if Ctrl/Cmd key is held
-- @param ctx ImGui context (raw or wrapper)
-- @return boolean True if Ctrl (Windows/Linux) or Cmd (macOS) is held
function M.is_ctrl_held(ctx)
    local raw_ctx = ctx.ctx or ctx
    -- ImGui_Key_ModCtrl handles Cmd on macOS automatically
    return r.ImGui_IsKeyDown(raw_ctx, r.ImGui_Mod_Ctrl())
end

--- Horizontal slider with fine control, text input, and double-click reset
-- Features:
--   - Alt+drag for fine control (10% sensitivity)
--   - Double-click to reset to default value
--   - Ctrl/Cmd+click to enter value as text (when text_input_enabled)
-- @param ctx ImGui context wrapper
-- @param label string Slider label
-- @param value number Current value
-- @param min number Minimum value
-- @param max number Maximum value
-- @param format string Display format (optional)
-- @param fine_factor number Fine control multiplier (default 0.1)
-- @param display_mult number Multiplier for display value (e.g., 100 for percentage)
-- @param default_value number Default value for double-click reset (optional)
-- @param text_input_enabled boolean Whether Ctrl+click text input is enabled (default true)
-- @return boolean changed, number new_value, boolean in_text_mode
function M.slider_double_fine(ctx, label, value, min, max, format, fine_factor, display_mult, default_value, text_input_enabled)
    fine_factor = fine_factor or 0.1
    display_mult = display_mult or 1
    -- Default to true for backwards compatibility, but can be disabled
    if text_input_enabled == nil then text_input_enabled = true end
    local alt_held = M.is_alt_held(ctx)
    local ctrl_held = M.is_ctrl_held(ctx)

    local changed = false
    local new_value = value

    -- If we have a display multiplier, scale the slider range for display
    local display_value = value * display_mult
    local display_min = min * display_mult
    local display_max = max * display_mult

    local raw_ctx = ctx.ctx or ctx
    -- Use format for slider display, but always use proper format for text input
    local display_format = format or "%.3f"
    local text_input_format = "%.3f"  -- Always use proper format for text entry

    -- Check cursor position BEFORE drawing anything
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(raw_ctx)
    local item_w = r.ImGui_CalcItemWidth(raw_ctx)
    local item_h = r.ImGui_GetFrameHeight(raw_ctx)
    local mouse_x, mouse_y = r.ImGui_GetMousePos(raw_ctx)
    local is_mouse_over = mouse_x >= cursor_x and mouse_x <= cursor_x + item_w and
                          mouse_y >= cursor_y and mouse_y <= cursor_y + item_h
    local mouse_clicked = r.ImGui_IsMouseClicked(raw_ctx, 0)
    local mouse_double_clicked = r.ImGui_IsMouseDoubleClicked(raw_ctx, 0)

    -- Check if we're in text input mode for this slider
    local in_text_mode = M.slider_text_input[label]

    -- Ctrl+click to enter text input mode (only if text input is enabled)
    if text_input_enabled and is_mouse_over and mouse_clicked and ctrl_held and not in_text_mode then
        M.slider_text_input[label] = true
        M.slider_text_input_buffer[label] = string.format(text_input_format, display_value)
        in_text_mode = true
    end

    -- Double-click reset (only when not in text mode)
    if not in_text_mode and is_mouse_over and mouse_double_clicked and default_value ~= nil then
        new_value = default_value
        changed = true
        display_value = default_value * display_mult
    end

    if in_text_mode then
        -- Text input mode - use InputText and parse the number
        local input_flags = r.ImGui_InputTextFlags_AutoSelectAll()

        -- Focus the input on first frame
        if M.slider_text_input[label] == true then
            r.ImGui_SetKeyboardFocusHere(raw_ctx)
            M.slider_text_input[label] = "active"
        end

        local _, new_text = r.ImGui_InputText(raw_ctx, label, M.slider_text_input_buffer[label], input_flags)

        -- Update buffer with whatever user typed
        M.slider_text_input_buffer[label] = new_text

        -- Check if user finished editing (clicked away or pressed Enter)
        local should_apply = r.ImGui_IsItemDeactivatedAfterEdit(raw_ctx)
        local enter_pressed = r.ImGui_IsKeyPressed(raw_ctx, r.ImGui_Key_Enter()) or
                              r.ImGui_IsKeyPressed(raw_ctx, r.ImGui_Key_KeypadEnter())

        if should_apply or enter_pressed then
            -- Parse the value - handle both period and comma as decimal separator
            if new_text and #new_text > 0 then
                -- Trim whitespace and normalize decimal separator
                local text_to_parse = new_text:match("^%s*(.-)%s*$") or ""
                text_to_parse = text_to_parse:gsub(",", ".")
                local parsed = tonumber(text_to_parse)

                if parsed then
                    -- Clamp to range
                    local clamped = math.max(display_min, math.min(display_max, parsed))
                    new_value = clamped / display_mult
                    changed = true
                end
            end
            -- Exit text mode (always, even if parsing failed)
            M.slider_text_input[label] = nil
            M.slider_text_input_buffer[label] = nil
        end

        -- Escape to cancel
        if r.ImGui_IsKeyPressed(raw_ctx, r.ImGui_Key_Escape()) then
            M.slider_text_input[label] = nil
            M.slider_text_input_buffer[label] = nil
        end
    else
        -- Normal slider mode
        local flags = r.ImGui_SliderFlags_NoRoundToFormat() | r.ImGui_SliderFlags_AlwaysClamp()

        local slider_changed, new_display_value = r.ImGui_SliderDouble(raw_ctx, label, display_value, display_min, display_max, display_format, flags)

        -- Track if this slider is actively being dragged with Alt
        local is_active = r.ImGui_IsItemActive(raw_ctx)
        if is_active and alt_held then
            M.slider_fine_active = true
        elseif not is_active then
            M.slider_fine_active = false
        end

        -- Normal slider change with optional fine control (if not already reset by double-click)
        if slider_changed and not changed then
            new_value = new_display_value / display_mult

            if alt_held then
                -- Apply fine control: reduce the delta
                local delta = new_value - value
                new_value = value + delta * fine_factor
            end
            -- Clamp to range
            new_value = math.max(min, math.min(max, new_value))
            changed = true
        end
    end

    return changed, new_value, in_text_mode
end

--- Vertical slider with fine control, text input, and double-click reset
-- Features:
--   - Alt+drag for fine control (10% sensitivity)
--   - Double-click to reset to default value
--   - Ctrl/Cmd+click to enter value as text
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
    local alt_held = M.is_alt_held(ctx)

    local changed = false
    local new_value = value

    -- If we have a display multiplier, scale the slider range for display
    local display_value = value * display_mult
    local display_min = min * display_mult
    local display_max = max * display_mult

    local raw_ctx = ctx.ctx or ctx

    -- Check for double-click to reset BEFORE drawing slider (to capture the event first)
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(raw_ctx)
    local mouse_x, mouse_y = r.ImGui_GetMousePos(raw_ctx)
    local is_mouse_over = mouse_x >= cursor_x and mouse_x <= cursor_x + width and
                          mouse_y >= cursor_y and mouse_y <= cursor_y + height
    local mouse_double_clicked = r.ImGui_IsMouseDoubleClicked(raw_ctx, 0)

    -- Double-click reset (check before slider consumes the event)
    if is_mouse_over and mouse_double_clicked and default_value ~= nil then
        new_value = default_value
        changed = true
        -- Still draw slider but with the reset value
        display_value = default_value * display_mult
    end

    -- Use raw ImGui API with flags
    -- AlwaysClamp ensures input values stay in range
    -- Ctrl+click enables text input mode (ImGui built-in behavior)
    local flags = r.ImGui_SliderFlags_NoRoundToFormat() | r.ImGui_SliderFlags_AlwaysClamp()
    local display_format = format or "%.3f"

    local slider_changed, new_display_value = r.ImGui_VSliderDouble(raw_ctx, label, width, height, display_value, display_min, display_max, display_format, flags)

    -- Track if this slider is actively being dragged with Alt (for curve_editor conflict avoidance)
    local is_active = r.ImGui_IsItemActive(raw_ctx)
    if is_active and alt_held then
        M.slider_fine_active = true
    elseif not is_active then
        M.slider_fine_active = false
    end

    -- Normal slider change with optional fine control (if not already reset by double-click)
    if slider_changed and not changed then
        new_value = new_display_value / display_mult

        if alt_held then
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
function M.draw_db_scale_marks(ctx, draw_list, scale_x, screen_y, fader_h, scale_w, show_labels)
    if show_labels == nil then show_labels = true end
    local db_marks = {12, 6, 0, -6, -12, -18, -24}
    for _, db in ipairs(db_marks) do
        local mark_norm = (db + 24) / 36
        local mark_y = screen_y + fader_h - (fader_h * mark_norm)
        r.ImGui_DrawList_AddLine(draw_list, scale_x + scale_w - 6, mark_y, scale_x + scale_w, mark_y, 0x666666FF, 1)
        if show_labels and (db == 0 or db == -12 or db == 12) then
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
            -- Use same range as fader scale: -24dB to +12dB (36dB total)
            peak_db = math.max(-24, math.min(12, peak_db))
            local peak_norm = (peak_db + 24) / 36
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
-- @param draw_data boolean Whether to draw waveform data (default true)
-- @return boolean True if hovered
function M.draw_oscilloscope(ctx, label, width, height, slot, draw_data)
    slot = slot or 0
    if draw_data == nil then draw_data = true end
    local scope_slot_size = 2100
    local scope_base = 2000 + slot * scope_slot_size

    -- Read metadata from GMEM
    local num_samples = r.gmem_read(scope_base + 2048) or 0
    local view_msec = r.gmem_read(scope_base + 2049) or 100

    -- Use num_samples or default buffer size
    local buffer_size = num_samples > 0 and math.floor(num_samples) or 1024

    local x, y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    local grid_color = 0x333333FF
    local label_color = 0x888888FF
    local color_l = 0x80FF80FF  -- Light green for left
    local color_r = 0xFF80FFFF  -- Light magenta for right

    -- Background
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x1A1A1AFF, 0)

    -- Center line (silence / -48dB threshold)
    local center_y = y + height/2
    r.ImGui_DrawList_AddLine(draw_list, x, center_y, x + width, center_y, 0x666666FF, 1)

    -- Y-axis grid (dB levels) - logarithmic scale
    -- Display range: 0dB at edge, -48dB at center
    local db_range = 48
    local db_marks = {0, -12, -24, -36, -48}  -- Fewer marks for cleaner look
    local label_dim = 0x666666FF  -- Dimmer label color for grid
    for _, db in ipairs(db_marks) do
        -- Map dB to normalized position (0dB=1, -48dB=0)
        local normalized = (db + db_range) / db_range
        local offset = normalized * (height/2 - 4)
        -- Upper and lower lines (positive and negative amplitude)
        r.ImGui_DrawList_AddLine(draw_list, x, center_y - offset, x + width, center_y - offset, grid_color, 1)
        r.ImGui_DrawList_AddLine(draw_list, x, center_y + offset, x + width, center_y + offset, grid_color, 1)
        -- Labels inside grid (position below line to avoid clipping at edges)
        local label_text = string.format("%d", db)
        if offset > 5 then  -- Only show if not at center
            -- Upper label (positive amplitude side) - position below line
            r.ImGui_DrawList_AddText(draw_list, x + 4, center_y - offset + 2, label_dim, label_text)
            -- Lower label (negative amplitude side) - position above line
            r.ImGui_DrawList_AddText(draw_list, x + 4, center_y + offset - 11, label_dim, label_text)
        else
            -- At center, just show the dB value once
            r.ImGui_DrawList_AddText(draw_list, x + 4, center_y - offset + 2, label_dim, label_text)
        end
    end

    -- X-axis grid (time divisions)
    local num_x_divs = 4
    for i = 1, num_x_divs - 1 do
        local line_x = x + (width * i / num_x_divs)
        r.ImGui_DrawList_AddLine(draw_list, line_x, y, line_x, y + height, grid_color, 1)
        -- Time label (shorter format) - inside grid
        local t = view_msec * (1 - i / num_x_divs)  -- Time ago from right
        local label_text
        if t >= 1000 then
            label_text = string.format("%.0fs", t/1000)
        else
            label_text = string.format("%.0f", t)
        end
        r.ImGui_DrawList_AddText(draw_list, line_x + 3, y + height - 13, label_dim, label_text)
    end

    -- Helper: convert linear amplitude to logarithmic display position
    -- Maps amplitude to dB scale, preserving sign for display
    local function amp_to_log_y(sample)
        local sign = sample >= 0 and 1 or -1
        local abs_sample = math.abs(sample)

        -- Clamp minimum to avoid log(0)
        if abs_sample < 0.001 then
            return center_y  -- Below -60dB, treat as zero
        end

        -- Convert to dB (0dB = amplitude 1.0)
        local db = 20 * math.log(abs_sample, 10)

        -- Map dB to display: 0dB at edge, -48dB at center
        -- This gives us a useful range where quiet signals are visible
        local db_range = 48  -- Display range in dB
        local normalized = math.max(0, math.min(1, (db + db_range) / db_range))

        -- Apply sign and convert to Y position
        local offset = normalized * (height/2 - 4)
        return center_y - sign * offset
    end

    -- Track peak values for display
    local peak_l_pos, peak_l_neg = 0, 0
    local peak_r_pos, peak_r_neg = 0, 0

    -- Draw both channels if we have samples and draw_data is true
    if draw_data and buffer_size > 0 then
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

                -- Track peaks (bipolar)
                if sample_l > peak_l_pos then peak_l_pos = sample_l end
                if sample_l < peak_l_neg then peak_l_neg = sample_l end
                if sample_r > peak_r_pos then peak_r_pos = sample_r end
                if sample_r < peak_r_neg then peak_r_neg = sample_r end

                local px = x + i
                local py_l = amp_to_log_y(sample_l)
                local py_r = amp_to_log_y(sample_r)

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

        -- Helper: amplitude to dB string (short format)
        local function amp_to_db_str(amp)
            if math.abs(amp) < 0.001 then return "-oo" end
            local db = 20 * math.log(math.abs(amp), 10)
            return string.format("%.0f", db)
        end

        -- Channel legend with bipolar peak values (+peak/-peak dB)
        local l_pos_str = amp_to_db_str(peak_l_pos)
        local l_neg_str = amp_to_db_str(peak_l_neg)
        local r_pos_str = amp_to_db_str(peak_r_pos)
        local r_neg_str = amp_to_db_str(peak_r_neg)

        -- Show L/R with bipolar peak values (pos/neg dB) in top-right corner
        local text_x = x + width - 95
        r.ImGui_DrawList_AddText(draw_list, text_x, y + 4, color_l, string.format("L: %s / %s", l_pos_str, l_neg_str))
        r.ImGui_DrawList_AddText(draw_list, text_x, y + 16, color_r, string.format("R: %s / %s", r_pos_str, r_neg_str))
    end

    -- Border (3 sides - no top to avoid double line with header)
    local border_color = 0x444444FF
    r.ImGui_DrawList_AddLine(draw_list, x, y, x, y + height, border_color, 1)  -- left
    r.ImGui_DrawList_AddLine(draw_list, x, y + height, x + width, y + height, border_color, 1)  -- bottom
    r.ImGui_DrawList_AddLine(draw_list, x + width, y, x + width, y + height, border_color, 1)  -- right

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
-- @param draw_data boolean Whether to draw spectrum data (default true)
-- @return boolean True if hovered
function M.draw_spectrum(ctx, label, width, height, slot, draw_data)
    slot = slot or 0
    if draw_data == nil then draw_data = true end
    local fft_slot_size = 520
    local fft_base = 10000 + slot * fft_slot_size

    -- Read metadata from GMEM
    local num_bins = r.gmem_read(fft_base + 512) or 256
    local floor_db = r.gmem_read(fft_base + 513) or -120
    local sample_rate = r.gmem_read(fft_base + 514) or 44100
    local fft_size = r.gmem_read(fft_base + 516) or 512

    num_bins = math.max(1, math.min(256, math.floor(num_bins)))  -- Cap at 256 (GMEM limit)
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
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x1A1A1AFF, 0)

    -- Y-axis grid (dB levels) - adapt to floor setting, fewer marks
    local label_dim = 0x666666FF  -- Dimmer label color for grid
    local db_levels = {0, -12, -24, -36, -48, -60}
    for _, db in ipairs(db_levels) do
        if db >= floor_db then
            local norm = (db - floor_db) / (-floor_db)
            local line_y = y + height - norm * height
            r.ImGui_DrawList_AddLine(draw_list, x, line_y, x + width, line_y, grid_color, 1)
            -- Position label below line to stay inside grid
            local label_y = db == 0 and line_y + 2 or line_y - 11
            r.ImGui_DrawList_AddText(draw_list, x + 4, label_y, label_dim, string.format("%d", db))
        end
    end

    -- X-axis grid (frequency markers - logarithmic positions)
    local freq_markers = {50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000}
    for _, hz in ipairs(freq_markers) do
        if hz >= min_freq and hz <= max_freq then
            local line_x = freq_to_x(hz)
            if line_x > x + 5 and line_x < x + width - 5 then
                r.ImGui_DrawList_AddLine(draw_list, line_x, y, line_x, y + height, grid_color, 1)
                local label_text = hz >= 1000 and string.format("%dk", hz/1000) or string.format("%d", hz)
                r.ImGui_DrawList_AddText(draw_list, line_x + 3, y + 4, label_dim, label_text)
            end
        end
    end

    -- Draw spectrum using smooth curve (only if draw_data is true)
    if draw_data then
        -- Build array of (x_pos, magnitude) points from FFT bins
        local bin_points = {}
        for bin = 1, num_bins - 1 do  -- Skip bin 0 (DC)
            local freq = bin * hz_per_bin
            if freq >= min_freq and freq <= max_freq then
                local bin_x = freq_to_x(freq)
                local mag = r.gmem_read(fft_base + bin) or 0
                mag = math.max(0, math.min(1, mag))
                table.insert(bin_points, {x = bin_x, mag = mag})
            end
        end

        local bottom_y = y + height - 1

        -- Sample at regular pixel intervals with interpolation for smooth curve
        local curve_points = {}
        local step = 2  -- Sample every 2 pixels for smoother curve
        for px = 0, width - 1, step do
            local px_x = x + px
            local mag = 0
            local found = false

            -- Find surrounding bin points for interpolation
            if #bin_points >= 2 then
                for i = 1, #bin_points - 1 do
                    if bin_points[i].x <= px_x and bin_points[i+1].x >= px_x then
                        -- Smooth interpolation between bins
                        local dx = bin_points[i+1].x - bin_points[i].x
                        if dx > 0.001 then
                            local t = (px_x - bin_points[i].x) / dx
                            -- Smoothstep for smoother transitions
                            t = math.max(0, math.min(1, t))
                            t = t * t * (3 - 2 * t)
                            mag = bin_points[i].mag * (1 - t) + bin_points[i+1].mag * t
                        else
                            mag = (bin_points[i].mag + bin_points[i+1].mag) * 0.5
                        end
                        found = true
                        break
                    end
                end

                -- Handle edges (before first or after last bin)
                if not found then
                    if px_x <= bin_points[1].x then
                        -- Fade in from zero at low frequencies
                        local fade_dist = bin_points[1].x - x
                        if fade_dist > 0 then
                            local t = (px_x - x) / fade_dist
                            mag = bin_points[1].mag * t
                        end
                    elseif px_x >= bin_points[#bin_points].x then
                        -- Fade out to zero at high frequencies (beyond data range)
                        local fade_start = bin_points[#bin_points].x
                        local fade_end = x + width
                        local fade_dist = fade_end - fade_start
                        if fade_dist > 0 then
                            local t = 1 - (px_x - fade_start) / fade_dist
                            t = math.max(0, t)
                            mag = bin_points[#bin_points].mag * t * t  -- Quadratic fade
                        end
                    end
                end
            elseif #bin_points == 1 then
                mag = bin_points[1].mag
            end

            mag = math.max(0, math.min(1, mag))
            local point_y = bottom_y - mag * (height - 2)
            table.insert(curve_points, {x = px_x, y = point_y, mag = mag})
        end

        -- Apply smoothing pass to curve points (3-point weighted average)
        if #curve_points > 2 then
            local smoothed = {}
            for i = 1, #curve_points do
                if i == 1 or i == #curve_points then
                    smoothed[i] = curve_points[i].y
                else
                    -- Weighted average: 25% prev, 50% current, 25% next
                    smoothed[i] = curve_points[i-1].y * 0.25 +
                                  curve_points[i].y * 0.5 +
                                  curve_points[i+1].y * 0.25
                end
            end
            -- Apply smoothed values
            for i = 1, #curve_points do
                curve_points[i].y = smoothed[i]
            end
            -- Second smoothing pass for extra smoothness
            for i = 1, #curve_points do
                if i == 1 or i == #curve_points then
                    smoothed[i] = curve_points[i].y
                else
                    smoothed[i] = curve_points[i-1].y * 0.25 +
                                  curve_points[i].y * 0.5 +
                                  curve_points[i+1].y * 0.25
                end
            end
            for i = 1, #curve_points do
                curve_points[i].y = smoothed[i]
            end
        end

        -- Draw filled area under curve using triangles
        local fill_color = 0xCC990066  -- Semi-transparent orange/yellow
        for i = 1, #curve_points - 1 do
            local p1 = curve_points[i]
            local p2 = curve_points[i + 1]
            -- Draw quad as two triangles
            r.ImGui_DrawList_AddTriangleFilled(draw_list,
                p1.x, p1.y,
                p2.x, p2.y,
                p2.x, bottom_y,
                fill_color)
            r.ImGui_DrawList_AddTriangleFilled(draw_list,
                p1.x, p1.y,
                p2.x, bottom_y,
                p1.x, bottom_y,
                fill_color)
        end

        -- Draw smooth curve line on top
        local line_color = 0xFFCC00FF  -- Yellow
        for i = 1, #curve_points - 1 do
            local p1 = curve_points[i]
            local p2 = curve_points[i + 1]
            r.ImGui_DrawList_AddLine(draw_list, p1.x, p1.y, p2.x, p2.y, line_color, 2.0)
        end
    end

    -- Border (3 sides - no top to avoid double line with header)
    local border_color = 0x444444FF
    r.ImGui_DrawList_AddLine(draw_list, x, y, x, y + height, border_color, 1)  -- left
    r.ImGui_DrawList_AddLine(draw_list, x, y + height, x + width, y + height, border_color, 1)  -- bottom
    r.ImGui_DrawList_AddLine(draw_list, x + width, y, x + width, y + height, border_color, 1)  -- right

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local hovered = r.ImGui_IsItemHovered(ctx.ctx)

    return hovered
end

return M
