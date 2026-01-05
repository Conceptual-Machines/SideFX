--- Plugin Browser Panel UI Component
-- Renders the plugin browser with search and filtering
-- @module ui.browser_panel
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local helpers = require('helpers')
local constants = require('lib.constants')

local M = {}

--------------------------------------------------------------------------------
-- Plugin Browser
--------------------------------------------------------------------------------

--- Draw the plugin browser panel
-- @param ctx ImGui context wrapper
-- @param state table State object with browser data
-- @param icon_font ImGui font handle for icons (optional)
-- @param icon_size number Size of icon font (optional)
-- @param on_plugin_add function Callback when plugin is added: (plugin) -> nil
-- @param filter_plugins function Function to filter plugins: () -> nil
function M.draw(ctx, state, icon_font, icon_size, on_plugin_add, filter_plugins)
    ctx:set_next_item_width(-1)
    local changed, search = ctx:input_text("##search", state.browser.search)
    if changed then
        state.browser.search = search
        filter_plugins()
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Search plugins...") end

    if ctx:begin_tab_bar("BrowserTabs") then
        if ctx:begin_tab_item("  All  ") then
            if state.browser.filter ~= "all" then
                state.browser.filter = "all"
                filter_plugins()
            end
            ctx:end_tab_item()
        end
        if ctx:begin_tab_item(" Inst ") then
            if state.browser.filter ~= "instruments" then
                state.browser.filter = "instruments"
                filter_plugins()
            end
            ctx:end_tab_item()
        end
        if ctx:begin_tab_item(" FX ") then
            if state.browser.filter ~= "effects" then
                state.browser.filter = "effects"
                filter_plugins()
            end
            ctx:end_tab_item()
        end
        ctx:end_tab_bar()
    end

    if ctx:begin_child("PluginList", 0, 0, imgui.ChildFlags.Border()) then
        local i = 0
        for plugin in helpers.iter(state.browser.filtered) do
            i = i + 1
            ctx:push_id(i)

            -- Icon with emoji font
            if icon_font then ctx:push_font(icon_font, icon_size) end
            -- Get emojimgui from global (set up in main script)
            local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
            local icon = plugin.is_instrument 
                and constants.icon_text(emojimgui, constants.Icons.musical_keyboard) 
                or constants.icon_text(emojimgui, constants.Icons.wrench)
            ctx:text(icon)
            if icon_font then ctx:pop_font() end

            -- Text with default font
            ctx:same_line()
            if ctx:selectable(plugin.name, false) then
                on_plugin_add(plugin)
            end

            -- Drag source for plugin (drag to add to chain)
            if ctx:begin_drag_drop_source() then
                ctx:set_drag_drop_payload("PLUGIN_ADD", plugin.full_name)
                ctx:text("Add: " .. plugin.name)
                ctx:end_drag_drop_source()
            end

            if ctx:is_item_hovered() then
                ctx:set_tooltip(plugin.full_name .. "\n(drag to chain or click to add)")
            end

            ctx:pop_id()
        end
        ctx:end_child()
    end
end

return M

