-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.5.0
-- @provides
--   [nomain] lib/*.lua
--   [nomain] jsfx/SideFX_Modulator.jsfx
-- @link https://github.com/Conceptual-Machines/SideFX
-- @about
--   # SideFX
--
--   Rack-style FX container management for Reaper 7+.
--   Ableton/Bitwig-inspired UI for FX chains.
--
-- @changelog
--   v0.5.0 - JSFX Modulator Integration
--     + Added SideFX_Modulator JSFX with custom curve editor
--     + Modulator panel in sidebar to add/manage JSFX modulators
--     + Serum/ShaperBox-style multi-point Bezier curve editor
--     + Use REAPER's parameter modulation to link modulator output
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

-- EmojImGui path
local emojimgui_path = scripts_folder .. "ReaTeam Scripts/Development/talagan_EmojImGui/"

-- Load EmojImGui FIRST with ReaImGui's builtin path (before ReaWrap's imgui shadows it)
local reaimgui_path = r.ImGui_GetBuiltinPath and (r.ImGui_GetBuiltinPath() .. "/?.lua;") or ""
package.path = reaimgui_path .. emojimgui_path .. "?.lua;" .. package.path
local EmojImGui = require('emojimgui')

-- Clear the cached ReaImGui 'imgui' so we can load ReaWrap's version
package.loaded['imgui'] = nil

-- NOW set up ReaWrap paths (these will shadow ReaImGui's imgui with ReaWrap's imgui)
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
-- Icons (using OpenMoji font)
--------------------------------------------------------------------------------

local Icons = {
    folder_open = "1F4C2",      -- 📂
    folder_closed = "1F4C1",    -- 📁
    package = "1F4E6",          -- 📦
    plug = "1F50C",             -- 🔌
    musical_keyboard = "1F3B9", -- 🎹
    wrench = "1F527",           -- 🔧
    speaker_high = "1F50A",     -- 🔊
    speaker_muted = "1F507",    -- 🔇
    arrows_counterclockwise = "1F504", -- 🔄
}

local icon_font = nil
local icon_size = 16
local default_font = nil

local function icon_text(icon_id)
    local info = EmojImGui.Asset.CharInfo("OpenMoji", icon_id)
    return info and info.utf8 or "?"
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local state = {
    track = nil,
    track_name = "No track selected",

    -- FX data
    top_level_fx = {},
    last_fx_count = 0,  -- For detecting external FX changes

    -- Column navigation: list of expanded container GUIDs (breadcrumb trail)
    expanded_path = {},  -- e.g. {container1_guid, container2_guid, ...}

    -- Selected FX for detail panel
    selected_fx = nil,

    -- Multi-select for operations
    multi_select = {},

    -- Rename state
    renaming_fx = nil,  -- GUID of FX being renamed
    rename_text = "",    -- Current rename text

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

-- Create dynamic REAPER theme (reads actual theme colors)
local reaper_theme = theme.from_reaper_theme("REAPER Dynamic")

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
    if not state.track then 
        state.last_fx_count = 0
        return 
    end

    for fx in state.track:iter_track_fx_chain() do
        local parent = fx:get_parent_container()
        if not parent then
            state.top_level_fx[#state.top_level_fx + 1] = fx
        end
    end
    state.last_fx_count = state.track:get_track_fx_count()
end

local function clear_multi_select()
    state.multi_select = {}
end

-- Check if FX chain changed externally and refresh if needed
local function check_fx_changes()
    if not state.track then return end
    local current_count = state.track:get_track_fx_count()
    if current_count ~= state.last_fx_count then
        refresh_fx_list()
        -- Clear invalid selections
        clear_multi_select()
        state.selected_fx = nil
        -- Validate expanded_path - remove any GUIDs that no longer exist
        local valid_path = {}
        for _, guid in ipairs(state.expanded_path) do
            if state.track:find_fx_by_guid(guid) then
                valid_path[#valid_path + 1] = guid
            else
                break  -- Stop at first invalid - rest would be children
            end
        end
        state.expanded_path = valid_path
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

-- Get display name for FX (uses renamed_name if set, otherwise default name)
local function get_fx_display_name(fx)
    if not fx then return "Unknown" end
    local ok, renamed = pcall(function() return fx:get_named_config_param("renamed_name") end)
    if ok and renamed and renamed ~= "" then
        return renamed
    end
    return fx:get_name()
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
    if state.expanded_path[depth] == guid then
        collapse_from_depth(depth)
    else
        collapse_from_depth(depth)
        state.expanded_path[depth] = guid
    end
    state.selected_fx = nil
end

-- Toggle FX selection for detail panel
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

local function dissolve_container(container)
    if not container or not container:is_container() then return false end
    if not state.track then return false end

    -- Get all children before we start moving them
    local children = {}
    for child in container:iter_container_children() do
        children[#children + 1] = child:get_guid()
    end

    if #children == 0 then
        -- Empty container, just delete it
        container:delete()
        return true
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get the parent container (or nil if at track level)
    local parent_container = container:get_parent_container()
    
    -- Move all children out of the container
    -- We need to re-lookup by GUID after each move since pointers may change
    for _, child_guid in ipairs(children) do
        local child = state.track:find_fx_by_guid(child_guid)
        if child then
            -- Move out of container - this will move to parent or track level
            while child:get_parent_container() and child:get_parent_container():get_guid() == container:get_guid() do
                child:move_out_of_container()
                -- Re-lookup after move (pointer may have changed)
                child = state.track:find_fx_by_guid(child_guid)
                if not child then break end
            end
        end
    end

    -- Re-lookup container (pointer may have changed after moves)
    local container_guid = container:get_guid()
    container = state.track:find_fx_by_guid(container_guid)
    
    -- Delete the now-empty container
    if container then
        container:delete()
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Dissolve Container", -1)

    return true
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
            if icon_font then r.ImGui_PushFont(ctx.ctx, icon_font, icon_size) end
            local icon = plugin.is_instrument and icon_text(Icons.musical_keyboard) or icon_text(Icons.wrench)
            ctx:text(icon)
            if icon_font then r.ImGui_PopFont(ctx.ctx) end

            -- Text with default font
            ctx:same_line()
            if ctx:selectable(plugin.name, false) then
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

local function draw_fx_list_column(ctx, fx_list, column_title, depth, width, parent_container_guid)
    if ctx:begin_child("Column" .. depth, width, 0, imgui.ChildFlags.Border()) then
        ctx:text(column_title)
        ctx:separator()
        
        -- Drop zone for this column
        local has_payload = ctx:get_drag_drop_payload("FX_GUID")
        if has_payload then
            local drop_label = depth == 1 and "Drop to move to track" or ("Drop to add to " .. column_title)
            ctx:push_style_color(imgui.Col.Button(), 0x4488FF88)
            ctx:button(drop_label .. "##drop" .. depth, -1, 24)
            ctx:pop_style_color()
            if ctx:begin_drag_drop_target() then
                local accepted, guid = ctx:accept_drag_drop_payload("FX_GUID")
                if accepted and guid then
                    local fx = state.track:find_fx_by_guid(guid)
                    if fx then
                        local fx_parent = fx:get_parent_container()
                        local fx_parent_guid = fx_parent and fx_parent:get_guid() or nil
                        
                        if depth == 1 then
                            -- Move to track level (only if FX is in a container)
                            if fx_parent then
                                while fx:get_parent_container() do
                                    fx:move_out_of_container()
                                    fx = state.track:find_fx_by_guid(guid)
                                    if not fx then break end
                                end
                                refresh_fx_list()
                            end
                        elseif parent_container_guid then
                            -- Move into this column's container (if not already there)
                            if fx_parent_guid ~= parent_container_guid then
                                local target_container = state.track:find_fx_by_guid(parent_container_guid)
                                if target_container then
                                    -- Build path from FX to target container
                                    -- We need to move through intermediate containers
                                    local target_path = {}  -- GUIDs from root to target
                                    local container = target_container
                                    while container do
                                        table.insert(target_path, 1, container:get_guid())
                                        container = container:get_parent_container()
                                    end
                                    
                                    -- Move FX through each level
                                    for _, container_guid in ipairs(target_path) do
                                        fx = state.track:find_fx_by_guid(guid)
                                        if not fx then break end
                                        
                                        local current_parent = fx:get_parent_container()
                                        local current_parent_guid = current_parent and current_parent:get_guid() or nil
                                        
                                        if current_parent_guid ~= container_guid then
                                            local c = state.track:find_fx_by_guid(container_guid)
                                            if c then
                                                c:add_fx_to_container(fx)
                                            end
                                        end
                                    end
                                    refresh_fx_list()
                                end
                            end
                        end
                    end
                end
                ctx:end_drag_drop_target()
            end
        end

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

            -- Use depth + index for unique IDs across columns
            ctx:push_id(depth * 1000 + i)

            local is_container = fx:is_container()
            local is_expanded = state.expanded_path[depth] == guid
            local is_selected = state.selected_fx == guid
            local is_multi = state.multi_select[guid] ~= nil
            local enabled = fx:get_enabled()

            -- Layout constants (relative to column width)
            local icon_w = 24
            local btn_w = 34
            local wet_w = 52
            local controls_w = btn_w + wet_w + 8
            local name_w = width - icon_w - controls_w - 30  -- 30px gap
            local controls_x = width - controls_w - 8
            
            -- Icon with emoji font
            if icon_font then r.ImGui_PushFont(ctx.ctx, icon_font, icon_size) end
            local icon = is_container
                and (is_expanded and icon_text(Icons.folder_open) or icon_text(Icons.folder_closed))
                or icon_text(Icons.plug)
            ctx:text(icon)
            if icon_font then r.ImGui_PopFont(ctx.ctx) end

            -- Name as selectable (or input text if renaming)
            ctx:same_line()
            local highlight = is_expanded or is_selected or is_multi
            local is_renaming = state.renaming_fx == guid
            
            if is_renaming then
                -- Inline rename input
                ctx:set_next_item_width(name_w)
                local changed, new_text = ctx:input_text("##rename" .. i, state.rename_text, imgui.InputTextFlags.EnterReturnsTrue())
                if changed then
                    state.rename_text = new_text
                    -- If Enter was pressed (EnterReturnsTrue flag), save and finish
                    if state.rename_text ~= "" then
                        -- Save renamed name
                        fx:set_named_config_param("renamed_name", state.rename_text)
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Check if item was deactivated after edit (clicked away)
                if r.ImGui_IsItemDeactivatedAfterEdit(ctx.ctx) then
                    if state.rename_text ~= "" then
                        -- Save renamed name
                        fx:set_named_config_param("renamed_name", state.rename_text)
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Cancel on Escape
                if ctx:is_key_pressed(r.ImGui_Key_Escape()) then
                    -- Cancel rename
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
            else
                local name = get_fx_display_name(fx)
                -- Truncate based on available width (approx 7px per char)
                local max_chars = math.floor(name_w / 7)
                if #name > max_chars then
                    name = string.sub(name, 1, max_chars - 2) .. ".."
                end

                if ctx:selectable(name .. "##sel" .. i, highlight, 0, name_w, 0) then
                    if ctx:is_shift_down() then
                        if state.selected_fx and get_multi_select_count() == 0 then
                            state.multi_select[state.selected_fx] = true
                        end
                        if state.multi_select[guid] then
                            state.multi_select[guid] = nil
                        else
                            state.multi_select[guid] = true
                        end
                        state.selected_fx = nil
                    else
                        clear_multi_select()
                        if is_container then
                            toggle_container(guid, depth)
                        else
                            toggle_fx_detail(guid)
                        end
                    end
                end
            end
            
            -- Drag source for moving FX (must be right after selectable)
            if ctx:begin_drag_drop_source() then
                ctx:set_drag_drop_payload("FX_GUID", guid)
                ctx:text("Moving: " .. get_fx_display_name(fx))
                ctx:end_drag_drop_source()
            end

            -- Drop target for ALL FX items (reordering and container drops)
            if ctx:begin_drag_drop_target() then
                local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
                if accepted and payload and payload ~= guid then
                    local drag_fx = state.track:find_fx_by_guid(payload)
                    if drag_fx then
                        if is_container then
                            -- Dropping onto a container: move into it
                            drag_fx:move_to_container(fx)
                        else
                            -- Dropping onto a non-container FX: reorder
                            local drag_parent = drag_fx:get_parent_container()
                            local target_parent = fx:get_parent_container()
                            local drag_parent_guid = drag_parent and drag_parent:get_guid() or nil
                            local target_parent_guid = target_parent and target_parent:get_guid() or nil
                            
                            if drag_parent_guid == target_parent_guid then
                                -- Same container: reorder using REAPER's swap
                                -- Get positions
                                local drag_pos = drag_fx.pointer
                                local target_pos = fx.pointer
                                
                                if target_parent then
                                    -- Inside a container - use container child positions
                                    local children = {}
                                    for child in target_parent:iter_container_children() do
                                        children[#children + 1] = child
                                    end
                                    for idx, child in ipairs(children) do
                                        if child:get_guid() == payload then drag_pos = idx - 1 end
                                        if child:get_guid() == guid then target_pos = idx - 1 end
                                    end
                                end
                                
                                -- Swap using TrackFX_CopyToTrack
                                if drag_pos ~= target_pos then
                                    r.TrackFX_CopyToTrack(
                                        state.track.pointer, drag_fx.pointer,
                                        state.track.pointer, fx.pointer,
                                        true
                                    )
                                end
                            else
                                -- Different containers: move to target's container at target's position
                                if target_parent then
                                    -- Find target's position in its container
                                    local target_pos = 0
                                    for child in target_parent:iter_container_children() do
                                        if child:get_guid() == guid then break end
                                        target_pos = target_pos + 1
                                    end
                                    target_parent:add_fx_to_container(drag_fx, target_pos)
                                else
                                    -- Target is at track level
                                    drag_fx:move_out_of_container()
                                end
                            end
                        end
                        refresh_fx_list()
                    end
                end
                ctx:end_drag_drop_target()
            end

            -- Right-click context menu (must be right after selectable)
            if ctx:begin_popup_context_item("fxmenu" .. i) then
                if ctx:menu_item("Open FX Window") then
                    fx:show(3)
                end
                if ctx:menu_item(enabled and "Bypass" or "Enable") then
                    fx:set_enabled(not enabled)
                end
                ctx:separator()
                if ctx:menu_item("Rename") then
                    state.renaming_fx = guid
                    state.rename_text = get_fx_display_name(fx)
                end
                ctx:separator()
                -- Remove from container option (only if inside a container)
                local parent = fx:get_parent_container()
                if parent then
                    if ctx:menu_item("Remove from Container") then
                        fx:move_out_of_container()
                        collapse_from_depth(depth)
                        refresh_fx_list()
                    end
                    ctx:separator()
                end
                -- Dissolve container option (only for containers)
                if is_container then
                    if ctx:menu_item("Dissolve Container") then
                        dissolve_container(fx)
                        collapse_from_depth(depth)
                        refresh_fx_list()
                    end
                    ctx:separator()
                end
                if ctx:menu_item("Delete") then
                    fx:delete()
                    collapse_from_depth(depth)
                    refresh_fx_list()
                end
                ctx:separator()
                local sel_count = get_multi_select_count()
                if sel_count > 0 then
                    if ctx:menu_item("Add Selected to Container (" .. sel_count .. ")") then
                        add_to_new_container(get_multi_selected_fx())
                        clear_multi_select()
                    end
                else
                    -- Single item - add to new container (works for FX and containers)
                    if ctx:menu_item("Add to New Container") then
                        add_to_new_container({fx})
                    end
                end
                ctx:end_popup()
            end
            
            if ctx:is_item_hovered() then ctx:set_tooltip(get_fx_display_name(fx)) end

            -- Controls on the right
            ctx:same_line_ex(controls_x)
            
            -- Wet/Dry slider
            local wet_idx = fx:get_param_from_ident(":wet")
            if wet_idx >= 0 then
                local wet_val = fx:get_param(wet_idx)
                ctx:set_next_item_width(wet_w - 5)
                local wet_changed, new_wet = ctx:slider_double("##wet" .. i, wet_val, 0, 1, "%.0f%%")
                if wet_changed then
                    fx:set_param(wet_idx, new_wet)
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Wet: " .. string.format("%.0f%%", wet_val * 100)) end
                ctx:same_line()
            end

            -- Bypass button (colored)
            if enabled then
                ctx:push_style_color(imgui.Col.Button(), 0x44AA44FF)
            else
                ctx:push_style_color(imgui.Col.Button(), 0xAA4444FF)
            end
            if ctx:small_button(enabled and "ON##" .. i or "OFF##" .. i) then
                fx:set_enabled(not enabled)
            end
            ctx:pop_style_color()

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
        ctx:text(get_fx_display_name(fx))
        ctx:separator()

        -- Bypass toggle + Open button on same line
        local enabled = fx:get_enabled()
        local button_w = (width - 20) / 2
        if ctx:button(enabled and "ON" or "OFF", button_w, 0) then
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

                if use_two_cols then
                    local half = math.ceil(param_count / 2)

                    if r.ImGui_BeginTable(ctx.ctx, "ParamTable", 2) then
                        r.ImGui_TableSetupColumn(ctx.ctx, "Col1", r.ImGui_TableColumnFlags_WidthStretch())
                        r.ImGui_TableSetupColumn(ctx.ctx, "Col2", r.ImGui_TableColumnFlags_WidthStretch())

                        for row = 0, half - 1 do
                            r.ImGui_TableNextRow(ctx.ctx)

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
-- UI: Modulator Panel
--------------------------------------------------------------------------------

local JSFX_NAME = "SideFX_Modulator"

local function find_modulators_on_track(track)
    if not track then return {} end
    local modulators = {}
    local fx_count = track:get_fx_count()
    for i = 0, fx_count - 1 do
        local name = r.TrackFX_GetFXName(track.pointer, i, "")
        if name and (name:find(JSFX_NAME) or name:find("SideFX Modulator")) then
            table.insert(modulators, {
                index = i,
                name = name,
            })
        end
    end
    return modulators
end

local function add_modulator_to_track(track)
    if not track then return end
    r.Undo_BeginBlock()
    local fx_idx = r.TrackFX_AddByName(track.pointer, JSFX_NAME, false, -1)
    if fx_idx >= 0 then
        r.TrackFX_Show(track.pointer, fx_idx, 3)  -- Show floating window
    end
    r.Undo_EndBlock("Add SideFX Modulator", -1)
end

local function delete_modulator(track, fx_idx)
    if not track then return end
    r.Undo_BeginBlock()
    r.TrackFX_Delete(track.pointer, fx_idx)
    r.Undo_EndBlock("Delete SideFX Modulator", -1)
end

local function show_modulator_ui(track, fx_idx)
    if not track then return end
    r.TrackFX_Show(track.pointer, fx_idx, 3)  -- Show floating window
end

local function draw_modulator_panel(ctx)
    ctx:text("Modulators")
    ctx:same_line()
    if ctx:small_button("+ Add") then
        add_modulator_to_track(state.track)
    end
    ctx:separator()
    
    if not state.track then
        ctx:text_colored(0x888888FF, "Select a track")
        return
    end
    
    local modulators = find_modulators_on_track(state.track)
    
    if #modulators == 0 then
        ctx:text_colored(0x888888FF, "No modulators")
        ctx:text_colored(0x888888FF, "Click '+ Add'")
    else
        for i, mod in ipairs(modulators) do
            ctx:push_id("mod_" .. mod.index)
            
            -- Modulator label
            ctx:text("LFO " .. i)
            ctx:same_line()
            
            -- UI button
            if ctx:small_button("UI") then
                show_modulator_ui(state.track, mod.index)
            end
            ctx:same_line()
            
            -- Delete button
            ctx:push_style_color(r.ImGui_Col_Button(), 0xAA3333FF)
            if ctx:small_button("X") then
                delete_modulator(state.track, mod.index)
                ctx:pop_style_color()
                ctx:pop_id()
                return  -- Exit since list changed
            end
            ctx:pop_style_color()
            
            ctx:pop_id()
        end
    end
end

--------------------------------------------------------------------------------
-- UI: Toolbar
--------------------------------------------------------------------------------

local function draw_toolbar(ctx)
    -- Refresh button (icon only)
    if icon_font then r.ImGui_PushFont(ctx.ctx, icon_font, icon_size) end
    if ctx:button(icon_text(Icons.arrows_counterclockwise)) then
        refresh_fx_list()
    end
    if icon_font then r.ImGui_PopFont(ctx.ctx) end
    if ctx:is_item_hovered() then ctx:set_tooltip("Refresh") end

    ctx:same_line()

    -- Add to container button (icon only)
    local sel_count = get_multi_select_count()
    ctx:with_disabled(sel_count < 1, function()
        if icon_font then r.ImGui_PushFont(ctx.ctx, icon_font, icon_size) end
        if ctx:button(icon_text(Icons.package)) then
            add_to_new_container(get_multi_selected_fx())
            clear_multi_select()
        end
        if icon_font then r.ImGui_PopFont(ctx.ctx) end
    end)
    if ctx:is_item_hovered() then ctx:set_tooltip("Add selected to new container (" .. sel_count .. " selected)") end

    ctx:same_line()
    ctx:text("|")
    ctx:same_line()
    ctx:text(state.track_name)

    -- Breadcrumb trail
    if #state.expanded_path > 0 then
        ctx:same_line()
        ctx:text(">")
        for i, guid in ipairs(state.expanded_path) do
            ctx:same_line()
            local container = state.track:find_fx_by_guid(guid)
            if container then
                if ctx:small_button(get_fx_display_name(container)) then
                    collapse_from_depth(i + 1)
                end
            end
            if i < #state.expanded_path then
                ctx:same_line()
                ctx:text(">")
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
            reaper_theme:apply(ctx)

            -- Load fonts on first frame
            if not default_font then
                -- Create a larger, more legible default font
                -- Try common system fonts that are known to be readable
                local font_families = {
                    "Segoe UI",      -- Windows default
                    "Helvetica Neue", -- macOS default
                    "Arial",         -- Fallback
                    "DejaVu Sans",   -- Linux/common
                }
                
                for _, family in ipairs(font_families) do
                    -- ImGui_CreateFont takes: family_or_file, size (flags are optional via separate call)
                    default_font = r.ImGui_CreateFont(family, 14)
                    if default_font then
                        break
                    end
                end
                
                -- If no font was created, try with a generic name
                if not default_font then
                    default_font = r.ImGui_CreateFont("", 14)
                end
            end
            
            -- Push default font if available
            if default_font then
                r.ImGui_PushFont(ctx.ctx, default_font, 14)
            end
            
            -- Load icon font on first frame
            if not icon_font then
                icon_font = EmojImGui.Asset.Font(ctx.ctx, "OpenMoji")
            end

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
            else
                -- Check for external FX changes (e.g. user deleted FX in REAPER)
                check_fx_changes()
            end

            -- Toolbar
            draw_toolbar(ctx)
            ctx:separator()

            -- Column widths
            local col_w = 280
            local browser_w = 260

            -- Detail column width depends on param count
            local detail_w = 220
            if state.selected_fx and state.track then
                local fx = state.track:find_fx_by_guid(state.selected_fx)
                if fx then
                    local param_count = fx:get_num_params()
                    if param_count > 8 then
                        detail_w = 400
                    end
                end
            end

            -- Left panel: Browser + Modulators
            if ctx:begin_child("LeftPanel", browser_w, 0, imgui.ChildFlags.None()) then
                
                -- Plugin Browser (top portion)
                local avail_h = ctx:get_content_region_avail_y()
                local modulator_h = 150  -- Fixed height for modulator panel
                local browser_h = avail_h - modulator_h - 10  -- Leave some padding
                
                if ctx:begin_child("Browser", 0, browser_h, imgui.ChildFlags.Border()) then
                    ctx:text("Plugins")
                    ctx:separator()
                    draw_plugin_browser(ctx)
                    ctx:end_child()
                end
                
                ctx:spacing()
                
                -- Modulator Panel (bottom portion)
                if ctx:begin_child("Modulators", 0, modulator_h, imgui.ChildFlags.Border()) then
                    draw_modulator_panel(ctx)
                    ctx:end_child()
                end
                
                ctx:end_child()
            end

            ctx:same_line()

            -- Scrollable columns area for FX chain + containers
            local flags = r.ImGui_WindowFlags_AlwaysHorizontalScrollbar()
            if ctx:begin_child("ColumnsArea", 0, 0, imgui.ChildFlags.None(), flags) then

                -- Column 1: Top-level FX chain (no parent container)
                draw_fx_list_column(ctx, state.top_level_fx, "FX Chain", 1, col_w, nil)

                -- Additional columns for each expanded container
                for depth, container_guid in ipairs(state.expanded_path) do
                    ctx:same_line()
                    local children = get_container_children(container_guid)
                    local container = state.track:find_fx_by_guid(container_guid)
                    local title = container and get_fx_display_name(container) or "Container"
                    -- Pass the container guid so drops can target this container
                    draw_fx_list_column(ctx, children, title, depth + 1, col_w, container_guid)
                end

                -- Detail column (if FX selected)
                if state.selected_fx then
                    ctx:same_line()
                    draw_fx_detail_column(ctx, detail_w)
                end

                ctx:end_child()
            end

            reaper_theme:unapply(ctx)
            
            -- Pop default font if we pushed it
            if default_font then
                r.ImGui_PopFont(ctx.ctx)
            end
        end,
    })
end

main()
