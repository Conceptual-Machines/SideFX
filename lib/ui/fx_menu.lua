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
--   - on_dissolve_container: (fx, depth) -> nil
--   - on_delete: (fx, depth) -> nil
--   - on_add_to_container: (fx_list) -> nil
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
        -- Remove from container option (only if inside a container)
        local parent = fx:get_parent_container()
        if parent then
            if ctx:menu_item("Remove from Container") then
                callbacks.on_remove_from_container(fx, depth)
            end
            ctx:separator()
        end
        -- Dissolve container option (only for containers)
        if is_container then
            if ctx:menu_item("Dissolve Container") then
                callbacks.on_dissolve_container(fx, depth)
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

return M


