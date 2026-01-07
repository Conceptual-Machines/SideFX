--- Device Panel UI Component
-- Renders a single FX as an Ableton-style device panel.
-- @module ui.device_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper
local imgui = require('imgui')
local widgets = require('lib.ui.widgets')
local fx_utils = require('lib.fx_utils')
local modulator_sidebar = require('lib.ui.modulator_sidebar')
local drawing = require('lib.ui.drawing')
local fx_naming = require('lib.fx_naming')
local param_utils = require('lib.param_utils')

local M = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

M.config = {
    column_width = 180,        -- Width per parameter column
    header_height = 32,
    param_height = 38,         -- Height per param row (label + slider)
    sidebar_width = 120,       -- Width for sidebar (controls on right)
    sidebar_padding = 12,      -- Extra padding for scrollbar
    padding = 8,               -- Padding around content
    border_radius = 6,
    fader_width = 28,          -- Fader width
    fader_height = 70,         -- Fader height
    knob_size = 48,            -- Knob diameter
    -- Modulator sidebar (left side of device)
    mod_sidebar_width = 260,   -- Width for modulator 4×2 grid
    mod_sidebar_collapsed_width = 24,  -- Collapsed width
    mod_slot_width = 60,
    mod_slot_height = 60,
    mod_slot_padding = 4,
}

-- Utility JSFX name for detection
M.UTILITY_JSFX = "SideFX_Utility"

