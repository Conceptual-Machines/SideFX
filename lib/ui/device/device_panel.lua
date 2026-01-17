--- Device Panel UI Component
-- Renders a single FX as an Ableton-style device panel.
-- @module ui.device_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper
local imgui = require('imgui')
local widgets = require('lib.ui.common.widgets')
local fx_utils = require('lib.fx.fx_utils')
local modulator_sidebar = require('lib.ui.device.modulator_sidebar')
local drawing = require('lib.ui.common.drawing')
local icons = require('lib.ui.common.icons')
local fx_naming = require('lib.fx.fx_naming')
local param_utils = require('lib.utils.param_utils')
local state_module = require('lib.core.state')
local state = state_module.state

-- Device panel sub-modules
local header = require('lib.ui.device.device_panel.header')
local collapsed_header = require('lib.ui.device.device_panel.collapsed_header')
local modulator_header = require('lib.ui.device.device_panel.modulator_header')
local device_column = require('lib.ui.device.device_panel.device_column')

local M = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

M.config = {
    column_width = 180,        -- Width per parameter column
    header_height = 32,
    param_height = 50,         -- Height per param row (label + slider + value)
    sidebar_width = 120,       -- Width for sidebar (controls on right)
    sidebar_padding = 12,      -- Extra padding for scrollbar
    padding = 8,               -- Padding around content
    border_radius = 6,
    fader_width = 28,          -- Fader width
    fader_height = 70,         -- Fader height
    knob_size = 48,            -- Knob diameter
    -- Modulator sidebar (left side of device)
    mod_sidebar_width = 250,   -- Width for modulator controls
    mod_sidebar_collapsed_width = 24,  -- Collapsed width
    mod_slot_width = 54,
    mod_slot_height = 54,
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

-- NOTE: Panel collapsed states are now managed by the state module for persistence:
-- state.device_panel_collapsed - whole panel collapsed to header strip
-- state.device_sidebar_collapsed - utility sidebar collapsed
-- state.device_controls_collapsed - device params collapsed, but modulators visible
-- state.mod_sidebar_collapsed - modulator sidebar collapsed
-- state.expanded_mod_slot - which modulator slot is expanded

-- Local aliases for convenience (updated each frame from state)
local sidebar_collapsed
local panel_collapsed
local device_collapsed

-- Rename state: which FX is being renamed and the edit buffer
local rename_active = {}    -- guid -> true if rename mode active
local rename_buffer = {}    -- guid -> current edit text

--------------------------------------------------------------------------------
-- Utility Restoration
--------------------------------------------------------------------------------

--- Restore missing utility FX to a device container
local function restore_utility(container)
    if not container or not container:is_container() then
        return false
    end
    
    if not state.track then
        return false
    end
    
    -- Set flag to stop rendering immediately (prevents stale data errors)
    state.deletion_pending = true
    
    -- Use the JSFX path constant from device module
    local device_module = require('lib.device.device')
    local utility_jsfx = device_module.UTILITY_JSFX
    
    -- Step 1: Add utility to the TRACK first (not directly to container)
    local ok_add, util_fx = pcall(function()
        return state.track:add_fx_by_name(utility_jsfx, false, -1)
    end)
    
    if not ok_add or not util_fx or util_fx.pointer < 0 then
        return false
    end
    
    -- Step 2: Move utility INTO the container at position 1 (after main FX)
    local ok_move = pcall(function()
        container:add_fx_to_container(util_fx, 1)
    end)
    
    if not ok_move then
        -- Clean up: delete the utility we just added
        pcall(function() util_fx:delete() end)
        return false
    end
    
    -- Step 3: Rename utility to match device naming and initialize parameters
    local ok_name, container_name = pcall(function() return container:get_name() end)
    if ok_name and container_name then
        local device_idx = container_name:match("^D(%d+):")
        if device_idx then
            local util_name = string.format("D%d_Util", tonumber(device_idx))
            -- Re-find utility inside container after move
            local util_inside = fx_utils.get_device_utility(container)
            if util_inside then
                pcall(function() util_inside:set_named_config_param("renamed_name", util_name) end)
                -- Initialize gain to 0dB
                pcall(function() util_inside:set_param(0, 0) end)
            end
        end
    end
    
    return true
end

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
local function draw_header(ctx, fx, is_panel_collapsed, panel_collapsed, state_guid, guid, name, device_id, drag_guid, opts, colors, enabled, is_device_collapsed)
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
                state_module.save_device_collapsed_states()
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
    end

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
        if ui_avail_w > 0 and drawing.draw_ui_icon(ctx, "##ui_" .. state_guid, ui_avail_w, 24, opts.icon_font) then
            fx:show(3)
            interacted = true
        end
        if r.ImGui_IsItemHovered(ctx.ctx) then
            ctx:set_tooltip("Open " .. name)
        end

        -- ON/OFF toggle
        r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
        local on_tint = enabled and 0x88FF88FF or 0x888888FF
        if icons.button_bordered(ctx, "on_off_" .. state_guid, icons.Names.on, 18, on_tint) then
            fx:set_enabled(not enabled)
            interacted = true
        end

        -- Close button
        r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
        if icons.button_bordered(ctx, "delete_" .. state_guid, icons.Names.cancel, 18, 0xFF6666FF) then
            if opts.on_delete then
                opts.on_delete(fx)
            else
                fx:delete()
            end
            interacted = true
        end

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
    local modulator_sidebar = require('lib.ui.device.modulator_sidebar')
    return modulator_sidebar.draw(ctx, fx, container, guid, state_guid, cfg, opts)
end


--- Module requires
local params_column = require('lib.ui.device.device_panel.params')
local sidebar_column = require('lib.ui.device.device_panel.sidebar')

--- Draw chain sidebar column wrapper
local function draw_sidebar_column(ctx, fx, container, state_guid, sidebar_actual_w, is_sidebar_collapsed, cfg, opts, colors)
    -- Add on_restore_utility callback to opts if not present
    local sidebar_opts = opts
    if not opts.on_restore_utility then
        sidebar_opts = {}
        for k, v in pairs(opts) do sidebar_opts[k] = v end
        sidebar_opts.on_restore_utility = function(target_container)
            restore_utility(target_container)
        end
    end
    return sidebar_column.draw(ctx, fx, container, state_guid, sidebar_actual_w, is_sidebar_collapsed, cfg, sidebar_opts, colors)
end

--- Filter FX parameters, excluding sidebar controls (wet, delta, bypass)
-- Uses stored parameter selections from state if available, otherwise defaults to first 32.
-- Respects user-configured maximum parameter limit.
local function get_visible_params(fx)
    local r = reaper
    local visible_params = {}
    
    -- Get max params from config (default 64, max 128)
    local MAX_VISIBLE_PARAMS = state_module.get_max_visible_params()
    
    -- Get the actual plugin name (stripped of SideFX prefixes)
    local ok_name, fx_name = pcall(function() return fx:get_name() end)
    if not ok_name or not fx_name then
        return visible_params
    end
    
    -- Strip SideFX prefixes to get clean plugin name
    local naming = require('lib.utils.naming')
    local clean_name = naming.strip_sidefx_prefixes(fx_name)
    
    -- Try to find stored parameter selections
    -- Check both with and without format prefixes (VST:, AU:, etc.)
    local selected_params = nil
    if state.param_selections then
        -- Try exact match first
        if state.param_selections[fx_name] then
            selected_params = state.param_selections[fx_name]
        elseif state.param_selections[clean_name] then
            selected_params = state.param_selections[clean_name]
        else
            -- Try matching with common prefixes
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
        -- Use stored selections (enforce max limit)
        for i, param_idx in ipairs(selected_params) do
            -- Enforce maximum limit even for saved selections
            if #visible_params >= MAX_VISIBLE_PARAMS then
                break
            end
            
            if param_idx >= 0 and param_idx < param_count then
                -- Verify it's not a sidebar control
                local ok_pn, pname = pcall(function() return fx:get_param_name(param_idx) end)
                if ok_pn and pname then
                    local lower = pname:lower()
                    if lower ~= "wet" and lower ~= "delta" and lower ~= "bypass" then
                        table.insert(visible_params, param_idx)
                    end
                end
            end
        end
    else
        -- Default: first MAX_VISIBLE_PARAMS
    for i = 0, param_count - 1 do
            if #visible_params >= MAX_VISIBLE_PARAMS then
                break
            end

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

--- Draw expanded panel content (2-column table: modulators | device_wrapper)
-- Device wrapper contains nested 2-column table: device_content | gain_pan
local function draw_expanded_panel(ctx, fx, container, panel_height, cfg, visible_params, visible_count, num_columns, params_per_column, is_sidebar_collapsed, collapsed_sidebar_w, mod_sidebar_w, content_width, state_guid, guid, name, device_id, drag_guid, enabled, opts, colors, panel_collapsed, is_selected)
    local r = reaper
    local interacted = false

    -- Check if device controls are collapsed
    local is_device_collapsed = device_collapsed[state_guid] or false

    -- Fixed width for gain/pan column (right side of nested table)
    local gain_pan_w = 62

    -- Outer table: dynamically 2 or 3 columns based on collapse state
    -- When expanded: 3 columns (modulators | device content | gain/pan)
    -- When collapsed: 2 columns (modulators | device content)
    local num_cols = is_device_collapsed and 2 or 3

    -- Use pcall to ensure ID stack cleanup even on errors
    local ok_render, render_err = pcall(function()
        ctx:with_table("panel_outer_" .. guid, num_cols, r.ImGui_TableFlags_BordersInnerV(), function()
            -- Column 1: Modulators (left) - fixed width
            r.ImGui_TableSetupColumn(ctx.ctx, "modulators", r.ImGui_TableColumnFlags_WidthFixed(), mod_sidebar_w)

        -- Column 2: Device Content (center) - stretches when expanded, fixed narrow when collapsed
        if is_device_collapsed then
            -- Collapsed: narrow fixed width (buttons + name + fader)
            local collapsed_width = 100  -- Narrow width for collapsed view
            r.ImGui_TableSetupColumn(ctx.ctx, "device_content", r.ImGui_TableColumnFlags_WidthFixed(), collapsed_width)
        else
            -- Expanded: stretch to fit params
            r.ImGui_TableSetupColumn(ctx.ctx, "device_content", r.ImGui_TableColumnFlags_WidthStretch())
        end

        -- Column 3: Gain/Pan (right) - fixed width (only when expanded)
        if not is_device_collapsed then
            r.ImGui_TableSetupColumn(ctx.ctx, "gain_pan", r.ImGui_TableColumnFlags_WidthFixed(), gain_pan_w)
        end

        -- === ROW 1: HEADER ===
        r.ImGui_TableNextRow(ctx.ctx)

        -- Set header row background color when selected (subtle highlight)
        if is_selected then
            r.ImGui_TableSetBgColor(ctx.ctx, r.ImGui_TableBgTarget_RowBg0(), 0x3A3A4AFF)
        end

        -- Header Column 1: Modulator collapse button + "Mod" label + matrix button
        r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
        if modulator_header.draw(ctx, state_guid, { on_mod_matrix = opts.on_mod_matrix }) then
            interacted = true
        end

        -- Header Column 2: Device name/path/mix/delta/ui when expanded, buttons when collapsed
        r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
        if not is_device_collapsed then
            -- Expanded: show full device header
            if header.draw_device_name_path(ctx, fx, container, guid, name, device_id, drag_guid, enabled, opts, colors, state_guid, device_collapsed) then
                interacted = true
            end
        else
            -- Collapsed: show 2-row button layout
            if collapsed_header.draw(ctx, fx, container, state_guid, enabled, device_collapsed, opts, colors) then
                interacted = true
            end
        end

        -- Header Column 3: Control buttons (only when expanded)
        if not is_device_collapsed then
            r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
            
            -- Prepare options for header buttons
            local header_opts = {
                on_delete = opts.on_delete,
            }
            
            if header.draw_device_buttons(ctx, fx, container, state_guid, enabled, is_device_collapsed, device_collapsed, header_opts, colors) then
                interacted = true
            end
        end

        -- CRITICAL: If FX list was invalidated by header operations (e.g., delete), bail out
        if state.fx_list_invalid then
            return  -- Early return from with_table callback
        end

        -- Separator row between header and content
        r.ImGui_TableNextRow(ctx.ctx)
        r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
        ctx:separator()
        r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
        ctx:separator()
        if not is_device_collapsed then
            r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
            ctx:separator()
        end

        -- === ROW 2: CONTENT ===
        r.ImGui_TableNextRow(ctx.ctx)

        -- Content Column 1: Modulators
        r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
        if draw_modulator_column(ctx, fx, container, guid, state_guid, cfg, opts) then
            interacted = true
        end

        -- CRITICAL: If FX list was invalidated (e.g., modulator added), bail out immediately
        -- to avoid accessing stale FX references in the rest of this callback
        if state.fx_list_invalid then
            return  -- Early return from with_table callback
        end

        -- Content Column 2: Device params or collapsed view
        -- Build mod_links: map of param_idx -> link_info for all modulated params
        local mod_links = {}
        local link_count = 0
        local ok_params, param_count = pcall(function() return fx:get_num_params() end)
        if ok_params and param_count then
            -- Initialize baseline_formatted cache if needed
            state.baseline_formatted = state.baseline_formatted or {}

            for param_idx = 0, param_count - 1 do
                local link_info = fx:get_param_link_info(param_idx)
                if link_info then
                    -- Add bipolar flag from state (if set)
                    local link_key = guid .. "_" .. param_idx
                    link_info.is_bipolar = state.link_bipolar and state.link_bipolar[link_key] or false

                    -- Cache formatted baseline value on first detection
                    if not state.baseline_formatted[link_key] and link_info.baseline then
                        local ok_cache = pcall(function()
                            local current_val = fx:get_param_normalized(param_idx)
                            fx:set_param_normalized(param_idx, link_info.baseline)
                            local baseline_fmt = fx:get_formatted_param_value(param_idx)
                            fx:set_param_normalized(param_idx, current_val)
                            if baseline_fmt then
                                state.baseline_formatted[link_key] = baseline_fmt
                            end
                        end)
                    end
                    link_info.baseline_formatted = state.baseline_formatted[link_key]

                    mod_links[param_idx] = link_info
                    link_count = link_count + 1
                end
            end
        end

        -- Get modulators for right-click linking in params
        -- Also find the container-local index of the selected modulator for filtering
        local modulators = {}
        local selected_mod_container_idx = nil  -- Container-local index of the selected modulator
        local selected_slot = state.expanded_mod_slot and state.expanded_mod_slot[state_guid]
        if container then
            local container_idx = 0
            local ok_iter, iter = pcall(function() return container:iter_container_children() end)
            if ok_iter and iter then
                local mod_slot = 0
                for child in iter do
                    local ok_name, child_name = pcall(function() return child:get_name() end)
                    if ok_name and child_name and child_name:match("SideFX[_ ]Modulator") then
                        table.insert(modulators, child)
                        -- Check if this is the selected modulator
                        if selected_slot ~= nil and mod_slot == selected_slot then
                            selected_mod_container_idx = container_idx
                        end
                        mod_slot = mod_slot + 1
                    end
                    container_idx = container_idx + 1
                end
            end
        end

        -- Keep unfiltered links for baseline values (so slider doesn't jump when switching LFOs)
        local all_mod_links = mod_links

        -- Filter mod_links to only show UI indicators for selected modulator (if one is selected)
        if selected_mod_container_idx ~= nil then
            local filtered_links = {}
            for param_idx, link_info in pairs(mod_links) do
                if link_info.effect == selected_mod_container_idx then
                    filtered_links[param_idx] = link_info
                end
            end
            mod_links = filtered_links
        end

        -- Set opts AFTER filtering
        -- mod_links = filtered (for modulation UI indicators)
        -- all_mod_links = unfiltered (for baseline values)
        opts.mod_links = mod_links
        opts.all_mod_links = all_mod_links
        opts.state = state  -- Pass state so params can update link_baselines
        opts.fx_guid = guid  -- Pass guid for building link keys
        -- opts.plugin_name is set in M.draw before this function is called
        opts.modulators = modulators
        opts.track = state.track  -- Pass track for bake operations
        opts.state_guid = state_guid  -- Pass state_guid to look up selected LFO slot

        if device_column.draw(ctx, is_device_collapsed, params_column, fx, guid, visible_params, visible_count, num_columns, params_per_column, opts, name, fx_naming, draw_sidebar_column, container, state_guid, gain_pan_w, is_sidebar_collapsed, cfg, colors) then
            interacted = true
        end

        -- Content Column 3: Gain/Pan controls (only when expanded - column doesn't exist when collapsed)
        if not is_device_collapsed then
            r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
            if draw_sidebar_column(ctx, fx, container, state_guid, gain_pan_w, is_sidebar_collapsed, cfg, opts, colors) then
                interacted = true
            end
        end

        end)  -- end with_table (panel_outer)
    end)

    if not ok_render then
        r.ShowConsoleMsg("Error rendering device panel: " .. tostring(render_err) .. "\n")
    end

    return interacted
end

--- Draw panel frame (background + border)
local function draw_panel_background(draw_list, cursor_x, cursor_y, panel_width, panel_height, colors, cfg)
    local r = reaper
    -- Draw panel background (filled rectangle, square corners)
    r.ImGui_DrawList_AddRectFilled(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        colors.panel_bg, 0)  -- 0 = square corners
end

local function draw_panel_border(draw_list, cursor_x, cursor_y, panel_width, panel_height, colors, cfg, is_selected)
    local r = reaper
    -- Draw full rectangle border (all four sides)
    -- No highlight - selection indicated by header background change
    local border_color = colors.panel_border
    r.ImGui_DrawList_AddRect(draw_list,
        cursor_x, cursor_y,
        cursor_x + panel_width, cursor_y + panel_height,
        border_color, 0, 0, 1)  -- 0 = no rounding, 0 = all corners, 1 = thickness
end

--- Calculate panel dimensions based on collapsed state
local function calculate_panel_dimensions(is_panel_collapsed, avail_height, cfg, visible_count, is_sidebar_collapsed, collapsed_sidebar_w, mod_sidebar_w, is_device_collapsed, show_mix_delta)
    local panel_height, panel_width, content_width, num_columns, params_per_column

    -- Fixed width for gain/pan column (right side of nested table)
    local gain_pan_w = 62

    -- Extra width for mix/delta columns in header when shown
    local mix_delta_extra_w = show_mix_delta and 60 or 0  -- mix (28) + delta (32)

    if is_panel_collapsed then
        -- Collapsed: full height but narrow width
        panel_height = avail_height
        panel_width = 140  -- Minimal width for collapsed panel
        content_width = 0
        num_columns = 0
        params_per_column = 0
    else
        -- Expanded: use full available height to align with chain
        panel_height = avail_height

        -- Calculate how many params fit per column based on available height
        local usable_height = panel_height - cfg.header_height - cfg.padding * 2
        params_per_column = math.floor(usable_height / cfg.param_height)
        params_per_column = math.max(1, params_per_column)

        -- Calculate columns needed to show visible params only
        num_columns = math.ceil(visible_count / params_per_column)
        num_columns = math.max(1, num_columns)

        -- Calculate device content width (for params) based on collapse state
        local device_content_width
        if is_device_collapsed then
            -- Fixed 2x2 layout (UI|◀ then ON|×)
            device_content_width = 60
        else
            device_content_width = cfg.column_width * num_columns  -- Full width for params
        end

        -- Calculate device wrapper width: device_content + gain_pan (only when expanded)
        local device_wrapper_width
        if is_device_collapsed then
            -- Collapsed: no separate gain/pan column, it's in the device column
            device_wrapper_width = device_content_width
        else
            -- Expanded: device content + gain/pan column + extra for mix/delta
            device_wrapper_width = device_content_width + gain_pan_w + mix_delta_extra_w
        end

        -- Calculate total panel width: modulator column + device wrapper + padding
        content_width = cfg.column_width * num_columns
        panel_width = mod_sidebar_w + device_wrapper_width + cfg.padding * 2
    end

    return {
        panel_height = panel_height,
        panel_width = panel_width,
        content_width = content_width,
        num_columns = num_columns,
        params_per_column = params_per_column
    }
end

--- Extract FX display name and device identifier
-- @param fx ReaWrap FX object
-- @param container ReaWrap container FX object (optional)
-- @return string name, string device_id
local function extract_fx_display_info(fx, container)
    local fx_utils = require('lib.fx.fx_utils')
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

    return name, device_id
end

--- Setup modulator sidebar state and calculate width
-- @param state_guid string GUID for state lookup
-- @param cfg table Configuration table
-- @return boolean is_collapsed, number width
local function setup_modulator_sidebar_state(state_guid, cfg)
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

    return is_mod_sidebar_collapsed, mod_sidebar_w
end

--- Validate FX before rendering
-- @param fx ReaWrap FX object
-- @return boolean false if FX is invalid (should skip rendering), true otherwise
local function validate_fx_for_rendering(fx)
    if not fx then return false end

    -- Safety check: FX might have been deleted
    local ok, guid = pcall(function() return fx:get_guid() end)
    if not ok or not guid then return false end

    -- Skip rendering modulators - they're handled by modulator_grid_panel
    local is_modulator = fx_utils.is_modulator_fx(fx)
    if is_modulator then
        return false
    end

    return true
end

--- Draw right-click context menu for device panel
local function draw_context_menu(ctx, fx, guid, name, enabled, opts)
    local r = reaper

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
                state.renaming_fx = guid  -- Use FX GUID
                state.rename_text = name
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
end

--- Draw panel content (header + collapsed/expanded body)
local function draw_panel_content(ctx, fx, container, guid, is_panel_collapsed, is_sidebar_collapsed, cfg, visible_params, visible_count, collapsed_sidebar_w, mod_sidebar_w, state_guid, name, device_id, drag_guid, enabled, opts, colors, avail_height)
    local r = reaper

    -- Check if device controls are collapsed
    local is_device_collapsed = device_collapsed[state_guid] or false

    -- Check config for mix/delta display
    local config = require('lib.core.config')
    local show_mix_delta = config.get('show_mix_delta')

    -- Calculate panel dimensions
    local dims = calculate_panel_dimensions(is_panel_collapsed, avail_height, cfg, visible_count, is_sidebar_collapsed, collapsed_sidebar_w, mod_sidebar_w, is_device_collapsed, show_mix_delta)
    local panel_height = dims.panel_height
    local panel_width = dims.panel_width
    local content_width = dims.content_width
    local num_columns = dims.num_columns
    local params_per_column = dims.params_per_column

    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    local interacted = false

    -- Draw panel background first
    draw_panel_background(draw_list, cursor_x, cursor_y, panel_width, panel_height, colors, cfg)

    -- Begin child for panel content (no child border - we draw it manually)
    local window_flags = imgui.WindowFlags.NoScrollbar()
    if ctx:begin_child("panel_" .. guid, panel_width, panel_height, 0, window_flags) then
        -- Click-to-select: detect clicks on panel background (not on widgets)
        if opts.on_select and r.ImGui_IsWindowHovered(ctx.ctx, r.ImGui_HoveredFlags_ChildWindows())
           and r.ImGui_IsMouseClicked(ctx.ctx, 0)
           and not r.ImGui_IsAnyItemHovered(ctx.ctx) then
            opts.on_select()
        end

        -- Wrap ALL content in pcall to ensure end_child is ALWAYS called
        -- This prevents ImGui state corruption ("Missing EndChild" errors)
        local ok, err = pcall(function()
            -- Draw collapsed body and return early if collapsed
            if is_panel_collapsed then
                -- For collapsed, still draw a simple header + body
                local header_interacted = draw_header(ctx, fx, is_panel_collapsed, panel_collapsed, state_guid, guid, name, device_id, drag_guid, opts, colors, enabled, is_device_collapsed)
                if header_interacted then interacted = true end

                local collapsed_interacted = draw_collapsed_body(ctx, fx, state_guid, guid, name, enabled, opts, colors)
                if collapsed_interacted then interacted = true end
                return
            end

            -- Draw expanded panel with 3-column layout (no top header)
            -- Device header will be drawn inside column 2
            if draw_expanded_panel(ctx, fx, container, panel_height, cfg, visible_params, visible_count, num_columns, params_per_column, is_sidebar_collapsed, collapsed_sidebar_w, mod_sidebar_w, content_width, state_guid, guid, name, device_id, drag_guid, enabled, opts, colors, panel_collapsed, opts.is_selected) then
                interacted = true
            end
        end)

        ctx:end_child()  -- ALWAYS end panel, even on error

        if not ok then
            -- Log error but don't propagate - we've already cleaned up ImGui state
            r.ShowConsoleMsg("SideFX panel error: " .. tostring(err) .. "\n")
        end
    end

    -- Draw border AFTER content so it's on top
    draw_panel_border(draw_list, cursor_x, cursor_y, panel_width, panel_height, colors, cfg, opts.is_selected)

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

    -- Initialize state aliases (from state module for persistence)
    state.device_panel_collapsed = state.device_panel_collapsed or {}
    state.device_sidebar_collapsed = state.device_sidebar_collapsed or {}
    state.device_controls_collapsed = state.device_controls_collapsed or {}
    panel_collapsed = state.device_panel_collapsed
    sidebar_collapsed = state.device_sidebar_collapsed
    device_collapsed = state.device_controls_collapsed

    -- Skip rendering if FX list is already invalid (stale data from previous operations)
    if state.fx_list_invalid then return false end

    -- Validate FX before rendering
    if not validate_fx_for_rendering(fx) then return false end

    -- Get FX GUID (safe since validation passed)
    local guid = fx:get_guid()

    -- Use container GUID for drag/drop if we have a container
    local container = opts.container
    local drag_guid = container and container:get_guid() or guid

    -- Extract FX display info
    local name, device_id = extract_fx_display_info(fx, container)

    -- Get full plugin name for unit override lookups (different from display name)
    -- First try to get the original plugin name stored when device was created
    local full_name = state_module.get_fx_original_name(guid)
    if not full_name then
        -- Fall back to current FX name (may be renamed like "D1_FX: ...")
        local ok_full_name
        ok_full_name, full_name = pcall(function() return fx:get_name() end)
        if not ok_full_name then full_name = name end
    end

    -- Set plugin name in opts for unit override lookups in nested functions
    opts.plugin_name = full_name

    -- Get enabled state from container (or FX if no container)
    local enabled = false
    if container then
        local ok3, enabled_val = pcall(function() return container:get_enabled() end)
        if ok3 then enabled = enabled_val end
    else
        local ok3, enabled_val = pcall(function() return fx:get_enabled() end)
        if ok3 then enabled = enabled_val end
    end

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

    -- Setup modulator sidebar state and calculate width
    local is_mod_sidebar_collapsed, mod_sidebar_w = setup_modulator_sidebar_state(state_guid, cfg)

    local interacted = false

    ctx:push_id(guid)

    -- Draw panel content (frame + header + body)
    if draw_panel_content(ctx, fx, container, guid, is_panel_collapsed, is_sidebar_collapsed, cfg, visible_params, visible_count, collapsed_sidebar_w, mod_sidebar_w, state_guid, name, device_id, drag_guid, enabled, opts, colors, avail_height) then
        interacted = true
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
    state.device_sidebar_collapsed = {}
    state_module.save_device_collapsed_states()
end

--- Set sidebar collapsed state for a specific FX.
-- @param guid string FX GUID
-- @param collapsed boolean
function M.set_sidebar_collapsed(guid, collapsed)
    state.device_sidebar_collapsed = state.device_sidebar_collapsed or {}
    state.device_sidebar_collapsed[guid] = collapsed
    state_module.save_device_collapsed_states()
end

--- Get sidebar collapsed state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_sidebar_collapsed(guid)
    return (state.device_sidebar_collapsed and state.device_sidebar_collapsed[guid]) or false
end

--- Collapse all sidebars
function M.collapse_all_sidebars()
    state.device_sidebar_collapsed = state.device_sidebar_collapsed or {}
    for guid, _ in pairs(expanded_state) do
        state.device_sidebar_collapsed[guid] = true
    end
    state_module.save_device_collapsed_states()
end

--- Expand all sidebars
function M.expand_all_sidebars()
    state.device_sidebar_collapsed = {}
    state_module.save_device_collapsed_states()
end

--- Reset all panel collapsed states.
function M.reset_panel_collapsed()
    state.device_panel_collapsed = {}
    state_module.save_device_collapsed_states()
end

--- Set panel collapsed state for a specific FX.
-- @param guid string FX GUID
-- @param collapsed boolean
function M.set_panel_collapsed(guid, collapsed)
    state.device_panel_collapsed = state.device_panel_collapsed or {}
    state.device_panel_collapsed[guid] = collapsed
    state_module.save_device_collapsed_states()
end

--- Get panel collapsed state for a specific FX.
-- @param guid string FX GUID
-- @return boolean
function M.is_panel_collapsed(guid)
    return (state.device_panel_collapsed and state.device_panel_collapsed[guid]) or false
end

--- Collapse all panels
function M.collapse_all_panels()
    state.device_panel_collapsed = state.device_panel_collapsed or {}
    for guid, _ in pairs(expanded_state) do
        state.device_panel_collapsed[guid] = true
    end
    state_module.save_device_collapsed_states()
end

--- Expand all panels
function M.expand_all_panels()
    state.device_panel_collapsed = {}
    state_module.save_device_collapsed_states()
end

return M
