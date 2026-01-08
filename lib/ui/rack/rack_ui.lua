--- Rack UI Component
-- Comprehensive rack panel UI with chains, meters, and nested rack support
-- @module ui.rack_ui
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper
local widgets = require('lib.ui.common.widgets')
local drawing = require('lib.ui.common.drawing')

local M = {}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Finalize/save rack rename
-- @param state table State object
-- @param rack_guid string Rack GUID
-- @param state_module table State module reference
local function finalize_rack_rename(state, rack_guid, state_module)
    if state.rename_text ~= "" then
        state.display_names[rack_guid] = state.rename_text
    else
        state.display_names[rack_guid] = nil
    end
    state_module.save_display_names()
    state.renaming_fx = nil
    state.rename_text = ""
    state._rename_focused = nil
end

--- Cancel rack rename
-- @param state table State object
local function cancel_rack_rename(state)
    state.renaming_fx = nil
    state.rename_text = ""
    state._rename_focused = nil
end

--- Draw rack rename input field
-- @param ctx ImGui context
-- @param rack_guid string Rack GUID
-- @param state table State object
-- @param state_module table State module reference
-- @return boolean True if interacted
local function draw_rack_rename_input(ctx, rack_guid, state, state_module)
    local interacted = false

    -- Initialize rename text if not set
    if not state.rename_text or state.rename_text == "" then
        state.rename_text = state.display_names[rack_guid] or ""
    end

    ctx:set_next_item_width(-1)

    -- Set keyboard focus on first frame
    if not state._rename_focused then
        ctx:set_keyboard_focus_here()
        state._rename_focused = true
    end

    -- Style the input to be visible
    ctx:push_style_color(imgui.Col.FrameBg(), 0x4A4A4AFF)
    ctx:push_style_color(imgui.Col.Text(), 0xFFFFFFFF)
    local changed, new_text = ctx:input_text("##rack_rename" .. rack_guid, state.rename_text, imgui.InputTextFlags.EnterReturnsTrue())
    ctx:pop_style_color(2)

    state.rename_text = new_text

    -- Handle input events
    if changed then
        finalize_rack_rename(state, rack_guid, state_module)
        interacted = true
    elseif ctx:is_item_deactivated_after_edit() then
        finalize_rack_rename(state, rack_guid, state_module)
        interacted = true
    elseif ctx:is_key_pressed(imgui.Key.Escape()) then
        cancel_rack_rename(state)
        interacted = true
    end

    return interacted
end

--- Draw rack context menu (Rename, Dissolve, Delete)
-- @param ctx ImGui context
-- @param button_id string Button ID for popup context
-- @param rack_guid string Rack GUID
-- @param rack ReaWrap rack FX object
-- @param state table State object
-- @param callbacks table Callbacks {on_rename, on_dissolve, on_delete}
local function draw_rack_context_menu(ctx, button_id, rack_guid, rack, state, callbacks)
    if ctx:begin_popup_context_item(button_id) then
        if ctx:menu_item("Rename") then
            callbacks.on_rename(rack_guid, state.display_names[rack_guid])
        end
        ctx:separator()
        if ctx:menu_item("Dissolve Container") then
            callbacks.on_dissolve(rack)
        end
        ctx:separator()
        if ctx:menu_item("Delete") then
            callbacks.on_delete(rack)
        end
        ctx:end_popup()
    end
end

--- Draw rack toggle/name button
-- @param ctx ImGui context
-- @param rack_guid string Rack GUID
-- @param expand_icon string Icon to display (▼ or ▶)
-- @param rack_name string Display name of rack
-- @param is_expanded boolean Whether rack is expanded
-- @param button_id string Unique button ID
-- @param callbacks table Callbacks {on_toggle_expand}
-- @return boolean True if clicked
local function draw_rack_toggle_button(ctx, rack_guid, expand_icon, rack_name, is_expanded, button_id, callbacks)
    -- Show only icon when collapsed, full name when expanded
    local button_text = is_expanded and (expand_icon .. " " .. rack_name:sub(1, 20)) or expand_icon
    if ctx:button(button_text .. "##" .. button_id, -1, 20) then
        callbacks.on_toggle_expand(rack_guid, is_expanded)
        return true
    end
    return false