-- Colors (RGBA as 0xRRGGBBAA)
M.colors = {
    panel_bg = 0x2A2A2AFF,
    panel_bg_hover = 0x333333FF,
    panel_border = 0x444444FF,
    header_bg = 0x383838FF,
    header_text = 0xDDDDDDFF,
    param_label = 0xAAAAAAFF,
    param_value = 0xCCCCCCFF,
    bypass_on = 0x44AA44FF,
    bypass_off = 0xAA4444FF,
    slider_bg = 0x1A1A1AFF,
    slider_fill = 0x5588CCFF,
    slider_grab = 0x77AAEEFF,
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Track expanded state per FX (by GUID)
local expanded_state = {}

-- Track sidebar collapsed state per FX (by GUID)
local sidebar_collapsed = {}

-- Track panel collapsed state per FX (by GUID) - collapses the whole panel to just header
local panel_collapsed = {}

-- NOTE: Modulator sidebar state is now managed by the state module
-- (accessed via state.mod_sidebar_collapsed and state.expanded_mod_slot)

-- Rename state: which FX is being renamed and the edit buffer
local rename_active = {}    -- guid -> true if rename mode active
local rename_buffer = {}    -- guid -> current edit text

--------------------------------------------------------------------------------
-- Custom Widgets
--------------------------------------------------------------------------------

--- Draw a UI button icon (window/screen icon)
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param width number Button width
-- @param height number Button height
-- @return boolean True if clicked
--------------------------------------------------------------------------------
-- Modulator Support
--------------------------------------------------------------------------------

-- Available modulator types

--------------------------------------------------------------------------------
-- Device Panel Component - Helper Functions
--------------------------------------------------------------------------------

--- Draw device panel header (collapsed or expanded)
local function draw_header(ctx, fx, is_panel_collapsed, panel_collapsed, state_guid, guid, name, device_id, drag_guid, opts, colors, enabled)
    local r = reaper
    local imgui = require('imgui')
    local interacted = false

    -- Header row using table for proper alignment
    if is_panel_collapsed then
        -- Collapsed header: collapse button | path
        if r.ImGui_BeginTable(ctx.ctx, "header_collapsed_" .. guid, 2, 0) then
            r.ImGui_TableSetupColumn(ctx.ctx, "collapse", r.ImGui_TableColumnFlags_WidthFixed(), 24)
            r.ImGui_TableSetupColumn(ctx.ctx, "path", r.ImGui_TableColumnFlags_WidthStretch())

            r.ImGui_TableNextRow(ctx.ctx)

            -- Collapse button
            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
            ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
            if ctx:button("▶##collapse_" .. state_guid, 20, 20) then
                panel_collapsed[state_guid] = false
                interacted = true
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Expand panel")
            end

            -- Path identifier
            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
            if device_id then
                ctx:push_style_color(r.ImGui_Col_Text(), 0x888888FF)
                ctx:text("[" .. device_id .. "]")
                ctx:pop_style_color()
            end

            r.ImGui_EndTable(ctx.ctx)
        end
    else
        -- Expanded header: drag | name (50%) | path (15%) | ui | on | x | collapse (buttons fixed width)
        local table_flags = imgui.TableFlags.SizingStretchProp()
        if ctx:begin_table("header_" .. guid, 7, table_flags) then
            ctx:table_setup_column("drag", imgui.TableColumnFlags.WidthFixed(), 24)
            ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch(), 50)  -- 50%
            ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 15)  -- 15%
            ctx:table_setup_column("ui", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed
            ctx:table_setup_column("on", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed
            ctx:table_setup_column("x", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed
            ctx:table_setup_column("collapse", imgui.TableColumnFlags.WidthFixed(), 24)  -- Fixed

            ctx:table_next_row()

            -- Drag handle / collapse toggle
            ctx:table_set_column_index(0)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
            ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
            local collapse_icon = is_panel_collapsed and "▶" or "≡"
            if ctx:button(collapse_icon .. "##drag", 20, 20) then
                -- Toggle panel collapse on click
                panel_collapsed[state_guid] = not is_panel_collapsed
                interacted = true
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(is_panel_collapsed and "Expand panel" or "Collapse panel (drag to reorder)")
            end

            if ctx:begin_drag_drop_source() then
                ctx:set_drag_drop_payload("FX_GUID", drag_guid)
                ctx:text("Moving: " .. fx_naming.truncate(name, 20))
                ctx:end_drag_drop_source()
            end

            if ctx:begin_drag_drop_target() then
                -- Accept FX reorder drops
                local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
                if accepted and payload and payload ~= drag_guid then
                    if opts.on_drop then
                        opts.on_drop(payload, drag_guid)
                    end
                    interacted = true
                end

                -- Accept plugin drops (insert before this FX/container)
                local accepted_plugin, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                if accepted_plugin and plugin_name then
                    if opts.on_plugin_drop then
                        opts.on_plugin_drop(plugin_name, fx.pointer)
                    end
                    interacted = true
                end

                -- Accept rack drops (insert before this FX/container)
                local accepted_rack = ctx:accept_drag_drop_payload("RACK_ADD")
                if accepted_rack then
                    if opts.on_rack_drop then
                        opts.on_rack_drop(fx.pointer)
                    end
                    interacted = true
                end

                ctx:end_drag_drop_target()
            end

            -- Device name (editable)
            ctx:table_set_column_index(1)

            local sidefx_state = require('lib.state').state
            local is_renaming = rename_active[guid] or false

            if is_renaming then
                -- Rename mode: show input box
                ctx:set_next_item_width(-1)
                local changed, text = ctx:input_text("##rename_" .. guid, rename_buffer[guid] or name, imgui.InputTextFlags.EnterReturnsTrue())

                if changed then
                    -- Save new display name
                    sidefx_state.display_names[guid] = text
                    local state_module = require('lib.state')
                    state_module.save_display_names()
                    rename_active[guid] = nil
                    rename_buffer[guid] = ""
                end

                if ctx:is_item_deactivated() then
                    rename_active[guid] = nil
                    rename_buffer[guid] = ""
                end
            else
                -- Normal mode: show text, double-click to rename
                local display_name = fx_naming.truncate(name, 50)  -- Reasonable max length
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

            -- Path identifier
            ctx:table_set_column_index(2)
            if device_id then
                ctx:push_style_color(r.ImGui_Col_Text(), 0x666666FF)
                ctx:text("[" .. device_id .. "]")
                ctx:pop_style_color()
            end

            -- UI button
            ctx:table_set_column_index(3)
            if drawing.draw_ui_icon(ctx, "##ui_header_" .. state_guid, math.min(24, 24), 20) then
                fx:show(3)
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Open plugin UI")
            end

            -- ON/OFF toggle
            ctx:table_set_column_index(4)
            if drawing.draw_on_off_circle(ctx, "##on_off_header_" .. state_guid, enabled, math.min(24, 24), 20, colors.bypass_on, colors.bypass_off) then
                fx:set_enabled(not enabled)
                interacted = true
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(enabled and "Bypass" or "Enable")
            end

            -- Delete button
            ctx:table_set_column_index(5)
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

            -- Collapse button (rightmost)
            ctx:table_set_column_index(6)
            ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
            ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
            ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x55555588)
            if ctx:button("◀##collapse_" .. state_guid, 20, 20) then
                panel_collapsed[state_guid] = true
                interacted = true
            end
            ctx:pop_style_color(3)
            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip("Collapse panel")
            end

            ctx:end_table()
        end  -- end expanded header
    end  -- end if is_panel_collapsed check for header

    return interacted
end

--- Draw collapsed panel body (minimal view with UI/ON/X buttons)
local function draw_collapsed_body(ctx, fx, state_guid, guid, name, enabled, opts, colors)
    local r = reaper
    local interacted = false

    ctx:separator()

    -- Collapsed view table layout
    -- Row 1: ui | on | x
    -- Row 2: name
    if r.ImGui_BeginTable(ctx.ctx, "controls_" .. guid, 3, r.ImGui_TableFlags_SizingStretchSame()) then
        r.ImGui_TableSetupColumn(ctx.ctx, "ui", r.ImGui_TableColumnFlags_WidthStretch())
        r.ImGui_TableSetupColumn(ctx.ctx, "on", r.ImGui_TableColumnFlags_WidthStretch())
        r.ImGui_TableSetupColumn(ctx.ctx, "x", r.ImGui_TableColumnFlags_WidthStretch())

        r.ImGui_TableNextRow(ctx.ctx)

        -- UI button
        r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
        local ui_avail_w = ctx:get_content_region_avail()
        if ui_avail_w > 0 and drawing.draw_ui_icon(ctx, "##ui_" .. state_guid, ui_avail_w, 24) then
            fx:show(3)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Open " .. name)
        end

        -- ON/OFF toggle
        r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
        local avail_w, avail_h = ctx:get_content_region_avail()
        if avail_w > 0 and drawing.draw_on_off_circle(ctx, "##on_off_" .. state_guid, enabled, avail_w, 24, colors.bypass_on, colors.bypass_off) then
            fx:set_enabled(not enabled)
            interacted = true
        end

        -- Close button
        r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x663333FF)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x444444FF)
        if ctx:button("×", -1, 24) then
            if opts.on_delete then
                opts.on_delete(fx)
            else
                fx:delete()
            end
            interacted = true
        end
        ctx:pop_style_color(2)

        r.ImGui_EndTable(ctx.ctx)
    end

    -- Row 2: name
    local imgui = require('imgui')
    ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
    ctx:text(name)
    ctx:pop_style_color()

    return interacted
