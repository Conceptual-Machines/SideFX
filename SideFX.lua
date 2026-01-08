-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.1.1
-- @provides
--   [nomain] lib/*.lua
--   [nomain] lib/ui/*.lua
-- @depends ReaWrap>=0.7.3
-- @depends ReaImGui
-- @depends talagan_EmojImGui
-- @link https://github.com/Conceptual-Machines/SideFX
-- @about
--   # SideFX
--
--   Rack-style FX container management for Reaper 7+.
--   Ableton/Bitwig-inspired horizontal device chain UI.
--
--   ## Features
--   - Horizontal device chain layout
--   - Device panels with inline parameter control
--   - Parallel rack containers
--   - Modulator routing with parameter links
--   - Plugin browser with search
--
-- @changelog
--   v0.1.1 - Rack Header Layout & UI Polish
--     + Hierarchical naming display for racks, chains, devices
--     + Improved rack header layout with proper alignment
--     + Collapsed rack view with controls (chain count, pan, fader)
--     + Device header UI improvements (inline controls)
--     + Add empty chain creation
--     + Smaller, refined UI controls
--   v0.1.0 - Initial Release
--     + Horizontal device chain layout
--     + Device panels with expand/collapse parameters
--     + Parallel rack containers
--     + Modulator routing with parameter links
--     + Plugin browser with search
--     + Drag and drop support
--     + ReaWrap integration

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

-- SideFX modules
local naming = require('lib.utils.naming')
local fx_utils = require('lib.fx.fx_utils')
local state_module = require('lib.core.state')
local rack_module = require('lib.rack.rack')
local rack_backend = require('lib.rack.rack_backend')
local device_module = require('lib.device.device')
local container_module = require('lib.device.container')
local modulator_module = require('lib.modulator.modulator')
local browser_module = require('lib.browser.browser')
local constants = require('lib.core.constants')

-- UI modules
local widgets = require('lib.ui.common.widgets')
local drawing = require('lib.ui.common.drawing')
local chain_item = require('lib.ui.chain.chain_item')
local browser_panel = require('lib.ui.main.browser_panel')
local fx_menu = require('lib.ui.fx.fx_menu')
local fx_detail_panel = require('lib.ui.fx.fx_detail_panel')
local fx_list_column = require('lib.ui.fx.fx_list_column')
local device_chain = require('lib.ui.chain.device_chain')
local chain_column = require('lib.ui.chain.chain_column')
local rack_panel_main = require('lib.ui.rack.rack_panel_main')
local main_window = require('lib.ui.main.main_window')
local toolbar = require('lib.ui.main.toolbar')
local drag_drop = require('lib.ui.common.drag_drop')
local rack_ui = require('lib.ui.rack.rack_ui')

--------------------------------------------------------------------------------
-- Icons (using OpenMoji font)
--------------------------------------------------------------------------------

local Icons = constants.Icons
local icon_font = nil
local icon_size = 16
local default_font = nil

local function icon_text(icon_id)
    return constants.icon_text(EmojImGui, icon_id)
end

--------------------------------------------------------------------------------
-- State (from lib/state.lua)
--------------------------------------------------------------------------------

local state = state_module.state

-- Create dynamic REAPER theme (reads actual theme colors)
local reaper_theme = theme.from_reaper_theme("REAPER Dynamic")

--------------------------------------------------------------------------------
-- Helpers (from lib/state.lua)
--------------------------------------------------------------------------------

-- Forward declarations for functions defined later
local renumber_device_chain
local get_device_utility
local renumber_chains_in_rack
local draw_rack_panel  -- Forward declaration for draw_chain_column

-- Use state module functions
local get_selected_track = state_module.get_selected_track
local clear_multi_select = state_module.clear_multi_select
local check_fx_changes = state_module.check_fx_changes
local get_multi_selected_fx = state_module.get_multi_selected_fx
local get_multi_select_count = state_module.get_multi_select_count

-- Local wrapper for refresh_fx_list that sets up the callback
local function refresh_fx_list()
    -- Set callback before refreshing
    state_module.on_refresh = renumber_device_chain
    state_module.refresh_fx_list()
end

-- Initialize rack backend with dependencies
rack_backend.init(rack_module, state_module, refresh_fx_list)

-- Initialize modulator module with refresh callback
modulator_module.init(refresh_fx_list)

-- Use fx_utils module for display name
local get_fx_display_name = fx_utils.get_display_name

-- Use state module for navigation functions
local collapse_from_depth = state_module.collapse_from_depth
local toggle_container = state_module.toggle_container
local toggle_fx_detail = state_module.toggle_fx_detail

--------------------------------------------------------------------------------
-- Plugin Browser Helpers
--------------------------------------------------------------------------------

-- Plugin scanning/filtering moved to lib/browser.lua
local scan_plugins = browser_module.scan_plugins
local filter_plugins = browser_module.filter_plugins

-- Use fx_utils module for is_utility_fx
local is_utility_fx = fx_utils.is_utility_fx

-- Use fx_utils module for find_paired_utility
local find_paired_utility = fx_utils.find_paired_utility

--------------------------------------------------------------------------------
-- D-Container (Device) Helpers
--------------------------------------------------------------------------------

-- Use fx_utils module for container type detection
local is_device_container = fx_utils.is_device_container
local is_rack_container = fx_utils.is_rack_container

-- Use fx_utils module for device helpers
local get_device_main_fx = fx_utils.get_device_main_fx
get_device_utility = fx_utils.get_device_utility

-- Renumber all D-containers after chain changes
renumber_device_chain = function()
    if not state.track then return end

    local device_idx = 0
    for fx in state.track:iter_track_fx_chain() do
        local parent = fx:get_parent_container()
        if not parent then  -- Top level only
            local name = fx:get_name()

            -- Check if it's a D-container
            local old_idx, fx_name = name:match("^D(%d+): (.+)$")
            if old_idx and fx_name then
                device_idx = device_idx + 1
                local new_name = string.format("D%d: %s", device_idx, fx_name)
                if new_name ~= name then
                    fx:set_named_config_param("renamed_name", new_name)

                    -- Also rename FX inside (has _FX suffix)
                    local main_fx = get_device_main_fx(fx)
                    if main_fx then
                        local main_fx_name = string.format("D%d_FX: %s", device_idx, fx_name)
                        main_fx:set_named_config_param("renamed_name", main_fx_name)
                    end

                    -- Also rename utility inside
                    local utility = get_device_utility(fx)
                    if utility then
                        local util_name = string.format("D%d_Util", device_idx)
                        utility:set_named_config_param("renamed_name", util_name)
                    end
                end
            end

            -- Check if it's an R-container (rack)
            local rack_idx = name:match("^R(%d+)")
            if rack_idx then
                device_idx = device_idx + 1
                -- TODO: Renumber rack and its children
            end
        end
    end
end

-- Device operations (uses state singleton via device_module)
local function add_plugin_to_track(plugin, position)
    local result = device_module.add_plugin_to_track(plugin, position)
    if result then refresh_fx_list() end
    return result
end

local function add_plugin_by_name(plugin_name, position)
    local result = device_module.add_plugin_by_name(plugin_name, position)
    if result then refresh_fx_list() end
    return result
end

--------------------------------------------------------------------------------
-- R-Container (Rack) Functions (from lib/rack_backend.lua)
--------------------------------------------------------------------------------

-- Use rack backend functions with state management
local add_rack_to_track = rack_backend.add_rack_to_track
local add_chain_to_rack = rack_backend.add_chain_to_rack
local add_empty_chain_to_rack = rack_backend.add_empty_chain_to_rack
local add_nested_rack_to_rack = rack_backend.add_nested_rack_to_rack
local add_device_to_chain = rack_backend.add_device_to_chain
local add_rack_to_chain = rack_backend.add_rack_to_chain
local reorder_chain_in_rack = rack_backend.reorder_chain_in_rack
local move_chain_between_racks = rack_backend.move_chain_between_racks
local renumber_chains_in_rack = rack_backend.renumber_chains_in_rack

-- Use helper functions from other modules
local get_rack_mixer = fx_utils.get_rack_mixer
local draw_pan_slider = widgets.draw_pan_slider
local draw_fader = widgets.draw_fader

--------------------------------------------------------------------------------
-- Container Operations
--------------------------------------------------------------------------------

-- Container operations (uses container_module)
local function add_to_new_container(fx_list)
    local container = container_module.add_to_new_container(fx_list)
    if container then
        -- Use expanded_racks for containers (consistent with racks)
        state.expanded_racks[container:get_guid()] = true
        refresh_fx_list()
    end
    return container
end

local function dissolve_container(container)
    local result = container_module.dissolve_container(container)
    if result then refresh_fx_list() end
    return result
end

--------------------------------------------------------------------------------
-- UI: Plugin Browser
--------------------------------------------------------------------------------

local function draw_plugin_browser(ctx)
    browser_panel.draw(ctx, state, icon_font, icon_size, add_plugin_to_track, filter_plugins)
end

--------------------------------------------------------------------------------
-- UI: FX Context Menu
--------------------------------------------------------------------------------

local function draw_fx_context_menu(ctx, fx, guid, i, enabled, is_container, depth)
    fx_menu.draw_with_sidefx_callbacks(ctx, fx, guid, i, enabled, is_container, depth, get_fx_display_name, {
        state = state,
        collapse_from_depth = collapse_from_depth,
        refresh_fx_list = refresh_fx_list,
        dissolve_container = dissolve_container,
        add_to_new_container = add_to_new_container,
        get_multi_select_count = get_multi_select_count,
        get_multi_selected_fx = get_multi_selected_fx,
        clear_multi_select = clear_multi_select,
    })
end

--- Handle drop target for FX reordering and container drops.
local function handle_fx_drop_target(ctx, fx, guid, is_container)
    drag_drop.handle_fx_drop_target(ctx, fx, guid, is_container, state.track, {
        on_refresh = refresh_fx_list
    })
end

--- Move FX to track level (out of all containers).
local function move_fx_to_track_level(guid)
    drag_drop.move_fx_to_track_level(guid, state.track)
end

--- Move FX to a target container by navigating through hierarchy.
local function move_fx_to_container(guid, target_container_guid)
    drag_drop.move_fx_to_container(guid, target_container_guid, state.track)
end

--------------------------------------------------------------------------------
-- UI: FX List Column (reusable for any level)
--------------------------------------------------------------------------------

local function draw_fx_list_column(ctx, fx_list, column_title, depth, width, parent_container_guid)
    fx_list_column.draw(ctx, fx_list, column_title, depth, width, parent_container_guid, {
        state = state,
        state_module = state_module,
        track = state.track,
        icon_font = icon_font,
        icon_size = icon_size,
        icon_text = icon_text,
        Icons = Icons,
        get_fx_display_name = get_fx_display_name,
        move_fx_to_track_level = move_fx_to_track_level,
        move_fx_to_container = move_fx_to_container,
        refresh_fx_list = refresh_fx_list,
        handle_fx_drop_target = handle_fx_drop_target,
        draw_fx_context_menu = draw_fx_context_menu,
        toggle_container = toggle_container,
        toggle_fx_detail = toggle_fx_detail,
        clear_multi_select = clear_multi_select,
        get_multi_select_count = get_multi_select_count,
    })
end

--------------------------------------------------------------------------------
-- UI: FX Detail Column
--------------------------------------------------------------------------------

local function draw_fx_detail_column(ctx, width)
    fx_detail_panel.draw(ctx, width, state.selected_fx, function(guid)
        return state.track and state.track:find_fx_by_guid(guid) or nil
    end, get_fx_display_name)
end

--------------------------------------------------------------------------------
-- Modulators
--------------------------------------------------------------------------------

-- Modulator operations (uses modulator_module)
-- All functions now handle refresh internally via init callback
local find_modulators_on_track = modulator_module.find_modulators_on_track
local get_linkable_fx = modulator_module.get_linkable_fx
local create_param_link = modulator_module.create_param_link
local remove_param_link = modulator_module.remove_param_link
local get_modulator_links = modulator_module.get_modulator_links
local add_modulator = modulator_module.add_modulator
local delete_modulator = modulator_module.delete_modulator
local add_modulator_to_device = modulator_module.add_modulator_to_device

-- Use fx_utils module for is_modulator_fx
local is_modulator_fx = fx_utils.is_modulator_fx

--------------------------------------------------------------------------------
-- UI: Toolbar (v2 - horizontal layout)
--------------------------------------------------------------------------------

local function draw_toolbar(ctx)
    toolbar.draw(ctx, state, icon_font, icon_size, get_fx_display_name, {
        on_refresh = refresh_fx_list,
        on_add_rack = add_rack_to_track,
        on_add_fx = function() end,  -- TODO: Implement
        on_collapse_from_depth = collapse_from_depth,
    })
end

--------------------------------------------------------------------------------
-- UI: Horizontal Device Chain (v2)
--------------------------------------------------------------------------------

local device_panel = nil  -- Lazy loaded
local rack_panel = nil    -- Lazy loaded

-- draw_drop_zone moved to widgets module (not currently used, but available if needed)

--------------------------------------------------------------------------------
-- Rack Drawing Helpers
--------------------------------------------------------------------------------

-- Rack panel drawing helpers moved to lib/ui/rack_panel_main.lua
-- Chain column drawing moved to lib/ui/chain_column.lua

-- Draw expanded chain column with devices
local function draw_chain_column(ctx, selected_chain, rack_h)
    chain_column.draw(ctx, selected_chain, rack_h, {
        state = state,
        get_fx_display_name = get_fx_display_name,
                            refresh_fx_list = refresh_fx_list,
        get_device_main_fx = get_device_main_fx,
        get_device_utility = get_device_utility,
        is_rack_container = is_rack_container,
        add_device_to_chain = add_device_to_chain,
        add_rack_to_chain = add_rack_to_chain,
        draw_rack_panel = draw_rack_panel,
        icon_font = icon_font,
        default_font = default_font,
    })
end

-- Draw the rack panel (main rack UI without chain column)
local function draw_rack_panel(ctx, rack, avail_height, is_nested, callbacks)
    callbacks = callbacks or {}
    return rack_panel_main.draw(ctx, rack, avail_height, is_nested, {
        state = state,
            icon_font = icon_font,
        state_module = state_module,
        refresh_fx_list = refresh_fx_list,
        get_rack_mixer = get_rack_mixer,
        draw_pan_slider = draw_pan_slider,
        dissolve_container = dissolve_container,
        get_fx_display_name = get_fx_display_name,
        add_device_to_chain = add_device_to_chain,
        reorder_chain_in_rack = reorder_chain_in_rack,
        move_chain_between_racks = move_chain_between_racks,
        add_chain_to_rack = add_chain_to_rack,
        add_empty_chain_to_rack = add_empty_chain_to_rack,
        add_nested_rack_to_rack = add_nested_rack_to_rack,
        drawing = drawing,
        on_drop = callbacks.on_drop,  -- Pass through on_drop callback for rack swapping
    })
end

--- Draw selected chain column if rack is expanded
-- @param ctx ImGui context
-- @param rack_data table Data returned from draw_rack_panel {is_expanded, chains, rack_h}
-- @param rack_guid string GUID of the rack
local function draw_selected_chain_column_if_expanded(ctx, rack_data, rack_guid)
    local selected_chain_guid = state.expanded_nested_chains[rack_guid]
    if rack_data.is_expanded and selected_chain_guid then
        local selected_chain = nil
        for _, chain in ipairs(rack_data.chains) do
            local ok_guid, chain_guid = pcall(function() return chain:get_guid() end)
            if ok_guid and chain_guid and chain_guid == selected_chain_guid then
                selected_chain = chain
                break
            end
        end

        if selected_chain then
            ctx:same_line()
            draw_chain_column(ctx, selected_chain, rack_data.rack_h)
        end
    end
end

local function draw_device_chain(ctx, fx_list, avail_width, avail_height)
    device_chain.draw(ctx, fx_list, avail_width, avail_height, {
        state = state,
        get_fx_display_name = get_fx_display_name,
        refresh_fx_list = refresh_fx_list,
        add_plugin_by_name = add_plugin_by_name,
        add_rack_to_track = add_rack_to_track,
        get_device_main_fx = get_device_main_fx,
        get_device_utility = get_device_utility,
        is_device_container = is_device_container,
        is_rack_container = is_rack_container,
        is_utility_fx = is_utility_fx,
        chain_item = chain_item,
        icon_font = icon_font,
        draw_selected_chain_column_if_expanded = draw_selected_chain_column_if_expanded,
        draw_rack_panel = draw_rack_panel,
    })
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

    -- Load expansion state and display names for current track
    if state.track then
        state_module.load_expansion_state()
        state_module.load_display_names()
    end

    -- Create font reference tables so they can be updated by callbacks
    local default_font_ref = { value = default_font }
    local icon_font_ref = { value = icon_font }

    -- Create window callbacks
    local window_callbacks = main_window.create_callbacks({
        state = state,
        state_module = state_module,
        default_font = default_font,
        icon_font = icon_font,
        reaper_theme = reaper_theme,
        get_selected_track = get_selected_track,
        check_fx_changes = check_fx_changes,
        clear_multi_select = clear_multi_select,
        draw_toolbar = draw_toolbar,
        draw_plugin_browser = draw_plugin_browser,
        draw_device_chain = draw_device_chain,
        refresh_fx_list = refresh_fx_list,
        EmojImGui = EmojImGui,
        default_font_ref = default_font_ref,
        icon_font_ref = icon_font_ref,
    })

    Window.run({
        title = "SideFX",
        width = 1400,
        height = 800,
        dockable = true,
        on_close = window_callbacks.on_close,
        on_draw = window_callbacks.on_draw,
    })
end

main()
