--- Bare Device Panel UI Component
-- Simple panel for bare devices (raw plugins without D-container)
-- No modulator support, no utility controls - just params and basic controls
-- @module ui.bare_device_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper
local imgui = require('imgui')
local icons = require('lib.ui.common.icons')
local fx_naming = require('lib.fx.fx_naming')
local state_module = require('lib.core.state')
local state = state_module.state

local M = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

M.config = {
    column_width = 160,
    header_height = 28,
    param_height = 46,
    padding = 6,
}

M.colors = {
    panel_bg = 0x252530FF,
    panel_border = 0x404050FF,
    header_bg = 0x303040FF,
    header_text = 0xCCCCCCFF,
    param_label = 0xAAAAAAFF,
}

-- Rename state
local rename_active = {}
local rename_buffer = {}

--------------------------------------------------------------------------------
-- Parameter Helpers
--------------------------------------------------------------------------------

--- Get visible parameters for bare device
local function get_visible_params(fx)
    local visible_params = {}
    local MAX_PARAMS = state_module.get_max_visible_params()

    -- Get FX name for parameter selection lookup
    local ok_name, fx_name = pcall(function() return fx:get_name() end)
    if not ok_name or not fx_name then return visible_params end

    local naming = require('lib.utils.naming')
    local clean_name = naming.strip_sidefx_prefixes(fx_name)

    -- Check for stored parameter selections
    local selected_params = nil
    if state.param_selections then
        if state.param_selections[fx_name] then
            selected_params = state.param_selections[fx_name]
        elseif state.param_selections[clean_name] then
            selected_params = state.param_selections[clean_name]
        else
            for key, params in pairs(state.param_selections) do
                local key_clean = naming.strip_sidefx_prefixes(key)
                if key_clean == clean_name then
                    selected_params = params
                    break
                end
            end
        end
    end

    local ok_count, param_count = pcall(function() return fx:get_num_params() end)
    if not ok_count then param_count = 0 end

    if selected_params then
        for _, param_idx in ipairs(selected_params) do
            if #visible_params >= MAX_PARAMS then break end
            if param_idx >= 0 and param_idx < param_count then
                table.insert(visible_params, param_idx)
            end
        end
    else
        for i = 0, param_count - 1 do
            if #visible_params >= MAX_PARAMS then break end
            local ok_pn, pname = pcall(function() return fx:get_param_name(i) end)
            local skip = false
            if ok_pn and pname then
                local lower = pname:lower()
                if lower == "wet" or lower == "delta" or lower == "bypass" then
                    skip = true
                end
            end
            if not skip then
                table.insert(visible_params, i)
            end
        end
    end

    return visible_params
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

--- Draw a single parameter row
local function draw_param(ctx, fx, param_idx, col_width)
    local ok_name, pname = pcall(function() return fx:get_param_name(param_idx) end)
    local ok_val, pval = pcall(function() return fx:get_param_normalized(param_idx) end)

    if not ok_name or not ok_val then return false end

    local interacted = false
    local display_name = (pname or "P" .. param_idx):sub(1, 18)

    -- Label
    ctx:push_style_color(imgui.Col.Text(), M.colors.param_label)
    ctx:text(display_name)
    ctx:pop_style_color()

    -- Slider
    ctx:set_next_item_width(col_width - 12)
    local changed, new_val = ctx:slider_double("##p" .. param_idx, pval or 0, 0, 1, "")
    if changed then
        pcall(function() fx:set_param_normalized(param_idx, new_val) end)
        interacted = true
    end

    -- Value tooltip
    if r.ImGui_IsItemHovered(ctx.ctx) then
        local ok_fmt, formatted = pcall(function() return fx:get_formatted_param_value(param_idx) end)
        if ok_fmt and formatted then
            ctx:set_tooltip(pname .. ": " .. formatted)
        end
    end

    return interacted
end

