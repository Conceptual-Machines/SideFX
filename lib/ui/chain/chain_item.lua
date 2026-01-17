--- Device Chain Item Renderer
-- Renders individual items in the device chain (racks, containers, devices)
-- @module ui.chain_item
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper
local rack_ui = require('lib.ui.rack.rack_ui')
local bare_device_panel = require('lib.ui.device.bare_device_panel')

local M = {}

-- Dependencies injected by caller
local get_fx_display_name
local device_panel
local state
local icon_font
local header_font
local refresh_fx_list
local add_plugin_by_name
local add_rack_to_track
local get_device_utility
local draw_selected_chain_column_if_expanded
local draw_rack_panel
local on_mod_matrix

--- Initialize with dependencies
function M.init(deps)
    get_fx_display_name = deps.get_fx_display_name
    device_panel = deps.device_panel
    state = deps.state
    icon_font = deps.icon_font
    header_font = deps.header_font
    refresh_fx_list = deps.refresh_fx_list
    add_plugin_by_name = deps.add_plugin_by_name
    add_rack_to_track = deps.add_rack_to_track
    get_device_utility = deps.get_device_utility
    draw_selected_chain_column_if_expanded = deps.draw_selected_chain_column_if_expanded
    draw_rack_panel = deps.draw_rack_panel
    on_mod_matrix = deps.on_mod_matrix
end

--- Draw fallback device panel UI (when device_panel module not loaded)
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param guid string FX GUID
-- @param avail_height number Available height
-- @param utility ReaWrap utility FX (optional)
-- @param on_select function Optional callback when panel is clicked
local function draw_fallback_device_panel(ctx, fx, guid, avail_height, utility, on_select)
    local name = get_fx_display_name(fx)
    local enabled = fx:get_enabled()
    local total_params = fx:get_num_params()
    local panel_h = avail_height - 10
    local param_row_h = 38
    local sidebar_w = 36
    local col_w = 180
    local params_per_col = math.floor((panel_h - 40) / param_row_h)
    params_per_col = math.max(1, params_per_col)
    local num_cols = math.ceil(total_params / params_per_col)
    num_cols = math.max(1, num_cols)
    local panel_w = col_w * num_cols + sidebar_w + 16

    ctx:push_style_color(imgui.Col.ChildBg(), enabled and 0x2A2A2AFF or 0x1A1A1AFF)
    if ctx:begin_child("fx_" .. guid, panel_w, panel_h, imgui.ChildFlags.Border()) then
        -- Click-to-select: detect clicks on panel background
        if on_select and r.ImGui_IsWindowHovered(ctx.ctx, r.ImGui_HoveredFlags_ChildWindows())
           and r.ImGui_IsMouseClicked(ctx.ctx, 0) then
            on_select()
        end
        ctx:text(name:sub(1, 35))
        ctx:separator()

        -- Params area (left)
        local params_w = col_w * num_cols
        if ctx:begin_child("params_" .. guid, params_w, panel_h - 40, 0) then
            if total_params > 0 and ctx:begin_table("params_fb_" .. guid, num_cols, imgui.TableFlags.SizingStretchSame()) then
                for row = 0, params_per_col - 1 do
                    ctx:table_next_row()
                    for col = 0, num_cols - 1 do
                        local p = col * params_per_col + row
                        ctx:table_set_column_index(col)
                        if p < total_params then
                            local pname = fx:get_param_name(p)
                            local pval = fx:get_param_normalized(p) or 0
                            ctx:push_id(p)
                            ctx:text((pname or "P" .. p):sub(1, 14))
                            ctx:set_next_item_width(-8)
                            local changed, new_val = ctx:slider_double("##p", pval, 0, 1, "%.2f")
                            if changed then
                                fx:set_param_normalized(p, new_val)
                            end
                            ctx:pop_id()
                        end
                    end
                end
                ctx:end_table()
            end
            ctx:end_child()
        end

        -- Sidebar (right)
        ctx:same_line()
        local sb_w = 60
        if ctx:begin_child("sidebar_" .. guid, sb_w, panel_h - 40, 0) then
            if ctx:button("UI", sb_w - 4, 24) then fx:show(3) end
            ctx:push_style_color(imgui.Col.Button(), enabled and 0x44AA44FF or 0xAA4444FF)
            if ctx:button(enabled and "ON" or "OFF", sb_w - 4, 24) then
                fx:set_enabled(not enabled)
            end
            ctx:pop_style_color()

            -- Wet/Dry
            local wet_idx = fx:get_param_from_ident(":wet")
            if wet_idx >= 0 then
                ctx:text("Wet")
                local wet_val = fx:get_param(wet_idx)
                ctx:set_next_item_width(sb_w - 4)
                local wet_changed, new_wet = ctx:v_slider_double("##wet", sb_w - 4, 60, wet_val, 0, 1, "")
                if wet_changed then fx:set_param(wet_idx, new_wet) end
            end

            -- Utility controls
            if utility then
                ctx:text("Gain")
                local gain_val = utility:get_param_normalized(0) or 0.5
                ctx:set_next_item_width(sb_w - 4)
                local gain_changed, new_gain = ctx:v_slider_double("##gain", sb_w - 4, 60, gain_val, 0, 1, "")
                if gain_changed then utility:set_param_normalized(0, new_gain) end
            end

            ctx:end_child()
        end

        ctx:end_child()
    end
    ctx:pop_style_color()
end

