--[[
Parameters Column Module - Draws device parameter grid with sliders
]]

local M = {}
local drawing = require('lib.ui.common.drawing')
local unit_detector = require('lib.utils.unit_detector')
local state_module = require('lib.core.state')

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

        -- Param name (truncated) - highlight if modulated
        if link then
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

        -- Horizontal slider (shorter width)
        ctx:push_style_color(imgui.Col.FrameBg(), 0x555555FF)
        ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x666666FF)
        ctx:push_style_color(imgui.Col.FrameBgActive(), 0x777777FF)
        ctx:push_style_color(imgui.Col.SliderGrab(), 0x5588AAFF)
        ctx:push_style_color(imgui.Col.SliderGrabActive(), 0x77AACCFF)

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
        local is_percentage = ok_fmt and param_formatted and param_formatted:match("%%$")

        local slider_format, slider_mult
        if unit_override then
            local unit_info = unit_detector.get_unit_info(unit_override)
            slider_format = unit_info.format
            slider_mult = unit_info.display_mult
        elseif is_percentage then
            slider_format = "%.1f%%"
            slider_mult = 100
        else
            -- Non-percentage: use space format, overlay plugin's value
            slider_format = " "
            slider_mult = 1
        end

        local changed, new_val = drawing.slider_double_fine(ctx, "##slider_" .. param_name .. "_" .. param_idx, display_val, 0.0, 1.0, slider_format, nil, slider_mult)

        -- For non-percentage values, overlay plugin's formatted value (with unit) on slider
        if not unit_override and not is_percentage and ok_fmt and param_formatted then
            local text_w = r.ImGui_CalcTextSize(ctx.ctx, param_formatted)
            local text_x = slider_x + (slider_w - text_w) / 2
            local slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
            local text_y = slider_y + (slider_h - r.ImGui_GetTextLineHeight(ctx.ctx)) / 2
            local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
            r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0xFFFFFFFF, param_formatted)
        end

        -- Show unit next to slider (override or detected)
        local unit_to_show = nil
        if unit_override then
            -- Show the overridden unit
            if unit_override ~= "percent" and unit_override ~= "linear" and unit_override ~= "linear100" then
                unit_to_show = unit_override
            end
        elseif ok_fmt and param_formatted then
            -- Show detected unit
            local detected = unit_detector.detect_unit(param_formatted)
            if detected and detected.unit ~= "percent" and detected.unit ~= "linear" and detected.unit ~= "linear100" then
                unit_to_show = detected.unit
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
            r.ImGui_DrawList_AddRectFilled(draw_list,
                range_x1, slider_y + slider_h - 3,
                range_x2, slider_y + slider_h,
                0x88CCFFAA)  -- Blue range indicator at bottom
            
            -- Draw moving indicator at current modulated value
            local indicator_x = slider_x + param_val * slider_w
            r.ImGui_DrawList_AddRectFilled(draw_list,
                indicator_x - 2, slider_y,
                indicator_x + 2, slider_y + slider_h,
                0xFFFFFFFF)  -- White indicator
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
