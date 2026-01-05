--- UI Widgets
-- Reusable UI components (sliders, faders, drop zones, etc.)
-- @module ui.widgets
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')

local M = {}

--------------------------------------------------------------------------------
-- Pan Slider
--------------------------------------------------------------------------------

--- Draw a custom pan slider with center line indicator
-- @param ctx ImGui context wrapper
-- @param label string Unique label for the widget
-- @param pan_val number Current pan value (-100 to +100)
-- @param width number Width of the slider (default: 50)
-- @return boolean changed, number new_value
function M.draw_pan_slider(ctx, label, pan_val, width)
    width = width or 50
    local slider_h = 12
    local text_h = 16
    local gap = 2
    local total_h = slider_h + gap + text_h

    local changed = false
    local new_val = pan_val

    -- Format label
    local pan_format
    if pan_val <= -1 then
        pan_format = string.format("%.0fL", -pan_val)
    elseif pan_val >= 1 then
        pan_format = string.format("%.0fR", pan_val)
    else
        pan_format = "C"
    end

    local screen_x, screen_y = ctx:get_cursor_screen_pos()
    local draw_list = ctx:get_window_draw_list()

    -- Background track
    ctx:draw_list_add_rect_filled(draw_list, screen_x, screen_y, screen_x + width, screen_y + slider_h, 0x333333FF, 2)

    -- Center line (vertical tick)
    local center_x = screen_x + width / 2
    ctx:draw_list_add_line(draw_list, center_x, screen_y - 1, center_x, screen_y + slider_h + 1, 0x666666FF, 1)

    -- Pan indicator line from center
    local pan_norm = (pan_val + 100) / 200  -- 0 to 1
    local pan_x = screen_x + pan_norm * width

    -- Draw filled region from center to pan position
    if pan_val < -1 then
        ctx:draw_list_add_rect_filled(draw_list, pan_x, screen_y + 1, center_x, screen_y + slider_h - 1, 0x5588AAFF, 1)
    elseif pan_val > 1 then
        ctx:draw_list_add_rect_filled(draw_list, center_x, screen_y + 1, pan_x, screen_y + slider_h - 1, 0x5588AAFF, 1)
    end

    -- Pan position indicator (small line)
    ctx:draw_list_add_line(draw_list, pan_x, screen_y, pan_x, screen_y + slider_h, 0xAADDFFFF, 2)

    -- Text label background (full width)
    local text_y = screen_y + slider_h + gap
    ctx:draw_list_add_rect_filled(draw_list, screen_x, text_y, screen_x + width, text_y + text_h, 0x222222FF, 2)

    -- Invisible button for slider dragging (only covers slider area)
    ctx:set_cursor_screen_pos(screen_x, screen_y)
    ctx:invisible_button(label .. "_slider_btn", width, slider_h)

    -- Handle dragging
    if ctx:is_item_active() then
        local mouse_x = ctx:get_mouse_pos()
        local new_norm = (mouse_x - screen_x) / width
        new_norm = math.max(0, math.min(1, new_norm))
        new_val = -100 + new_norm * 200
        changed = true
    end

    -- Double-click on slider to reset to center
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        new_val = 0
        changed = true
    end

    -- Draw formatted text centered
    local text_w = ctx:calc_text_size(pan_format)
    ctx:draw_list_add_text(draw_list, screen_x + (width - text_w) / 2, text_y + 2, 0xCCCCCCFF, pan_format)

    -- Invisible button for text label (separate from slider)
    ctx:set_cursor_screen_pos(screen_x, text_y)
    ctx:invisible_button(label .. "_text_btn", width, text_h)

    -- Double-click on text to edit value
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        ctx:open_popup(label .. "_edit_popup")
    end

    -- Edit popup
    if ctx:begin_popup(label .. "_edit_popup") then
        ctx:set_next_item_width(60)
        ctx:set_keyboard_focus_here()
        local input_changed, input_val = ctx:input_double("##" .. label .. "_input", pan_val, 0, 0, "%.0f")
        if input_changed then
            new_val = math.max(-100, math.min(100, input_val))
            changed = true
        end
        if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
            ctx:close_current_popup()
        end
        ctx:end_popup()
    end

    -- Advance cursor
    ctx:set_cursor_screen_pos(screen_x, screen_y + total_h)
    ctx:dummy(width, 0)

    return changed, new_val
end

--------------------------------------------------------------------------------
-- Vertical Fader
--------------------------------------------------------------------------------

