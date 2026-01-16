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

    local mod_links = opts and opts.mod_links
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

        -- Check if this param has modulation
        local link = mod_links and mod_links[param_idx]

        -- Check if link is disabled
        local link_key = fx_guid and (fx_guid .. "_" .. param_idx) or nil
        local is_link_disabled = link and link_key and state and state.link_disabled and state.link_disabled[link_key]

        -- Param name (truncated) - highlight if modulated, grey if disabled
        if is_link_disabled then
            ctx:push_style_color(imgui.Col.Text(), 0x666688FF)  -- Grey-blue for disabled modulation
        elseif link then
            ctx:push_style_color(imgui.Col.Text(), 0x88CCFFFF)  -- Blue for modulated
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
        local base_val = param_val  -- Default: actual current value
        if link then
            local baseline = link.baseline or 0
            base_val = baseline
        end
        
        -- Draw the slider with the BASELINE value if modulated, otherwise current value
        local display_val = link and base_val or param_val

        -- Check for user override first, otherwise auto-detect
        local unit_override = plugin_name and state_module.get_param_unit_override(plugin_name, param_idx)
        local unit_info = unit_override and unit_detector.get_unit_info(unit_override)
        local is_percentage = ok_fmt and param_formatted and param_formatted:match("%%$")

        local changed, new_val = false, display_val

        -- Handle switch type: render as toggle
        if unit_info and unit_info.is_switch then
            local is_on = display_val >= 0.5
            local toggled
            toggled, is_on = ctx:checkbox("##switch_" .. param_name .. "_" .. param_idx, is_on)
            if toggled then
                new_val = is_on and 1.0 or 0.0
                changed = true
            end
        -- Handle bipolar type: -50 to +50
        elseif unit_info and unit_info.is_bipolar then
            local bipolar_val = (display_val - 0.5) * 100  -- Convert 0-1 to -50 to +50
            local slider_changed, new_bipolar = drawing.slider_double_fine(ctx, "##slider_" .. param_name .. "_" .. param_idx, bipolar_val, -50, 50, "%+.0f", nil, 1)
            if slider_changed then
                new_val = (new_bipolar / 100) + 0.5  -- Convert back to 0-1
                changed = true
            end
        else
            -- Check if Shift is held for mod depth adjustment (not when link is disabled)
            local shift_held = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
            local is_mod_depth_mode = link and shift_held and not is_link_disabled

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
                        local link_key = fx_guid .. "_" .. param_idx
                        state.link_bipolar[link_key] = is_bipolar
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

                local depth_changed, new_depth_norm = drawing.slider_double_fine(ctx, "##depth_" .. param_name .. "_" .. param_idx, depth_norm, 0.0, 1.0, "##", nil, 1)

                -- Overlay depth text with mode indicator
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
            else
                -- Normal slider
                local slider_format, slider_mult
                if unit_info then
                    slider_format = unit_info.format
                    slider_mult = unit_info.display_mult
                    -- If using plugin format, hide slider text and overlay plugin value
                    if unit_info.use_plugin_format then
                        slider_format = "##"
                    end
                elseif is_percentage then
                    slider_format = "%.1f%%"
                    slider_mult = 100
                else
                    -- Non-percentage: hide slider text, overlay plugin's value
                    slider_format = "##"
                    slider_mult = 1
                end

                -- When modulated, hide slider text (we'll overlay baseline for computable units)
                if link then
                    slider_format = "##"
                end

                changed, new_val = drawing.slider_double_fine(ctx, "##slider_" .. param_name .. "_" .. param_idx, display_val, 0.0, 1.0, slider_format, nil, slider_mult)

            -- Overlay text on slider
            -- When modulated: show cached baseline formatted value (static)
            -- When not modulated: show plugin's current formatted value
            local overlay_text = nil
            if link then
                -- Prefer cached baseline formatted value (static, doesn't change with modulation)
                if link.baseline_formatted then
                    overlay_text = link.baseline_formatted
                else
                    -- Fallback: compute from baseline if we have a computable unit
                    local baseline = link.baseline or 0
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

            -- Tooltip showing modulation range when hovering (not when disabled)
            -- TODO: Show range in actual units (Hz, dB, etc.) instead of percentage.
            -- This requires caching formatted values for lower/upper bounds, which gets
            -- complicated when bipolar mode changes. Need to either:
            -- 1. Cache on-demand when tooltip is shown (temporarily set param, get format, restore)
            -- 2. Invalidate cache properly when baseline/scale/bipolar changes
            -- 3. Store formatted bounds when modulation link is created in modulator.lua
            if link and not is_link_disabled and r.ImGui_IsItemHovered(ctx.ctx) then
                local baseline = link.baseline or 0
                local scale = link.scale or 0.5
                local tooltip

                if link.is_bipolar then
                    -- Bipolar: centered on baseline, ± half range
                    local half_range = math.abs(scale) / 2
                    local lower = math.max(0, baseline - half_range) * 100
                    local upper = math.min(1, baseline + half_range) * 100
                    tooltip = string.format("Mod range: %.0f%% <-> %.0f%% (center: %.0f%%)",
                        lower, upper, baseline * 100)
                else
                    -- Unipolar: baseline to baseline+scale
                    local lower = math.max(0, math.min(baseline, baseline + scale)) * 100
                    local upper = math.min(1, math.max(baseline, baseline + scale)) * 100
                    tooltip = string.format("Mod range: %.0f%% -> %.0f%%", lower, upper)
                end
                ctx:set_tooltip(tooltip)
            end
            end  -- end of normal slider else branch
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
                ctx:text_disabled("Link to Modulator")
                ctx:separator()
                for i, mod in ipairs(modulators) do
                    local mod_name = "LFO " .. i
                    if ctx:menu_item(mod_name) then
                        -- Check modifier keys for link options
                        local shift = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Shift())
                        local ctrl = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Ctrl())
                        local alt = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Mod_Alt())

                        -- Determine depth: Shift=100%, Alt=inverted, default=50%
                        local depth = 0.5
                        if shift then depth = 1.0 end
                        if alt then depth = -depth end

                        -- Determine bipolar: Ctrl=bipolar
                        local is_bipolar = ctrl

                        local PARAM_OUTPUT = 3  -- slider4 output
                        local initial_value = fx:get_param_normalized(param_idx) or 0
                        local success = fx:create_param_link(mod, PARAM_OUTPUT, param_idx, depth)
                        if success then
                            -- Store baseline and initialize link state
                            local plink_prefix = string.format("param.%d.plink.", param_idx)
                            local mod_prefix = string.format("param.%d.mod.", param_idx)
                            fx:set_named_config_param(mod_prefix .. "baseline", tostring(initial_value))

                            -- Set offset for bipolar mode
                            local offset = is_bipolar and "-0.5" or "0"
                            fx:set_named_config_param(plink_prefix .. "offset", offset)

                            local link_key = fx_guid .. "_" .. param_idx
                            if state then
                                state.link_baselines = state.link_baselines or {}
                                state.link_baselines[link_key] = initial_value
                                state.link_bipolar = state.link_bipolar or {}
                                state.link_bipolar[link_key] = is_bipolar
                            end
                            interacted = true
                        end
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
            if link then
                -- If modulated, update baseline in both REAPER and UI state
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
        
        -- Draw modulation indicator overlay on top of slider
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