end

--------------------------------------------------------------------------------
-- Column Drawing Functions
--------------------------------------------------------------------------------

--- Draw modulator sidebar column
local function draw_modulator_column(ctx, fx, container, guid, state_guid, cfg, opts)
    local modulator_sidebar = require('lib.ui.modulator_sidebar')
    return modulator_sidebar.draw(ctx, fx, container, guid, state_guid, cfg, opts)
end


--- Module requires
local params_column = require('lib.ui.device_panel.params')
local sidebar_column = require('lib.ui.device_panel.sidebar')

--- Filter FX parameters, excluding sidebar controls (wet, delta, bypass)
local function get_visible_params(fx)
    local r = reaper
    local visible_params = {}

    local ok_count, param_count = pcall(function() return fx:get_num_params() end)
    if not ok_count then param_count = 0 end

    for i = 0, param_count - 1 do
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

    return visible_params
end

--- Draw panel frame (background + border)
local function draw_panel_frame(draw_list, cursor_x, cursor_y, panel_width, panel_height, colors, cfg)
    local r = reaper

    -- Draw panel background (filled rectangle)
    r.ImGui_DrawList_AddRectFilled(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_bg, cfg.border_radius)

    -- Draw panel border
    r.ImGui_DrawList_AddRect(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_border, cfg.border_radius, 0, 1)
