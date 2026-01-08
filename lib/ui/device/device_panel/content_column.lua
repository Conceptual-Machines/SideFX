--[[
Content Column Module - Draws device params or collapsed vertical stack
]]

local M = {}

--- Draw content column (expanded: params, collapsed: name + gain/pan stack)
function M.draw(ctx, is_device_collapsed, params_column, fx, guid, visible_params, visible_count, num_columns, params_per_column, opts, name, fx_naming, draw_sidebar_column, container, state_guid, gain_pan_w, is_sidebar_collapsed, cfg, colors)
    local r = reaper
    local interacted = false

    -- Content Column 2: Device params or collapsed view
    r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
    if not is_device_collapsed then
        -- Expanded: show device params
        if params_column.draw(ctx, fx, guid, visible_params, visible_count, num_columns, params_per_column, opts) then
            interacted = true
        end
    else
        -- Collapsed: show vertical stack (name | gain/pan) - buttons are in header
        -- Row 1: Device name
        ctx:push_style_color(r.ImGui_Col_Text(), 0xCCCCCCFF)
        local display_name = fx_naming.truncate(name, 30)
        ctx:text(display_name)
        ctx:pop_style_color()

        -- Row 2: Gain/Pan controls (in same column when collapsed)
        if draw_sidebar_column(ctx, fx, container, state_guid, gain_pan_w, is_sidebar_collapsed, cfg, opts, colors) then
            interacted = true
        end
    end

    return interacted
end

return M
