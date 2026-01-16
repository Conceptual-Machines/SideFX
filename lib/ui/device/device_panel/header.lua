--[[
Device Header Module - Draws device panel header with name, controls, and buttons
]]

local icons = require('lib.ui.common.icons')

local M = {}

-- Track rename state per FX (by GUID)
local rename_active = {}
local rename_buffer = {}

--- Draw device name/path with mix/delta/UI buttons (left side of header)
function M.draw_device_name_path(ctx, fx, container, guid, name, device_id, drag_guid, enabled, opts, colors, state_guid, device_collapsed)
    local r = reaper
    local imgui = require('imgui')
    local drawing = require('lib.ui.common.drawing')
    local fx_naming = require('lib.fx.fx_naming')
    local interacted = false

    -- Check config for which controls to show
    local config = require('lib.core.config')
    local show_mix_delta = config.get('show_mix_delta')

    -- Check for mix (container parameter)
    local has_mix = false
    local mix_val, mix_idx
    if container and show_mix_delta then
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
    if container and show_mix_delta then
        local ok_delta
        ok_delta, delta_idx = pcall(function() return container:get_param_from_ident(":delta") end)
        if ok_delta and delta_idx and delta_idx >= 0 then
            local ok_dv
            ok_dv, delta_val = pcall(function() return container:get_param_normalized(delta_idx) end)
            has_delta = ok_dv and delta_val
        end
    end

    -- Calculate number of columns: drag | name | mix | delta | ui
    -- (path column removed - now shown in breadcrumbs)
    local num_cols = 2  -- base: drag, name
    if has_mix then num_cols = num_cols + 1 end
    if has_delta then num_cols = num_cols + 1 end
    num_cols = num_cols + 1  -- ui button

    -- Track header position for context menu overlay
    local header_start_x, header_start_y = r.ImGui_GetCursorScreenPos(ctx.ctx)

    -- Use table for proper layout
    local table_flags = imgui.TableFlags.SizingStretchProp()
    if ctx:begin_table("header_left_" .. guid, num_cols, table_flags) then
        ctx:table_setup_column("drag", imgui.TableColumnFlags.WidthFixed(), 48)
        ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch(), 70)
        if has_mix then
            ctx:table_setup_column("mix", imgui.TableColumnFlags.WidthFixed(), 28)
        end
        if has_delta then
            ctx:table_setup_column("delta", imgui.TableColumnFlags.WidthFixed(), 32)
        end
        ctx:table_setup_column("ui", imgui.TableColumnFlags.WidthFixed(), 24)

        ctx:table_next_row()

        -- Column 1: Drag handle + Collapse button
        ctx:table_set_column_index(0)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
        if ctx:button("≡##drag_" .. guid, 20, 20) then
            -- Drag handle doesn't do anything on click
        end
        -- Drag source must be right after the drag handle button
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
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Drag to reorder")
        end
        ctx:same_line(0, 2)  -- Minimal gap
        if ctx:button("▼##collapse_" .. guid, 20, 20) then
            local state_module = require('lib.core.state')
            local state = state_module.state
            state.device_controls_collapsed = state.device_controls_collapsed or {}
            state.device_controls_collapsed[state_guid] = true
            state_module.save_device_collapsed_states()
        end
        ctx:pop_style_color(3)
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Collapse device")
        end

        -- Column 2: Device name (editable)
        ctx:table_set_column_index(1)
        local sidefx_state = require('lib.core.state').state

        -- Check if context menu triggered rename
        if sidefx_state.renaming_fx == guid and not rename_active[guid] then
            rename_active[guid] = true
            rename_buffer[guid] = sidefx_state.rename_text or name
            sidefx_state.renaming_fx = nil
            sidefx_state.rename_text = nil
        end

        local is_renaming = rename_active[guid] or false

        -- Use bold header font for device name (with safety check)
        local font_pushed = false
        if opts.header_font then
            local ok = pcall(r.ImGui_PushFont, ctx.ctx, opts.header_font, 14)
            font_pushed = ok
        end

        if is_renaming then
            ctx:set_next_item_width(-1)
            ctx:set_keyboard_focus_here()
            local changed, text = ctx:input_text("##rename_" .. guid, rename_buffer[guid] or name, imgui.InputTextFlags.EnterReturnsTrue())
            if changed then
                sidefx_state.display_names[guid] = text
                local state_module = require('lib.core.state')
                state_module.save_display_names()
                rename_active[guid] = nil
                rename_buffer[guid] = ""
            end
            if ctx:is_item_deactivated_after_edit() then
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

        if font_pushed then
            r.ImGui_PopFont(ctx.ctx)
        end

        local col_idx = 2

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
            if ctx:button((delta_on and "∆" or "—") .. "##delta_" .. state_guid, 24, 20) then
                pcall(function() container:set_param_normalized(delta_idx, delta_on and 0 or 1) end)
                interacted = true
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(delta_on and "Delta Solo: ON (wet - dry)\nClick to toggle" or "Delta Solo: OFF\nClick to toggle")
            end
        end

        -- Column: UI button (wrench icon)
        ctx:table_set_column_index(col_idx)
        if icons.button_bordered(ctx, "ui_header_" .. state_guid, icons.Names.wrench, 20) then
            pcall(function() fx:show(3) end)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Open plugin UI")
        end

        ctx:end_table()
    end

    -- Get header end position and calculate size for context menu overlay
    local header_end_x, header_end_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local header_width = r.ImGui_GetContentRegionAvail(ctx.ctx)
    local header_height = header_end_y - header_start_y

    -- Draw invisible button over header area for context menu (go back to start position)
    r.ImGui_SetCursorScreenPos(ctx.ctx, header_start_x, header_start_y)
    r.ImGui_InvisibleButton(ctx.ctx, "##header_ctx_" .. guid, header_width, header_height)

    -- Right-click context menu on entire header area
    if ctx:begin_popup_context_item("device_menu_" .. guid) then
        if ctx:menu_item("Open FX Window") then
            fx:show(3)
        end
        if ctx:menu_item(enabled and "Bypass" or "Enable") then
            fx:set_enabled(not enabled)
        end
        ctx:separator()
        if ctx:menu_item("Rename...") then
            if opts.on_rename then
                opts.on_rename(fx)
            else
                -- Fallback: use SideFX state system directly
                local state_module = require('lib.core.state')
                local sidefx_state_local = state_module.state
                sidefx_state_local.renaming_fx = guid
                sidefx_state_local.rename_text = name
            end
        end
        ctx:separator()

        -- Device-specific options (D-containers)
        if container then
            local container_name = container:get_name() or ""
            local is_device_container = container_name:match("^D%d+")

            if is_device_container then
                if ctx:menu_item("Convert to Rack") then
                    local container_module = require('lib.device.container')
                    local result = container_module.convert_device_to_rack(container)
                    if result then
                        local state_mod = require('lib.core.state')
                        state_mod.invalidate_fx_list()
                    end
                end
                ctx:separator()
            end
        end

        if ctx:menu_item("Delete") then
            -- Clean up any external source sends before deleting
            local modulator_sidebar = require('lib.ui.device.modulator_sidebar')
            if container and fx.track then
                modulator_sidebar.cleanup_device_sends(container, fx.track)
            end
            if opts.on_delete then
                opts.on_delete(fx)
            else
                fx:delete()
            end
        end
        ctx:end_popup()
    end

    -- Restore cursor position after overlay
    r.ImGui_SetCursorScreenPos(ctx.ctx, header_start_x, header_end_y)

    return interacted