--- Draw bare device panel
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param opts table Options {avail_height, on_delete, on_drop, ...}
-- @return boolean True if interacted
function M.draw(ctx, fx, opts)
    opts = opts or {}
    local cfg = M.config
    local colors = M.colors

    if not fx then return false end

    -- Get FX info
    local ok_guid, guid = pcall(function() return fx:get_guid() end)
    if not ok_guid or not guid then return false end

    local ok_name, _ = pcall(function() return fx:get_name() end)
    local name = ok_name and fx_naming.get_display_name(fx) or "Unknown"

    local ok_enabled, enabled = pcall(function() return fx:get_enabled() end)
    enabled = ok_enabled and enabled or true

    -- Get visible params
    local visible_params = get_visible_params(fx)
    local visible_count = #visible_params

    -- Calculate dimensions
    local avail_height = opts.avail_height or 400
    local usable_height = avail_height - cfg.header_height - cfg.padding * 2
    local params_per_column = math.floor(usable_height / cfg.param_height)
    params_per_column = math.max(1, params_per_column)
    local num_columns = math.ceil(visible_count / params_per_column)
    num_columns = math.max(1, num_columns)

    local panel_width = cfg.column_width * num_columns + cfg.padding * 2
    local panel_height = avail_height

    local interacted = false

    ctx:push_id("bare_" .. guid)

    -- Panel background
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height, colors.panel_bg, 4)
    r.ImGui_DrawList_AddRect(draw_list, cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height, colors.panel_border, 4, 0, 1)

    -- Begin child for content
    if ctx:begin_child("bare_panel_" .. guid, panel_width, panel_height, 0, imgui.WindowFlags.NoScrollbar()) then
        -- Header row
        if ctx:begin_table("bare_header_" .. guid, 5, r.ImGui_TableFlags_SizingFixedFit()) then
            ctx:table_setup_column("drag", imgui.TableColumnFlags.WidthFixed(), 24)
            ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch())
            ctx:table_setup_column("ui", imgui.TableColumnFlags.WidthFixed(), 22)
            ctx:table_setup_column("on", imgui.TableColumnFlags.WidthFixed(), 22)
            ctx:table_setup_column("x", imgui.TableColumnFlags.WidthFixed(), 22)

            ctx:table_next_row()

            -- Drag handle
            ctx:table_set_column_index(0)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
            ctx:button("≡##drag", 20, 20)  -- Drag handle button (interaction via drag/drop)
            ctx:pop_style_color(2)

            if ctx:begin_drag_drop_source() then
                ctx:set_drag_drop_payload("FX_GUID", guid)
                ctx:text("Moving: " .. fx_naming.truncate(name, 20))
                ctx:end_drag_drop_source()
            end
            if ctx:begin_drag_drop_target() then
                local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
                if accepted and payload and payload ~= guid then
                    if opts.on_drop then
                        opts.on_drop(payload, guid)
                    end
                    interacted = true
                end
                ctx:end_drag_drop_target()
            end

            -- Name (editable)
            ctx:table_set_column_index(1)

            if state.renaming_fx == guid and not rename_active[guid] then
                rename_active[guid] = true
                rename_buffer[guid] = state.rename_text or name
                state.renaming_fx = nil
                state.rename_text = nil
            end

            local is_renaming = rename_active[guid] or false

            if is_renaming then
                ctx:set_next_item_width(-1)
                ctx:set_keyboard_focus_here()
                local changed, text = ctx:input_text("##rename", rename_buffer[guid] or name, imgui.InputTextFlags.EnterReturnsTrue())
                if changed then
                    state.display_names[guid] = text
                    state_module.save_display_names()
                    rename_active[guid] = nil
                    rename_buffer[guid] = ""
                end
                if ctx:is_item_deactivated_after_edit() then
                    rename_active[guid] = nil
                    rename_buffer[guid] = ""
                end
            else
                if not enabled then
                    ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                end
                ctx:text(fx_naming.truncate(name, 20))
                if not enabled then
                    ctx:pop_style_color()
                end
                if ctx:is_item_hovered() and r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
                    rename_active[guid] = true
                    rename_buffer[guid] = name
                end
            end

            -- UI button
            ctx:table_set_column_index(2)
            if icons.button_bordered(ctx, "ui_" .. guid, icons.Names.wrench, 18) then
                pcall(function() fx:show(3) end)
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Open plugin UI")
            end

            -- ON/OFF
            ctx:table_set_column_index(3)
            local on_tint = enabled and 0x88FF88FF or 0x888888FF
            if icons.button_bordered(ctx, "on_" .. guid, icons.Names.on, 18, on_tint) then
                pcall(function() fx:set_enabled(not enabled) end)
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(enabled and "Bypass" or "Enable")
            end

            -- Delete
            ctx:table_set_column_index(4)
            if icons.button_bordered(ctx, "del_" .. guid, icons.Names.cancel, 18, 0xFF6666FF) then
                if opts.on_delete then
                    opts.on_delete(fx)
                else
                    pcall(function() fx:delete() end)
                end
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Delete")
            end

            ctx:end_table()
        end

        -- Right-click context menu
        if ctx:begin_popup_context_item("bare_menu_" .. guid) then
            if ctx:menu_item("Open FX Window") then
                fx:show(3)
            end
            if ctx:menu_item(enabled and "Bypass" or "Enable") then
                fx:set_enabled(not enabled)
            end
            ctx:separator()
            if ctx:menu_item("Rename...") then
                state.renaming_fx = guid
                state.rename_text = name
            end
            ctx:separator()
            if ctx:menu_item("Delete") then
                if opts.on_delete then
                    opts.on_delete(fx)
                else
                    fx:delete()
                end
            end
            ctx:end_popup()
        end

        ctx:separator()

        -- Parameters grid
        if visible_count > 0 and ctx:begin_table("bare_params_" .. guid, num_columns, imgui.TableFlags.SizingStretchSame()) then
            for col = 0, num_columns - 1 do
                ctx:table_setup_column("col" .. col, imgui.TableColumnFlags.WidthFixed(), cfg.column_width - 8)
            end

            for row = 0, params_per_column - 1 do
                ctx:table_next_row()
                for col = 0, num_columns - 1 do
                    local param_i = col * params_per_column + row + 1
                    if param_i <= visible_count then
                        ctx:table_set_column_index(col)
                        ctx:push_id(param_i)
                        if draw_param(ctx, fx, visible_params[param_i], cfg.column_width - 8) then
                            interacted = true
                        end
                        ctx:pop_id()
                    end
                end
            end

            ctx:end_table()
        elseif visible_count == 0 then
            ctx:text_disabled("No parameters")
        end

        ctx:end_child()
    end

    ctx:pop_id()

    return interacted
end

return M