end

--- Finalize/save chain rename
-- @param state table State object
-- @param chain_guid string Chain GUID
-- @param state_module table State module reference
local function finalize_chain_rename(state, chain_guid, state_module)
    if state.rename_text ~= "" then
        state.display_names[chain_guid] = state.rename_text
    else
        state.display_names[chain_guid] = nil
    end
    state_module.save_display_names()
    state.renaming_fx = nil
    state.rename_text = ""
    state._rename_focused = nil
end

--- Cancel chain rename
-- @param state table State object
local function cancel_chain_rename(state)
    state.renaming_fx = nil
    state.rename_text = ""
    state._rename_focused = nil
end

--- Draw chain rename input field
-- @param ctx ImGui context
-- @param chain_guid string Chain GUID
-- @param state table State object
-- @param state_module table State module reference
-- @return boolean True if interacted
local function draw_chain_rename_input(ctx, chain_guid, state, state_module)
    local interacted = false

    -- Initialize rename text if not set
    if not state.rename_text or state.rename_text == "" then
        state.rename_text = state.display_names[chain_guid] or ""
    end

    ctx:set_next_item_width(-1)

    -- Set keyboard focus on first frame
    if not state._rename_focused then
        ctx:set_keyboard_focus_here()
        state._rename_focused = true
    end

    -- Style the input to be visible
    ctx:push_style_color(imgui.Col.FrameBg(), 0x4A4A4AFF)
    ctx:push_style_color(imgui.Col.Text(), 0xFFFFFFFF)
    local changed, new_text = ctx:input_text("##chain_rename" .. chain_guid, state.rename_text, imgui.InputTextFlags.EnterReturnsTrue())
    ctx:pop_style_color(2)

    state.rename_text = new_text

    -- Handle input events
    if changed then
        finalize_chain_rename(state, chain_guid, state_module)
        interacted = true
    elseif ctx:is_item_deactivated_after_edit() then
        finalize_chain_rename(state, chain_guid, state_module)
        interacted = true
    elseif ctx:is_key_pressed(imgui.Key.Escape()) then
        cancel_chain_rename(state)
        interacted = true
    end

    return interacted
end

--- Draw chain button with selection state
-- @param ctx ImGui context
-- @param chain_name string Display name of chain
-- @param chain_guid string Chain GUID
-- @param chain_btn_id string Button ID for popup context
-- @param row_color number Button color (RGBA)
-- @param is_selected boolean Whether chain is selected
-- @param is_nested_rack boolean Whether this is a nested rack
-- @param state table State object
-- @param rack ReaWrap rack FX object
-- @param callbacks table Callbacks {on_chain_select, on_rename_chain}
-- @return boolean True if clicked
local function draw_chain_button(ctx, chain_name, chain_guid, chain_btn_id, row_color, is_selected, is_nested_rack, state, rack, callbacks)
    ctx:push_style_color(imgui.Col.Button(), row_color)
    if ctx:button(chain_name .. "##" .. chain_btn_id, -1, 20) then
        local rack_guid = rack:get_guid()
        callbacks.on_chain_select(chain_guid, is_selected, is_nested_rack, rack_guid)
    end
    ctx:pop_style_color()

    -- Check for double-click to rename (after button is drawn)
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        local custom_name = state.display_names[chain_guid]
        callbacks.on_rename_chain(chain_guid, custom_name)
    end
end

--- Draw chain context menu (Rename, Delete)
-- @param ctx ImGui context
-- @param chain_btn_id string Button ID for popup context
-- @param chain_guid string Chain GUID
-- @param chain ReaWrap chain FX object
-- @param is_selected boolean Whether chain is selected
-- @param is_nested_rack boolean Whether this is a nested rack
-- @param rack ReaWrap rack FX object
-- @param state table State object
-- @param callbacks table Callbacks {on_rename_chain, on_delete_chain, on_refresh}
local function draw_chain_context_menu(ctx, chain_btn_id, chain_guid, chain, is_selected, is_nested_rack, rack, state, callbacks)
    if ctx:begin_popup_context_item(chain_btn_id) then
        if ctx:menu_item("Rename") then
            local custom_name = state.display_names[chain_guid]
            callbacks.on_rename_chain(chain_guid, custom_name)
        end
        ctx:separator()
        if ctx:menu_item("Delete") then
            chain:delete()
            local rack_guid = rack:get_guid()
            callbacks.on_delete_chain(chain, is_selected, is_nested_rack, rack_guid)
            callbacks.on_refresh()
        end
        ctx:end_popup()
    end
