--[[
Sidebar Column Module - Draws chain sidebar with Mix, Delta, Pan, Gain, Phase controls
]]

local M = {}

--- Draw Mix knob column (centered knob with label and percentage)
local function draw_mix_column(ctx, container, mix_val, mix_idx)
    local r = reaper
    local drawing = require('lib.ui.common.drawing')
    local interacted = false

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
    local mix_changed, new_mix = drawing.draw_knob(ctx, "##mix_knob", mix_val, mix_knob_size)
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

    return interacted
end

--- Draw Delta toggle button column
local function draw_delta_column(ctx, fx, delta_val, delta_idx)
    local r = reaper
    local interacted = false

    -- "Delta" label (centered horizontally)
    local delta_text = "Delta"
    local delta_text_w = r.ImGui_CalcTextSize(ctx.ctx, delta_text)
    local delta_col_start_x = r.ImGui_GetCursorPosX(ctx.ctx)
    local col_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
    r.ImGui_SetCursorPosX(ctx.ctx, delta_col_start_x + (col_w - delta_text_w) / 2)
    ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAACCFF)
    ctx:text(delta_text)
    ctx:pop_style_color()

    ctx:spacing()
    r.ImGui_Dummy(ctx.ctx, 0, 6)

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
    r.ImGui_SetCursorPosX(ctx.ctx, delta_col_start_x + (col_w_btn - delta_btn_w) / 2)
    if ctx:button(delta_on and "∆" or "—", delta_btn_w, delta_btn_h) then
        pcall(function() fx:set_param_normalized(delta_idx, delta_on and 0 or 1) end)
        interacted = true
    end
    ctx:pop_style_color()

    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip(delta_on and "Delta Solo: ON (wet - dry)" or "Delta Solo: OFF")
    end

    return interacted
end

--- Draw Pan slider control
local function draw_pan_control(ctx, utility, pan_val)
    local widgets = require('lib.ui.common.widgets')
    local interacted = false

    pan_val = pan_val or 0.5
    local pan_pct = (pan_val - 0.5) * 200

    ctx:spacing()

    local avail_w, _ = ctx:get_content_region_avail()
    local pan_w = math.min(avail_w - 4, 40)
    local pan_offset = math.max(0, (avail_w - pan_w) / 2)
    ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + pan_offset)
    local pan_changed, new_pan = widgets.draw_pan_slider(ctx, "##utility_pan", pan_pct, pan_w)
    if pan_changed then
        local new_norm = (new_pan + 100) / 200
        pcall(function() utility:set_param_normalized(1, new_norm) end)
        interacted = true
    end

    return interacted
end

