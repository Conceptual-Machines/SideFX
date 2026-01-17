-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.2.0
-- @provides
--   [nomain] lib/*.lua
--   [nomain] lib/ui/*.lua
-- @depends ReaWrap>=0.8.1
-- @depends ReaImGui
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
local reawrap_reapack = scripts_folder .. "ReaWrap/lua/"
local sidefx_parent = script_path:match("^(.+[/\\])SideFX[/\\]")
local reawrap_dev = sidefx_parent and (sidefx_parent .. "ReaWrap/lua/") or ""

-- Force reload all lib modules during development
for name in pairs(package.loaded) do
    if name:match("^lib%.") then
        package.loaded[name] = nil
    end
end

-- NOW set up ReaWrap paths (these will shadow ReaImGui's imgui with ReaWrap's imgui)
package.path = script_path .. "?.lua;"
    .. script_path .. "lib/?.lua;"
    .. reawrap_dev .. "?.lua;"
    .. reawrap_dev .. "?/init.lua;"
    .. reawrap_reapack .. "?.lua;"
    .. reawrap_reapack .. "?/init.lua;"
    .. package.path

--------------------------------------------------------------------------------
-- Dependency Check
--------------------------------------------------------------------------------

local function check_dependencies()
    local missing = {}
    local has_reapack = r.ReaPack_BrowsePackages ~= nil

    -- Check ReaImGui extension
    if not r.ImGui_CreateContext then
        table.insert(missing, {
            name = "ReaImGui",
            desc = "ImGui bindings for REAPER UI",
            search = "ReaImGui",
            required = true
        })
    end

    -- Check ReaWrap
    local ok_reawrap = pcall(require, 'imgui')
    if not ok_reawrap then
        table.insert(missing, {
            name = "ReaWrap",
            desc = "OOP wrapper library",
            search = "ReaWrap",
            required = true
        })
    end

    -- Check RPP-Parser (for preset import/export)
    local rpp_parser_path = r.GetResourcePath() .. "/Scripts/ReaTeam Scripts/Development/RPP-Parser/Reateam_RPP-Parser.lua"
    local f = io.open(rpp_parser_path, "r")
    if f then
        f:close()
    else
        table.insert(missing, {
            name = "RPP-Parser",
            desc = "Required for preset import/export",
            search = "RPP-Parser",
            required = false
        })
    end

    -- Check JSFX files
    local jsfx_path = r.GetResourcePath() .. "/Effects/SideFX/"
    local jsfx_files = {
        "SideFX_Mixer.jsfx",
        "SideFX_Utility.jsfx",
        "SideFX_Modulator.jsfx"
    }
    for _, jsfx in ipairs(jsfx_files) do
        local jf = io.open(jsfx_path .. jsfx, "r")
        if jf then
            jf:close()
        else
            table.insert(missing, {
                name = jsfx,
                desc = "Should be in Effects/SideFX/",
                search = nil,  -- Not available via ReaPack
                required = true
            })
        end
    end

    -- Separate required vs optional
    local required_missing = {}
    local optional_missing = {}
    for _, dep in ipairs(missing) do
        if dep.required then
            table.insert(required_missing, dep)
        else
            table.insert(optional_missing, dep)
        end
    end

    -- Show dialog for missing dependencies
    if #required_missing > 0 or #optional_missing > 0 then
        local msg = "SideFX Dependency Check\n\n"

        if #required_missing > 0 then
            msg = msg .. "REQUIRED (script will not run without these):\n"
            for i, dep in ipairs(required_missing) do
                msg = msg .. "  " .. i .. ". " .. dep.name .. " - " .. dep.desc .. "\n"
            end
            msg = msg .. "\n"
        end

        if #optional_missing > 0 then
            msg = msg .. "OPTIONAL (some features may not work):\n"
            for i, dep in ipairs(optional_missing) do
                msg = msg .. "  " .. i .. ". " .. dep.name .. " - " .. dep.desc .. "\n"
            end
            msg = msg .. "\n"
        end

        if has_reapack then
            msg = msg .. "Click OK to open ReaPack and install missing packages."
        else
            msg = msg .. "Please install dependencies via Extensions > ReaPack > Browse packages"
        end

        -- Show message and optionally open ReaPack
        local result = r.ShowMessageBox(msg, "SideFX - Missing Dependencies", has_reapack and 1 or 0)

        if has_reapack and result == 1 then
            -- Open ReaPack for each missing dependency that has a search term
            for _, dep in ipairs(missing) do
                if dep.search then
                    r.ReaPack_BrowsePackages(dep.search)
                    break  -- Only open once, user can search for others
                end
            end
        end

        -- Block script if required dependencies are missing
        if #required_missing > 0 then
            return false
        end
    end

    return true
end

if not check_dependencies() then
    return  -- Exit script if dependencies are missing
end

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
package.loaded['lib.ui.common.drawing'] = nil  -- Force reload during dev
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
local icons = require('lib.ui.common.icons')

--------------------------------------------------------------------------------
-- Icons
--------------------------------------------------------------------------------

-- Initialize icons module with script path
icons.init(script_path)

local icon_size = 16
local default_font = nil

-- Font references (updated by main_window when fonts are loaded)
local default_font_ref = { value = nil }
local icon_font_ref = { value = nil }  -- Kept for API compatibility

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
            local is_container = fx:is_container()

            -- Check if it's a D-container (matches pattern)
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
            elseif is_container and not name:match("^R%d+") then
                -- Container that doesn't match D{n}: or R{n} pattern - might have been renamed
                -- Skip R-containers (racks) - they have their own naming scheme
                -- Check if it has a main FX inside (SideFX device structure)
                local main_fx = get_device_main_fx(fx)
                if main_fx then
                    -- This looks like a SideFX device that was renamed
                    device_idx = device_idx + 1
                    
                    -- Get original plugin name by temporarily clearing renamed_name
                    -- This gets the actual plugin identifier, not the renamed name
                    local ok_renamed, renamed_name = pcall(function() 
                        return main_fx:get_named_config_param("renamed_name") 
                    end)
                    
                    -- Clear renamed_name temporarily to get original plugin name
                    if ok_renamed and renamed_name and renamed_name ~= "" then
                        main_fx:set_named_config_param("renamed_name", "")
                    end
                    
                    local ok_plugin, plugin_name = pcall(function() return main_fx:get_name() end)
                    
                    -- Restore renamed_name if we cleared it
                    if ok_renamed and renamed_name and renamed_name ~= "" then
                        main_fx:set_named_config_param("renamed_name", renamed_name)
                    end
                    
                    if ok_plugin and plugin_name then
                        -- Get short name from original plugin identifier
                        local short_name = naming.get_short_plugin_name(plugin_name)
                        local new_container_name = naming.build_device_name(device_idx, short_name)
                        local new_fx_name = naming.build_device_fx_name(device_idx, short_name)
                        local new_util_name = naming.build_device_util_name(device_idx)
                        
                        -- Restore container name
                        fx:set_named_config_param("renamed_name", new_container_name)
                        
                        -- Restore FX name inside
                        main_fx:set_named_config_param("renamed_name", new_fx_name)
                        
                        -- Restore utility name inside
                        local utility = get_device_utility(fx)
                        if utility then
                            utility:set_named_config_param("renamed_name", new_util_name)
                        end
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
local function add_plugin_to_track(plugin, position, opts)
    opts = opts or {}
    local result = device_module.add_plugin_to_track(plugin, position, opts)
    if result then
        -- Auto-select the newly created standalone device
        local device_guid = result:get_guid()
        if device_guid then
            state_module.select_standalone_device(device_guid)
        end
        refresh_fx_list()
    end
    return result
end

local function add_plugin_by_name(plugin_name, position, opts)
    opts = opts or {}
    local plugin = { full_name = plugin_name, name = plugin_name }
    local result = device_module.add_plugin_to_track(plugin, position, opts)
    if result then
        -- Auto-select the newly created standalone device
        local device_guid = result:get_guid()
        if device_guid then
            state_module.select_standalone_device(device_guid)
        end
        refresh_fx_list()
    end
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

--------------------------------------------------------------------------------
-- UI: Plugin Browser
--------------------------------------------------------------------------------

local function draw_plugin_browser(ctx, icon_font_ref)
    browser_panel.draw(ctx, state, icon_font_ref.value, icon_size, add_plugin_to_track, filter_plugins)
end

--------------------------------------------------------------------------------
-- Device Utilities
--------------------------------------------------------------------------------

local function convert_device_to_rack(device)
    local result = container_module.convert_device_to_rack(device)
    if result then refresh_fx_list() end
    return result
end

local function convert_chain_to_devices(chain)
    local result = container_module.convert_chain_to_devices(chain)
    if result and #result > 0 then refresh_fx_list() end
    return result
end

--------------------------------------------------------------------------------
-- Scope/Spectrum Utilities (singleton analyzers)
--------------------------------------------------------------------------------

local SCOPE_JSFX_NAME = "SideFX_Oscilloscope"
local SPECTRUM_JSFX_NAME = "SideFX_Spectrum"
-- Patterns to match both "SideFX Oscilloscope" (desc) and "SideFX_Oscilloscope" (file)
local SCOPE_PATTERN = "SideFX[_ ]Oscilloscope"
local SPECTRUM_PATTERN = "SideFX[_ ]Spectrum"

--- Find scope/spectrum FX on track by name pattern
local function find_analyzer_fx(track, pattern)
    if not track then return nil end
    local fx_count = track:get_track_fx_count()
    for i = 0, fx_count - 1 do
        local ok, fx = pcall(function() return track:get_track_fx(i) end)
        if ok and fx then
            local ok_name, name = pcall(function() return fx:get_name() end)
            if ok_name and name and name:find(pattern) then
                return fx, i
            end
        end
    end
    return nil
end

--- Check if scope exists on current track
local function has_scope_on_track()
    return find_analyzer_fx(state.track, SCOPE_PATTERN) ~= nil
end

--- Check if spectrum exists on current track
local function has_spectrum_on_track()
    return find_analyzer_fx(state.track, SPECTRUM_PATTERN) ~= nil
end

--- Update analyzer state flags
local function update_analyzer_state()
    state.has_scope = find_analyzer_fx(state.track, SCOPE_PATTERN) ~= nil
    state.has_spectrum = find_analyzer_fx(state.track, SPECTRUM_PATTERN) ~= nil
end

--- Get track slot (0-15) for GMEM isolation
local function get_track_slot()
    if not state.track then return 0 end
    -- Use track index mod 16 as slot
    local track_idx = math.floor(state.track:get_info_value("IP_TRACKNUMBER"))
    return (track_idx - 1) % 16  -- 0-indexed, wrap to 0-15
end

--- Toggle oscilloscope on/off
local function toggle_scope()
    if not state.track then return end
    local existing_fx = find_analyzer_fx(state.track, SCOPE_PATTERN)
    if existing_fx then
        -- Remove it
        existing_fx:delete()
        state.has_scope = false
    else
        -- Add at end of chain (use file name for adding)
        local fx_idx = r.TrackFX_AddByName(state.track.pointer, "JS:" .. SCOPE_JSFX_NAME, false, -1)
        if fx_idx >= 0 then
            -- Set slot parameter (slider7, param index 6) to isolate GMEM
            local slot = get_track_slot()
            r.TrackFX_SetParamNormalized(state.track.pointer, fx_idx, 6, slot / 15)
        end
        state.has_scope = true
    end
    refresh_fx_list()
end

--- Toggle spectrum analyzer on/off
local function toggle_spectrum()
    if not state.track then return end
    local existing_fx = find_analyzer_fx(state.track, SPECTRUM_PATTERN)
    if existing_fx then
        -- Remove it
        existing_fx:delete()
        state.has_spectrum = false
    else
        -- Add at end of chain (use file name for adding)
        local fx_idx = r.TrackFX_AddByName(state.track.pointer, "JS:" .. SPECTRUM_JSFX_NAME, false, -1)
        if fx_idx >= 0 then
            -- Set slot parameter (slider7, param index 6) to isolate GMEM
            local slot = get_track_slot()
            r.TrackFX_SetParamNormalized(state.track.pointer, fx_idx, 6, slot / 15)
        end
        state.has_spectrum = true
    end
    refresh_fx_list()
end

--------------------------------------------------------------------------------
-- UI: FX Context Menu
--------------------------------------------------------------------------------

local function draw_fx_context_menu(ctx, fx, guid, i, enabled, is_container, depth)
    fx_menu.draw_with_sidefx_callbacks(ctx, fx, guid, i, enabled, is_container, depth, get_fx_display_name, {
        state = state,
        collapse_from_depth = collapse_from_depth,
        refresh_fx_list = refresh_fx_list,
        add_to_new_container = add_to_new_container,
        convert_to_rack = convert_device_to_rack,
        convert_to_devices = convert_chain_to_devices,
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
        icon_font = icon_font_ref.value,
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

-- Settings and Preset dialogs
local settings_dialog = require('lib.ui.settings.settings_dialog')
local preset_dialog = require('lib.ui.presets.preset_dialog')
local mod_matrix = require('lib.ui.modulator.mod_matrix')
local presets_mod = require('lib.utils.presets')

local function draw_toolbar(ctx, icon_font_ref)
    toolbar.draw(ctx, state, icon_font_ref.value, icon_size, get_fx_display_name, {
        on_refresh_sidefx = function()
            -- Ensure callback is set before refreshing
            state_module.on_refresh = renumber_device_chain
            refresh_fx_list()
        end,
        on_refresh = function()
            refresh_fx_list()
            browser_module.rescan_plugins()
        end,
        on_add_rack = add_rack_to_track,
        on_add_fx = function() end,  -- TODO: Implement
        on_collapse_from_depth = collapse_from_depth,
        on_config = function() settings_dialog.open(ctx) end,
        on_preset = function() preset_dialog.open(ctx) end,
        on_toggle_scope = toggle_scope,
        on_toggle_spectrum = toggle_spectrum,
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

-- Forward declaration for mutual recursion
local draw_chain_column

-- Draw the rack panel (main rack UI without chain column)
-- NOTE: Must be defined BEFORE draw_chain_column which references it
local function draw_rack_panel(ctx, rack, avail_height, is_nested, callbacks)
    callbacks = callbacks or {}
    return rack_panel_main.draw(ctx, rack, avail_height, is_nested, {
        state = state,
        icon_font = icon_font_ref.value,
        state_module = state_module,
        refresh_fx_list = refresh_fx_list,
        get_rack_mixer = get_rack_mixer,
        draw_pan_slider = draw_pan_slider,
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

-- Draw expanded chain column with devices
-- NOTE: Uses draw_rack_panel for nested racks inside chains
draw_chain_column = function(ctx, selected_chain, rack_h)
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
        icon_font = icon_font_ref.value,
        default_font = default_font_ref.value,
        on_mod_matrix = function(device, device_name) mod_matrix.open(device, device_name) end,
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

local function draw_device_chain(ctx, fx_list, avail_width, avail_height, icon_font_ref, header_font_ref)
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
        icon_font = icon_font_ref and icon_font_ref.value or nil,
        header_font = header_font_ref and header_font_ref.value or nil,
        draw_selected_chain_column_if_expanded = draw_selected_chain_column_if_expanded,
        draw_rack_panel = draw_rack_panel,
        on_mod_matrix = function(device, device_name) mod_matrix.open(device, device_name) end,
    })
end

-- Default analyzer panel sizes (can be adjusted via state)
local DEFAULT_ANALYZER_W = 600
local DEFAULT_ANALYZER_H = 200

--- Draw analyzer visualizations (scope/spectrum) at end of chain
--- Draw scope controls (shared between inline and popout) - single row
-- @param suffix string Optional suffix for widget IDs (e.g., "_pop" for popout)
local function draw_scope_controls(ctx, scope_fx, analyzer_w, suffix)
    suffix = suffix or ""
    local ch_w = 50  -- Smaller width for channel selector
    local ctrl_w = (analyzer_w - 20 - ch_w) / 4  -- 4 main controls + smaller channel

    -- Time window slider (param 0) - 1-500 ms
    ctx:push_item_width(ctrl_w)
    local time_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 0)
    local time_ms = 1 + time_val * 499
    local changed, new_time = r.ImGui_SliderDouble(ctx.ctx, "##scope_time" .. suffix, time_ms, 1, 500, "%.0fms")
    if changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 0, (new_time - 1) / 499)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Time window") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Gain slider (param 1) - -24 to +24 dB
    ctx:push_item_width(ctrl_w)
    local gain_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 1)
    local gain_db = -24 + gain_val * 48
    local gain_changed, new_gain = r.ImGui_SliderDouble(ctx.ctx, "##scope_gain" .. suffix, gain_db, -24, 24, "%.0fdB")
    if gain_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 1, (new_gain + 24) / 48)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Gain") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Trigger mode combo (param 2)
    ctx:push_item_width(ctrl_w)
    local trig_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 2)
    local trig_mode = math.floor(trig_val * 2 + 0.5)
    local trig_changed, new_trig = r.ImGui_Combo(ctx.ctx, "##scope_trig" .. suffix, trig_mode, "Auto\0Rise\0Fall\0")
    if trig_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 2, new_trig / 2)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Trigger mode") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Trigger level slider (param 3) - -1 to +1
    ctx:push_item_width(ctrl_w)
    local level_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 3)
    local level = -1 + level_val * 2
    local level_changed, new_level = r.ImGui_SliderDouble(ctx.ctx, "##scope_level" .. suffix, level, -1, 1, "%.2f")
    if level_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 3, (new_level + 1) / 2)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Trigger level") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Channel combo (param 4) - smaller
    ctx:push_item_width(ch_w)
    local ch_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 4)
    local ch_mode = math.floor(ch_val * 2 + 0.5)
    local ch_changed, new_ch = r.ImGui_Combo(ctx.ctx, "##scope_ch" .. suffix, ch_mode, "St\0L\0R\0")
    if ch_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 4, new_ch / 2)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Channel") end
    ctx:pop_item_width()
end

--- Draw spectrum controls (shared between inline and popout) - single row
-- @param suffix string Optional suffix for widget IDs (e.g., "_pop" for popout)
local function draw_spectrum_controls(ctx, spectrum_fx, analyzer_w, suffix)
    suffix = suffix or ""
    local ch_w = 50  -- Smaller width for channel selector
    local ctrl_w = (analyzer_w - 20 - ch_w) / 4  -- 4 main controls + smaller channel

    -- FFT size combo (param 0) - 0-8 maps to 64-16384
    ctx:push_item_width(ctrl_w)
    local fft_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 0)
    local fft_idx = math.floor(fft_val * 8 + 0.5)
    local n = "\x00"
    local fft_options = "64"..n.."128"..n.."256"..n.."512"..n.."1k"..n.."2k"..n.."4k"..n.."8k"..n.."16k"..n..n
    local fft_changed, new_fft = r.ImGui_Combo(ctx.ctx, "##spec_fft" .. suffix, fft_idx, fft_options)
    if fft_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 0, new_fft / 8)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("FFT size") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Floor dB slider (param 1) - -90 to -12 dB
    ctx:push_item_width(ctrl_w)
    local floor_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 1)
    local floor_db = -90 + floor_val * 78
    local floor_changed, new_floor = r.ImGui_SliderDouble(ctx.ctx, "##spec_floor" .. suffix, floor_db, -90, -12, "%.0fdB")
    if floor_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 1, (new_floor + 90) / 78)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Floor level") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Smoothing slider (param 2) - 0 to 0.95
    ctx:push_item_width(ctrl_w)
    local smooth_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 2)
    local smooth = smooth_val * 0.95
    local smooth_changed, new_smooth = r.ImGui_SliderDouble(ctx.ctx, "##spec_smooth" .. suffix, smooth * 100, 0, 95, "%.0f%%")
    if smooth_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 2, new_smooth / 100 / 0.95)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Smoothing") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Slope slider (param 3) - 0 to 12 dB/oct
    ctx:push_item_width(ctrl_w)
    local slope_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 3)
    local slope = slope_val * 12
    local slope_changed, new_slope = r.ImGui_SliderDouble(ctx.ctx, "##spec_slope" .. suffix, slope, 0, 12, "%.0f/oct")
    if slope_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 3, new_slope / 12)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Slope (high freq boost)") end
    ctx:pop_item_width()

    ctx:same_line()

    -- Channel combo (param 4) - smaller
    ctx:push_item_width(ch_w)
    local ch_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 4)
    local ch_mode = math.floor(ch_val * 2 + 0.5)
    local ch_changed, new_ch = r.ImGui_Combo(ctx.ctx, "##spec_ch" .. suffix, ch_mode, "St\0L\0R\0")
    if ch_changed then
        r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 4, new_ch / 2)
    end
    if ctx:is_item_hovered() then ctx:set_tooltip("Channel") end
    ctx:pop_item_width()
end

--- Draw analyzer popout windows (called from main render)
local function draw_analyzer_popouts(ctx)
    local drawing = require('lib.ui.common.drawing')
    local imgui = require('imgui')

    if not state.track then return end

    -- Connect to JSFX GMEM namespace
    r.gmem_attach("SideFX")

    local slot = get_track_slot()

    -- Scope popout window
    if state.scope_popout and state.has_scope then
        local scope_fx = find_analyzer_fx(state.track, SCOPE_PATTERN)

        ctx:set_next_window_size(650, 400, imgui.Cond.FirstUseEver())
        local window_flags = 0
        local visible, open = ctx:begin_window("Oscilloscope##popout", true, window_flags)
        if visible then
            -- Header with controls
            if scope_fx then
                -- Freeze toggle
                local freeze_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 5)
                local is_frozen = freeze_val > 0.5
                ctx:push_style_color(imgui.Col.Button(), is_frozen and 0x4488FFFF or 0x444444FF)
                if ctx:button(is_frozen and "||" or ">", 24, 20) then
                    r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 5, is_frozen and 0 or 1)
                end
                ctx:pop_style_color()
                if ctx:is_item_hovered() then ctx:set_tooltip(is_frozen and "Unfreeze" or "Freeze") end
            end

            -- Visualization - use available space
            local avail_w, avail_h = ctx:get_content_region_avail()
            local viz_h = avail_h - 60  -- Leave room for controls
            local is_enabled = scope_fx and r.TrackFX_GetEnabled(state.track.pointer, scope_fx.pointer)
            local scope_pop_hovered = drawing.draw_oscilloscope(ctx, "##scope_popout_viz", avail_w, viz_h, slot, is_enabled)
            if scope_pop_hovered and is_enabled then
                ctx:set_tooltip("Oscilloscope - Stereo waveform display\nL (green) / R (magenta)\nLogarithmic dB scale")
            end

            -- Controls
            if scope_fx then
                draw_scope_controls(ctx, scope_fx, avail_w, "_pop")
            end

            ctx:end_window()
        end
        if not open then
            state.scope_popout = false
        end
    end

    -- Spectrum popout window
    if state.spectrum_popout and state.has_spectrum then
        local spectrum_fx = find_analyzer_fx(state.track, SPECTRUM_PATTERN)

        ctx:set_next_window_size(650, 400, imgui.Cond.FirstUseEver())
        local window_flags = 0
        local visible, open = ctx:begin_window("Spectrum Analyzer##popout", true, window_flags)
        if visible then
            -- Header with controls
            if spectrum_fx then
                -- Freeze toggle
                local freeze_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 5)
                local is_frozen = freeze_val > 0.5
                ctx:push_style_color(imgui.Col.Button(), is_frozen and 0x4488FFFF or 0x444444FF)
                if ctx:button(is_frozen and "||" or ">", 24, 20) then
                    r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 5, is_frozen and 0 or 1)
                end
                ctx:pop_style_color()
                if ctx:is_item_hovered() then ctx:set_tooltip(is_frozen and "Unfreeze" or "Freeze") end
            end

            -- Visualization - use available space
            local avail_w, avail_h = ctx:get_content_region_avail()
            local viz_h = avail_h - 60  -- Leave room for controls
            local is_enabled = spectrum_fx and r.TrackFX_GetEnabled(state.track.pointer, spectrum_fx.pointer)
            local spectrum_pop_hovered = drawing.draw_spectrum(ctx, "##spectrum_popout_viz", avail_w, viz_h, slot, is_enabled)
            if spectrum_pop_hovered and is_enabled then
                ctx:set_tooltip("Spectrum Analyzer - Frequency response\nLogarithmic frequency scale (20Hz-20kHz)\nClick/drag: Adjust floor dB")
            end

            -- Controls
            if spectrum_fx then
                draw_spectrum_controls(ctx, spectrum_fx, avail_w, "_pop")
            end

            ctx:end_window()
        end
        if not open then
            state.spectrum_popout = false
        end
    end
end

local function draw_analyzers(ctx, avail_height)
    local drawing = require('lib.ui.common.drawing')
    local imgui = require('imgui')

    -- Draw popout windows first (always, even if inline panels are hidden)
    draw_analyzer_popouts(ctx)

    local has_any = state.has_scope or state.has_spectrum
    if not has_any then return end

    -- Check if any inline panels should be shown
    local show_inline_scope = state.has_scope and not state.scope_popout
    local show_inline_spectrum = state.has_spectrum and not state.spectrum_popout
    if not show_inline_scope and not show_inline_spectrum then return end

    -- Connect to JSFX GMEM namespace (required to read GMEM data)
    r.gmem_attach("SideFX")

    ctx:same_line()

    -- Get sizes from state or use defaults
    local analyzer_w = state.analyzer_width or DEFAULT_ANALYZER_W
    local controls_h = 26  -- Single row of controls
    local header_h = 26
    local padding = 16
    local analyzer_h = avail_height - controls_h - header_h - padding
    local panel_h = avail_height - 4

    -- Get current track slot for GMEM isolation
    local slot = get_track_slot()

    -- Draw scope if active and not popped out
    -- Params: 0=Time, 1=Gain, 2=TrigMode, 3=TrigLevel, 4=Channel, 5=Freeze, 6=Slot
    if show_inline_scope then
        local scope_fx = find_analyzer_fx(state.track, SCOPE_PATTERN)
        local is_collapsed = state.scope_collapsed or false

        ctx:push_style_color(imgui.Col.ChildBg(), 0x1A1A1AFF)
        local no_scroll = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
        local scope_w = is_collapsed and 50 or (analyzer_w + 12)

        if ctx:begin_child("scope_panel", scope_w, panel_h, imgui.ChildFlags.Border(), no_scroll) then
            if is_collapsed then
                -- Collapsed view: vertical strip with buttons
                ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
                if ctx:button("▶##expand_scope", 20, 20) then
                    state.scope_collapsed = false
                end
                ctx:pop_style_color(2)
                if ctx:is_item_hovered() then ctx:set_tooltip("Expand Scope") end

                ctx:spacing()

                -- Popout button
                if icons.button_bordered(ctx, "popout_scope_c", icons.Names.popout, 18) then
                    state.scope_popout = true
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Open in separate window") end

                ctx:spacing()

                -- ON/OFF button
                if scope_fx then
                    local enabled = r.TrackFX_GetEnabled(state.track.pointer, scope_fx.pointer)
                    local on_tint = enabled and 0x88FF88FF or 0x888888FF
                    if icons.button_bordered(ctx, "on_scope_c", icons.Names.on, 18, on_tint) then
                        r.TrackFX_SetEnabled(state.track.pointer, scope_fx.pointer, not enabled)
                    end
                    if ctx:is_item_hovered() then ctx:set_tooltip(enabled and "Bypass" or "Enable") end
                end

                ctx:spacing()

                -- Delete button
                if icons.button_bordered(ctx, "del_scope_c", icons.Names.cancel, 18, 0xFF6666FF) then
                    toggle_scope()
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Remove") end

                ctx:spacing()
                ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                ctx:text("Sco")
                ctx:pop_style_color()
            else
                -- Expanded view
                -- Header background
                local hdr_x, hdr_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                r.ImGui_DrawList_AddRectFilled(draw_list, hdr_x - 4, hdr_y - 4, hdr_x + analyzer_w + 8, hdr_y + 20, 0x252525FF, 0)

                -- Collapse button
                ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
                if ctx:button("▼##collapse_scope", 20, 20) then
                    state.scope_collapsed = true
                end
                ctx:pop_style_color(2)
                if ctx:is_item_hovered() then ctx:set_tooltip("Collapse") end

                ctx:same_line()

                -- Header row with icon, title, and controls
                icons.image(ctx, icons.Names.oscilloscope, 14)
                ctx:same_line()
                ctx:text("Scope")

                if scope_fx then
                    -- Freeze toggle (param 5)
                    ctx:same_line()
                    local freeze_val = r.TrackFX_GetParamNormalized(state.track.pointer, scope_fx.pointer, 5)
                    local is_frozen = freeze_val > 0.5
                    local freeze_tint = is_frozen and 0x4488FFFF or 0xCCCCCCFF
                    if icons.button(ctx, "freeze_scope", icons.Names.pause, 16, freeze_tint) then
                        r.TrackFX_SetParamNormalized(state.track.pointer, scope_fx.pointer, 5, is_frozen and 0 or 1)
                    end
                    if ctx:is_item_hovered() then ctx:set_tooltip(is_frozen and "Unfreeze" or "Freeze") end
                end

                -- Popout button
                ctx:same_line(analyzer_w - 56)
                if icons.button(ctx, "popout_scope", icons.Names.popout, 16) then
                    state.scope_popout = true
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Open in separate window") end

                -- ON/OFF button
                ctx:same_line()
                if scope_fx then
                    local enabled = r.TrackFX_GetEnabled(state.track.pointer, scope_fx.pointer)
                    local on_tint = enabled and 0x88FF88FF or 0x888888FF
                    if icons.button(ctx, "on_scope", icons.Names.on, 16, on_tint) then
                        r.TrackFX_SetEnabled(state.track.pointer, scope_fx.pointer, not enabled)
                    end
                    if ctx:is_item_hovered() then ctx:set_tooltip(enabled and "Bypass" or "Enable") end
                end

                ctx:same_line()
                if icons.button(ctx, "del_scope", icons.Names.cancel, 16, 0xFF6666FF) then
                    toggle_scope()
                end

                -- Spacing after header
                ctx:dummy(0, 4)

                -- Visualization
                local is_enabled = scope_fx and r.TrackFX_GetEnabled(state.track.pointer, scope_fx.pointer)
                local scope_hovered = drawing.draw_oscilloscope(ctx, "##scope_viz", analyzer_w, analyzer_h, slot, is_enabled)
                if scope_hovered and is_enabled then
                    ctx:set_tooltip("Oscilloscope - Stereo waveform display\nL (green) / R (magenta)\nLogarithmic dB scale")
                end

                -- Controls
                if scope_fx then
                    draw_scope_controls(ctx, scope_fx, analyzer_w)
                end
            end

            ctx:end_child()
        end
        ctx:pop_style_color()
        ctx:same_line()
    end

    -- Draw spectrum if active and not popped out
    -- Params: 0=FFTSize, 1=Floor, 2=Smoothing, 3=Slope, 4=Channel, 5=Freeze, 6=Slot
    if show_inline_spectrum then
        local spectrum_fx = find_analyzer_fx(state.track, SPECTRUM_PATTERN)
        local is_collapsed = state.spectrum_collapsed or false

        ctx:push_style_color(imgui.Col.ChildBg(), 0x1A1A1AFF)
        local no_scroll = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
        local spectrum_w = is_collapsed and 50 or (analyzer_w + 12)

        if ctx:begin_child("spectrum_panel", spectrum_w, panel_h, imgui.ChildFlags.Border(), no_scroll) then
            if is_collapsed then
                -- Collapsed view: vertical strip with buttons
                ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
                if ctx:button("▶##expand_spectrum", 20, 20) then
                    state.spectrum_collapsed = false
                end
                ctx:pop_style_color(2)
                if ctx:is_item_hovered() then ctx:set_tooltip("Expand Spectrum") end

                ctx:spacing()

                -- Popout button
                if icons.button_bordered(ctx, "popout_spectrum_c", icons.Names.popout, 18) then
                    state.spectrum_popout = true
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Open in separate window") end

                ctx:spacing()

                -- ON/OFF button
                if spectrum_fx then
                    local enabled = r.TrackFX_GetEnabled(state.track.pointer, spectrum_fx.pointer)
                    local on_tint = enabled and 0x88FF88FF or 0x888888FF
                    if icons.button_bordered(ctx, "on_spectrum_c", icons.Names.on, 18, on_tint) then
                        r.TrackFX_SetEnabled(state.track.pointer, spectrum_fx.pointer, not enabled)
                    end
                    if ctx:is_item_hovered() then ctx:set_tooltip(enabled and "Bypass" or "Enable") end
                end

                ctx:spacing()

                -- Delete button
                if icons.button_bordered(ctx, "del_spectrum_c", icons.Names.cancel, 18, 0xFF6666FF) then
                    toggle_spectrum()
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Remove") end

                ctx:spacing()
                ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                ctx:text("Spe")
                ctx:pop_style_color()
            else
                -- Expanded view
                -- Header background
                local hdr_x, hdr_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                r.ImGui_DrawList_AddRectFilled(draw_list, hdr_x - 4, hdr_y - 4, hdr_x + analyzer_w + 8, hdr_y + 20, 0x252525FF, 0)

                -- Collapse button
                ctx:push_style_color(r.ImGui_Col_Button(), 0x00000000)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444488)
                if ctx:button("▼##collapse_spectrum", 20, 20) then
                    state.spectrum_collapsed = true
                end
                ctx:pop_style_color(2)
                if ctx:is_item_hovered() then ctx:set_tooltip("Collapse") end

                ctx:same_line()

                -- Header row with icon, title, and controls
                icons.image(ctx, icons.Names.spectrum, 14)
                ctx:same_line()
                ctx:text("Spectrum")

                if spectrum_fx then
                    -- Freeze toggle (param 5)
                    ctx:same_line()
                    local freeze_val = r.TrackFX_GetParamNormalized(state.track.pointer, spectrum_fx.pointer, 5)
                    local is_frozen = freeze_val > 0.5
                    local freeze_tint = is_frozen and 0x4488FFFF or 0xCCCCCCFF
                    if icons.button(ctx, "freeze_spectrum", icons.Names.pause, 16, freeze_tint) then
                        r.TrackFX_SetParamNormalized(state.track.pointer, spectrum_fx.pointer, 5, is_frozen and 0 or 1)
                    end
                    if ctx:is_item_hovered() then ctx:set_tooltip(is_frozen and "Unfreeze" or "Freeze") end
                end

                -- Popout button
                ctx:same_line(analyzer_w - 56)
                if icons.button(ctx, "popout_spectrum", icons.Names.popout, 16) then
                    state.spectrum_popout = true
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Open in separate window") end

                -- ON/OFF button
                ctx:same_line()
                if spectrum_fx then
                    local enabled = r.TrackFX_GetEnabled(state.track.pointer, spectrum_fx.pointer)
                    local on_tint = enabled and 0x88FF88FF or 0x888888FF
                    if icons.button(ctx, "on_spectrum", icons.Names.on, 16, on_tint) then
                        r.TrackFX_SetEnabled(state.track.pointer, spectrum_fx.pointer, not enabled)
                    end
                    if ctx:is_item_hovered() then ctx:set_tooltip(enabled and "Bypass" or "Enable") end
                end

                ctx:same_line()
                if icons.button(ctx, "del_spectrum", icons.Names.cancel, 16, 0xFF6666FF) then
                    toggle_spectrum()
                end

                -- Spacing after header
                ctx:dummy(0, 4)

                -- Visualization
                local is_enabled = spectrum_fx and r.TrackFX_GetEnabled(state.track.pointer, spectrum_fx.pointer)
                local spectrum_hovered = drawing.draw_spectrum(ctx, "##spectrum_viz", analyzer_w, analyzer_h, slot, is_enabled)
                if spectrum_hovered and is_enabled then
                    ctx:set_tooltip("Spectrum Analyzer - Frequency response\nLogarithmic frequency scale (20Hz-20kHz)\nClick/drag: Adjust floor dB")
                end

                -- Controls
                if spectrum_fx then
                    draw_spectrum_controls(ctx, spectrum_fx, analyzer_w)
                end
            end

            ctx:end_child()
        end
        ctx:pop_style_color()
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
    update_analyzer_state()
    scan_plugins()
    
    -- Initialize presets module
    presets_mod.init()
    presets_mod.ensure_folder()
    
    -- Load user configuration (global, not per-track)
    state_module.load_config()

    -- Load parameter selections (global, not per-track)
    state_module.load_param_selections()

    -- Load parameter unit overrides (global, not per-track)
    state_module.load_param_unit_overrides()

    -- Load expansion state, display names, link scales, and mod slots for current track
    if state.track then
        state_module.load_expansion_state()
        state_module.load_display_names()
        state_module.load_link_scales()
        state_module.load_expanded_mod_slots()
        state_module.load_mod_sidebar_collapsed()
        state_module.load_device_collapsed_states()
    end

    -- Initialize module-level font references (will be updated by main_window when fonts load)
    default_font_ref.value = default_font

    -- Create window callbacks
    local window_callbacks = main_window.create_callbacks({
        state = state,
        state_module = state_module,
        device_module = device_module,
        default_font = default_font,
        reaper_theme = reaper_theme,
        get_selected_track = get_selected_track,
        check_fx_changes = check_fx_changes,
        clear_multi_select = clear_multi_select,
        update_analyzer_state = update_analyzer_state,
        draw_toolbar = draw_toolbar,
        draw_plugin_browser = draw_plugin_browser,
        draw_device_chain = draw_device_chain,
        draw_analyzers = draw_analyzers,
        refresh_fx_list = refresh_fx_list,
        icons = icons,
        default_font_ref = default_font_ref,
        icon_font_ref = icon_font_ref,
        settings_dialog = settings_dialog,
        preset_dialog = preset_dialog,
        mod_matrix = mod_matrix,
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
