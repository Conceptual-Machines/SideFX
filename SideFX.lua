-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.4.1
-- @provides
--   [nomain] lib/*.lua
-- @link https://github.com/Conceptual-Machines/SideFX
-- @about
--   # SideFX
--
--   Rack-style FX container management for Reaper 7+.
--   Ableton/Bitwig-inspired UI for FX chains.
--
-- @changelog
--   v0.4.1 - UI fixes
--     + Horizontal scrolling for nested columns
--     + Fixed container toggle behavior
--     + Improved tab sizing
--   v0.4.0 - Column-based UI
--     + Miller columns layout (FX Chain | Container | Details)
--     + Expandable containers
--     + FX detail panel with parameters
--   v0.3.0 - Rack UI rewrite
--   v0.2.0 - ReaWrap integration
--   v0.1.0 - Initial release

local r = reaper

--------------------------------------------------------------------------------
-- Path Setup
--------------------------------------------------------------------------------

local script_path = ({ r.get_action_context() })[2]:match('^.+[\\//]')
local scripts_folder = r.GetResourcePath() .. "/Scripts/"

-- ReaWrap paths
local reawrap_reapack = scripts_folder .. "ReaWrap/Libraries/lua/"
local sidefx_parent = script_path:match("^(.+[/\\])SideFX[/\\]")
local reawrap_dev = sidefx_parent and (sidefx_parent .. "ReaWrap/lua/") or ""

-- Dev paths first, then ReaPack install
package.path = script_path .. "?.lua;"
    .. script_path .. "lib/?.lua;"
    .. reawrap_dev .. "?.lua;"
    .. reawrap_dev .. "?/init.lua;"
    .. reawrap_reapack .. "?.lua;"
    .. reawrap_reapack .. "?/init.lua;"
    .. package.path

--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------

local imgui = require('imgui')
local Window = require('imgui.window').Window
local theme = require('imgui.theme')
local Project = require('project')
local Plugins = require('plugins')
local helpers = require('helpers')

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local state = {
    track = nil,
    track_name = "No track selected",
    
    -- FX data
    top_level_fx = {},
    
    -- Column navigation: list of expanded container GUIDs (breadcrumb trail)
    expanded_path = {},  -- e.g. {container1_guid, container2_guid, ...}
    
    -- Selected FX for detail panel
    selected_fx = nil,
    
    -- Multi-select for operations
    multi_select = {},
    
    show_debug = false,
    
    -- Plugin browser state
    browser = {
        search = "",
        filter = "all",
        plugins = {},
        filtered = {},
        scanned = false,
    },
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local project = Project:new()

local function get_selected_track()
    if not project:has_selected_tracks() then
        return nil, "No track selected"
    end
    local track = project:get_selected_track(0)
    return track, track:get_name()
end

local function refresh_fx_list()
    state.top_level_fx = {}
    if not state.track then return end
    
    for fx in state.track:iter_track_fx_chain() do
        local parent = fx:get_parent_container()
        if not parent then
            state.top_level_fx[#state.top_level_fx + 1] = fx
        end
    end
end

local function get_container_children(container_guid)
    if not state.track or not container_guid then return {} end
    
    local container = state.track:find_fx_by_guid(container_guid)
    if not container or not container:is_container() then return {} end
    
    local children = {}
    for child in container:iter_container_children() do
        children[#children + 1] = child
    end
    return children
end

local function clear_multi_select()
    state.multi_select = {}
end

local function get_multi_selected_fx()
    if not state.track then return {} end
    local list = {}
    for guid in pairs(state.multi_select) do
        local fx = state.track:find_fx_by_guid(guid)
        if fx then
            list[#list + 1] = fx
        end
    end
    return list
end

local function get_multi_select_count()
    local count = 0
    for _ in pairs(state.multi_select) do count = count + 1 end
    return count
end

-- Collapse all columns from a certain depth onwards
local function collapse_from_depth(depth)
    while #state.expanded_path >= depth do
        table.remove(state.expanded_path)
    end
    state.selected_fx = nil
end

-- Toggle container at a specific depth
local function toggle_container(guid, depth)
    -- If this container is already expanded at this depth, collapse it and all children
    if state.expanded_path[depth] == guid then
        collapse_from_depth(depth)
    else
        -- Collapse anything beyond this depth first
        collapse_from_depth(depth)
        -- Then expand this container
        state.expanded_path[depth] = guid
    end
    state.selected_fx = nil
end

-- Toggle FX selection for detail panel (clicking same FX closes detail)
local function toggle_fx_detail(guid)
    if state.selected_fx == guid then
        state.selected_fx = nil
    else
        state.selected_fx = guid
    end
end

--------------------------------------------------------------------------------
-- Plugin Browser Helpers
--------------------------------------------------------------------------------

local function scan_plugins()
    if state.browser.scanned then return end
    
    Plugins.scan()
    state.browser.plugins = {}
    for plugin in Plugins.iter_all() do
        state.browser.plugins[#state.browser.plugins + 1] = plugin
    end
    state.browser.filtered = state.browser.plugins
    state.browser.scanned = true
end

local function filter_plugins()
    local search = state.browser.search:lower()
    local filter = state.browser.filter
    local results = {}
    
    local source = state.browser.plugins
    if filter == "instruments" then
        source = {}
        for plugin in Plugins.iter_instruments() do
            source[#source + 1] = plugin
        end
    elseif filter == "effects" then
        source = {}
        for plugin in Plugins.iter_effects() do
            source[#source + 1] = plugin
        end
    end
    
    for plugin in helpers.iter(source) do
        if search == "" then
            results[#results + 1] = plugin
        else
            local name_lower = plugin.name:lower()
            local mfr_lower = (plugin.manufacturer or ""):lower()
            if name_lower:find(search, 1, true) or mfr_lower:find(search, 1, true) then
                results[#results + 1] = plugin
            end
        end
    end
    
    state.browser.filtered = results
end

local function add_plugin_to_track(plugin)
    if not state.track then return end
    
    local fx = state.track:add_fx_by_name(plugin.full_name, false, -1)
    if fx then
        refresh_fx_list()
    end
end

--------------------------------------------------------------------------------
-- Container Operations
--------------------------------------------------------------------------------

local function add_to_new_container(fx_list)
    if #fx_list == 0 then return end
    if not state.track then return end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local container = state.track:add_fx_to_new_container(fx_list)
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add to Container", -1)
    
    if container then
        state.expanded_path = { container:get_guid() }
        refresh_fx_list()
    end
    
    return container
end

--------------------------------------------------------------------------------
-- UI: Plugin Browser
--------------------------------------------------------------------------------

local function draw_plugin_browser(ctx)
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
        if ctx:begin_tab_item(" 🎹 Inst ") then
            if state.browser.filter ~= "instruments" then
                state.browser.filter = "instruments"
                filter_plugins()
            end
            ctx:end_tab_item()
        end
        if ctx:begin_tab_item(" 🔧 FX ") then
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
            
            local icon = plugin.is_instrument and "🎹" or "🔧"
            local label = icon .. " " .. plugin.name
            
            if ctx:selectable(label, false) then
                add_plugin_to_track(plugin)
            end
            
            if ctx:is_item_hovered() then
                ctx:set_tooltip(plugin.full_name)
            end
            
            ctx:pop_id()
        end
        ctx:end_child()
    end
end

--------------------------------------------------------------------------------
-- UI: FX List Column (reusable for any level)
--------------------------------------------------------------------------------

local function draw_fx_list_column(ctx, fx_list, column_title, depth, width)
    if ctx:begin_child("Column" .. depth, width, 0, imgui.ChildFlags.Border()) then
        ctx:text(column_title)
        ctx:separator()
        
        if #fx_list == 0 then
            ctx:text_disabled("Empty")
            ctx:end_child()
            return
        end
        
        local i = 0
        for fx in helpers.iter(fx_list) do
            i = i + 1
            local guid = fx:get_guid()
            if not guid then goto continue end
            
            ctx:push_id(i)
            
            local is_container = fx:is_container()
            local is_expanded = state.expanded_path[depth] == guid
            local is_selected = state.selected_fx == guid
            local is_multi = state.multi_select[guid] ~= nil
            local enabled = fx:get_enabled()
            
            if not enabled then
                ctx:push_style_color(imgui.Col.Text(), 0x808080FF)
            end
            
            local icon = is_container and (is_expanded and "📂" or "📁") or "🔌"
            local label = icon .. " " .. fx:get_name()
            
            -- Highlight if expanded OR selected for detail OR multi-selected
            local highlight = is_expanded or is_selected or is_multi
            
            if ctx:selectable(label, highlight) then
                if ctx:is_key_down(imgui.Key.Shift()) then
                    -- Multi-select toggle
                    if state.multi_select[guid] then
                        state.multi_select[guid] = nil
                    else
                        state.multi_select[guid] = true
                    end
                else
                    clear_multi_select()
                    if is_container then
                        toggle_container(guid, depth)
                    else
                        toggle_fx_detail(guid)
                    end
                end
            end
            
            if not enabled then
                ctx:pop_style_color()
            end
            
            -- Right-click context menu
            if ctx:begin_popup_context_item() then
                if ctx:menu_item("Open FX Window") then
                    fx:show(3)
                end
                if ctx:menu_item(enabled and "Bypass" or "Enable") then
                    fx:set_enabled(not enabled)
                end
                ctx:separator()
                if ctx:menu_item("Delete") then
                    fx:delete()
                    collapse_from_depth(depth)
                    refresh_fx_list()
                end
                ctx:separator()
                local sel_count = get_multi_select_count()
                if sel_count > 0 then
                    if ctx:menu_item("Add Selected to Container") then
                        add_to_new_container(get_multi_selected_fx())
                        clear_multi_select()
                    end
                end
                ctx:end_popup()
            end
            
            -- Double-click
            if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                if is_container then
                    toggle_container(guid, depth)
                else
                    fx:show(3)
                end
            end
            
            ctx:pop_id()
            ::continue::
        end
        
        ctx:end_child()
    end
end

--------------------------------------------------------------------------------
-- UI: FX Detail Column
--------------------------------------------------------------------------------

local function draw_fx_detail_column(ctx, width)
    if not state.selected_fx then return end
    
    if ctx:begin_child("FXDetail", width, 0, imgui.ChildFlags.Border()) then
        local fx = state.track:find_fx_by_guid(state.selected_fx)
        if not fx then
            ctx:text_disabled("FX not found")
            ctx:end_child()
            return
        end
        
        -- Header
        ctx:text("🎛️ " .. fx:get_name())
        ctx:separator()
        
        -- Bypass toggle + Open button on same line
        local enabled = fx:get_enabled()
        local button_w = (width - 20) / 2
        if ctx:button(enabled and "🔊 On" or "🔇 Off", button_w, 0) then
            fx:set_enabled(not enabled)
        end
        ctx:same_line()
        if ctx:button("Open FX", button_w, 0) then
            fx:show(3)
        end
        
        ctx:separator()
        
        -- Parameters header
        local param_count = fx:get_num_params()
        ctx:text(string.format("Parameters (%d)", param_count))
        
        if param_count == 0 then
            ctx:text_disabled("No parameters")
        else
            -- Scrollable parameter list with two columns for many params
            if ctx:begin_child("ParamList", 0, 0, imgui.ChildFlags.Border()) then
                local use_two_cols = param_count > 8 and width > 350
                local col_width = use_two_cols and ((width - 30) / 2) or (width - 20)
                
                if use_two_cols then
                    -- Two-column layout
                    local half = math.ceil(param_count / 2)
                    
                    if r.ImGui_BeginTable(ctx.ctx, "ParamTable", 2) then
                        r.ImGui_TableSetupColumn(ctx.ctx, "Col1", r.ImGui_TableColumnFlags_WidthStretch())
                        r.ImGui_TableSetupColumn(ctx.ctx, "Col2", r.ImGui_TableColumnFlags_WidthStretch())
                        
                        for row = 0, half - 1 do
                            r.ImGui_TableNextRow(ctx.ctx)
                            
                            -- Left column
                            r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
                            local i = row
                            if i < param_count then
                                local name = fx:get_param_name(i)
                                local val = fx:get_param_normalized(i) or 0
                                local display_name = (name and name ~= "") and name or ("P" .. (i + 1))
                                
                                ctx:push_id(i)
                                ctx:text(display_name)
                                ctx:set_next_item_width(-1)
                                local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, "%.2f")
                                if changed then
                                    fx:set_param_normalized(i, new_val)
                                end
                                ctx:pop_id()
                            end
                            
                            -- Right column
                            r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
                            local j = row + half
                            if j < param_count then
                                local name = fx:get_param_name(j)
                                local val = fx:get_param_normalized(j) or 0
                                local display_name = (name and name ~= "") and name or ("P" .. (j + 1))
                                
                                ctx:push_id(j)
                                ctx:text(display_name)
                                ctx:set_next_item_width(-1)
                                local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, "%.2f")
                                if changed then
                                    fx:set_param_normalized(j, new_val)
                                end
                                ctx:pop_id()
                            end
                        end
                        
                        r.ImGui_EndTable(ctx.ctx)
                    end
                else
                    -- Single column layout
                    for i = 0, param_count - 1 do
                        local name = fx:get_param_name(i)
                        local val = fx:get_param_normalized(i) or 0
                        local display_name = (name and name ~= "") and name or ("Param " .. (i + 1))
                        
                        ctx:push_id(i)
                        ctx:text(display_name)
                        ctx:set_next_item_width(-1)
                        local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, "%.3f")
                        if changed then
                            fx:set_param_normalized(i, new_val)
                        end
                        ctx:spacing()
                        ctx:pop_id()
                    end
                end
                ctx:end_child()
            end
        end
        
        ctx:end_child()
    end
end

--------------------------------------------------------------------------------
-- UI: Toolbar
--------------------------------------------------------------------------------

local function draw_toolbar(ctx)
    if ctx:button("↻") then
        refresh_fx_list()
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Refresh") end
    
    ctx:same_line()
    
    local sel_count = get_multi_select_count()
    ctx:with_disabled(sel_count < 1, function()
        if ctx:button("📦+") then
            add_to_new_container(get_multi_selected_fx())
            clear_multi_select()
        end
    end)
    if ctx:is_item_hovered() then ctx:set_tooltip("Add selected to new container") end
    
    ctx:same_line()
    ctx:text("|")
    ctx:same_line()
    ctx:text(state.track_name)
    
    -- Breadcrumb trail
    if #state.expanded_path > 0 then
        ctx:same_line()
        ctx:text("→")
        for i, guid in ipairs(state.expanded_path) do
            ctx:same_line()
            local container = state.track:find_fx_by_guid(guid)
            if container then
                if ctx:small_button(container:get_name()) then
                    -- Click on breadcrumb collapses everything after it
                    collapse_from_depth(i + 1)
                end
            end
            if i < #state.expanded_path then
                ctx:same_line()
                ctx:text("→")
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

local function main()
    if not imgui.is_available() then
        r.ShowMessageBox(
            "SideFX requires ReaImGui.\nInstall via ReaPack.",
            "Missing Dependency", 0
        )
        return
    end
    
    state.track, state.track_name = get_selected_track()
    refresh_fx_list()
    scan_plugins()
    
    Window.run({
        title = "SideFX",
        width = 1000,
        height = 500,
        dockable = true,
        
        on_draw = function(self, ctx)
            theme.Reaper:apply(ctx)
            
            -- Track change detection
            local track, name = get_selected_track()
            local track_changed = (track and state.track and track.pointer ~= state.track.pointer)
                or (track and not state.track)
                or (not track and state.track)
            if track_changed then
                state.track, state.track_name = track, name
                state.expanded_path = {}
                state.selected_fx = nil
                clear_multi_select()
                refresh_fx_list()
            end
            
            -- Toolbar
            draw_toolbar(ctx)
            ctx:separator()
            
            -- Column widths
            local col_w = 200
            local browser_w = 260
            
            -- Detail column width depends on param count
            local detail_w = 220
            if state.selected_fx and state.track then
                local fx = state.track:find_fx_by_guid(state.selected_fx)
                if fx then
                    local param_count = fx:get_num_params()
                    if param_count > 8 then
                        detail_w = 400  -- Wide for two-column layout
                    end
                end
            end
            
            -- Plugin Browser (fixed left)
            if ctx:begin_child("Browser", browser_w, 0, imgui.ChildFlags.Border()) then
                ctx:text("Plugins")
                ctx:separator()
                draw_plugin_browser(ctx)
                ctx:end_child()
            end
            
            ctx:same_line()
            
            -- Scrollable columns area for FX chain + containers
            local flags = r.ImGui_WindowFlags_HorizontalScrollbar()
            if ctx:begin_child("ColumnsArea", 0, 0, imgui.ChildFlags.None(), flags) then
                
                -- Column 1: Top-level FX chain
                draw_fx_list_column(ctx, state.top_level_fx, "FX Chain", 1, col_w)
                
                -- Additional columns for each expanded container
                for depth, container_guid in ipairs(state.expanded_path) do
                    ctx:same_line()
                    local children = get_container_children(container_guid)
                    local container = state.track:find_fx_by_guid(container_guid)
                    local title = container and ("📦 " .. container:get_name()) or "Container"
                    draw_fx_list_column(ctx, children, title, depth + 1, col_w)
                end
                
                -- Detail column (if FX selected)
                if state.selected_fx then
                    ctx:same_line()
                    draw_fx_detail_column(ctx, detail_w)
                end
                
                ctx:end_child()
            end
            
            theme.Reaper:unapply(ctx)
        end,
    })
end

main()