--- Draw Gain fader with meters and dB scale
local function draw_gain_fader_control(ctx, utility, gain_val)
    local r = reaper
    local imgui = require('imgui')
    local drawing = require('lib.ui.common.drawing')
    local state_module = require('lib.core.state')
    local interacted = false

    -- Range: -24 to +12 dB (36dB total), matches rack mixer
    local DB_MIN, DB_MAX = -24, 12
    local DB_RANGE = DB_MAX - DB_MIN  -- 36

    -- gain_val is already the dB value (from get_param, not normalized)
    local gain_db = gain_val or 0
    local gain_norm = (gain_db - DB_MIN) / DB_RANGE  -- for visual position

    ctx:spacing()

    -- Fader with meter and scale
    local fader_w = 18
    local meter_w = 10
    local scale_w = 16

    local _, remaining_h = ctx:get_content_region_avail()
    -- Leave room for dB label (22px) + phase controls below (50px) if enabled
    local config = require('lib.core.config')
    local phase_reserve = config.get('show_phase_controls') and 50 or 0
    local fader_h = remaining_h - 22 - phase_reserve  -- 22px for dB label at bottom (matches rack)
    fader_h = math.max(50, fader_h)

    local avail_w, _ = ctx:get_content_region_avail()
    local total_w = scale_w + fader_w + meter_w + 4
    local offset_x = math.max(0, (avail_w - total_w) / 2)

    ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + offset_x)

    local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    local scale_x = screen_x
    local fader_x = screen_x + scale_w + 2
    local meter_x = fader_x + fader_w + 2

    -- dB scale - tick marks at key points, labels at 12, 0, -12 (matches rack)
    local db_marks = {12, 0, -12, -24}
    for _, db in ipairs(db_marks) do
        local mark_norm = (db - DB_MIN) / DB_RANGE
        local mark_y = screen_y + fader_h - (fader_h * mark_norm)
        r.ImGui_DrawList_AddLine(draw_list, scale_x + scale_w - 4, mark_y, scale_x + scale_w, mark_y, 0x666666FF, 1)
        -- Label 12, 0, -12
        if db == 12 or db == 0 or db == -12 then
            local label = db == 0 and "0" or tostring(db)
            r.ImGui_DrawList_AddText(draw_list, scale_x, mark_y - 5, 0x666666FF, label)
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
    -- 0dB line
    local zero_norm = (0 - DB_MIN) / DB_RANGE  -- ~0.889
    local zero_y = screen_y + fader_h - (fader_h * zero_norm)
    r.ImGui_DrawList_AddLine(draw_list, fader_x, zero_y, fader_x + fader_w, zero_y, 0xFFFFFF44, 1)

    -- Stereo meters (mono meter from utility output level)
    local meter_l_x = meter_x
    local meter_r_x = meter_x + meter_w / 2 + 1
    local half_meter_w = meter_w / 2 - 1
    r.ImGui_DrawList_AddRectFilled(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)
    r.ImGui_DrawList_AddRectFilled(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)

    -- Get output levels from utility JSFX via gmem (more reliable than param reading)
    -- gmem[2] = output level L, gmem[3] = output level R (written by SideFX_Utility)
    r.gmem_attach("SideFX")  -- attach to SideFX gmem namespace
    local level_l = r.gmem_read(2) or 0
    local level_r = r.gmem_read(3) or 0


    local function draw_meter_bar(x, w, peak)
        if peak > 0.001 then
            local peak_db = 20 * math.log(peak, 10)
            -- Clamp to fader range
            peak_db = math.max(DB_MIN, math.min(DB_MAX, peak_db))
            local peak_norm = (peak_db - DB_MIN) / DB_RANGE
            local meter_fill_h = fader_h * peak_norm
            if meter_fill_h > 1 then
                local meter_top = screen_y + fader_h - meter_fill_h
                local meter_color
                if peak_db > 0 then meter_color = 0xFF4444FF
                elseif peak_db > -6 then meter_color = 0xFFAA44FF
                elseif peak_db > -12 then meter_color = 0x44FF44FF
                else meter_color = 0x44AA44FF end
                r.ImGui_DrawList_AddRectFilled(draw_list, x, meter_top, x + w, screen_y + fader_h - 1, meter_color, 0)
            end
        end
    end
    draw_meter_bar(meter_l_x + 1, half_meter_w - 1, level_l)
    draw_meter_bar(meter_r_x + 1, half_meter_w - 1, level_r)

    r.ImGui_DrawList_AddRect(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)
    r.ImGui_DrawList_AddRect(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)

    -- Invisible button for meter hover detection
    r.ImGui_SetCursorScreenPos(ctx.ctx, meter_l_x, screen_y)
    ctx:invisible_button("##meter_hover", meter_w, fader_h)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        -- Calculate peak dB values
        local peak_db_l = level_l > 0.001 and (20 * math.log(level_l, 10)) or -60
        local peak_db_r = level_r > 0.001 and (20 * math.log(level_r, 10)) or -60
        peak_db_l = math.max(DB_MIN, math.min(DB_MAX, peak_db_l))
        peak_db_r = math.max(DB_MIN, math.min(DB_MAX, peak_db_r))

        -- Smooth the display values (store in state)
        local state = state_module.state
        state.meter_display_l = state.meter_display_l or peak_db_l
        state.meter_display_r = state.meter_display_r or peak_db_r
        -- Fast attack, slow release for readable display
        if peak_db_l > state.meter_display_l then
            state.meter_display_l = peak_db_l
        else
            state.meter_display_l = state.meter_display_l * 0.92 + peak_db_l * 0.08
        end
        if peak_db_r > state.meter_display_r then
            state.meter_display_r = peak_db_r
        else
            state.meter_display_r = state.meter_display_r * 0.92 + peak_db_r * 0.08
        end

        -- Format display strings (compact)
        local l_val = state.meter_display_l
        local r_val = state.meter_display_r
        local l_str = l_val <= DB_MIN and "-∞" or string.format("%.0f", l_val)
        local r_str = r_val <= DB_MIN and "-∞" or string.format("%.0f", r_val)

        -- Show as tooltip (font size is controlled by ImGui style, not PushFont)
        ctx:set_tooltip(string.format("L %s | R %s dB", l_str, r_str))
    end

    -- Invisible slider for fader interaction
    -- Features: Shift+drag for fine control, Ctrl/Cmd+click to reset to 0dB, double-click for text input
    r.ImGui_SetCursorScreenPos(ctx.ctx, fader_x, screen_y)
    ctx:push_style_color(imgui.Col.FrameBg(), 0x00000000)
    ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x00000000)
    ctx:push_style_color(imgui.Col.FrameBgActive(), 0x00000000)
    ctx:push_style_color(imgui.Col.SliderGrab(), 0xAAAAAAFF)
    ctx:push_style_color(imgui.Col.SliderGrabActive(), 0xFFFFFFFF)
    local gain_changed, new_gain_db = drawing.v_slider_double_fine(ctx, "##gain_fader_v", fader_w, fader_h, gain_db, DB_MIN, DB_MAX, "", nil, nil, 0)
    if gain_changed then
        pcall(function() utility:set_param(0, new_gain_db) end)  -- set actual dB value
        interacted = true
    end
    ctx:pop_style_color(5)

    -- Show gain value prominently on hover
    local is_fader_hovered = r.ImGui_IsItemHovered(ctx.ctx)
    if is_fader_hovered then
        -- Draw floating value box next to fader
        local hover_label = string.format("%.1f dB", gain_db)
        local hover_text_w = r.ImGui_CalcTextSize(ctx.ctx, hover_label)
        local hover_box_w = hover_text_w + 8
        local hover_box_h = 18
        local hover_x = fader_x - hover_box_w - 4
        local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx.ctx)
        local hover_y = mouse_y - hover_box_h / 2
        -- Clamp to fader bounds
        hover_y = math.max(screen_y, math.min(screen_y + fader_h - hover_box_h, hover_y))

        r.ImGui_DrawList_AddRectFilled(draw_list, hover_x, hover_y, hover_x + hover_box_w, hover_y + hover_box_h, 0x222222EE, 3)
        r.ImGui_DrawList_AddRect(draw_list, hover_x, hover_y, hover_x + hover_box_w, hover_y + hover_box_h, 0x888888FF, 3)
        r.ImGui_DrawList_AddText(draw_list, hover_x + 4, hover_y + 2, 0xFFFFFFFF, hover_label)
    end

    -- dB label below fader
    local label_h = 16
    local label_y = screen_y + fader_h + 2
    local label_x = fader_x
    r.ImGui_DrawList_AddRectFilled(draw_list, label_x, label_y, label_x + fader_w, label_y + label_h, 0x222222FF, 2)
    local db_label = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.0f", gain_db) or string.format("%.0f", gain_db))
    local text_w = r.ImGui_CalcTextSize(ctx.ctx, db_label)
    r.ImGui_DrawList_AddText(draw_list, label_x + (fader_w - text_w) / 2, label_y + 1, 0xCCCCCCFF, db_label)

    -- Invisible button for dB label
    r.ImGui_SetCursorScreenPos(ctx.ctx, label_x, label_y)
    ctx:invisible_button("##gain_db_label", fader_w, label_h)

    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        ctx:open_popup("##gain_edit_popup")
    end

    if ctx:begin_popup("##gain_edit_popup") then
        ctx:set_next_item_width(60)
        ctx:set_keyboard_focus_here()
        local input_changed, input_val = ctx:input_double("##gain_input", gain_db, 0, 0, "%.1f")
        if input_changed then
            local clamped_db = math.max(DB_MIN, math.min(DB_MAX, input_val))
            pcall(function() utility:set_param(0, clamped_db) end)  -- set actual dB value
            interacted = true
        end
        if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
            ctx:close_current_popup()
        end
        ctx:end_popup()
    end

    r.ImGui_SetCursorScreenPos(ctx.ctx, screen_x, label_y + label_h)

    return interacted