--- Draw a vertical fader with fill and dB display
-- @param ctx ImGui context wrapper
-- @param label string Unique label for the widget
-- @param db_val number Current dB value
-- @param width number Width of the fader (default: 30)
-- @param height number Height of the fader (default: 120)
-- @param min_db number Minimum dB value (default: -24)
-- @param max_db number Maximum dB value (default: 12)
-- @return boolean changed, number new_value
function M.draw_fader(ctx, label, db_val, width, height, min_db, max_db)
    width = width or 30
    height = height or 120
    min_db = min_db or -24
    max_db = max_db or 12

    local changed = false
    local new_val = db_val

    local screen_x, screen_y = ctx:get_cursor_screen_pos()
    local draw_list = ctx:get_window_draw_list()

    -- Background track
    ctx:draw_list_add_rect_filled(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, 0x1A1A1AFF, 3)

    -- Calculate fill height based on dB value
    local normalized = (db_val - min_db) / (max_db - min_db)
    normalized = math.max(0, math.min(1, normalized))
    local fill_height = height * normalized

    -- Draw fill from bottom
    if fill_height > 2 then
        local fill_top = screen_y + height - fill_height
        -- Color gradient based on level
        local fill_color
        if db_val > 0 then
            fill_color = 0xDD8844CC  -- Orange for above 0dB
        elseif db_val > -6 then
            fill_color = 0x66AA88CC  -- Green-ish for normal
        else
            fill_color = 0x5588AACC  -- Blue for lower levels
        end
        ctx:draw_list_add_rect_filled(draw_list, screen_x + 2, fill_top, screen_x + width - 2, screen_y + height - 2, fill_color, 2)
    end

    -- Border
    ctx:draw_list_add_rect(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, 0x555555FF, 3)

    -- Draw dB tick marks on the right side
    local tick_dbs = {12, 6, 0, -6, -12, -18, -24}
    for _, tick_db in ipairs(tick_dbs) do
        if tick_db >= min_db and tick_db <= max_db then
            local tick_norm = (tick_db - min_db) / (max_db - min_db)
            local tick_y = screen_y + height - (tick_norm * height)
            local tick_len = (tick_db == 0) and 6 or 3
            local tick_color = (tick_db == 0) and 0x888888FF or 0x444444FF
            ctx:draw_list_add_line(draw_list, screen_x + width - tick_len, tick_y, screen_x + width, tick_y, tick_color, 1)
        end
    end

    -- Zero line indicator (horizontal across the full width at 0dB)
    local zero_norm = (0 - min_db) / (max_db - min_db)
    local zero_y = screen_y + height - (zero_norm * height)
    ctx:draw_list_add_line(draw_list, screen_x, zero_y, screen_x + width, zero_y, 0x666666AA, 1)

    -- Invisible button for dragging
    ctx:set_cursor_screen_pos(screen_x, screen_y)
    ctx:invisible_button(label .. "_fader_btn", width, height)

    -- Handle dragging (inverted because Y increases downward)
    if ctx:is_item_active() then
        local _, mouse_y = ctx:get_mouse_pos()
        local new_norm = 1 - ((mouse_y - screen_y) / height)
        new_norm = math.max(0, math.min(1, new_norm))
        new_val = min_db + new_norm * (max_db - min_db)
        changed = true
    end

    -- Double-click to reset to 0dB
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        new_val = 0
        changed = true
    end

    -- Draw dB value label below fader
    local label_h = 16
    local label_y = screen_y + height + 2
    ctx:draw_list_add_rect_filled(draw_list, screen_x, label_y, screen_x + width, label_y + label_h, 0x222222FF, 2)

    local db_label = db_val >= 0 and string.format("+%.0f", db_val) or string.format("%.0f", db_val)
    local text_w, _ = ctx:calc_text_size(db_label)
    ctx:draw_list_add_text(draw_list, screen_x + (width - text_w) / 2, label_y + 1, 0xCCCCCCFF, db_label)

    -- Advance cursor
    ctx:set_cursor_screen_pos(screen_x, label_y + label_h)
    ctx:dummy(width, 0)

    return changed, new_val
end

--------------------------------------------------------------------------------
-- Drop Zone
--------------------------------------------------------------------------------

--- Draw a drop zone for drag-and-drop operations
-- Always reserves space to prevent scroll jumping, but only shows visual when dragging
-- @param ctx ImGui context wrapper
-- @param position number Position identifier for unique IDs
-- @param is_empty boolean Whether this is an empty chain (shows larger label)
-- @param avail_height number Available height for the drop zone
-- @return boolean True if space was reserved
function M.draw_drop_zone(ctx, position, is_empty, avail_height)
    local has_plugin_payload = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_fx_payload = ctx:get_drag_drop_payload("FX_GUID")
    local is_dragging = has_plugin_payload or has_fx_payload

    local zone_w = 24
    local zone_h = math.min(avail_height - 20, 80)
    local label = is_empty and "+ Drop here" or "+"
    local btn_w = is_empty and 100 or zone_w

    if is_dragging then
        -- Show visible drop indicator when dragging
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)

        ctx:button(label .. "##drop_" .. position, btn_w, zone_h)
        ctx:pop_style_color(3)

        if ctx:begin_drag_drop_target() then
            -- Accept plugin drops
            local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted and plugin_name then
                -- Callback will be handled by caller
                return true
            end

            -- Accept FX reorder drops
            local accepted_fx, fx_guid = ctx:accept_drag_drop_payload("FX_GUID")
            if accepted_fx and fx_guid then
                -- Callback will be handled by caller
                return true
            end

            ctx:end_drag_drop_target()
        end
    else
        -- Reserve space with invisible element to prevent scroll jumping
        -- Don't show between items when not dragging (only at end)
        if not is_empty then
            return false  -- Don't reserve space between items when not dragging
        end
        ctx:dummy(btn_w, zone_h)
    end
    return true
end

return M

