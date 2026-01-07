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

    local ok4, param_count = pcall(function() return fx:get_num_params() end)
    if not ok4 then param_count = 0 end

    -- Build list of visible params (exclude sidebar controls: wet, delta, bypass)
    local visible_params = {}
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

    local interacted = false

    ctx:push_id(guid)

    -- Panel background
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    -- Draw panel frame
    r.ImGui_DrawList_AddRectFilled(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_bg, cfg.border_radius)
    r.ImGui_DrawList_AddRect(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_border, cfg.border_radius, 0, 1)

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

        -- Panel is expanded - show wrapper table with modulator sidebar
        -- Wrapper table: [Modulator Sidebar | Main Content]
        -- (mod_sidebar_w already calculated above for panel width)
        if r.ImGui_BeginTable(ctx.ctx, "device_wrapper_" .. guid, 2, r.ImGui_TableFlags_BordersInnerV()) then
            r.ImGui_TableSetupColumn(ctx.ctx, "modulators", r.ImGui_TableColumnFlags_WidthFixed(), mod_sidebar_w)
            r.ImGui_TableSetupColumn(ctx.ctx, "content", r.ImGui_TableColumnFlags_WidthStretch())

            r.ImGui_TableNextRow(ctx.ctx)

            -- === MODULATOR SIDEBAR ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)

            local mod_interacted = modulator_sidebar.draw(ctx, fx, container, guid, state_guid, cfg, opts)
            if mod_interacted then
                interacted = true
            end

            -- === MAIN CONTENT ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)


        ctx:separator()

        -- Main content area: use a table for params (left) + sidebar (right)
        local content_h = panel_height - cfg.header_height - 10
        local sidebar_actual_w = is_sidebar_collapsed and 8 or cfg.sidebar_width
        local btn_h = 22

        if r.ImGui_BeginTable(ctx.ctx, "device_layout_" .. guid, 2, r.ImGui_TableFlags_BordersInnerV()) then
            r.ImGui_TableSetupColumn(ctx.ctx, "params", r.ImGui_TableColumnFlags_WidthFixed(), content_width)
            r.ImGui_TableSetupColumn(ctx.ctx, "sidebar", r.ImGui_TableColumnFlags_WidthStretch())  -- Stretch to fill remaining space

            r.ImGui_TableNextRow(ctx.ctx)

            -- === PARAMS COLUMN ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)

            if visible_count > 0 then
                -- Use nested table for parameter columns
                if r.ImGui_BeginTable(ctx.ctx, "params_" .. guid, num_columns, r.ImGui_TableFlags_SizingStretchSame()) then

                    for col = 0, num_columns - 1 do
                        r.ImGui_TableSetupColumn(ctx.ctx, "col" .. col, r.ImGui_TableColumnFlags_WidthStretch())
                    end

                    -- Draw parameters row by row across columns (using pre-filtered visible_params)
                    for row = 0, params_per_column - 1 do
                        r.ImGui_TableNextRow(ctx.ctx)

                        for col = 0, num_columns - 1 do
                            local visible_idx = col * params_per_column + row + 1  -- +1 for Lua 1-based

                            r.ImGui_TableSetColumnIndex(ctx.ctx, col)

                            if visible_idx <= visible_count then
                                local param_idx = visible_params[visible_idx]

                                -- Safely get param info (FX might have been deleted)
                                local ok_name, param_name = pcall(function() return fx:get_param_name(param_idx) end)
                                local ok_val, param_val = pcall(function() return fx:get_param_normalized(param_idx) end)

                                if ok_name and ok_val then
                                    param_val = param_val or 0
                                    local display_label = (param_name and param_name ~= "") and fx_naming.truncate(param_name, 14) or ("P" .. (param_idx + 1))

                                    ctx:push_id(param_idx)

                                    -- Parameter label
                                    ctx:push_style_color(r.ImGui_Col_Text(), colors.param_label)
                                    ctx:text(display_label)
                                    ctx:pop_style_color()

                                    -- Smart detection: switch vs continuous
                                    local is_switch = param_utils.is_switch_param(fx, param_idx)

                                    if is_switch then
                                        -- Draw as toggle button
                                        local is_on = param_val > 0.5
                                        if is_on then
                                            ctx:push_style_color(r.ImGui_Col_Button(), 0x5588AAFF)
                                        else
                                            ctx:push_style_color(r.ImGui_Col_Button(), 0x333333FF)
                                        end
                                        if ctx:button(is_on and "ON" or "OFF", -cfg.padding, 0) then
                                            pcall(function() fx:set_param_normalized(param_idx, is_on and 0 or 1) end)
                                            interacted = true
                                        end
                                        ctx:pop_style_color()
                                    else
                                        -- Draw as slider
                                        ctx:set_next_item_width(-cfg.padding)
                                        local changed, new_val = ctx:slider_double("##p", param_val, 0, 1, "%.2f")
                                        if changed then
                                            pcall(function() fx:set_param_normalized(param_idx, new_val) end)
                                            interacted = true
                                        end
                                    end

                                    ctx:pop_id()
                                end
                            end
                        end
                    end

                    r.ImGui_EndTable(ctx.ctx)
                end
            else
                ctx:text_disabled("No parameters")
            end

            -- === SIDEBAR COLUMN ===
            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)

            -- Get column starting X position for centering calculations
            local col_start_x = r.ImGui_GetCursorPosX(ctx.ctx)
            local sidebar_w = sidebar_actual_w

            -- Helper to center an item of given width within sidebar
            local function center_item(item_w)
                local offset = (sidebar_w - item_w) / 2
                if offset > 0 then
                    r.ImGui_SetCursorPosX(ctx.ctx, col_start_x + offset)
                end
            end

            if is_sidebar_collapsed then
                -- Collapsed: just empty space (expand button is in header)
                -- Nothing to render
            else
                -- Expanded sidebar
                local ctrl_w = cfg.sidebar_width - cfg.padding * 2  -- Full width controls
                local btn_w = 70  -- Narrower buttons (for pan slider)

                -- Mix and Delta on the same line using a table with bottom border
                local container = opts.container
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

                local has_delta = false
                local delta_val, delta_idx
                local ok_delta
                ok_delta, delta_idx = pcall(function() return fx:get_param_from_ident(":delta") end)
                if ok_delta and delta_idx and delta_idx >= 0 then
                    local ok_dv
                    ok_dv, delta_val = pcall(function() return fx:get_param_normalized(delta_idx) end)
                    has_delta = ok_dv and delta_val
                end

                -- Only show table if we have mix or delta
                if has_mix or has_delta then
                    local imgui = require('imgui')
                    local table_flags = imgui.TableFlags.BordersH()
                    if ctx:begin_table("mix_delta_" .. state_guid, 2, table_flags) then
                        ctx:table_setup_column("mix", imgui.TableColumnFlags.WidthStretch())
                        ctx:table_setup_column("delta", imgui.TableColumnFlags.WidthStretch())

                        ctx:table_next_row()

                        -- Mix column
                        ctx:table_set_column_index(0)
                        if has_mix then
                            -- "Mix" label (centered)
                            local mix_text = "Mix"
                            local mix_text_w = r.ImGui_CalcTextSize(ctx.ctx, mix_text)
                            local col_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - mix_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xCC88FFFF)  -- Purple for container
                            ctx:text(mix_text)
                            ctx:pop_style_color()

                            -- Smaller knob (30px)
                            local mix_knob_size = 30
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - mix_knob_size) / 2)
                            local mix_changed, new_mix = drawing.draw_knob(ctx, "##mix_knob", mix_val, mix_knob_size)
                            if mix_changed then
                                pcall(function() container:set_param_normalized(mix_idx, new_mix) end)
                                interacted = true
                            end

                            -- Value below knob (centered)
                            local mix_val_text = string.format("%.0f%%", mix_val * 100)
                            local mix_val_text_w = r.ImGui_CalcTextSize(ctx.ctx, mix_val_text)
                            r.ImGui_SetCursorPosX(ctx.ctx, r.ImGui_GetCursorPosX(ctx.ctx) + (col_w - mix_val_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAAAAFF)
                            ctx:text(mix_val_text)
                            ctx:pop_style_color()

                            if r.ImGui_IsItemHovered(ctx.ctx) then
                                ctx:set_tooltip(string.format("Device Mix: %.0f%% (parallel blend)", mix_val * 100))
                            end
                        end

                        -- Delta column
                        ctx:table_set_column_index(1)
                        if has_delta then
                            -- "Delta" label (centered horizontally)
                            local delta_text = "Delta"
                            local delta_text_w = r.ImGui_CalcTextSize(ctx.ctx, delta_text)
                            local col_start_x = r.ImGui_GetCursorPosX(ctx.ctx)
                            local col_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, col_start_x + (col_w - delta_text_w) / 2)
                            ctx:push_style_color(r.ImGui_Col_Text(), 0xAAAACCFF)
                            ctx:text(delta_text)
                            ctx:pop_style_color()

                            -- Center button vertically with mix knob
                            -- Mix column: label (~20px) + spacing (~5px) + knob (30px) + spacing (~5px) + value (~20px) = ~80px total
                            -- Knob center is at: label (20px) + spacing (5px) + knob_radius (15px) = ~40px from top
                            -- Delta column: label (~20px) + button (18px) = ~38px minimum
                            -- To center button with knob: button center should be at ~40px
                            -- Button center is 9px from button top, so button top should be at 40 - 9 = 31px
                            -- After label (~20px), we need 31 - 20 = 11px spacing
                            ctx:spacing()  -- Small spacing after label
                            r.ImGui_Dummy(ctx.ctx, 0, 6)  -- Additional spacing to align with knob center

                            local delta_on = delta_val > 0.5
                            if delta_on then
                                ctx:push_style_color(r.ImGui_Col_Button(), 0x6666CCFF)
                            else
                                ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                            end

                            -- Delta button (centered horizontally)
                            local delta_btn_w = 36
                            local delta_btn_h = 18
                            local col_w_btn = r.ImGui_GetContentRegionAvail(ctx.ctx)
                            r.ImGui_SetCursorPosX(ctx.ctx, col_start_x + (col_w_btn - delta_btn_w) / 2)
                            if ctx:button(delta_on and "∆" or "—", delta_btn_w, delta_btn_h) then
                                pcall(function() fx:set_param_normalized(delta_idx, delta_on and 0 or 1) end)
                                interacted = true
                            end
                            ctx:pop_style_color()

                            if r.ImGui_IsItemHovered(ctx.ctx) then
                                ctx:set_tooltip(delta_on and "Delta Solo: ON (wet - dry)" or "Delta Solo: OFF")
                            end
                        end

                        ctx:end_table()
                    end
                end

                -- Gain control as FADER (from paired utility)
                local utility = opts.utility
                if utility then
                    local ok_g, gain_val = pcall(function() return utility:get_param_normalized(0) end)
                    local ok_p, pan_val = pcall(function() return utility:get_param_normalized(1) end)

                    -- Pan slider first (above fader)
                    if ok_p then
                        pan_val = pan_val or 0.5
                        local pan_pct = (pan_val - 0.5) * 200

                        ctx:spacing()

                        -- Use collapsed rack pan slider (with label underneath)
                        local avail_w, _ = ctx:get_content_region_avail()
                        local pan_w = math.min(avail_w - 4, 80)
                        local pan_offset = math.max(0, (avail_w - pan_w) / 2)
                        ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + pan_offset)
                        local pan_changed, new_pan = widgets.draw_pan_slider(ctx, "##utility_pan", pan_pct, pan_w)
                        if pan_changed then
                            local new_norm = (new_pan + 100) / 200
                            pcall(function() utility:set_param_normalized(1, new_norm) end)
                            interacted = true
                        end
                    end

                    if ok_g then
                        gain_val = gain_val or 0.5
                        local gain_norm = gain_val
                        local gain_db = (gain_val - 0.5) * 48

                        ctx:spacing()

                        -- Fader with meter and scale (same as collapsed rack)
                        local fader_w = 32
                        local meter_w = 12
                        local scale_w = 20

                        -- Calculate fader height (accounting for pan slider above)
                        local _, remaining_h = ctx:get_content_region_avail()
                        local fader_h = remaining_h - 22  -- Leave room for dB label
                        fader_h = math.max(50, fader_h)  -- Minimum 50px, but can extend

                        local avail_w, _ = ctx:get_content_region_avail()
                        local total_w = scale_w + fader_w + meter_w + 4
                        local offset_x = math.max(0, (avail_w - total_w) / 2)

                        ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + offset_x)

                        local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                        local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

                        local scale_x = screen_x
                        local fader_x = screen_x + scale_w + 2
                        local meter_x = fader_x + fader_w + 2

                        -- dB scale
                        local db_marks = {24, 12, 0, -12, -24}
                        for _, db in ipairs(db_marks) do
                            local mark_norm = (db + 24) / 48
                            local mark_y = screen_y + fader_h - (fader_h * mark_norm)
                            r.ImGui_DrawList_AddLine(draw_list, scale_x + scale_w - 6, mark_y, scale_x + scale_w, mark_y, 0x666666FF, 1)
                            if db == 0 or db == -12 or db == 12 or db == 24 then
                                local label = db == 0 and "0" or tostring(db)
                                r.ImGui_DrawList_AddText(draw_list, scale_x, mark_y - 5, 0x888888FF, label)
                            end
                        end

                        -- Fader background
                        r.ImGui_DrawList_AddRectFilled(draw_list, fader_x, screen_y, fader_x + fader_w, screen_y + fader_h, 0x1A1A1AFF, 3)
                        -- Fader fill
                        local fill_h = fader_h * gain_norm
                        if fill_h > 2 then
                            local fill_top = screen_y + fader_h - fill_h
                            r.ImGui_DrawList_AddRectFilled(draw_list, fader_x + 2, fill_top, fader_x + fader_w - 2, screen_y + fader_h - 2, 0x5588AACC, 2)
                        end
                        -- Fader border
                        r.ImGui_DrawList_AddRect(draw_list, fader_x, screen_y, fader_x + fader_w, screen_y + fader_h, 0x555555FF, 3)
                        -- 0dB line (at center since range is -24 to +24)
                        local zero_db_norm = 24 / 48
                        local zero_y = screen_y + fader_h - (fader_h * zero_db_norm)
                        r.ImGui_DrawList_AddLine(draw_list, fader_x, zero_y, fader_x + fader_w, zero_y, 0xFFFFFF44, 1)

                        -- Stereo meters
                        local meter_l_x = meter_x
                        local meter_r_x = meter_x + meter_w / 2 + 1
                        local half_meter_w = meter_w / 2 - 1
                        r.ImGui_DrawList_AddRectFilled(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)
                        r.ImGui_DrawList_AddRectFilled(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)

                        -- Get track for meters (if available)
                        local state_module = require('lib.state')
                        local sidefx_state = state_module.state
                        if sidefx_state.track and sidefx_state.track.pointer then
                            local peak_l = r.Track_GetPeakInfo(sidefx_state.track.pointer, 0)
                            local peak_r = r.Track_GetPeakInfo(sidefx_state.track.pointer, 1)
                            local function draw_meter_bar(x, w, peak)
                                if peak > 0 then
                                    local peak_db = 20 * math.log(peak, 10)
                                    peak_db = math.max(-60, math.min(24, peak_db))
                                    local peak_norm = (peak_db + 60) / 84
                                    local meter_fill_h = fader_h * peak_norm
                                    if meter_fill_h > 1 then
                                        local meter_top = screen_y + fader_h - meter_fill_h
                                        local meter_color
                                        if peak_db > 0 then meter_color = 0xFF4444FF
                                        elseif peak_db > -6 then meter_color = 0xFFAA44FF
                                        elseif peak_db > -18 then meter_color = 0x44FF44FF
                                        else meter_color = 0x44AA44FF end
                                        r.ImGui_DrawList_AddRectFilled(draw_list, x, meter_top, x + w, screen_y + fader_h - 1, meter_color, 0)
                                    end
                                end
                            end
                            draw_meter_bar(meter_l_x + 1, half_meter_w - 1, peak_l)
                            draw_meter_bar(meter_r_x + 1, half_meter_w - 1, peak_r)
                        end

                        r.ImGui_DrawList_AddRect(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)
                        r.ImGui_DrawList_AddRect(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)

                        -- Invisible slider for fader interaction
                        r.ImGui_SetCursorScreenPos(ctx.ctx, fader_x, screen_y)
                        local imgui = require('imgui')
                        ctx:push_style_color(imgui.Col.FrameBg(), 0x00000000)
                        ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x00000000)
                        ctx:push_style_color(imgui.Col.FrameBgActive(), 0x00000000)
                        ctx:push_style_color(imgui.Col.SliderGrab(), 0xAAAAAAFF)
                        ctx:push_style_color(imgui.Col.SliderGrabActive(), 0xFFFFFFFF)
                        local gain_changed, new_gain_db = ctx:v_slider_double("##gain_fader_v", fader_w, fader_h, gain_db, -24, 24, "")
                        if gain_changed then
                            local new_norm = (new_gain_db + 24) / 48
                            pcall(function() utility:set_param_normalized(0, new_norm) end)
                            interacted = true
                        end
                        if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                            pcall(function() utility:set_param_normalized(0, 0.5) end)  -- Reset to 0dB
                            interacted = true
                        end
                        ctx:pop_style_color(5)

                        -- dB label below fader (with double-click editing)
                        local label_h = 16
                        local label_y = screen_y + fader_h + 2
                        local label_x = fader_x
                        r.ImGui_DrawList_AddRectFilled(draw_list, label_x, label_y, label_x + fader_w, label_y + label_h, 0x222222FF, 2)
                        local db_label = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.0f", gain_db) or string.format("%.0f", gain_db))
                        local text_w = r.ImGui_CalcTextSize(ctx.ctx, db_label)
                        r.ImGui_DrawList_AddText(draw_list, label_x + (fader_w - text_w) / 2, label_y + 1, 0xCCCCCCFF, db_label)

                        -- Invisible button for dB label (for double-click editing)
                        r.ImGui_SetCursorScreenPos(ctx.ctx, label_x, label_y)
                        ctx:invisible_button("##gain_db_label", fader_w, label_h)

                        -- Double-click on dB label to edit value
                        if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                            ctx:open_popup("##gain_edit_popup")
                        end

                        -- Edit popup for gain
                        if ctx:begin_popup("##gain_edit_popup") then
                            local imgui = require('imgui')
                            ctx:set_next_item_width(60)
                            ctx:set_keyboard_focus_here()
                            local input_changed, input_val = ctx:input_double("##gain_input", gain_db, 0, 0, "%.1f")
                            if input_changed then
                                local new_norm = (math.max(-24, math.min(24, input_val)) + 24) / 48
                                pcall(function() utility:set_param_normalized(0, new_norm) end)
                                interacted = true
                            end
                            if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
                                ctx:close_current_popup()
                            end
                            ctx:end_popup()
                        end

                        -- Advance cursor past fader
                        r.ImGui_SetCursorScreenPos(ctx.ctx, screen_x, label_y + label_h)
                    end

                    -- Phase Invert controls
                    local ok_phase_l, phase_l = pcall(function() return utility:get_param_normalized(2) end)
                    local ok_phase_r, phase_r = pcall(function() return utility:get_param_normalized(3) end)

                    if ok_phase_l and ok_phase_r then
                        ctx:spacing()

                        -- Center "Phase" label
                        local phase_text = "Phase"
                        local phase_text_w = r.ImGui_CalcTextSize(ctx.ctx, phase_text)
                        center_item(phase_text_w)
                        ctx:push_style_color(r.ImGui_Col_Text(), 0xCC8888FF)
                        ctx:text(phase_text)
                        ctx:pop_style_color()

                        local phase_btn_w = 28
                        local phase_gap = 4
                        local phase_total_w = phase_btn_w * 2 + phase_gap

                        -- Center the pair of phase buttons
                        center_item(phase_total_w)

                        -- Phase L button
                        local phase_l_on = phase_l > 0.5
                        if phase_l_on then
                            ctx:push_style_color(r.ImGui_Col_Button(), 0xCC6666FF)
                        else
                            ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                        end
                        if ctx:button(phase_l_on and "ØL" or "L", phase_btn_w, 20) then
                            pcall(function() utility:set_param_normalized(2, phase_l_on and 0 or 1) end)
                            interacted = true
                        end
                        ctx:pop_style_color()
                        if r.ImGui_IsItemHovered(ctx.ctx) then
                            ctx:set_tooltip(phase_l_on and "Left Phase: Inverted" or "Left Phase: Normal")
                        end

                        ctx:same_line(0, phase_gap)

                        -- Phase R button
                        local phase_r_on = phase_r > 0.5
                        if phase_r_on then
                            ctx:push_style_color(r.ImGui_Col_Button(), 0xCC6666FF)
                        else
                            ctx:push_style_color(r.ImGui_Col_Button(), 0x444444FF)
                        end
                        if ctx:button(phase_r_on and "ØR" or "R", phase_btn_w, 20) then
                            pcall(function() utility:set_param_normalized(3, phase_r_on and 0 or 1) end)
                            interacted = true
                        end
                        ctx:pop_style_color()
                        if r.ImGui_IsItemHovered(ctx.ctx) then
                            ctx:set_tooltip(phase_r_on and "Right Phase: Inverted" or "Right Phase: Normal")
                        end
                    end
                end
            end  -- end expanded sidebar

            r.ImGui_EndTable(ctx.ctx)
        end  -- end device_layout table

            r.ImGui_EndTable(ctx.ctx)  -- end device_wrapper table
        end

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
