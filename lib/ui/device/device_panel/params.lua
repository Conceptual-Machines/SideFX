--[[
Parameters Column Module - Draws device parameter grid with sliders
]]

local M = {}
local drawing = require('lib.ui.common.drawing')
local unit_detector = require('lib.utils.unit_detector')
local state_module = require('lib.core.state')
local modulator_module = require('lib.modulator.modulator')
local bake_module = require('lib.modulator.modulator_bake')

--- Draw a single parameter cell (label + slider + modulation overlay)
-- @param ctx ImGui context
-- @param fx The FX object
-- @param param_idx Parameter index
-- @param opts Table with mod_links, state, fx_guid, plugin_name
local function draw_param_cell(ctx, fx, param_idx, opts)
    local r = reaper
    local imgui = require('imgui')

    -- mod_links = filtered links for selected modulator only (for UI indicators)
    -- all_mod_links = all links regardless of modulator (for baseline values)
    local mod_links = opts and opts.mod_links
    local all_mod_links = opts and opts.all_mod_links or mod_links
    local state = opts and opts.state
    local fx_guid = opts and opts.fx_guid
    local plugin_name = opts and opts.plugin_name

    -- Safely get param info (FX might have been deleted)
    local ok_name, param_name = pcall(function() return fx:get_param_name(param_idx) end)
    local ok_val, param_val = pcall(function() return fx:get_param_normalized(param_idx) end)
    local ok_fmt, param_formatted = pcall(function() return fx:get_formatted_param_value(param_idx) end)

    local interacted = false
    if ok_name and ok_val then
        param_val = param_val or 0

        -- Check if this param has modulation from the SELECTED modulator (for UI indicators)
        local link = mod_links and mod_links[param_idx]
        -- Check if this param has modulation from ANY modulator (for baseline value)
        local any_link = all_mod_links and all_mod_links[param_idx]

        -- Check if link is disabled
        local link_key = fx_guid and (fx_guid .. "_" .. param_idx) or nil
        local is_link_disabled = link and link_key and state and state.link_disabled and state.link_disabled[link_key]

        -- Param name (truncated) - highlight if modulated by SELECTED LFO, grey if disabled
        if is_link_disabled then
            ctx:push_style_color(imgui.Col.Text(), 0x666688FF)  -- Grey-blue for disabled modulation
        elseif link then
            ctx:push_style_color(imgui.Col.Text(), 0x88CCFFFF)  -- Blue for modulated by selected LFO
        else
            ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
        end
        local truncated = param_name:sub(1, 12)
        if #param_name > 12 then truncated = truncated .. ".." end
        ctx:text(truncated)
        ctx:pop_style_color()

        if r.ImGui_IsItemHovered(ctx.ctx) and #param_name > 12 then
            ctx:set_tooltip(param_name)
        end

        -- Horizontal slider (shorter width) - grey out if link is disabled
        if is_link_disabled then
            ctx:push_style_color(imgui.Col.FrameBg(), 0x3A3A44FF)
            ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x444450FF)
            ctx:push_style_color(imgui.Col.FrameBgActive(), 0x4A4A55FF)
            ctx:push_style_color(imgui.Col.SliderGrab(), 0x556677FF)
            ctx:push_style_color(imgui.Col.SliderGrabActive(), 0x667788FF)
        else
            ctx:push_style_color(imgui.Col.FrameBg(), 0x555555FF)
            ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x666666FF)
            ctx:push_style_color(imgui.Col.FrameBgActive(), 0x777777FF)
            ctx:push_style_color(imgui.Col.SliderGrab(), 0x5588AAFF)
            ctx:push_style_color(imgui.Col.SliderGrabActive(), 0x77AACCFF)
        end

        -- Make slider thinner vertically
        ctx:push_style_var(imgui.StyleVar.FramePadding(), 2, 1)  -- x=2, y=1 (thin slider bar)

        -- Make slider shorter horizontally - 80% of available width
        local avail_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
        local slider_w = avail_w * 0.8
        ctx:set_next_item_width(slider_w)
        
        -- Get slider position BEFORE drawing
        local slider_x, slider_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
        
        -- Unipolar uses: baseline + (lfo * scale)
        -- baseline = initial value, scale = depth
        -- Use any_link (from ANY modulator) for baseline so slider stays stable when switching LFOs
        local base_val = param_val  -- Default: actual current value
        if any_link then
            local baseline = any_link.baseline or 0
            base_val = baseline
        end

        -- Draw the slider with the BASELINE value if modulated by ANY LFO, otherwise current value
        local display_val = any_link and base_val or param_val

        -- Check for user override first, otherwise auto-detect
        local unit_override, range_min, range_max
        if plugin_name then
            unit_override, range_min, range_max = state_module.get_param_unit_override(plugin_name, param_idx)
        end
        local unit_info = unit_override and unit_detector.get_unit_info(unit_override, range_min, range_max)
        local is_percentage = ok_fmt and param_formatted and param_formatted:match("%%$")

        local changed, new_val = false, display_val

        -- Check if Shift is held for mod depth adjustment (applies to ALL parameter types)
        -- Only activate when mouse is hovering over this slider's area
        local shift_held = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
        local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx.ctx)
        local slider_h_check = r.ImGui_GetFrameHeight(ctx.ctx)
        local is_hovering_slider = mouse_x >= slider_x and mouse_x <= slider_x + slider_w
                               and mouse_y >= slider_y and mouse_y <= slider_y + slider_h_check
        local is_mod_depth_mode = link and shift_held and is_hovering_slider and not is_link_disabled

        if is_mod_depth_mode then
            -- Shift+drag: adjust modulation depth instead of parameter value
            local current_depth = link.scale or 0.5
            local depth_norm = (current_depth + 1) / 2  -- Convert -1..1 to 0..1
            local is_bipolar = link.is_bipolar or false

            -- Check for Ctrl press to toggle bipolar (check both left and right Ctrl)
            local ctrl_pressed = r.ImGui_IsKeyPressed(ctx.ctx, r.ImGui_Key_LeftCtrl())
                or r.ImGui_IsKeyPressed(ctx.ctx, r.ImGui_Key_RightCtrl())
            if ctrl_pressed then
                -- Toggle bipolar mode
                is_bipolar = not is_bipolar
                local plink_prefix = string.format("param.%d.plink.", param_idx)
                local offset = is_bipolar and "-0.5" or "0"
                fx:set_named_config_param(plink_prefix .. "offset", offset)

                -- Update state
                if state and fx_guid then
                    state.link_bipolar = state.link_bipolar or {}
                    local link_key_local = fx_guid .. "_" .. param_idx
                    state.link_bipolar[link_key_local] = is_bipolar
                end
                interacted = true
            end

            -- Draw depth slider with blue styling (purple tint if bipolar)
            local frame_bg = is_bipolar and 0x4A2A6AFF or 0x2A4A6AFF
            local frame_hover = is_bipolar and 0x5A3A7AFF or 0x3A5A7AFF
            local frame_active = is_bipolar and 0x6A4A8AFF or 0x4A6A8AFF
            local grab_color = is_bipolar and 0xCC88FFFF or 0x88CCFFFF
            local grab_active = is_bipolar and 0xDDAAFFFF or 0xAADDFFFF

            ctx:push_style_color(r.ImGui_Col_FrameBg(), frame_bg)
            ctx:push_style_color(r.ImGui_Col_FrameBgHovered(), frame_hover)
            ctx:push_style_color(r.ImGui_Col_FrameBgActive(), frame_active)
            ctx:push_style_color(r.ImGui_Col_SliderGrab(), grab_color)
            ctx:push_style_color(r.ImGui_Col_SliderGrabActive(), grab_active)

            local depth_changed, new_depth_norm, depth_in_text_mode = drawing.slider_double_fine(ctx, "##depth_" .. param_name .. "_" .. param_idx, depth_norm, 0.0, 1.0, "##", nil, 1)

            -- Overlay depth text with mode indicator (only when not in text input mode)
            if not depth_in_text_mode then
                local depth_display = current_depth * 100
                local mode_indicator = is_bipolar and "B" or "U"
                local depth_text = string.format("%s %.0f%%", mode_indicator, depth_display)
                local text_w = r.ImGui_CalcTextSize(ctx.ctx, depth_text)
                local text_x = slider_x + (slider_w - text_w) / 2
                local slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
                local text_y = slider_y + (slider_h - r.ImGui_GetTextLineHeight(ctx.ctx)) / 2
                local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                local text_color = is_bipolar and 0xCC88FFFF or 0x88CCFFFF
                r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, depth_text)
            end

            ctx:pop_style_color(5)

            if depth_changed then
                local new_depth = new_depth_norm * 2 - 1  -- Convert 0..1 to -1..1
                local plink_prefix = string.format("param.%d.plink.", param_idx)
                fx:set_named_config_param(plink_prefix .. "scale", tostring(new_depth))
                interacted = true
            end

            -- Tooltip for depth mode
            if r.ImGui_IsItemHovered(ctx.ctx) then
                local mode_name = is_bipolar and "Bipolar" or "Unipolar"
                ctx:set_tooltip("Mod depth: " .. string.format("%.0f%%", current_depth * 100) .. " (" .. mode_name .. ")\nCtrl: Toggle bipolar\nRelease Shift for normal control")
            end
        -- Handle switch type: render as toggle
        elseif unit_info and unit_info.is_switch then
            local is_on = display_val >= 0.5
            local toggled
            toggled, is_on = ctx:checkbox("##switch_" .. param_name .. "_" .. param_idx, is_on)
            if toggled then
                new_val = is_on and 1.0 or 0.0
                changed = true
            end
        -- Handle bipolar type: range centered around 0
        elseif unit_info and unit_info.is_bipolar then
            -- Get range from unit_info or calculate from display_mult
            local half_range = unit_info.display_mult / 2
            local min_display = unit_info.min or -half_range
            local max_display = unit_info.max or half_range
            local range = max_display - min_display
            local bipolar_val = min_display + display_val * range  -- Convert 0-1 to min..max
            local slider_format = unit_info.format or "%+.0f"
            local slider_changed, new_bipolar = drawing.slider_double_fine(ctx, "##slider_" .. param_name .. "_" .. param_idx, bipolar_val, min_display, max_display, slider_format, nil, 1, nil, true)
            if slider_changed then
                new_val = (new_bipolar - min_display) / range  -- Convert back to 0-1
                changed = true
            end
        else
            -- Normal slider
            local slider_format, slider_mult
            local text_input_enabled = false  -- Only enable for user-defined units or percentage

            if unit_info then
                slider_format = unit_info.format
                slider_mult = unit_info.display_mult
                -- If using plugin format, hide slider text and overlay plugin value
                if unit_info.use_plugin_format then
                    slider_format = "##"
                end
                -- Enable text input for user-defined units (they explicitly set the conversion)
                text_input_enabled = true
            elseif is_percentage then
                slider_format = "%.1f%%"
                slider_mult = 100
                text_input_enabled = true  -- Percentage has known conversion
            else
                -- Non-percentage: hide slider text, overlay plugin's value
                slider_format = "##"
                slider_mult = 1
                text_input_enabled = false  -- No conversion available
            end

            -- When modulated by ANY LFO, hide slider text (we'll overlay baseline for computable units)
            if any_link then
                slider_format = "##"
            end

            local slider_in_text_mode
            changed, new_val, slider_in_text_mode = drawing.slider_double_fine(ctx, "##slider_" .. param_name .. "_" .. param_idx, display_val, 0.0, 1.0, slider_format, nil, slider_mult, nil, text_input_enabled)

            -- Overlay text on slider (only when not in text input mode)
            -- When linked by ANY LFO: show static baseline, but show live value while dragging
            -- When not linked: show plugin's current formatted value
            if not slider_in_text_mode then
                local overlay_text = nil
                local is_dragging = r.ImGui_IsItemActive(ctx.ctx)
                if any_link then
                    if is_dragging and ok_fmt and param_formatted then
                        -- User is dragging: show live value as they adjust baseline
                        overlay_text = param_formatted
                    elseif any_link.baseline_formatted then
                        -- Not dragging: show cached baseline formatted value (static)
                        overlay_text = any_link.baseline_formatted
                    else
                        -- Fallback: compute from baseline if we have a computable unit
                        local baseline = any_link.baseline or 0
                        if unit_info and not unit_info.use_plugin_format then
                            local display_mult = unit_info.display_mult or 1
                            local fmt = unit_info.format or "%.1f"
                            overlay_text = string.format(fmt, baseline * display_mult)
                        else
                            -- Last resort: show as percentage
                            overlay_text = string.format("%.1f%%", baseline * 100)
                        end
                    end
                elseif ok_fmt and param_formatted then
                    -- Not modulated: show plugin's formatted value
                    overlay_text = param_formatted
                end

                if overlay_text then
                    local text_w = r.ImGui_CalcTextSize(ctx.ctx, overlay_text)
                    local text_x = slider_x + (slider_w - text_w) / 2
                    local slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
                    local text_y = slider_y + (slider_h - r.ImGui_GetTextLineHeight(ctx.ctx)) / 2
                    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0xFFFFFFFF, overlay_text)
                end
            end
        end

        -- Right-click context menu for parameter linking
        local modulators = opts and opts.modulators or {}
        local track = opts and opts.track
        if ctx:begin_popup_context_item("param_ctx_" .. param_idx .. "_" .. (fx_guid or "")) then
            -- If parameter has a link, show Remove, Disable, and Bake options first
            if link then
                local link_key = fx_guid and (fx_guid .. "_" .. param_idx) or nil
                local is_disabled = link_key and state and state.link_disabled and state.link_disabled[link_key]
                local disable_label = is_disabled and "Enable Link" or "Disable Link"

                if ctx:menu_item(disable_label) then
                    local plink_prefix = string.format("param.%d.plink.", param_idx)
                    if is_disabled then
                        -- Re-enable: restore saved scale
                        local saved = state.link_saved_scale and state.link_saved_scale[link_key] or 0.5
                        fx:set_named_config_param(plink_prefix .. "scale", tostring(saved))
                        state.link_disabled[link_key] = false
                    else
                        -- Disable: save current scale, set to 0
                        state.link_saved_scale = state.link_saved_scale or {}
                        state.link_saved_scale[link_key] = link.scale or 0.5
                        fx:set_named_config_param(plink_prefix .. "scale", "0")
                        state.link_disabled = state.link_disabled or {}
                        state.link_disabled[link_key] = true
                    end
                    state_module.save_link_scales()
                    interacted = true
                end
                if ctx:menu_item("Remove Link") then
                    modulator_module.remove_param_link(fx, param_idx)
                    -- Clear state
                    if state and fx_guid then
                        if state.link_baselines then state.link_baselines[link_key] = nil end
                        if state.link_bipolar then state.link_bipolar[link_key] = nil end
                        if state.baseline_formatted then state.baseline_formatted[link_key] = nil end
                        if state.link_disabled then state.link_disabled[link_key] = nil end
                        if state.link_saved_scale then state.link_saved_scale[link_key] = nil end
                    end
                    interacted = true
                end
                if ctx:menu_item("Bake to Automation") then
                    -- Find the modulator from the modulators list (first one that matches link.effect)
                    local modulator = nil
                    for _, mod in ipairs(modulators) do
                        -- Use first available modulator for now
                        -- TODO: match by link.effect index if multiple modulators
                        modulator = mod
                        break
                    end

                    if modulator and state then
                        -- Open bake modal like the sidebar does
                        local config = require('lib.core.config')
                        if config.get('bake_show_range_picker') then
                            -- Open bake modal for this specific link
                            state.bake_modal = state.bake_modal or {}
                            state.bake_modal[fx_guid] = {
                                open = true,
                                link = { param_idx = param_idx, scale = link.scale, baseline = link.baseline },
                                modulator = modulator,
                                fx = fx
                            }
                        else
                            -- Use default range directly
                            local bake_options = {
                                range_mode = config.get('bake_default_range_mode'),
                                disable_link = config.get('bake_disable_link_after')
                            }
                            local current_scale = link.scale
                            local ok, result, msg = pcall(function()
                                return bake_module.bake_to_automation(track, modulator, fx, param_idx, bake_options)
                            end)
                            if ok and result then
                                reaper.ShowConsoleMsg("SideFX: " .. (msg or "Baked") .. "\n")
                                if bake_options.disable_link then
                                    state.link_saved_scale = state.link_saved_scale or {}
                                    state.link_disabled = state.link_disabled or {}
                                    state.link_saved_scale[link_key] = current_scale
                                    state.link_disabled[link_key] = true
                                    state_module.save_link_scales()
                                end
                            elseif not ok then
                                reaper.ShowConsoleMsg("SideFX Bake Error: " .. tostring(result) .. "\n")
                            else
                                reaper.ShowConsoleMsg("SideFX: " .. tostring(msg or "No automation created") .. "\n")
                            end
                        end
                    end
                    interacted = true
                end
                ctx:separator()
            end

            -- Link to modulator options
            if #modulators > 0 then
                -- Get selected LFO slot (0-based index)
                local state_guid = opts and opts.state_guid
                local selected_lfo_slot = state_guid and state and state.expanded_mod_slot and state.expanded_mod_slot[state_guid]

                -- Find which modulator this param is linked to (if any)
                local linked_mod_idx = nil
                if link and link.effect ~= nil then
                    linked_mod_idx = link.effect
                end

                -- Helper function to create a link
                local function create_link_to_mod(mod)
                    local shift = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
                    local ctrl = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Ctrl())
                    local alt = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Alt())

                    local depth = 0.5
                    if shift then depth = 1.0 end
                    if alt then depth = -depth end
                    local is_bipolar = ctrl

                    local PARAM_OUTPUT = 3
                    local initial_value = fx:get_param_normalized(param_idx) or 0
                    local success = fx:create_param_link(mod, PARAM_OUTPUT, param_idx, depth)
                    if success then
                        local plink_prefix = string.format("param.%d.plink.", param_idx)
                        local mod_prefix = string.format("param.%d.mod.", param_idx)
                        fx:set_named_config_param(mod_prefix .. "baseline", tostring(initial_value))
                        local offset = is_bipolar and "-0.5" or "0"
                        fx:set_named_config_param(plink_prefix .. "offset", offset)

                        local link_key = fx_guid .. "_" .. param_idx
                        if state then
                            state.link_baselines = state.link_baselines or {}
                            state.link_baselines[link_key] = initial_value
                            state.link_bipolar = state.link_bipolar or {}
                            state.link_bipolar[link_key] = is_bipolar
                        end
                        return true
                    end
                    return false
                end

                -- Show currently selected LFO at top (if one is selected)
                if selected_lfo_slot ~= nil then
                    local selected_mod = modulators[selected_lfo_slot + 1]  -- Convert to 1-based
                    if selected_mod then
                        local is_linked = (linked_mod_idx == selected_lfo_slot)
                        local label = is_linked and "● LFO " or "Link to LFO "
                        label = label .. (selected_lfo_slot + 1)

                        if is_linked then
                            r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_Text(), 0x88CCFFFF)
                        end

                        if ctx:menu_item(label) then
                            if create_link_to_mod(selected_mod) then
                                interacted = true
                            end
                        end

                        if is_linked then
                            r.ImGui_PopStyleColor(ctx.ctx)
                        end
                    end
                end

                -- Show other LFOs in submenu (if more than one modulator)
                if #modulators > 1 then
                    if ctx:begin_menu("Other LFOs") then
                        for i, mod in ipairs(modulators) do
                            local mod_slot_idx = i - 1
                            -- Skip the selected one (already shown above)
                            if mod_slot_idx ~= selected_lfo_slot then
                                local is_linked = (linked_mod_idx == mod_slot_idx)
                                local label = is_linked and ("● LFO " .. i) or ("LFO " .. i)

                                if is_linked then
                                    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_Text(), 0x88CCFFFF)
                                end

                                if ctx:menu_item(label) then
                                    if create_link_to_mod(mod) then
                                        interacted = true
                                    end
                                end

                                if is_linked then
                                    r.ImGui_PopStyleColor(ctx.ctx)
                                end
                            end
                        end
                        ctx:end_menu()
                    end
                end

                ctx:separator()
                ctx:text_disabled("Shift: 100%  Ctrl: Bipolar  Alt: Invert")
            else
                ctx:text_disabled("No modulators")
                ctx:text_disabled("Add LFO first")
            end
            ctx:end_popup()
        end

        -- Show unit next to slider (override or detected) - unless hide_label is set
        local unit_to_show = nil
        local hide_label = unit_info and unit_info.hide_label
        if not hide_label then
            if unit_override then
                -- Show the overridden unit (skip certain types)
                if unit_override ~= "percent" and unit_override ~= "linear" and unit_override ~= "linear100"
                   and unit_override ~= "switch" and unit_override ~= "bipolar" and unit_override ~= "plugin" then
                    unit_to_show = unit_override
                end
            elseif ok_fmt and param_formatted then
                -- Show detected unit
                local detected = unit_detector.detect_unit(param_formatted)
                if detected and detected.unit ~= "percent" and detected.unit ~= "linear" and detected.unit ~= "linear100" then
                    unit_to_show = detected.unit
                end
            end
        end

        if unit_to_show then
            ctx:same_line()
            ctx:push_style_color(imgui.Col.Text(), 0x88AACCFF)
            ctx:text(unit_to_show)
            ctx:pop_style_color()
        end
        if changed then
            if any_link then
                -- If modulated by ANY LFO, update baseline in both REAPER and UI state
                local mod_prefix = string.format("param.%d.mod.", param_idx)
                fx:set_named_config_param(mod_prefix .. "baseline", tostring(new_val))
                -- Also update UI state so restore works correctly
                if state and fx_guid then
                    state.link_baselines = state.link_baselines or {}
                    local link_key = fx_guid .. "_" .. param_idx
                    state.link_baselines[link_key] = new_val
                end
            else
                pcall(function() fx:set_param_normalized(param_idx, new_val) end)
            end
            interacted = true
        end

        -- Draw modulation indicator overlay on top of slider (only for SELECTED LFO's links)
        if link then
            local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
            local slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
            
            local baseline = link.baseline or 0
            local offset = link.offset or 0
            local scale = link.scale or 0.5
            
            -- Calculate visualization range based on mode
            local range_start, range_end
            if link.is_bipolar then
                -- Bipolar: centered around baseline, ±|scale|/2
                local half_range = math.abs(scale) / 2
                range_start = baseline - half_range
                range_end = baseline + half_range
            else
                -- Unipolar: from baseline, direction based on scale sign
                range_start = baseline
                range_end = baseline + scale
            end
            local min_mod = math.max(0, math.min(range_start, range_end))
            local max_mod = math.min(1, math.max(range_start, range_end))
            local range_x1 = slider_x + min_mod * slider_w
            local range_x2 = slider_x + max_mod * slider_w
            -- Use greyed out colors if link is disabled
            local range_color = is_link_disabled and 0x55667766 or 0x88CCFFAA
            local indicator_color = is_link_disabled and 0x888888FF or 0xFFFFFFFF

            r.ImGui_DrawList_AddRectFilled(draw_list,
                range_x1, slider_y + slider_h - 3,
                range_x2, slider_y + slider_h,
                range_color)  -- Range indicator at bottom

            -- Draw moving indicator at current modulated value
            local indicator_x = slider_x + param_val * slider_w
            r.ImGui_DrawList_AddRectFilled(draw_list,
                indicator_x - 2, slider_y,
                indicator_x + 2, slider_y + slider_h,
                indicator_color)  -- Value indicator
        end

        ctx:pop_style_var(1)
        ctx:pop_style_color(5)
    end

    return interacted
end

--- Draw parameter grid (rows × columns)
-- @param opts Table with mod_links, state, fx_guid
local function draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column, opts)
    local r = reaper
    local interacted = false

    for row = 0, params_per_column - 1 do
        r.ImGui_TableNextRow(ctx.ctx)

        for col = 0, num_columns - 1 do
            local visible_idx = col * params_per_column + row + 1  -- +1 for Lua 1-based

            r.ImGui_TableSetColumnIndex(ctx.ctx, col)

            if visible_idx <= visible_count then
                local param_idx = visible_params[visible_idx]
                if draw_param_cell(ctx, fx, param_idx, opts) then
                    interacted = true
                end
            end
        end
    end

    return interacted
end

--- Draw device parameters column
-- @param opts Table with mod_links, state, fx_guid
function M.draw(ctx, fx, guid, visible_params, visible_count, num_columns, params_per_column, opts)
    local r = reaper
    local interacted = false

    if visible_count > 0 then
        -- Use nested table for parameter columns
        -- Wrap in pcall to handle context corruption gracefully
        local ok, err = pcall(function()
        if r.ImGui_BeginTable(ctx.ctx, "params_" .. guid, num_columns, r.ImGui_TableFlags_SizingStretchSame()) then
            for col = 0, num_columns - 1 do
                r.ImGui_TableSetupColumn(ctx.ctx, "col" .. col, r.ImGui_TableColumnFlags_WidthStretch())
            end

            if draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column, opts) then
                interacted = true
            end

            r.ImGui_EndTable(ctx.ctx)
            end
        end)
        
        if not ok then
            r.ShowConsoleMsg("Error rendering parameter table: " .. tostring(err) .. "\n")
            ctx:text_disabled("Error displaying parameters")
        end
    else
        ctx:text_disabled("No parameters")
    end

    return interacted
end

return M
