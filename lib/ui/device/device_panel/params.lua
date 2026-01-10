--[[
Parameters Column Module - Draws device parameter grid with sliders
]]

local M = {}

--- Draw a single parameter cell (label + slider + modulation overlay)
-- @param ctx ImGui context
-- @param fx The FX object
-- @param param_idx Parameter index
-- @param mod_links Table of param_idx -> link_info for modulated params (optional)
local function draw_param_cell(ctx, fx, param_idx, mod_links)
    local r = reaper
    local imgui = require('imgui')

    -- Safely get param info (FX might have been deleted)
    local ok_name, param_name = pcall(function() return fx:get_param_name(param_idx) end)
    local ok_val, param_val = pcall(function() return fx:get_param_normalized(param_idx) end)
    local ok_fmt, param_formatted = pcall(function() return fx:get_param_formatted(param_idx) end)

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
        
        -- Calculate base/center value for slider handle
        -- Unipolar: base is at offset (left edge of range)
        -- Bipolar: base is at offset + scale/2 (center of range)
        local base_val = param_val  -- Default: actual current value
        if link then
            local offset = link.offset or 0
            local scale = link.scale or 1
            if link.is_bipolar then
                -- Bipolar: center is at offset + scale/2
                base_val = offset + scale / 2
            else
                -- Unipolar: base is at offset
                base_val = offset
            end
        end
        
        -- Draw the slider with the BASE value if modulated, otherwise current value
        local display_val = link and base_val or param_val
        local changed, new_val = ctx:slider_double("##slider_" .. param_name .. "_" .. param_idx, display_val, 0.0, 1.0, "")
        if changed then
            if link then
                -- If modulated, update the base position by adjusting offset
                local plink_prefix = string.format("param.%d.plink.", param_idx)
                local offset = link.offset or 0
                local scale = link.scale or 1
                if link.is_bipolar then
                    -- Bipolar: new_offset = new_center - scale/2
                    local new_offset = new_val - scale / 2
                    fx:set_named_config_param(plink_prefix .. "offset", tostring(new_offset))
                else
                    -- Unipolar: offset = base
                    fx:set_named_config_param(plink_prefix .. "offset", tostring(new_val))
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
            
            local offset = link.offset or 0
            local scale = link.scale or 1
            
            -- Draw modulation range hint (blue bar at bottom) - draw FIRST so indicator is on top
            local min_mod = math.max(0, math.min(offset, offset + scale))
            local max_mod = math.min(1, math.max(offset, offset + scale))
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
            
            -- DEBUG: Show values as tooltip on hover
            if r.ImGui_IsItemHovered(ctx.ctx) then
                local tooltip = string.format("offset=%.3f scale=%.3f\ncurrent=%.3f base=%.3f\nbipolar=%s", 
                    offset, scale, param_val, base_val, link.is_bipolar and "yes" or "no")
                ctx:set_tooltip(tooltip)
            end
        end

        ctx:pop_style_var(1)
        ctx:pop_style_color(5)

        -- Value label (centered below slider)
        if ok_fmt then
            ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
            local val_text = param_formatted
            local text_w = r.ImGui_CalcTextSize(ctx.ctx, val_text)
            local avail_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
            if avail_w > text_w then
                r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (avail_w - text_w) / 2)
            end
            ctx:text(val_text)
            ctx:pop_style_color()
        end
    end

    return interacted
end

--- Draw parameter grid (rows × columns)
-- @param mod_links Table of param_idx -> link_info for modulated params (optional)
local function draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column, mod_links)
    local r = reaper
    local interacted = false

    for row = 0, params_per_column - 1 do
        r.ImGui_TableNextRow(ctx.ctx)

        for col = 0, num_columns - 1 do
            local visible_idx = col * params_per_column + row + 1  -- +1 for Lua 1-based

            r.ImGui_TableSetColumnIndex(ctx.ctx, col)

            if visible_idx <= visible_count then
                local param_idx = visible_params[visible_idx]
                if draw_param_cell(ctx, fx, param_idx, mod_links) then
                    interacted = true
                end
            end
        end
    end

    return interacted
end

--- Draw device parameters column
-- @param opts.mod_links Table of param_idx -> link_info for modulated params (optional)
function M.draw(ctx, fx, guid, visible_params, visible_count, num_columns, params_per_column, opts)
    local r = reaper
    local interacted = false
    local mod_links = opts and opts.mod_links

    if visible_count > 0 then
        -- Use nested table for parameter columns
        -- Wrap in pcall to handle context corruption gracefully
        local ok, err = pcall(function()
        if r.ImGui_BeginTable(ctx.ctx, "params_" .. guid, num_columns, r.ImGui_TableFlags_SizingStretchSame()) then
            for col = 0, num_columns - 1 do
                r.ImGui_TableSetupColumn(ctx.ctx, "col" .. col, r.ImGui_TableColumnFlags_WidthStretch())
            end

            if draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column, mod_links) then
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