--- Draw a rack item with its chain column
-- @param ctx ImGui context
-- @param fx ReaWrap rack FX
-- @param avail_height number Available height
function M.draw_rack_item(ctx, fx, avail_height, callbacks)
    -- Check if FX list is invalid - bail out early
    if state.fx_list_invalid then return end

    -- Draw rack using helper function (top-level rack, explicitly not nested)
    local rack_data = draw_rack_panel(ctx, fx, avail_height, false, callbacks)

    -- Draw selected chain column if expanded (safely get GUID)
    local ok_guid, rack_guid = pcall(function() return fx:get_guid() end)
    if ok_guid and rack_guid then
        draw_selected_chain_column_if_expanded(ctx, rack_data, rack_guid)
    end
end

--- Draw an unknown container item
-- @param ctx ImGui context
-- @param fx ReaWrap container FX
function M.draw_container_item(ctx, fx)
    -- Check if FX list is invalid - bail out early
    if state.fx_list_invalid then return end

    -- Safely get GUID (may fail if stale)
    local ok_guid, guid = pcall(function() return fx:get_guid() end)
    if not ok_guid or not guid then return end

    ctx:push_style_color(imgui.Col.ChildBg(), 0x252530FF)
    if ctx:begin_child("container_" .. guid, 180, 100, imgui.ChildFlags.Border()) then
        local ok_name, display_name = pcall(function() return get_fx_display_name(fx) end)
        ctx:text((ok_name and display_name or "Container"):sub(1, 15))
        if ctx:small_button("Open") then
            pcall(function() fx:show(3) end)
        end
        ctx:end_child()
    end
    ctx:pop_style_color()
end

--- Draw a device item (uses device_panel if available, falls back to basic UI)
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param item table Item data {fx, utility, container}
-- @param avail_height number Available height
-- @param callbacks table Callback functions
function M.draw_device_item(ctx, fx, item, avail_height, callbacks)
    -- Check if FX list is invalid - bail out early to avoid stale pointer errors
    if state.fx_list_invalid then return end

    -- Safely get GUID (may fail if FX was deleted/moved)
    local ok_guid, guid = pcall(function() return fx:get_guid() end)
    if not ok_guid or not guid then return end

    local utility = item.utility
    local container = item.container

    -- Safely get container name (may fail if container is stale)
    local container_name = nil
    if container then
        local ok_name, name = pcall(function() return container:get_name() end)
        if ok_name then container_name = name end
    end

    -- Use the container guid if available, otherwise the fx guid
    local device_guid = container and container:get_guid() or guid

    -- Check if this device is selected (standalone device = single item in path)
    local is_selected = (#state.expanded_path == 1 and state.expanded_path[1] == device_guid)

    ctx:begin_group()
    if item.is_bare then
        -- Use simplified bare device panel (no modulators, no utility)
        bare_device_panel.draw(ctx, fx, {
            avail_height = avail_height - 10,
            on_delete = function(fx_to_delete)
                local state_module = require('lib.core.state')
                state_module.state.deletion_pending = true
                fx_to_delete:delete()
                state_module.state.fx_list = nil
            end,
            on_drop = function(dragged_guid, target_guid)
                if callbacks.on_drop then
                    callbacks.on_drop(dragged_guid, target_guid)
                end
            end,
        })
    elseif device_panel then
        -- Use full device panel for D-containers
        device_panel.draw(ctx, fx, {
            avail_height = avail_height - 10,
            utility = utility,  -- Paired SideFX_Utility for gain/pan
            container = container,  -- Pass container reference
            container_name = container_name,
            missing_utility = item.missing_utility,  -- Flag for warning icon
            icon_font = icon_font,
            header_font = header_font,
            track = state.track,
            refresh_fx_list = refresh_fx_list,
            is_selected = is_selected,  -- For border highlighting
            on_select = function()
                -- Click-to-select for standalone devices
                local state_module = require('lib.core.state')
                if state.expanded_path[1] ~= device_guid then
                    state_module.select_standalone_device(device_guid)
                end
            end,
            on_delete = function(fx_to_delete)
                -- Set flag FIRST to stop all rendering immediately
                local state_module = require('lib.core.state')
                state_module.state.deletion_pending = true

                if container then
                    -- Delete the whole D-container
                    container:delete()
                else
                    -- Legacy: delete FX and paired utility
                    if utility then
                        utility:delete()
                    end
                    fx_to_delete:delete()
                end
                -- Clear FX list cache - will rebuild on next frame
                state_module.state.fx_list = nil
            end,
            on_drop = function(dragged_guid, target_guid)
                if callbacks.on_drop then
                    callbacks.on_drop(dragged_guid, target_guid)
                end
            end,
            on_plugin_drop = function(plugin_name, insert_before_idx, drop_opts)
                if callbacks.on_plugin_drop then
                    callbacks.on_plugin_drop(plugin_name, container and container.pointer or insert_before_idx, drop_opts)
                end
            end,
            on_rack_drop = function(insert_before_idx)
                if callbacks.on_rack_drop then
                    callbacks.on_rack_drop(container and container.pointer or insert_before_idx)
                end
            end,
            on_mod_matrix = on_mod_matrix,
        })
    else
        -- Fallback UI with on_select callback
        draw_fallback_device_panel(ctx, fx, guid, avail_height, utility, function()
            local state_module = require('lib.core.state')
            if state.expanded_path[1] ~= device_guid then
                state_module.select_standalone_device(device_guid)
            end
        end)
    end
    ctx:end_group()
end

return M