end

--------------------------------------------------------------------------------
-- Custom Widgets
--------------------------------------------------------------------------------

--- Draw an ON/OFF circle indicator with colored background
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param is_on boolean Whether the state is ON
-- @param width number Button width
-- @param height number Button height
-- @param bg_color_on number RGBA color for ON background
-- @param bg_color_off number RGBA color for OFF background
-- @return boolean True if clicked
local function draw_on_off_circle(ctx, label, is_on, width, height, bg_color_on, bg_color_off)
    -- Get cursor position for drawing
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local center_x = cursor_x + width / 2
    local center_y = cursor_y + height / 2
    local radius = 6  -- Small circle radius

    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local clicked = r.ImGui_IsItemClicked(ctx.ctx, 0)
    local is_hovered = r.ImGui_IsItemHovered(ctx.ctx)

    -- Draw background and circle
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)

    -- Draw background rectangle
    local bg_color = is_on and bg_color_on or bg_color_off
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + width, cursor_y + height, bg_color, 0)

    if is_on then
        -- Filled circle for ON state
        r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, 0xFFFFFFFF, 12)
    else
        -- Empty circle (outline only) for OFF state
        r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radius, 0xFFFFFFFF, 12, 2)
    end

    return clicked
end

--------------------------------------------------------------------------------
-- Rack Header
--------------------------------------------------------------------------------