end

--- Draw Phase invert toggle buttons (L/R) - compact Ø icons
local function draw_phase_controls(ctx, utility, phase_l, phase_r, center_item_fn)
    local r = reaper
    local interacted = false

    ctx:spacing()
    ctx:spacing()

    local phase_btn_size = 18
    local phase_gap = 4
    local phase_total_w = phase_btn_size * 2 + phase_gap
    center_item_fn(phase_total_w)

    -- Phase L button - always Ø, color indicates state
    local phase_l_on = phase_l > 0.5
    if phase_l_on then
        ctx:push_style_color(r.ImGui_Col_Button(), 0xCC4444FF)  -- Red when inverted
        ctx:push_style_color(r.ImGui_Col_Text(), 0xFFFFFFFF)
    else
        ctx:push_style_color(r.ImGui_Col_Button(), 0x555555FF)  -- Grey when normal
        ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAAAAFF)
    end
    if ctx:button("Ø##phase_l", phase_btn_size, phase_btn_size) then
        pcall(function() utility:set_param_normalized(2, phase_l_on and 0 or 1) end)
        interacted = true
    end
    ctx:pop_style_color(2)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip(phase_l_on and "Left Phase: Inverted" or "Left Phase: Normal")
    end

    ctx:same_line(0, phase_gap)

    -- Phase R button - always Ø, color indicates state
    local phase_r_on = phase_r > 0.5
    if phase_r_on then
        ctx:push_style_color(r.ImGui_Col_Button(), 0xCC4444FF)  -- Red when inverted
        ctx:push_style_color(r.ImGui_Col_Text(), 0xFFFFFFFF)
    else
        ctx:push_style_color(r.ImGui_Col_Button(), 0x555555FF)  -- Grey when normal
        ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAAAAFF)
    end
    if ctx:button("Ø##phase_r", phase_btn_size, phase_btn_size) then
        pcall(function() utility:set_param_normalized(3, phase_r_on and 0 or 1) end)
        interacted = true
    end
    ctx:pop_style_color(2)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip(phase_r_on and "Right Phase: Inverted" or "Right Phase: Normal")
    end

    -- Bottom padding
    ctx:spacing()
    ctx:spacing()
    ctx:spacing()

    return interacted