end

--- Calculate panel dimensions based on collapsed state
local function calculate_panel_dimensions(is_panel_collapsed, avail_height, cfg, visible_count, is_sidebar_collapsed, collapsed_sidebar_w, mod_sidebar_w)
    local panel_height, panel_width, content_width, num_columns, params_per_column

    if is_panel_collapsed then
        -- Collapsed: full height but narrow width
        panel_height = avail_height
        panel_width = 140  -- Minimal width for collapsed panel
        content_width = 0
        num_columns = 0
        params_per_column = 0
    else
        -- Expanded: full panel
        panel_height = avail_height

        -- Calculate how many params fit per column based on available height
        local usable_height = panel_height - cfg.header_height - cfg.padding * 2
        params_per_column = math.floor(usable_height / cfg.param_height)
        params_per_column = math.max(1, params_per_column)

        -- Calculate columns needed to show visible params only
        num_columns = math.ceil(visible_count / params_per_column)
        num_columns = math.max(1, num_columns)

        -- Calculate panel width: columns + sidebar (if visible) + modulator sidebar + padding
        content_width = cfg.column_width * num_columns
        local sidebar_w = is_sidebar_collapsed and collapsed_sidebar_w or (cfg.sidebar_width + cfg.sidebar_padding)

        panel_width = content_width + sidebar_w + mod_sidebar_w + cfg.padding * 2
    end

    return {
        panel_height = panel_height,
        panel_width = panel_width,
        content_width = content_width,
        num_columns = num_columns,
        params_per_column = params_per_column
    }
end

--- Draw chain sidebar column wrapper
local function draw_sidebar_column(ctx, fx, container, state_guid, sidebar_actual_w, is_sidebar_collapsed, cfg, opts, colors)
    return sidebar_column.draw(ctx, fx, container, state_guid, sidebar_actual_w, is_sidebar_collapsed, cfg, opts, colors)
end

--------------------------------------------------------------------------------
-- Device Panel Component
--------------------------------------------------------------------------------