--- Draw the rack header with name, identifier, ON button, and X button
-- @param ctx ImGui context wrapper
-- @param rack ReaWrap FX object (rack container)
-- @param is_nested boolean Whether this is a nested rack
-- @param state table State object
-- @param callbacks table Callbacks:
--   - on_toggle_expand: (rack_guid, is_expanded) -> nil
--   - on_rename: (rack_guid, display_name) -> nil
--   - on_dissolve: (rack) -> nil
--   - on_delete: (rack) -> nil
--   - icon_font: ImGui font for emojis (optional)
function M.draw_rack_header(ctx, rack, is_nested, state, callbacks)
    is_nested = (is_nested == true)

    local ok_guid, rack_guid = pcall(function() return rack:get_guid() end)
    if not ok_guid or not rack_guid then
        return -- Rack has been deleted
    end

    local fx_utils = require('lib.fx.fx_utils')
    local state_module = require('lib.core.state')


    local rack_name = fx_utils.get_rack_display_name(rack)
    local is_expanded = (state.expanded_racks[rack_guid] == true)
    local expand_icon = is_expanded and "▼" or "▶"
    local button_id = is_nested and ("rack_toggle_nested_" .. rack_guid) or ("rack_toggle_top_" .. rack_guid)

    -- Check if rack is being renamed
    local is_renaming_rack = (state.renaming_fx == rack_guid)

    -- Use table for layout with burger menu, name, path, on/off, and delete
    local table_flags = imgui.TableFlags.SizingStretchProp()
    if ctx:begin_table("rack_header_" .. rack_guid, 5, table_flags) then
        -- Column 0: Burger menu (fixed width)
        ctx:table_setup_column("drag", imgui.TableColumnFlags.WidthFixed(), 24)
        if is_expanded then
            -- Expanded: name gets most space
            ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch(), 7)
            ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("on", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("x", imgui.TableColumnFlags.WidthStretch(), 1)
        else
            -- Collapsed: equal distribution
            ctx:table_setup_column("collapse", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("on", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("x", imgui.TableColumnFlags.WidthStretch(), 1)
        end

        ctx:table_next_row()

        -- Column 0: Burger menu drag handle
        ctx:table_set_column_index(0)
        ctx:push_style_color(imgui.Col.Button(), 0x00000000)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x44444488)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x55555588)
        if ctx:button("≡##drag_rack_" .. rack_guid, 20, 20) then
            -- Drag handle doesn't do anything on click
        end
        ctx:pop_style_color(3)
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Drag to reorder")
        end

        -- Drag/drop handling on burger menu
        if ctx:begin_drag_drop_source() then
            ctx:set_drag_drop_payload("FX_GUID", rack_guid)
            ctx:text("Moving: " .. rack_name)
            ctx:end_drag_drop_source()
        end

        if ctx:begin_drag_drop_target() then
            local accepted, dragged_guid = ctx:accept_drag_drop_payload("FX_GUID")
            if accepted and dragged_guid and dragged_guid ~= rack_guid then
                if callbacks.on_drop then
                    callbacks.on_drop(dragged_guid, rack_guid)
                end
            end

            -- Preserve existing drop behavior for plugins and nested racks
            local plugin_accepted = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if plugin_accepted and callbacks.on_add_to_rack then
                callbacks.on_add_to_rack(plugin_accepted)
            end

            local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
            if rack_accepted and callbacks.on_add_nested_rack then
                callbacks.on_add_nested_rack()
            end

            ctx:end_drag_drop_target()
        end

        -- Column 1: Rack name
        ctx:table_set_column_index(1)
        if is_renaming_rack then
            draw_rack_rename_input(ctx, rack_guid, state, state_module)
        else
            draw_rack_toggle_button(ctx, rack_guid, expand_icon, rack_name, is_expanded, button_id, callbacks)
            draw_rack_context_menu(ctx, button_id, rack_guid, rack, state, callbacks)
        end

        -- Column 2: Path identifier
        ctx:table_set_column_index(2)
        local rack_id = fx_utils.get_rack_identifier(rack)
        if rack_id then
            ctx:text_colored(0x888888FF, "[" .. rack_id .. "]")
        end

        -- Column 3: ON button
        ctx:table_set_column_index(3)
        local ok_enabled, rack_enabled = pcall(function() return rack:get_enabled() end)
        rack_enabled = ok_enabled and rack_enabled or false
        -- Draw custom circle indicator with colored background
        local avail_w, _ = ctx:get_content_region_avail()
        if draw_on_off_circle(ctx, "##rack_on_off_" .. rack_guid, rack_enabled, avail_w, 20, 0x44AA44FF, 0xAA4444FF) then
            pcall(function() rack:set_enabled(not rack_enabled) end)
        end

        -- Column 4: X button
        ctx:table_set_column_index(4)
        ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
        if ctx:button("×##rack_del", -1, 20) then
            callbacks.on_delete(rack)
        end
        ctx:pop_style_color()

        ctx:end_table()
    end
end

--------------------------------------------------------------------------------
-- Chain Row (for chains table)
--------------------------------------------------------------------------------

--- Draw a single chain row in the chains table
-- @param ctx ImGui context wrapper
-- @param chain ReaWrap FX object (chain container)
-- @param chain_idx number Chain index (1-based)
-- @param rack ReaWrap FX object (rack container)
-- @param mixer ReaWrap FX object (rack mixer) or nil
-- @param is_selected boolean Whether this chain is selected/expanded
-- @param is_nested_rack boolean Whether this is a nested rack
-- @param state table State object
-- @param get_fx_display_name function Function to get display name: (fx) -> string
-- @param callbacks table Callbacks:
--   - on_chain_select: (chain_guid, is_selected, is_nested_rack, rack_guid) -> nil
--   - on_add_device_to_chain: (chain, plugin) -> nil
--   - on_reorder_chain: (rack, dragged_guid, target_guid) -> nil
--   - on_delete_chain: (chain, is_selected, is_nested_rack, rack_guid) -> nil
--   - on_rename_chain: (chain_guid, display_name) -> nil
--   - on_refresh: () -> nil
function M.draw_chain_row(ctx, chain, chain_idx, rack, mixer, is_selected, is_nested_rack, state, get_fx_display_name, callbacks)
    -- Explicitly check if is_nested_rack is true (not just truthy)
    is_nested_rack = (is_nested_rack == true)
    local ok_name, chain_raw_name = pcall(function() return chain:get_name() end)
    -- Use chain label name (just the name, no [R1_C1] in the row)
    local fx_utils = require('lib.fx.fx_utils')
    local chain_name = ok_name and fx_utils.get_chain_label_name(chain) or "Unknown"
    local ok_en, chain_enabled = pcall(function() return chain:get_enabled() end)
    chain_enabled = ok_en and chain_enabled or false
    local ok_guid, chain_guid = pcall(function() return chain:get_guid() end)
    if not ok_guid or not chain_guid then
        -- Chain has been deleted, skip drawing this row
        return
    end

    -- Column 1: Chain name button
    ctx:table_set_column_index(0)

    -- Check if dragging for visual feedback
    local has_plugin_drag = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_chain_drag = ctx:get_drag_drop_payload("CHAIN_REORDER")

    local row_color = chain_enabled and 0x3A4A5AFF or 0x2A2A35FF
    if is_selected then
        row_color = 0x5588AAFF
    elseif has_plugin_drag then
        row_color = 0x4488AA88  -- Blue tint when plugin dragging
    elseif has_chain_drag then
        row_color = 0x44AA4488  -- Green tint when chain dragging
    end

    -- Check if chain is being renamed
    local is_renaming_chain = (state.renaming_fx == chain_guid)
    local chain_btn_id = "chain_btn_" .. chain_guid

    local state_module = require('lib.core.state')

    if is_renaming_chain then
        draw_chain_rename_input(ctx, chain_guid, state, state_module)
    else
        draw_chain_button(ctx, chain_name, chain_guid, chain_btn_id, row_color, is_selected, is_nested_rack, state, rack, callbacks)
        draw_chain_context_menu(ctx, chain_btn_id, chain_guid, chain, is_selected, is_nested_rack, rack, state, callbacks)
    end

    -- Make the button a drag-drop target (must be called right after the button)
    if ctx:begin_drag_drop_target() then
        -- Handle plugin drop onto chain
        local accepted_plugin, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted_plugin and plugin_name then
            local plugin = { full_name = plugin_name, name = plugin_name }
            callbacks.on_add_device_to_chain(chain, plugin)
        end
        ctx:end_drag_drop_target()
    end

    -- Drag source for chain reordering
    if ctx:begin_drag_drop_source() then
        ctx:set_drag_drop_payload("CHAIN_REORDER", chain_guid)
        ctx:text("Moving: " .. chain_name)
        ctx:end_drag_drop_source()
    end

    -- Drop target for chain reordering (on the rest of the row)
    if ctx:begin_drag_drop_target() then
        -- Handle chain reorder
        local accepted_chain, dragged_guid = ctx:accept_drag_drop_payload("CHAIN_REORDER")
        if accepted_chain and dragged_guid then
            callbacks.on_reorder_chain(rack, dragged_guid, chain_guid)
        end
        ctx:end_drag_drop_target()
    end

    -- Tooltip
    if ctx:is_item_hovered() then
        if has_plugin_drag then
            ctx:set_tooltip("Drop to add FX to " .. chain_name)
        elseif has_chain_drag then
            ctx:set_tooltip("Drop to reorder chain")
        else
            ctx:set_tooltip("Click to " .. (is_selected and "collapse" or "expand"))
        end
    end

    -- Column 2: Enable button (circle icon) - same size as X button
    ctx:table_set_column_index(1)
    local bg_color_on = 0x44AA44FF  -- Green for ON
    local bg_color_off = 0xAA4444FF  -- Red for OFF
    if draw_on_off_circle(ctx, "##chain_on_off_" .. chain_guid, chain_enabled, 24, 20, bg_color_on, bg_color_off) then
        pcall(function() chain:set_enabled(not chain_enabled) end)
    end

    -- Column 3: Delete button (same size as ON button)
    ctx:table_set_column_index(2)
    ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
    if ctx:button("×", 24, 20) then
        chain:delete()
        local rack_guid = rack:get_guid()
        callbacks.on_delete_chain(chain, is_selected, is_nested_rack, rack_guid)
        callbacks.on_refresh()
    end
    ctx:pop_style_color()

    -- Column 4: Volume slider
    ctx:table_set_column_index(3)
    if mixer then
        local vol_param = 2 + (chain_idx - 1)  -- Params 2-17 are channel volumes
        local ok_vol, vol_norm = pcall(function() return mixer:get_param_normalized(vol_param) end)
        if ok_vol and vol_norm then
            -- Fixed: Range is -60 to +12 dB (72 dB total), not -24 to +12 (36 dB)
            local vol_db = -60 + vol_norm * 72
            local vol_format = (math.abs(vol_db) < 0.1) and "0" or (vol_db > 0 and string.format("+%.0f", vol_db) or string.format("%.0f", vol_db))
            ctx:set_next_item_width(-1)
            local vol_changed, new_vol_db = ctx:slider_double("##vol_" .. chain_idx, vol_db, -60, 12, vol_format)
            if vol_changed then
                -- Fixed: Convert back using correct range
                local new_norm = (new_vol_db + 60) / 72
                pcall(function() mixer:set_param_normalized(vol_param, new_norm) end)
            end
            if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                -- Fixed: 0 dB normalized = (0 + 60) / 72 = 60/72 = 0.8333
                pcall(function() mixer:set_param_normalized(vol_param, (0 + 60) / 72) end)
            end
        else
            ctx:text_disabled("--")
        end
    else
        ctx:text_disabled("--")
    end

    -- Column 5: Pan slider
    ctx:table_set_column_index(4)
    if mixer then
        local pan_param = 18 + (chain_idx - 1)  -- Params 18-33 are channel pans
        local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(pan_param) end)
        if ok_pan and pan_norm then
            local pan_val = -100 + pan_norm * 200
            local pan_changed, new_pan = widgets.draw_pan_slider(ctx, "##pan_" .. chain_idx, pan_val, 50)
            if pan_changed then
                pcall(function() mixer:set_param_normalized(pan_param, (new_pan + 100) / 200) end)
            end
        else
            ctx:text_disabled("C")
        end
    else
        ctx:text_disabled("C")
    end
