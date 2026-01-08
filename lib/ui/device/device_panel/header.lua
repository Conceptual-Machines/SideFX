--[[
Device Header Module - Draws device panel header with name, controls, and buttons
]]

local M = {}

-- Track rename state per FX (by GUID)
local rename_active = {}
local rename_buffer = {}

--- Draw device name/path with mix/delta/UI buttons (left side of header)
function M.draw_device_name_path(ctx, fx, container, guid, name, device_id, drag_guid, enabled, opts, colors, state_guid)
    local r = reaper
    local imgui = require('imgui')
    local drawing = require('lib.ui.common.drawing')
    local fx_naming = require('lib.fx.fx_naming')
    local interacted = false

    -- Check for mix (container parameter)
    local has_mix = false
    local mix_val, mix_idx
    if container then
        local ok_mix
        ok_mix, mix_idx = pcall(function() return container:get_param_from_ident(":wet") end)
        if ok_mix and mix_idx and mix_idx >= 0 then
            local ok_mv
            ok_mv, mix_val = pcall(function() return container:get_param_normalized(mix_idx) end)
            has_mix = ok_mv and mix_val
        end
    end

    -- Check for delta (container parameter)
    local has_delta = false
    local delta_val, delta_idx
    if container then
        local ok_delta
        ok_delta, delta_idx = pcall(function() return container:get_param_from_ident(":delta") end)
        if ok_delta and delta_idx and delta_idx >= 0 then
            local ok_dv
            ok_dv, delta_val = pcall(function() return container:get_param_normalized(delta_idx) end)
            has_delta = ok_dv and delta_val
        end
    end

    -- Calculate number of columns: drag | name | path | mix | delta | ui
    local num_cols = 3  -- base: drag, name, path
    if has_mix then num_cols = num_cols + 1 end
    if has_delta then num_cols = num_cols + 1 end
    num_cols = num_cols + 1  -- ui button

    -- Use table for proper layout
    local table_flags = imgui.TableFlags.SizingStretchProp()
    if ctx:begin_table("header_left_" .. guid, num_cols, table_flags) then
        ctx:table_setup_column("drag", imgui.TableColumnFlags.WidthFixed(), 24)
        ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch(), 50)
        ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 20)
        if has_mix then
            ctx:table_setup_column("mix", imgui.TableColumnFlags.WidthFixed(), 28)
        end
        if has_delta then
            ctx:table_setup_column("delta", imgui.TableColumnFlags.WidthFixed(), 32)
        end
        ctx:table_setup_column("ui", imgui.TableColumnFlags.WidthFixed(), 24)

        ctx:table_next_row()

        -- Column 1: Drag handle
        ctx:table_set_column_index(0)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
        if ctx:button("≡##drag_" .. guid, 20, 20) then
            -- Drag handle doesn't do anything on click
        end
        ctx:pop_style_color(3)
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Drag to reorder")
        end

        -- Drag/drop handling
        if ctx:begin_drag_drop_source() then
            ctx:set_drag_drop_payload("FX_GUID", drag_guid)
            ctx:text("Moving: " .. fx_naming.truncate(name, 20))
            ctx:end_drag_drop_source()
        end

        if ctx:begin_drag_drop_target() then
            local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
            if accepted and payload and payload ~= drag_guid then
                if opts.on_drop then
                    opts.on_drop(payload, drag_guid)
                end
                interacted = true
            end
            local accepted_plugin, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted_plugin and plugin_name then
                if opts.on_plugin_drop then
                    opts.on_plugin_drop(plugin_name, fx.pointer)
                end
                interacted = true
            end
            local accepted_rack = ctx:accept_drag_drop_payload("RACK_ADD")
            if accepted_rack then
                if opts.on_rack_drop then
                    opts.on_rack_drop(fx.pointer)
                end
                interacted = true
            end
            ctx:end_drag_drop_target()
        end

        -- Column 2: Device name (editable)
        ctx:table_set_column_index(1)
        local sidefx_state = require('lib.core.state').state
        local is_renaming = rename_active[guid] or false

        if is_renaming then
            ctx:set_next_item_width(-1)
            local changed, text = ctx:input_text("##rename_" .. guid, rename_buffer[guid] or name, imgui.InputTextFlags.EnterReturnsTrue())
            if changed then
                sidefx_state.display_names[guid] = text
                local state_module = require('lib.core.state')
                state_module.save_display_names()
                rename_active[guid] = nil
                rename_buffer[guid] = ""
            end
            if ctx:is_item_deactivated() then
                rename_active[guid] = nil
                rename_buffer[guid] = ""
            end
        else
            local display_name = fx_naming.truncate(name, 50)
            if not enabled then
                ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
            end
            ctx:text(display_name)
            if not enabled then
                ctx:pop_style_color()
            end
            if ctx:is_item_hovered() and r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
                rename_active[guid] = true
                rename_buffer[guid] = name
            end
        end

        -- Column 3: Path identifier
        ctx:table_set_column_index(2)
        if device_id then
            ctx:push_style_color(r.ImGui_Col_Text(), 0x666666FF)
            ctx:text("[" .. device_id .. "]")
            ctx:pop_style_color()
        end

        local col_idx = 3

        -- Column: Mix (if present)
        if has_mix then
            ctx:table_set_column_index(col_idx)
            col_idx = col_idx + 1

            local knob_size = 24
            local mix_changed, new_mix = drawing.draw_knob(ctx, "##mix_knob_" .. state_guid, mix_val, knob_size)
            if mix_changed then
                pcall(function() container:set_param_normalized(mix_idx, new_mix) end)
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                local mix_pct = math.floor(mix_val * 100)
                ctx:set_tooltip(string.format("Mix: %d%% (parallel blend)", mix_pct))
            end
        end

        -- Column: Delta (if present)
        if has_delta then
            ctx:table_set_column_index(col_idx)
            col_idx = col_idx + 1

            local delta_on = delta_val > 0.5
            if delta_on then
                ctx:push_style_color(r.ImGui_Col_Button(), 0x6666CCFF)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x7777DDFF)
                ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x8888EEFF)
            else
                ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x555555FF)
                ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x666666FF)
            end
            if ctx:button((delta_on and "∆" or "—") .. "##delta_" .. state_guid, 28, 20) then
                pcall(function() container:set_param_normalized(delta_idx, delta_on and 0 or 1) end)
                interacted = true
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(delta_on and "Delta Solo: ON (wet - dry)\nClick to toggle" or "Delta Solo: OFF\nClick to toggle")
            end
        end

        -- Column: UI button
        ctx:table_set_column_index(col_idx)
        if drawing.draw_ui_icon(ctx, "##ui_header_" .. state_guid, 24, 20) then
            pcall(function() fx:show(3) end)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Open plugin UI")
        end

        ctx:end_table()
    end

    return interacted