--- Draw a single device panel.
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param opts table Options {on_delete, on_open_ui, on_drag, avail_height, ...}
-- @return boolean True if panel was interacted with
function M.draw(ctx, fx, opts)
    opts = opts or {}
    local cfg = M.config
    local colors = M.colors

    -- Get icon font for UI button
    local icon_font = opts.icon_font
    local constants = require('lib.constants')
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
    local ui_icon = constants.icon_text(emojimgui, constants.Icons.window)

    if not fx then return false end

    -- Safety check: FX might have been deleted
    local ok, guid = pcall(function() return fx:get_guid() end)
    if not ok or not guid then return false end

    -- Skip rendering modulators - they're handled by modulator_grid_panel
    local is_modulator = fx_utils.is_modulator_fx(fx)
    if is_modulator then
        return false
    end

    -- Use container GUID for drag/drop if we have a container
    local container = opts.container
    local drag_guid = container and container:get_guid() or guid

    -- Get device name and identifier separately
    local fx_utils = require('lib.fx_utils')
    local name = "Unknown"
    local device_id = nil
    if container then
        -- Get actual FX name (plugin name, not hierarchical) and identifier separately
        local ok_name, fx_name = pcall(function() return fx_utils.get_display_name(fx) end)
        if ok_name then name = fx_name end
        local ok_id, id = pcall(function() return fx_utils.get_device_identifier(container) end)
        if ok_id then device_id = id end
    else
        -- No container, use regular display name
        local ok2, fx_name = pcall(function() return fx_naming.get_display_name(fx) end)
        if ok2 then name = fx_name end
    end

    local ok3, enabled = pcall(function() return fx:get_enabled() end)
    if not ok3 then enabled = false end

    -- Build list of visible params (exclude sidebar controls: wet, delta, bypass)
    local visible_params = get_visible_params(fx)
    local visible_count = #visible_params

    -- Use available height passed in opts, or default
    local avail_height = opts.avail_height or 600

    -- Use drag_guid for state (container GUID if applicable)
    local state_guid = drag_guid

    -- Check if panel is collapsed (just header bar)
    local is_panel_collapsed = panel_collapsed[state_guid] or false

    -- Check if sidebar is collapsed
    local is_sidebar_collapsed = sidebar_collapsed[state_guid] or false
    local collapsed_sidebar_w = 8  -- Minimal width when collapsed (button is in header)

    -- Get state module for modulator sidebar state
    local state_module = require('lib.state')
    local state = state_module.state

    -- Initialize modulator sidebar state tables if needed
    state.mod_sidebar_collapsed = state.mod_sidebar_collapsed or {}
    state.expanded_mod_slot = state.expanded_mod_slot or {}

    -- Check modulator sidebar state early for panel width calculation
    -- Default to false (expanded) to match modulator_sidebar.lua
    local is_mod_sidebar_collapsed = state.mod_sidebar_collapsed[state_guid] or false

    local mod_sidebar_w
    if is_mod_sidebar_collapsed then
        mod_sidebar_w = cfg.mod_sidebar_collapsed_width
    else
        mod_sidebar_w = cfg.mod_sidebar_width
    end

    -- Calculate dimensions based on collapsed state
    local dims = calculate_panel_dimensions(is_panel_collapsed, avail_height, cfg, visible_count, is_sidebar_collapsed, collapsed_sidebar_w, mod_sidebar_w)
    local panel_height = dims.panel_height
    local panel_width = dims.panel_width
    local content_width = dims.content_width
    local num_columns = dims.num_columns
    local params_per_column = dims.params_per_column

    local interacted = false

    ctx:push_id(guid)

    -- Panel background and frame
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    -- Draw panel frame (background + border)
    draw_panel_frame(draw_list, cursor_x, cursor_y, panel_width, panel_height, colors, cfg)

    -- Begin child for panel content (hide scrollbars)
    local window_flags = imgui.WindowFlags.NoScrollbar()
    if ctx:begin_child("panel_" .. guid, panel_width, panel_height, 0, window_flags) then

        -- Draw header (always shown, whether collapsed or expanded)
        local header_interacted = draw_header(ctx, fx, is_panel_collapsed, panel_collapsed, state_guid, guid, name, device_id, drag_guid, opts, colors, enabled)
        if header_interacted then interacted = true end

        -- Draw collapsed body and return early if collapsed
        if is_panel_collapsed then
            local collapsed_interacted = draw_collapsed_body(ctx, fx, state_guid, guid, name, enabled, opts, colors)
            if collapsed_interacted then interacted = true end
            ctx:end_child()  -- end panel
            ctx:pop_id()
            return interacted
        end

        ctx:separator()

        -- Panel is expanded - show 3-column wrapper table
        -- Wrapper table: [Modulator Sidebar | Device Params | Chain Sidebar]
        local content_h = panel_height - cfg.header_height - 10
        local sidebar_actual_w = is_sidebar_collapsed and 8 or cfg.sidebar_width
        local btn_h = 22

        -- Use ReaWrap's with_table for automatic cleanup
        ctx:with_table("device_wrapper_" .. guid, 3, r.ImGui_TableFlags_BordersInnerV(), function()
            r.ImGui_TableSetupColumn(ctx.ctx, "modulators", r.ImGui_TableColumnFlags_WidthFixed(), mod_sidebar_w)
            r.ImGui_TableSetupColumn(ctx.ctx, "params", r.ImGui_TableColumnFlags_WidthFixed(), content_width)
            r.ImGui_TableSetupColumn(ctx.ctx, "sidebar", r.ImGui_TableColumnFlags_WidthFixed(), sidebar_actual_w)

            r.ImGui_TableNextRow(ctx.ctx)

            -- === COLUMN 1: MODULATOR SIDEBAR ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
            if draw_modulator_column(ctx, fx, container, guid, state_guid, cfg, opts) then
                interacted = true
            end

            -- === COLUMN 2: DEVICE PARAMS ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
            if params_column.draw(ctx, fx, guid, visible_params, visible_count, num_columns, params_per_column, opts) then
                interacted = true
            end

            -- === COLUMN 3: CHAIN SIDEBAR ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
            if draw_sidebar_column(ctx, fx, container, state_guid, sidebar_actual_w, is_sidebar_collapsed, cfg, opts, colors) then
                interacted = true
            end
        end)  -- end with_table (device_wrapper)

        ctx:end_child()  -- end panel
    end

    -- Right-click context menu
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
                -- Use FX GUID for renaming since we display the FX name
                local state_module = require('lib.state')
                local sidefx_state = state_module.state
                sidefx_state.renaming_fx = guid  -- Use FX GUID
                sidefx_state.rename_text = name
            end
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

    ctx:pop_id()

    return interacted
