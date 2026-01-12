--- FX Context Menu UI Component
-- Right-click context menu for FX items
-- @module ui.fx_menu
-- @author Nomad Monad
-- @license MIT

local M = {}

--------------------------------------------------------------------------------
-- FX Context Menu
--------------------------------------------------------------------------------

--- Draw FX context menu
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param guid string FX GUID
-- @param menu_id string Unique menu ID
-- @param enabled boolean Whether FX is enabled
-- @param is_container boolean Whether FX is a container
-- @param depth number Depth in hierarchy
-- @param get_fx_display_name function Function to get display name: (fx) -> string
-- @param callbacks table Callbacks:
--   - on_open_fx: (fx) -> nil
--   - on_toggle_enabled: (fx) -> nil
--   - on_rename: (guid, display_name) -> nil
--   - on_remove_from_container: (fx, depth) -> nil
--   - on_delete: (fx, depth) -> nil
--   - on_add_to_container: (fx_list) -> nil
--   - on_convert_to_rack: (fx, depth) -> nil (optional, for D-containers)
--   - on_convert_to_devices: (fx, depth) -> nil (optional, for C-containers)
--   - get_multi_select_count: () -> number
--   - get_multi_selected_fx: () -> table
--   - clear_multi_select: () -> nil
function M.draw(ctx, fx, guid, menu_id, enabled, is_container, depth, get_fx_display_name, callbacks)
    if ctx:begin_popup_context_item(menu_id) then
        if ctx:menu_item("Open FX Window") then
            callbacks.on_open_fx(fx)
        end
        if ctx:menu_item(enabled and "Bypass" or "Enable") then
            callbacks.on_toggle_enabled(fx)
        end
        ctx:separator()
        if ctx:menu_item("Rename") then
            callbacks.on_rename(guid, get_fx_display_name(fx))
        end
        ctx:separator()

        -- Check container type for special options
        local fx_name = ""
        if is_container then
            local ok, name = pcall(function() return fx:get_name() end)
            if ok and name then fx_name = name end
        end
        local is_device_container = fx_name:match("^D%d+")
        local is_chain_container = fx_name:match("^R%d+_C%d+")

        -- Remove from container option (only if inside a container)
        local parent = fx:get_parent_container()
        if parent then
            if ctx:menu_item("Remove from Container") then
                callbacks.on_remove_from_container(fx, depth)
            end
            ctx:separator()
        end

        -- Device-specific options (D-containers)
        if is_device_container then
            if callbacks.on_convert_to_rack then
                if ctx:menu_item("Convert to Rack") then
                    callbacks.on_convert_to_rack(fx, depth)
                end
            end
            ctx:separator()
        end

        -- Chain-specific options (C-containers)
        if is_chain_container then
            if callbacks.on_convert_to_devices then
                if ctx:menu_item("Convert to Devices") then
                    callbacks.on_convert_to_devices(fx, depth)
                end
            end
            ctx:separator()
        end

        if ctx:menu_item("Delete") then
            callbacks.on_delete(fx, depth)
        end
        ctx:separator()
        local sel_count = callbacks.get_multi_select_count()
        if sel_count > 0 then
            if ctx:menu_item("Add Selected to Container (" .. sel_count .. ")") then
                callbacks.on_add_to_container(callbacks.get_multi_selected_fx())
                callbacks.clear_multi_select()
            end
        else
            -- Single item - add to new container (works for FX and containers)
            if ctx:menu_item("Add to New Container") then
                callbacks.on_add_to_container({fx})
            end
        end
        ctx:end_popup()
    end
end

--------------------------------------------------------------------------------
-- Convenience wrapper for SideFX context menu
--------------------------------------------------------------------------------

--- Draw FX context menu with SideFX default callbacks
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object
-- @param guid string FX GUID
-- @param i number Index for unique menu ID
-- @param enabled boolean Whether FX is enabled
-- @param is_container boolean Whether FX is a container
-- @param depth number Depth in hierarchy
-- @param get_fx_display_name function Function to get display name: (fx) -> string
-- @param callbacks table Callbacks object with:
--   - state: State table (for renaming)
--   - collapse_from_depth: (depth) -> nil
--   - refresh_fx_list: () -> nil
--   - add_to_new_container: (fx_list) -> nil
--   - convert_to_rack: (fx) -> nil (optional)
--   - convert_to_devices: (fx) -> nil (optional)
--   - get_multi_select_count: () -> number
--   - get_multi_selected_fx: () -> table
--   - clear_multi_select: () -> nil
function M.draw_with_sidefx_callbacks(ctx, fx, guid, i, enabled, is_container, depth, get_fx_display_name, callbacks)
    M.draw(ctx, fx, guid, "fxmenu" .. i, enabled, is_container, depth, get_fx_display_name, {
        on_open_fx = function(fx) fx:show(3) end,
        on_toggle_enabled = function(fx) fx:set_enabled(not fx:get_enabled()) end,
        on_rename = function(guid, display_name)
            callbacks.state.renaming_fx = guid
            callbacks.state.rename_text = display_name
        end,
        on_remove_from_container = function(fx, depth)
            fx:move_out_of_container()
            callbacks.collapse_from_depth(depth)
            callbacks.refresh_fx_list()
        end,
        on_delete = function(fx, depth)
            fx:delete()
            callbacks.collapse_from_depth(depth)
            callbacks.refresh_fx_list()
        end,
        on_add_to_container = function(fx_list)
            callbacks.add_to_new_container(fx_list)
        end,
        on_convert_to_rack = callbacks.convert_to_rack and function(fx, depth)
            callbacks.convert_to_rack(fx)
            callbacks.collapse_from_depth(depth)
            callbacks.refresh_fx_list()
        end or nil,
        on_convert_to_devices = callbacks.convert_to_devices and function(fx, depth)
            callbacks.convert_to_devices(fx)
            callbacks.collapse_from_depth(depth)
            callbacks.refresh_fx_list()
        end or nil,
        get_multi_select_count = callbacks.get_multi_select_count,
        get_multi_selected_fx = callbacks.get_multi_selected_fx,
        clear_multi_select = callbacks.clear_multi_select,
    })
end

return M
