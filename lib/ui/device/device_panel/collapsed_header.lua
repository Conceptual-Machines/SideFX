--[[
Collapsed Device Header Module - Draws 2x2 button layout for collapsed device
Row 1: UI | ◀ (expand)
Row 2: ON | ×
]]

local M = {}

--- Draw collapsed device header with 2x2 button layout
function M.draw(ctx, fx, container, state_guid, enabled, device_collapsed, opts, colors)
    local r = reaper
    local drawing = require('lib.ui.common.drawing')
    local interacted = false

    -- === ROW 1: UI | ◀ ===
    -- UI button
    if drawing.draw_ui_icon(ctx, "##ui_collapsed_" .. state_guid, 24, 20, opts.icon_font) then
        pcall(function() fx:show(3) end)
        interacted = true
    end
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip("Open plugin UI")
    end

    -- Expand button
    ctx:same_line()
    ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
    ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
    if ctx:button("◀##expand_collapsed_" .. state_guid, 20, 20) then
        device_collapsed[state_guid] = false
        interacted = true
    end
    ctx:pop_style_color(3)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip("Expand device controls")
    end

    -- === ROW 2: ON | × ===
    -- ON/OFF toggle
    if drawing.draw_on_off_circle(ctx, "##on_off_collapsed_" .. state_guid, enabled, 24, 20, colors.bypass_on, colors.bypass_off) then
        container:set_enabled(not enabled)
        interacted = true
    end
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip(enabled and "Bypass" or "Enable")
    end

    -- Delete button
    ctx:same_line()
    ctx:push_style_color(r.ImGui_Col_Button(), 0x663333FF)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x884444FF)
    if ctx:button("×##delete_collapsed_" .. state_guid, 20, 20) then
        if opts.on_delete then
            opts.on_delete(fx)
        else
            fx:delete()
        end
        interacted = true
    end
    ctx:pop_style_color(2)
    if r.ImGui_IsItemHovered(ctx.ctx) then
        ctx:set_tooltip("Delete device")
    end

    return interacted
end

return M
