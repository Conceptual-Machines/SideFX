--- Rack UI Component
-- Comprehensive rack panel UI with chains, meters, and nested rack support
-- @module ui.rack_ui
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper
local widgets = require('lib.ui.widgets')

local M = {}

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
function M.draw_rack_header(ctx, rack, is_nested, state, callbacks)
    is_nested = (is_nested == true)
    
    local ok_guid, rack_guid = pcall(function() return rack:get_guid() end)
    if not ok_guid or not rack_guid then
        return -- Rack has been deleted
    end
    
    local fx_utils = require('lib.fx_utils')
    local state_module = require('lib.state')
    
    local rack_name = fx_utils.get_rack_display_name(rack)
    local is_expanded = (state.expanded_racks[rack_guid] == true)
    local expand_icon = is_expanded and "▼" or "▶"
    local button_id = is_nested and ("rack_toggle_nested_" .. rack_guid) or ("rack_toggle_top_" .. rack_guid)
    
    -- Check if rack is being renamed
    local is_renaming_rack = (state.renaming_fx == rack_guid)
    
    -- Use table for layout with different widths based on expansion state
    -- Collapsed: 25% | 25% | 25% | 25% (icon only)
    -- Expanded: 70% | 10% | 10% | 10% (full name)
    local table_flags = imgui.TableFlags.SizingStretchProp()
    if ctx:begin_table("rack_header_" .. rack_guid, 4, table_flags) then
        if is_expanded then
            -- Expanded: name gets 70%, others get 10% each
            ctx:table_setup_column("name", imgui.TableColumnFlags.WidthStretch(), 7)
            ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("on", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("x", imgui.TableColumnFlags.WidthStretch(), 1)
        else
            -- Collapsed: equal 25% per column
            ctx:table_setup_column("collapse", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("path", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("on", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("x", imgui.TableColumnFlags.WidthStretch(), 1)
        end
        
        ctx:table_next_row()
        
        -- Column 0: Rack name (70%)
        ctx:table_set_column_index(0)
        if is_renaming_rack then
            -- Inline rename input for rack
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
            if changed then
                if state.rename_text ~= "" then
                    state.display_names[rack_guid] = state.rename_text
                else
                    state.display_names[rack_guid] = nil
                end
                state_module.save_display_names()
                state.renaming_fx = nil
                state.rename_text = ""
                state._rename_focused = nil
            elseif ctx:is_item_deactivated_after_edit() then
                if state.rename_text ~= "" then
                    state.display_names[rack_guid] = state.rename_text
                else
                    state.display_names[rack_guid] = nil
                end
                state_module.save_display_names()
                state.renaming_fx = nil
                state.rename_text = ""
                state._rename_focused = nil
            elseif ctx:is_key_pressed(imgui.Key.Escape()) then
                state.renaming_fx = nil
                state.rename_text = ""
                state._rename_focused = nil
            end
        else
            -- Show only icon when collapsed, full name when expanded
            local button_text = is_expanded and (expand_icon .. " " .. rack_name:sub(1, 20)) or expand_icon
            if ctx:button(button_text .. "##" .. button_id, -1, 20) then
                callbacks.on_toggle_expand(rack_guid, is_expanded)
            end
            
            -- Rack context menu (attached to the button above)
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
        
        -- Column 1: Path identifier (10%)
        ctx:table_set_column_index(1)
        local rack_id = fx_utils.get_rack_identifier(rack)
        if rack_id then
            ctx:text_colored(0x888888FF, "[" .. rack_id .. "]")
        end
        
        -- Column 2: ON button (10%)
        ctx:table_set_column_index(2)
        local ok_enabled, rack_enabled = pcall(function() return rack:get_enabled() end)
        rack_enabled = ok_enabled and rack_enabled or false
        ctx:push_style_color(imgui.Col.Button(), rack_enabled and 0x44AA44FF or 0xAA4444FF)
        if ctx:button(rack_enabled and "ON" or "OF", -1, 20) then
            pcall(function() rack:set_enabled(not rack_enabled) end)
        end
        ctx:pop_style_color()

        -- Column 3: X button (10%)
        ctx:table_set_column_index(3)
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
    local fx_utils = require('lib.fx_utils')
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
    
    if is_renaming_chain then
        -- Inline rename input for chain
        -- Ensure rename_text is initialized (should be set by callback, but handle edge case)
        if not state.rename_text or state.rename_text == "" then
            state.rename_text = state.display_names[chain_guid] or ""
        end
        
        -- Set width to fill the table cell
        ctx:set_next_item_width(-1)
        
        -- Set keyboard focus on first frame of rename mode
        if not state._rename_focused then
            ctx:set_keyboard_focus_here()
            state._rename_focused = true
        end
        
        -- Style the input to be visible (light background, white text)
        ctx:push_style_color(imgui.Col.FrameBg(), 0x4A4A4AFF)
        ctx:push_style_color(imgui.Col.Text(), 0xFFFFFFFF)
        local changed, new_text = ctx:input_text("##chain_rename" .. chain_guid, state.rename_text, imgui.InputTextFlags.EnterReturnsTrue())
        ctx:pop_style_color(2)
        
        -- Update state.rename_text with the current input value
        state.rename_text = new_text
        
        if changed then
            if state.rename_text ~= "" then
                state.display_names[chain_guid] = state.rename_text
            else
                state.display_names[chain_guid] = nil
            end
            local state_module = require('lib.state')
            state_module.save_display_names()
            state.renaming_fx = nil
            state.rename_text = ""
            state._rename_focused = nil
        elseif ctx:is_item_deactivated_after_edit() then
            if state.rename_text ~= "" then
                state.display_names[chain_guid] = state.rename_text
            else
                state.display_names[chain_guid] = nil
            end
            local state_module = require('lib.state')
            state_module.save_display_names()
            state.renaming_fx = nil
            state.rename_text = ""
            state._rename_focused = nil
        elseif ctx:is_key_pressed(imgui.Key.Escape()) then
            state.renaming_fx = nil
            state.rename_text = ""
            state._rename_focused = nil
        end
    else
        ctx:push_style_color(imgui.Col.Button(), row_color)
        if ctx:button(chain_name .. "##" .. chain_btn_id, -1, 20) then
            local rack_guid = rack:get_guid()
            callbacks.on_chain_select(chain_guid, is_selected, is_nested_rack, rack_guid)
        end
        ctx:pop_style_color()
        
        -- Chain context menu
        if ctx:begin_popup_context_item(chain_btn_id) then
            if ctx:menu_item("Rename") then
                -- Get the custom name if it exists, otherwise use empty string
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

    -- Column 2: Enable button
    ctx:table_set_column_index(1)
    if chain_enabled then
        ctx:push_style_color(imgui.Col.Button(), 0x44AA44FF)
    else
        ctx:push_style_color(imgui.Col.Button(), 0xAA4444FF)
    end
    if ctx:small_button(chain_enabled and "ON" or "OF") then
        pcall(function() chain:set_enabled(not chain_enabled) end)
    end
    ctx:pop_style_color()

    -- Column 3: Delete button
    ctx:table_set_column_index(2)
    ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
    if ctx:small_button("×") then
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
            local vol_format = vol_db >= 0 and string.format("+%.0f", vol_db) or string.format("%.0f", vol_db)
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

return M