end

--------------------------------------------------------------------------------
-- Rack Visualization Functions
--------------------------------------------------------------------------------

--- Draw collapsed fader control (full vertical fader with meters and scale)
-- @param ctx ImGui context
-- @param mixer ReaWrap mixer FX
-- @param rack_guid string Rack GUID (for popup ID)
-- @param state table State object for peak info access
function M.draw_collapsed_fader_control(ctx, mixer, rack_guid, state)
    local fader_w = 32
    local meter_w = 12
    local scale_w = 20

    local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
    if not ok_gain or not gain_norm then return end

    local gain_db = -24 + gain_norm * 36
    local gain_format = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.0f", gain_db) or string.format("%.0f", gain_db))

    local _, remaining_h = ctx:get_content_region_avail()
    local fader_h = remaining_h - 22
    fader_h = math.max(50, fader_h)

    local avail_w, _ = ctx:get_content_region_avail()
    local total_w = scale_w + fader_w + meter_w + 4
    local offset_x = math.max(0, (avail_w - total_w) / 2 - 8)
    ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + offset_x)

    local screen_x, screen_y = ctx:get_cursor_screen_pos()
    local draw_list = ctx:get_window_draw_list()

    local scale_x = screen_x
    local fader_x = screen_x + scale_w + 2
    local meter_x = fader_x + fader_w + 2

    -- Draw scale, fader, and meters
    drawing.draw_db_scale_marks(ctx, draw_list, scale_x, screen_y, fader_h, scale_w)
    drawing.draw_fader_visualization(ctx, draw_list, fader_x, screen_y, fader_w, fader_h, gain_norm)
    drawing.draw_stereo_meters_visualization(ctx, draw_list, meter_x, screen_y, meter_w, fader_h)

    -- Draw peak meter bars if track available
    if state.track and state.track.pointer then
        local peak_l = r.Track_GetPeakInfo(state.track.pointer, 0)
        local peak_r = r.Track_GetPeakInfo(state.track.pointer, 1)
        local half_meter_w = meter_w / 2 - 1
        local meter_l_x = meter_x
        local meter_r_x = meter_x + meter_w / 2 + 1
        drawing.draw_peak_meters(ctx, draw_list, meter_l_x, meter_r_x, screen_y, fader_h, half_meter_w, peak_l, peak_r)
    end

    -- Interactive slider
    ctx:set_cursor_screen_pos(fader_x, screen_y)
    ctx:push_style_color(imgui.Col.FrameBg(), 0x00000000)
    ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x00000000)
    ctx:push_style_color(imgui.Col.FrameBgActive(), 0x00000000)
    ctx:push_style_color(imgui.Col.SliderGrab(), 0xAAAAAAFF)
    ctx:push_style_color(imgui.Col.SliderGrabActive(), 0xFFFFFFFF)
    local gain_changed, new_gain_db = ctx:v_slider_double("##master_gain_v", fader_w, fader_h, gain_db, -24, 12, "")
    if gain_changed then
        pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
    end
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
    end
    ctx:pop_style_color(5)

    -- dB label
    local label_y = screen_y + fader_h + 2
    local db_text_w, _ = ctx:calc_text_size(gain_format)
    local label_x = fader_x + (fader_w - db_text_w) / 2
    ctx:set_cursor_screen_pos(label_x, label_y)
    ctx:text(gain_format)

    -- Edit popup
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        ctx:open_popup("##gain_edit_popup_" .. rack_guid)
    end
    if ctx:begin_popup("##gain_edit_popup_" .. rack_guid) then
        ctx:set_next_item_width(60)
        ctx:set_keyboard_focus_here()
        local input_changed, input_val = ctx:input_double("##gain_input", gain_db, 0, 0, "%.1f")
        if input_changed then
            local new_db = math.max(-24, math.min(12, input_val))
            pcall(function() mixer:set_param_normalized(0, (new_db + 24) / 36) end)
        end
        if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
            ctx:close_current_popup()
        end
        ctx:end_popup()
    end
