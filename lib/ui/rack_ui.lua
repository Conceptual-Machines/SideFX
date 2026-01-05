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
--   - on_refresh: () -> nil
function M.draw_chain_row(ctx, chain, chain_idx, rack, mixer, is_selected, is_nested_rack, state, get_fx_display_name, callbacks)
    -- Explicitly check if is_nested_rack is true (not just truthy)
    is_nested_rack = (is_nested_rack == true)
    local ok_name, chain_raw_name = pcall(function() return chain:get_name() end)
    local chain_name = ok_name and get_fx_display_name(chain) or "Unknown"
    local ok_en, chain_enabled = pcall(function() return chain:get_enabled() end)
    chain_enabled = ok_en and chain_enabled or false
    local chain_guid = chain:get_guid()

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

    ctx:push_style_color(imgui.Col.Button(), row_color)
    if ctx:button(chain_name .. "##chain_btn", -1, 20) then
        local rack_guid = rack:get_guid()
        callbacks.on_chain_select(chain_guid, is_selected, is_nested_rack, rack_guid)
    end
    ctx:pop_style_color()

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


