--[[
Parameters Column Module - Draws device parameter grid with knobs
]]

local M = {}

--- Draw a single parameter cell (knob + name)
local function draw_param_cell(ctx, fx, param_idx)
    local r = reaper
    local drawing = require('lib.ui.drawing')
    local imgui = require('imgui')

    -- Safely get param info (FX might have been deleted)
    local ok_name, param_name = pcall(function() return fx:get_param_name(param_idx) end)
    local ok_val, param_val = pcall(function() return fx:get_param_normalized(param_idx) end)

    local interacted = false
    if ok_name and ok_val then
        param_val = param_val or 0
        local changed, new_val = drawing.draw_knob(ctx, "##" .. param_name .. "_" .. param_idx, param_val, 40)
        if changed then
            pcall(function() fx:set_param_normalized(param_idx, new_val) end)
            interacted = true
        end

        -- Param name below knob
        ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
        local truncated = param_name:sub(1, 12)
        if #param_name > 12 then truncated = truncated .. ".." end
        ctx:text(truncated)
        ctx:pop_style_color()

        if r.ImGui_IsItemHovered(ctx.ctx) and #param_name > 12 then
            ctx:set_tooltip(param_name)
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
        if r.ImGui_BeginTable(ctx.ctx, "params_" .. guid, num_columns, r.ImGui_TableFlags_SizingStretchSame()) then
            for col = 0, num_columns - 1 do
                r.ImGui_TableSetupColumn(ctx.ctx, "col" .. col, r.ImGui_TableColumnFlags_WidthStretch())
            end

            if draw_params_grid(ctx, fx, visible_params, visible_count, num_columns, params_per_column) then
                interacted = true
            end

            r.ImGui_EndTable(ctx.ctx)
        end
    else
        ctx:text_disabled("No parameters")
    end

    return interacted
end

return M
