--- Plugin Browser Panel UI Component
-- Renders the plugin browser with search and filtering
-- @module ui.browser_panel
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local helpers = require('helpers')
local icons = require('lib.ui.common.icons')
local param_selector = require('lib.ui.device.param_selector')
local click_or_drag = require('lib.ui.common.click_or_drag')

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
        local r = reaper
        local i = 0
        for plugin in helpers.iter(state.browser.filtered) do
            i = i + 1
            local item_id = "plugin_" .. i
            ctx:push_id(i)

            -- Icon
            local icon_name = plugin.is_instrument and icons.Names.keyboard or icons.Names.knobs
            icons.image(ctx, icon_name, 16)

            -- Text as selectable (but don't trigger on click - we handle it ourselves)
            ctx:same_line()
            click_or_drag.begin_item(ctx, item_id)
            ctx:selectable(plugin.name, false)
            local action = click_or_drag.end_item(ctx, item_id)

            -- Handle click (release without drag) = add plugin
            if action == "click" then
                on_plugin_add(plugin)
            end

            -- Handle drag = start drag-drop
            if action == "drag_start" or action == "dragging" then
                if ctx:begin_drag_drop_source(r.ImGui_DragDropFlags_SourceAllowNullID()) then
                    ctx:set_drag_drop_payload("PLUGIN_ADD", plugin.full_name)
                    ctx:text("Add: " .. plugin.name)
                    ctx:end_drag_drop_source()
                end
            end

            -- Right-click context menu (use plugin full_name for unique ID)
            local menu_id = "PluginContextMenu_" .. (plugin.full_name:gsub("[^%w]", "_"))
            if ctx:begin_popup_context_item(menu_id) then
                if ctx:menu_item("Select Parameters...") then
                    param_selector.open(plugin.name, plugin.full_name)
                end
                ctx:end_popup()
            end

            if r.ImGui_IsItemHovered(ctx.ctx) then
                ctx:set_tooltip(plugin.full_name .. "\n(drag to chain or click to add)\n(right-click to select parameters)")
            end

            ctx:pop_id()
        end
        ctx:end_child()
    end
    
    -- Draw parameter selector dialog if open
    if param_selector.is_open() then
        param_selector.draw(ctx, state)
    end
end

return M