end

--- Draw device control buttons (right side of header) - ON, Delete, and Device collapse
function M.draw_device_buttons(ctx, fx, container, state_guid, enabled, is_device_collapsed, device_collapsed, opts, colors)
    local r = reaper
    local drawing = require('lib.ui.common.drawing')
    local imgui = require('imgui')
    local interacted = false

    -- Use table for proper layout: on | x | collapse
    if ctx:begin_table("header_right_" .. state_guid, 3, 0) then
        ctx:table_setup_column("on", imgui.TableColumnFlags.WidthFixed(), 24)
        ctx:table_setup_column("x", imgui.TableColumnFlags.WidthFixed(), 20)
        ctx:table_setup_column("collapse", imgui.TableColumnFlags.WidthFixed(), 20)

        ctx:table_next_row()

        -- Column: ON/OFF toggle
        ctx:table_set_column_index(0)
        if drawing.draw_on_off_circle(ctx, "##on_off_header_" .. state_guid, enabled, 24, 20, colors.bypass_on, colors.bypass_off) then
            container:set_enabled(not enabled)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip(enabled and "Bypass" or "Enable")
        end

        -- Column: Delete button
        ctx:table_set_column_index(1)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x663333FF)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x884444FF)
        if ctx:button("×##delete_" .. state_guid, 20, 20) then
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

        -- Column: Collapse/Expand Device
        ctx:table_set_column_index(2)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
        local collapse_icon = "◀"
        if ctx:button(collapse_icon .. "##collapse_device_" .. state_guid, 20, 20) then
            device_collapsed[state_guid] = true
            interacted = true
        end
        ctx:pop_style_color(3)
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Collapse device controls")
        end

        ctx:end_table()
    end

    return interacted
end

return M
