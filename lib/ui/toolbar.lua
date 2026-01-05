--- Toolbar UI Component
-- Top toolbar with refresh, add buttons, and breadcrumb navigation
-- @module ui.toolbar
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local constants = require('lib.constants')

local M = {}

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

--- Draw the toolbar
-- @param ctx ImGui context wrapper
-- @param state table State object
-- @param icon_font ImGui font handle for icons (optional)
-- @param icon_size number Size of icon font (optional)
-- @param get_fx_display_name function Function to get display name: (fx) -> string
-- @param callbacks table Callbacks:
--   - on_refresh: () -> nil
--   - on_add_rack: () -> nil
--   - on_add_fx: () -> nil
--   - on_collapse_from_depth: (depth) -> nil
function M.draw(ctx, state, icon_font, icon_size, get_fx_display_name, callbacks)
    -- Refresh button
    if icon_font then ctx:push_font(icon_font, icon_size) end
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
    local refresh_icon = constants.icon_text(emojimgui, constants.Icons.arrows_counterclockwise)
    if ctx:button(refresh_icon) then
        callbacks.on_refresh()
    end
    if icon_font then ctx:pop_font() end
    if ctx:is_item_hovered() then ctx:set_tooltip("Refresh FX list") end

    ctx:same_line()

    -- Add Rack button (also draggable)
    ctx:push_style_color(imgui.Col.Button(), 0x446688FF)
    if ctx:button("+ Rack") then
        if state.track then
            callbacks.on_add_rack()
        end
    end
    ctx:pop_style_color()
    -- Drag source for rack
    if ctx:begin_drag_drop_source() then
        ctx:set_drag_drop_payload("RACK_ADD", "new_rack")
        ctx:text("Drop to create Rack")
        ctx:end_drag_drop_source()
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Click to add rack at end\nOr drag to drop anywhere") end

    ctx:same_line()

    -- Add FX button
    if ctx:button("+ FX") then
        -- TODO: Open FX browser popup or add last used FX
        if state.track then
            callbacks.on_add_fx()
        end
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Add FX at end of chain") end

    ctx:same_line()
    ctx:text("|")
    ctx:same_line()

    -- Track name
    ctx:push_style_color(imgui.Col.Text(), 0xAADDFFFF)
    ctx:text(state.track_name)
    ctx:pop_style_color()

    -- Breadcrumb trail (for navigating into containers)
    if #state.expanded_path > 0 then
        ctx:same_line()
        ctx:text_disabled(">")
        for i, guid in ipairs(state.expanded_path) do
            ctx:same_line()
            local container = state.track:find_fx_by_guid(guid)
            if container then
                if ctx:small_button(get_fx_display_name(container) .. "##bread_" .. i) then
                    callbacks.on_collapse_from_depth(i + 1)
                end
            end
            if i < #state.expanded_path then
                ctx:same_line()
                ctx:text_disabled(">")
            end
        end
    end
end

return M

