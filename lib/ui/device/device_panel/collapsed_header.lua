--[[
Collapsed Device Header Module - Draws 2x2 button layout for collapsed device
Row 1: UI | ◀ (expand)
Row 2: ON | ×
]]

local M = {}

--- Draw collapsed device header with 2x2 button layout (centered)
function M.draw(ctx, fx, container, state_guid, enabled, device_collapsed, opts, colors)
    local r = reaper
    local drawing = require('lib.ui.common.drawing')
    local imgui = require('imgui')
    local interacted = false

    local btn_size = 20

    -- Use a table to center the 2x2 grid
    if ctx:begin_table("collapsed_btns_" .. state_guid, 2, r.ImGui_TableFlags_SizingFixedFit()) then
        ctx:table_setup_column("col1", imgui.TableColumnFlags.WidthFixed(), btn_size + 4)
        ctx:table_setup_column("col2", imgui.TableColumnFlags.WidthFixed(), btn_size + 4)

        -- === ROW 1: UI | ◀ ===
        ctx:table_next_row()

        -- UI button
        ctx:table_set_column_index(0)
        if drawing.draw_ui_icon(ctx, "##ui_collapsed_" .. state_guid, btn_size, btn_size, opts.icon_font) then
            pcall(function() fx:show(3) end)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Open plugin UI")
        end

        -- Expand button
        ctx:table_set_column_index(1)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
        if ctx:button("◀##expand_collapsed_" .. state_guid, btn_size, btn_size) then
            local state_module = require('lib.core.state')
            local state = state_module.state
            state.device_controls_collapsed = state.device_controls_collapsed or {}
            state.device_controls_collapsed[state_guid] = false
            state_module.save_device_collapsed_states()
            interacted = true
        end
        ctx:pop_style_color(3)
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Expand device controls")
        end

        -- === ROW 2: ON | × ===
        ctx:table_next_row()

        -- ON/OFF toggle
        ctx:table_set_column_index(0)
        if drawing.draw_on_off_circle(ctx, "##on_off_collapsed_" .. state_guid, enabled, btn_size, btn_size, colors.bypass_on, colors.bypass_off) then
            container:set_enabled(not enabled)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip(enabled and "Bypass" or "Enable")
        end

        -- Delete button
        ctx:table_set_column_index(1)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x663333FF)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x884444FF)
        if ctx:button("×##delete_collapsed_" .. state_guid, btn_size, btn_size) then
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

        ctx:end_table()
    end

    return interacted
end

return M