end

--- Draw master controls table (gain + pan sliders)
-- @param ctx ImGui context
-- @param mixer ReaWrap mixer FX
function M.draw_master_controls_table(ctx, mixer)
    if ctx:begin_table("master_controls", 3, imgui.TableFlags.SizingStretchProp()) then
        ctx:table_setup_column("label", imgui.TableColumnFlags.WidthFixed(), 50)
        ctx:table_setup_column("gain", imgui.TableColumnFlags.WidthStretch(), 1)
        ctx:table_setup_column("pan", imgui.TableColumnFlags.WidthFixed(), 70)
        ctx:table_next_row()

        ctx:table_set_column_index(0)
        ctx:text_colored(0xAAAAAAFF, "Master")

        ctx:table_set_column_index(1)
        local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
        if ok_gain and gain_norm then
            local gain_db = -24 + gain_norm * 36
            local gain_format = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.1f", gain_db) or string.format("%.1f", gain_db))
            ctx:set_next_item_width(-1)
            local gain_changed, new_gain_db = ctx:slider_double("##master_gain", gain_db, -24, 12, gain_format)
            if gain_changed then
                pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
            end
            if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
            end
        else
            ctx:text_disabled("--")
        end

        ctx:table_set_column_index(2)
        local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(1) end)
        if ok_pan and pan_norm then
            local pan_val = -100 + pan_norm * 200
            local pan_changed, new_pan = widgets.draw_pan_slider(ctx, "##master_pan", pan_val, 60)
            if pan_changed then
                pcall(function() mixer:set_param_normalized(1, (new_pan + 100) / 200) end)
            end
        else
            ctx:text_disabled("C")
        end

        ctx:end_table()
    end
end

--- Draw rack drop zone for plugins/racks
-- @param ctx ImGui context
-- @param rack ReaWrap rack container
-- @param has_payload boolean Whether there's a drag payload
-- @param on_add_chain_plugin callback When plugin dropped
-- @param on_add_nested_rack callback When rack dropped
function M.draw_rack_drop_zone(ctx, rack, has_payload, on_add_chain_plugin, on_add_nested_rack)
    ctx:spacing()
    local drop_h = 40
    if has_payload then
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x33333344)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x44444466)
    end
    ctx:button("+ Drop plugin or rack##rack_drop", -1, drop_h)
    ctx:pop_style_color(2)

    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            local plugin = { full_name = plugin_name, name = plugin_name }
            if on_add_chain_plugin then
                on_add_chain_plugin(rack, plugin)
            end
        end
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            if on_add_nested_rack then
                on_add_nested_rack(rack)
            end
        end
        ctx:end_drag_drop_target()
    end
end

return M