end

--- Draw the full sidebar column
function M.draw(ctx, fx, container, state_guid, sidebar_actual_w, is_sidebar_collapsed, cfg, opts, colors)
    local r = reaper
    local interacted = false

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
        -- NOTE: Mix and Delta controls are now in the device header, not here

        -- Gain/Pan/Phase controls from utility FX
        local utility = opts.utility
        if utility then
            local ok_g, gain_val = pcall(function() return utility:get_param(0) end)  -- actual dB value
            local ok_p, pan_val = pcall(function() return utility:get_param_normalized(1) end)

            -- Pan slider first (above fader)
            if ok_p then
                if draw_pan_control(ctx, utility, pan_val) then
                    interacted = true
                end
            end

            if ok_g then
                if draw_gain_fader_control(ctx, utility, gain_val) then
                    interacted = true
                end
            end

            -- Phase Invert controls (if enabled in settings)
            local config = require('lib.core.config')
            if config.get('show_phase_controls') then
                local ok_phase_l, phase_l = pcall(function() return utility:get_param_normalized(2) end)
                local ok_phase_r, phase_r = pcall(function() return utility:get_param_normalized(3) end)

                if ok_phase_l and ok_phase_r then
                    if draw_phase_controls(ctx, utility, phase_l, phase_r, center_item) then
                        interacted = true
                    end
                end
            end
        elseif not opts.is_bare then
            -- Missing utility warning (skip for bare devices - they don't need utilities)
            ctx:spacing()
            ctx:spacing()

            -- Warning icon and text
            local warning_text = "⚠️"
            local warning_text_w = r.ImGui_CalcTextSize(ctx.ctx, warning_text)
            center_item(warning_text_w)
            ctx:push_style_color(r.ImGui_Col_Text(), 0xFFAA00FF)  -- Orange/yellow
            ctx:text(warning_text)
            ctx:pop_style_color()

            ctx:spacing()

            local label = "Gain Utils"
            local label_w = r.ImGui_CalcTextSize(ctx.ctx, label)
            center_item(label_w)
            ctx:push_style_color(r.ImGui_Col_Text(), 0xFFAA00FF)
            ctx:text(label)
            ctx:pop_style_color()

            local label2 = "Missing"
            local label2_w = r.ImGui_CalcTextSize(ctx.ctx, label2)
            center_item(label2_w)
            ctx:push_style_color(r.ImGui_Col_Text(), 0xFFAA00FF)
            ctx:text(label2)
            ctx:pop_style_color()

            ctx:spacing()
            ctx:spacing()

            -- Restore button
            local btn_w = 70
            center_item(btn_w)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x4A3A1AFF)  -- Dark yellow/orange
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x6A5A3AFF)
            ctx:push_style_color(r.ImGui_Col_Text(), 0xFFFFAAFF)
            if ctx:button("Restore", btn_w, 24) then
                if opts.on_restore_utility and container then
                    opts.on_restore_utility(container)
                    interacted = true
                end
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Restore missing SideFX_Utility\nfor gain, pan, and phase controls")
            end
        end
        -- For bare devices with no utility: empty space (no warning, no controls)
    end

    return interacted
end

return M
