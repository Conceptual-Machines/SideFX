--[[
Parameters Column Module - Draws device parameter grid with sliders
]]

local M = {}

--- Draw a single parameter cell (label + slider)
local function draw_param_cell(ctx, fx, param_idx)
    local r = reaper
    local imgui = require('imgui')

    -- Safely get param info (FX might have been deleted)
    local ok_name, param_name = pcall(function() return fx:get_param_name(param_idx) end)
    local ok_val, param_val = pcall(function() return fx:get_param_normalized(param_idx) end)
    local ok_fmt, param_formatted = pcall(function() return fx:get_param_formatted(param_idx) end)

    local interacted = false
    if ok_name and ok_val then
        param_val = param_val or 0

        -- Param name (truncated)
        ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
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
        local changed, new_val = ctx:slider_double("##slider_" .. param_name .. "_" .. param_idx, param_val, 0.0, 1.0, "")
        if changed then
            pcall(function() fx:set_param_normalized(param_idx, new_val) end)
            interacted = true
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
local function draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column)
    local r = reaper
    local interacted = false

    for row = 0, params_per_column - 1 do
        r.ImGui_TableNextRow(ctx.ctx)

        for col = 0, num_columns - 1 do
            local visible_idx = col * params_per_column + row + 1  -- +1 for Lua 1-based

            r.ImGui_TableSetColumnIndex(ctx.ctx, col)

            if visible_idx <= visible_count then
                local param_idx = visible_params[visible_idx]
                if draw_param_cell(ctx, fx, param_idx) then
                    interacted = true
                end
            end
        end
    end

    return interacted
end

--- Draw device parameters column
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

            if draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column) then
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