end

--- Draw device control buttons (right side of header) - ON and Delete
function M.draw_device_buttons(ctx, fx, container, state_guid, enabled, is_device_collapsed, device_collapsed, opts, colors)
    local r = reaper
    local drawing = require('lib.ui.common.drawing')
    local imgui = require('imgui')
    local interacted = false

    local btn_size = 20  -- Total button size (icon + padding + border)

    -- Use table with SizingFixedFit to center the buttons
    if ctx:begin_table("header_right_" .. state_guid, 2, r.ImGui_TableFlags_SizingFixedFit()) then
        ctx:table_setup_column("on", imgui.TableColumnFlags.WidthFixed(), btn_size)
        ctx:table_setup_column("x", imgui.TableColumnFlags.WidthFixed(), btn_size)

        ctx:table_next_row()

        -- Column: ON/OFF toggle
        ctx:table_set_column_index(0)
        local on_tint = enabled and 0x88FF88FF or 0x888888FF
        if icons.button_bordered(ctx, "on_off_" .. state_guid, icons.Names.on, 20, on_tint) then
            if container then
                container:set_enabled(not enabled)
            else
                -- Fallback: use FX directly if no container
                fx:set_enabled(not enabled)
            end
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip(enabled and "Bypass" or "Enable")
        end

        -- Column: Delete button
        ctx:table_set_column_index(1)
        if icons.button_bordered(ctx, "delete_" .. state_guid, icons.Names.cancel, 20, 0xFF6666FF) then
            -- Clean up any external source sends before deleting
            local modulator_sidebar = require('lib.ui.device.modulator_sidebar')
            if container and fx.track then
                modulator_sidebar.cleanup_device_sends(container, fx.track)
            end
            if opts.on_delete then
                opts.on_delete(fx)
            else
                fx:delete()
            end
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Delete device")
        end

        ctx:end_table()
    end

    return interacted
end

return M