end

--------------------------------------------------------------------------------
-- Compact Device Panel (for chains inside racks)
--------------------------------------------------------------------------------

--- Draw a compact device panel for chain view.
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param opts table Options
-- @return boolean True if interacted
function M.draw_compact(ctx, fx, opts)
    opts = opts or {}
    local cfg = M.config

    if not fx then return false end

    local guid = fx:get_guid()
    local name = fx_naming.get_display_name(fx)
    local enabled = fx:get_enabled()

    local interacted = false
    local compact_width = 120
    local compact_height = 24

    ctx:push_id("compact_" .. guid)

    -- Simple button-like appearance
    local btn_color = enabled and 0x3A3A3AFF or 0x2A2A2AFF
    ctx:push_style_color(r.ImGui_Col_Button(), btn_color)
    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x4A4A4AFF)

    if ctx:button(fx_naming.truncate(name, 14), compact_width, compact_height) then
        -- Click opens FX detail or native UI
        if opts.on_click then
            opts.on_click(fx)
        else
            fx:show(3)
        end
        interacted = true
    end

    ctx:pop_style_color(2)

    -- Drag source
    if ctx:begin_drag_drop_source() then
        ctx:set_drag_drop_payload("FX_GUID", guid)
        ctx:text("Moving: " .. fx_naming.truncate(name, 20))
        ctx:end_drag_drop_source()
    end

    -- Drop target
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

    -- Tooltip with full name
    if ctx:is_item_hovered() then
        ctx:set_tooltip(name)
    end

    ctx:pop_id()

    return interacted
end

--------------------------------------------------------------------------------
-- Utility
--------------------------------------------------------------------------------

--- Reset all expanded states.
function M.reset_expanded()
    expanded_state = {}
end

--- Set expanded state for a specific FX.
-- @param guid string FX GUID
-- @param expanded boolean
function M.set_expanded(guid, expanded)
    expanded_state[guid] = expanded
end

--- Get expanded state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_expanded(guid)
    return expanded_state[guid] or false
end

--- Reset all sidebar collapsed states.
function M.reset_sidebar()
    sidebar_collapsed = {}
end

--- Set sidebar collapsed state for a specific FX.
-- @param guid string FX GUID
-- @param collapsed boolean
function M.set_sidebar_collapsed(guid, collapsed)
    sidebar_collapsed[guid] = collapsed
end

--- Get sidebar collapsed state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_sidebar_collapsed(guid)
    return sidebar_collapsed[guid] or false
end

--- Collapse all sidebars
function M.collapse_all_sidebars()
    for guid, _ in pairs(expanded_state) do
        sidebar_collapsed[guid] = true
    end
end

--- Expand all sidebars
function M.expand_all_sidebars()
    sidebar_collapsed = {}
end

--- Reset all panel collapsed states.
function M.reset_panel_collapsed()
    panel_collapsed = {}
end

--- Set panel collapsed state for a specific FX.
-- @param guid string FX GUID
-- @param collapsed boolean
function M.set_panel_collapsed(guid, collapsed)
    panel_collapsed[guid] = collapsed
end

--- Get panel collapsed state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_panel_collapsed(guid)
    return panel_collapsed[guid] or false
end

--- Collapse all panels
function M.collapse_all_panels()
    for guid, _ in pairs(expanded_state) do
        panel_collapsed[guid] = true
    end
end

--- Expand all panels
function M.expand_all_panels()
    panel_collapsed = {}
end

return M
