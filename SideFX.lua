-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.1.0
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
--   v0.5.0 - Horizontal Device Chain UI
--     + New Ableton-style horizontal device layout
--     + Device panels with expand/collapse parameters
--     + Rack containers with stacked chains
--     + Donation link added
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

-- SideFX modules
local naming = require('lib.naming')
local fx_utils = require('lib.fx_utils')
local state_module = require('lib.state')
local rack_module = require('lib.rack')
local device_module = require('lib.device')
local container_module = require('lib.container')
local modulator_module = require('lib.modulator')
local browser_module = require('lib.browser')
local constants = require('lib.constants')

-- UI modules
local widgets = require('lib.ui.widgets')
local browser_panel = require('lib.ui.browser_panel')
local fx_menu = require('lib.ui.fx_menu')
local fx_detail_panel = require('lib.ui.fx_detail_panel')
local modulator_panel = require('lib.ui.modulator_panel')
local toolbar = require('lib.ui.toolbar')
local drag_drop = require('lib.ui.drag_drop')
local rack_ui = require('lib.ui.rack_ui')

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
-- R-Container (Rack) Functions (from lib/rack.lua)
--------------------------------------------------------------------------------

-- Use rack module functions
local get_rack_mixer = fx_utils.get_rack_mixer

-- Use widgets module for pan slider and fader
local draw_pan_slider = widgets.draw_pan_slider
local draw_fader = widgets.draw_fader

-- Rack operations (uses state singleton via rack_module)
local function add_rack_to_track(position)
    local rack = rack_module.add_rack_to_track(position)
    if rack then
        -- Use expanded_racks for top-level racks (consistent with nested racks)
        state.expanded_racks[rack:get_guid()] = true
        refresh_fx_list()
    end
    return rack
end

local function add_chain_to_rack(rack, plugin)
    -- Get rack info before adding chain (while reference is still valid)
    local rack_guid = rack:get_guid()
    local rack_parent = rack:get_parent_container()
    local is_nested = (rack_parent ~= nil)
    
    local chain = rack_module.add_chain_to_rack(rack, plugin)
    if chain then
        -- Get chain GUID (stable identifier)
        local chain_guid = chain:get_guid()
        if chain_guid then
            -- Force the chain to be expanded/selected so user can see it
            if rack_guid then
                -- Ensure rack is expanded (works for both top-level and nested)
                state.expanded_racks[rack_guid] = true
                -- Track which chain is selected (works for both top-level and nested)
                state.expanded_nested_chains[rack_guid] = chain_guid
            end
            state_module.save_expansion_state()
        end
        refresh_fx_list()
    end
    return chain
end

local function add_nested_rack_to_rack(parent_rack)
    -- Get parent rack info before adding nested rack
    local parent_rack_guid = parent_rack:get_guid()
    local parent_rack_parent = parent_rack:get_parent_container()
    local is_parent_nested = (parent_rack_parent ~= nil)
    
    local nested_rack = rack_module.add_nested_rack_to_rack(parent_rack)
    if nested_rack then
        -- Get nested rack GUID (stable identifier)
        local nested_rack_guid = nested_rack:get_guid()
        if nested_rack_guid then
            -- Find the chain that contains this nested rack
            local chain_container = nested_rack:get_parent_container()
            local chain_guid = chain_container and chain_container:get_guid()
            
            -- Force the nested rack to be expanded so user can see it
            state.expanded_racks[nested_rack_guid] = true
            
            -- Also select the chain that contains the nested rack
            if chain_guid then
                if parent_rack_guid then
                    -- Ensure parent rack is expanded (works for both top-level and nested)
                    state.expanded_racks[parent_rack_guid] = true
                    -- Track which chain is selected (works for both top-level and nested)
                    state.expanded_nested_chains[parent_rack_guid] = chain_guid
                end
            end
            state_module.save_expansion_state()
        end
        refresh_fx_list()
    end
    return nested_rack
end

local function add_device_to_chain(chain, plugin)
    -- Get chain GUID before adding device (GUIDs are stable)
    local chain_guid = chain:get_guid()
    if not chain_guid then
        return nil
    end
    
    -- Determine expansion state BEFORE adding device (while chain reference is still valid)
    local parent_rack = chain:get_parent_container()
    local is_nested = false
    local rack_guid = nil
    if parent_rack then
        rack_guid = parent_rack:get_guid()
        local rack_parent = parent_rack:get_parent_container()
        is_nested = (rack_parent ~= nil)
    end
    
    local device = rack_module.add_device_to_chain(chain, plugin)
    if device then
        -- Force the chain to be expanded/selected so user can see the device that was just added
        if rack_guid then
            -- Ensure rack is expanded (works for both top-level and nested)
            state.expanded_racks[rack_guid] = true
            -- Track which chain is selected (works for both top-level and nested)
            state.expanded_nested_chains[rack_guid] = chain_guid
        end
        state_module.save_expansion_state()
        refresh_fx_list()
    end
    return device
end

local function add_rack_to_chain(chain)
    local rack = rack_module.add_rack_to_chain(chain)
    if rack then refresh_fx_list() end
    return rack
end

local function reorder_chain_in_rack(rack, chain_guid, target_chain_guid)
    local result = rack_module.reorder_chain_in_rack(rack, chain_guid, target_chain_guid)
    if result then refresh_fx_list() end
    return result
end

local renumber_chains_in_rack = rack_module.renumber_chains_in_rack

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
    fx_menu.draw(ctx, fx, guid, "fxmenu" .. i, enabled, is_container, depth, get_fx_display_name, {
        on_open_fx = function(fx) fx:show(3) end,
        on_toggle_enabled = function(fx) fx:set_enabled(not fx:get_enabled()) end,
        on_rename = function(guid, display_name)
            state.renaming_fx = guid
            state.rename_text = display_name
        end,
        on_remove_from_container = function(fx, depth)
                fx:move_out_of_container()
                collapse_from_depth(depth)
                refresh_fx_list()
        end,
        on_dissolve_container = function(fx, depth)
                dissolve_container(fx)
                collapse_from_depth(depth)
                refresh_fx_list()
        end,
        on_delete = function(fx, depth)
            fx:delete()
            collapse_from_depth(depth)
            refresh_fx_list()
        end,
        on_add_to_container = function(fx_list)
            add_to_new_container(fx_list)
        end,
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
                                move_fx_to_track_level(guid)
                                    refresh_fx_list()
                                end
                        elseif parent_container_guid and fx_parent_guid ~= parent_container_guid then
                            -- Move into this column's container
                            move_fx_to_container(guid, parent_container_guid)
                            refresh_fx_list()
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
            if icon_font then ctx:push_font(icon_font, icon_size) end
            local icon = is_container
                and (is_expanded and icon_text(Icons.folder_open) or icon_text(Icons.folder_closed))
                or icon_text(Icons.plug)
            ctx:text(icon)
            if icon_font then ctx:pop_font() end

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
                    -- Store custom display name in state (SideFX-only, doesn't change REAPER name)
                    state.display_names[guid] = state.rename_text
                    state_module.save_display_names()
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Check if item was deactivated after edit (clicked away)
                if ctx:is_item_deactivated_after_edit() then
                    if state.rename_text ~= "" then
                    -- Store custom display name in state (SideFX-only, doesn't change REAPER name)
                    state.display_names[guid] = state.rename_text
                    state_module.save_display_names()
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Cancel on Escape
                if ctx:is_key_pressed(imgui.Key.Escape()) then
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

            -- Drop target for reordering and container drops
            handle_fx_drop_target(ctx, fx, guid, is_container)

            -- Right-click context menu
            draw_fx_context_menu(ctx, fx, guid, i, enabled, is_container, depth)

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
    fx_detail_panel.draw(ctx, width, state.selected_fx, function(guid)
        return state.track and state.track:find_fx_by_guid(guid) or nil
    end, get_fx_display_name)
end

--------------------------------------------------------------------------------
-- Modulators
--------------------------------------------------------------------------------

-- Modulator operations (uses modulator_module)
-- Pure forwards
local find_modulators_on_track = modulator_module.find_modulators_on_track
local get_linkable_fx = modulator_module.get_linkable_fx
local create_param_link = modulator_module.create_param_link
local remove_param_link = modulator_module.remove_param_link
local get_modulator_links = modulator_module.get_modulator_links

-- Wrappers that refresh UI
local function add_modulator()
    local fx = modulator_module.add_modulator()
    if fx then refresh_fx_list() end
    return fx
end

local function delete_modulator(fx_idx)
    modulator_module.delete_modulator(fx_idx)
    refresh_fx_list()
end

-- Use fx_utils module for is_modulator_fx
local is_modulator_fx = fx_utils.is_modulator_fx

local function draw_modulator_column(ctx, width)
    modulator_panel.draw(ctx, width, state, {
        find_modulators_on_track = find_modulators_on_track,
        get_linkable_fx = get_linkable_fx,
        get_modulator_links = get_modulator_links,
        create_param_link = create_param_link,
        remove_param_link = remove_param_link,
        add_modulator = add_modulator,
        delete_modulator = delete_modulator,
    })
end

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
-- Rack Drawing Helpers (extracted from draw_device_chain)
--------------------------------------------------------------------------------

-- draw_chain_row moved to rack_ui module

-- Draw expanded chain column with devices
local function draw_chain_column(ctx, selected_chain, rack_h)
    local selected_chain_guid = selected_chain:get_guid()
    -- Get chain name and identifier separately
    local chain_name = fx_utils.get_chain_label_name(selected_chain)
    local chain_id = nil
    local ok_name, raw_name = pcall(function() return selected_chain:get_name() end)
    if ok_name and raw_name then
        chain_id = raw_name:match("^(R%d+_C%d+)") or raw_name:match("R%d+_C%d+")
    end

    -- Get devices from chain
    local devices = {}
    for child in selected_chain:iter_container_children() do
        local ok, child_name = pcall(function() return child:get_name() end)
        if ok and child_name then
            table.insert(devices, child)
        end
    end

    local chain_content_h = rack_h - 30  -- Leave room for header
    local has_plugin_payload = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_rack_payload = ctx:get_drag_drop_payload("RACK_ADD")

    -- Auto-resize wrapper to fit content (Border=1, AutoResizeX=16)
    local wrapper_flags = 17  -- Border + AutoResizeX

    -- Add padding around content, especially on the right
    ctx:push_style_var(imgui.StyleVar.WindowPadding(), 12, 8)

    ctx:push_style_color(imgui.Col.ChildBg(), 0x252530FF)
    if ctx:begin_child("chain_wrapper_" .. selected_chain_guid, 0, rack_h, wrapper_flags) then
        -- Use table layout so header width matches content width
        local table_flags = imgui.TableFlags.SizingStretchSame()
        if ctx:begin_table("chain_table_" .. selected_chain_guid, 1, table_flags) then
            -- Row 1: Header
            ctx:table_next_row()
            ctx:table_set_column_index(0)
            ctx:text_colored(0xAAAAAAFF, "Chain:")
            ctx:same_line()
            ctx:text(chain_name)
            if chain_id then
                ctx:same_line()
                ctx:text_colored(0x888888FF, " [" .. chain_id .. "]")
            end
            ctx:separator()

            -- Row 2: Content
            ctx:table_next_row()
            ctx:table_set_column_index(0)

            -- Chain contents - auto-resize to fit devices
            -- Use same background as wrapper for seamless appearance
            ctx:push_style_color(imgui.Col.ChildBg(), 0x252530FF)
            -- ChildFlags: Border (1) + AutoResizeX (16) + AlwaysAutoResize (64) = 81
            local chain_content_flags = 81
            if ctx:begin_child("chain_contents_" .. selected_chain_guid, 0, chain_content_h, chain_content_flags) then

            if #devices == 0 then
                -- Empty chain - show drop zone
                if has_plugin_payload or has_rack_payload then
                    ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
                else
                    ctx:push_style_color(imgui.Col.Button(), 0x33333344)
                end
                ctx:button("+ Drop plugin or rack to add first device", 250, chain_content_h - 20)
                ctx:pop_style_color()

                if ctx:begin_drag_drop_target() then
                    local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                    if accepted and plugin_name then
                        r.ShowConsoleMsg(string.format("SideFX: Empty chain drag-drop accepted: plugin=%s\n", plugin_name))
                        local plugin = { full_name = plugin_name, name = plugin_name }
                        add_device_to_chain(selected_chain, plugin)
                    end
                    -- Accept rack drops -> create nested rack
                    local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
                    if rack_accepted then
                        add_rack_to_chain(selected_chain)
                    end
                    ctx:end_drag_drop_target()
                end
            else
                -- Draw each device or rack HORIZONTALLY with arrows
                ctx:begin_group()

                for k, dev in ipairs(devices) do
                    local dev_name = fx_utils.get_device_display_name(dev)
                    local dev_enabled = dev:get_enabled()

                    -- Arrow connector between items
                    if k > 1 then
                        ctx:same_line()
                        ctx:push_style_color(imgui.Col.Text(), 0x555555FF)
                        ctx:text("→")
                        ctx:pop_style_color()
                        ctx:same_line()
                    end

                    -- Check if it's a rack or a device
                    if is_rack_container(dev) then
                        -- It's a rack - draw using rack panel (mark as nested)
                        local rack_data = draw_rack_panel(ctx, dev, chain_content_h - 20, true)
                        
                        -- If a chain in this nested rack is selected, show its chain column
                        -- Use the rack's GUID to look up which chain is expanded for this specific rack
                        local rack_guid = dev:get_guid()
                        local nested_chain_guid = state.expanded_nested_chains[rack_guid]
                        if rack_data.is_expanded and nested_chain_guid then
                            local nested_chain = nil
                            for _, chain in ipairs(rack_data.chains) do
                                local ok_guid, chain_guid = pcall(function() return chain:get_guid() end)
                                if ok_guid and chain_guid and chain_guid == nested_chain_guid then
                                    nested_chain = chain
                                    break
                                end
                            end
                            
                            if nested_chain then
                                ctx:same_line()
                                draw_chain_column(ctx, nested_chain, rack_data.rack_h)
                            end
                        end
                    else
                        -- It's a device - find the actual FX inside the device container
                        local dev_main_fx = get_device_main_fx(dev)
                        local dev_utility = get_device_utility(dev)

                        if dev_main_fx and device_panel then
                            device_panel.draw(ctx, dev_main_fx, {
                                avail_height = chain_content_h - 20,
                                utility = dev_utility,
                                container = dev,
                                on_delete = function()
                                    dev:delete()
                                    refresh_fx_list()
                                end,
                                on_rename = function(fx)
                                    -- Rename the container (dev), not the main FX
                                    local dev_guid = dev:get_guid()
                                    state.renaming_fx = dev_guid
                                    state.rename_text = get_fx_display_name(dev)
                                end,
                                on_plugin_drop = function(plugin_name, insert_before_idx)
                                    local plugin = { full_name = plugin_name, name = plugin_name }
                                    add_device_to_chain(selected_chain, plugin)
                                end,
                            })
                        else
                            -- Fallback: simple button
                            local btn_color = dev_enabled and 0x3A5A4AFF or 0x2A2A35FF
                            ctx:push_style_color(imgui.Col.Button(), btn_color)
                            if ctx:button(dev_name:sub(1, 20) .. "##dev_" .. k, 120, chain_content_h - 20) then
                                dev:show(3)
                            end
                            ctx:pop_style_color()
                        end
                    end
                end

                -- Drop zone / add button at end of chain
                ctx:same_line(0, 4)
                local add_btn_h = chain_content_h - 20
                if has_plugin_payload or has_rack_payload then
                    ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
                    ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
                    ctx:button("+##chain_drop", 40, add_btn_h)
                    ctx:pop_style_color(2)
                else
                    ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A88)
                    ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8AAA)
                    ctx:button("+##chain_add", 40, add_btn_h)
                    ctx:pop_style_color(2)
                end

                if ctx:begin_drag_drop_target() then
                    local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                    if accepted and plugin_name then
                        local plugin = { full_name = plugin_name, name = plugin_name }
                        add_device_to_chain(selected_chain, plugin)
                    end
                    -- Accept rack drops -> create nested rack
                    local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
                    if rack_accepted then
                        add_rack_to_chain(selected_chain)
                    end
                    ctx:end_drag_drop_target()
                end

                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Drag plugin or rack here to add")
                end

                ctx:end_group()
            end

                ctx:end_child()
            end
            ctx:pop_style_color()

            ctx:end_table()
        end

        ctx:end_child()
    end
    ctx:pop_style_color()
    ctx:pop_style_var()
end

-- Draw the rack panel (main rack UI without chain column)
draw_rack_panel = function(ctx, rack, avail_height, is_nested)
    -- Explicitly check if is_nested is true (not just truthy)
    is_nested = (is_nested == true)
    local rack_guid = rack:get_guid()
    
    -- Use expanded_racks for ALL racks (both top-level and nested)
    -- This allows multiple top-level racks to be expanded independently
    local is_expanded = (state.expanded_racks[rack_guid] == true)

    -- Get chains from rack (filter out internal mixer)
    local chains = {}
    for child in rack:iter_container_children() do
        local ok, child_name = pcall(function() return child:get_name() end)
        if ok and child_name and not child_name:match("^_") and not child_name:find("Mixer") then
            table.insert(chains, child)
        end
    end

    local rack_w = is_expanded and 350 or 150
    local rack_h = avail_height - 10

    ctx:push_style_color(imgui.Col.ChildBg(), 0x252535FF)
    -- Use unique child ID that includes nested flag to ensure no state conflicts
    local child_id = is_nested and ("rack_nested_" .. rack_guid) or ("rack_" .. rack_guid)
    if ctx:begin_child(child_id, rack_w, rack_h, imgui.ChildFlags.Border()) then

        -- Draw rack header using widget
        rack_ui.draw_rack_header(ctx, rack, is_nested, state, {
            on_toggle_expand = function(rack_guid, is_expanded)
                if is_expanded then
                    state.expanded_racks[rack_guid] = nil
                    state.expanded_nested_chains[rack_guid] = nil
                else
                    state.expanded_racks[rack_guid] = true
                end
                state_module.save_expansion_state()
            end,
            on_rename = function(rack_guid, display_name)
                state.renaming_fx = rack_guid
                state.rename_text = display_name or ""
            end,
            on_dissolve = function(rack)
                dissolve_container(rack)
            end,
            on_delete = function(rack)
                rack:delete()
                refresh_fx_list()
            end,
        })

        -- Get mixer for controls
        local mixer = get_rack_mixer(rack)

        if not is_expanded then
            -- Collapsed view - full height fader with meter and scale
            ctx:text_disabled(string.format("%d chains", #chains))

            if mixer then
                local avail_w, _ = ctx:get_content_region_avail()
                local fader_w = 24
                local meter_w = 12  -- Stereo meter (2x6px)
                local scale_w = 20
                local total_w = scale_w + fader_w + meter_w + 4  -- scale + fader + meter + gaps

                -- Helper to center items
                local function center_offset(item_w)
                    return math.max(0, (avail_w - item_w) / 2)
                end

                -- Pan slider at top (centered)
                local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(1) end)
                if ok_pan and pan_norm then
                    local pan_val = -100 + pan_norm * 200
                    local pan_w = math.min(avail_w - 4, 80)
                    local pan_offset = math.max(0, (avail_w - pan_w) / 2)
                    ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + pan_offset)
                    local pan_changed, new_pan = draw_pan_slider(ctx, "##master_pan_c", pan_val, pan_w)
                    if pan_changed then
                        pcall(function() mixer:set_param_normalized(1, (new_pan + 100) / 200) end)
                    end
                end

                ctx:spacing()
                ctx:spacing()
                ctx:spacing()

                -- Calculate remaining height for fader (leave room for text label)
                local text_label_h = 18
                local _, remaining_h = ctx:get_content_region_avail()
                local fader_h = remaining_h - text_label_h - 4
                fader_h = math.max(50, fader_h)

                -- Gain fader with meter and scale
                local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
                if ok_gain and gain_norm then
                    local gain_db = -24 + gain_norm * 36
                    local gain_format = gain_db >= 0 and string.format("+%.0f", gain_db) or string.format("%.0f", gain_db)

                    -- Position for the whole control group
                    local cursor_x_start = ctx:get_cursor_pos_x()
                    local group_x = cursor_x_start + center_offset(total_w)
                    ctx:set_cursor_pos_x(group_x)

                    local screen_x, screen_y = ctx:get_cursor_screen_pos()
                    local draw_list = ctx:get_window_draw_list()

                    -- Positions
                    local scale_x = screen_x
                    local fader_x = screen_x + scale_w + 2
                    local meter_x = fader_x + fader_w + 2

                    -- dB scale markings on left
                    local db_marks = {12, 6, 0, -6, -12, -18, -24}
                    for _, db in ipairs(db_marks) do
                        local mark_norm = (db + 24) / 36
                        local mark_y = screen_y + fader_h - (fader_h * mark_norm)
                        -- Tick line
                        ctx:draw_list_add_line(draw_list, scale_x + scale_w - 6, mark_y, scale_x + scale_w, mark_y, 0x666666FF, 1)
                        -- dB label (only for key values)
                        if db == 0 or db == -12 or db == 12 then
                            local label = db == 0 and "0" or tostring(db)
                            ctx:draw_list_add_text(draw_list, scale_x, mark_y - 5, 0x888888FF, label)
                        end
                    end

                    -- Fader background
                    ctx:draw_list_add_rect_filled(draw_list, fader_x, screen_y, fader_x + fader_w, screen_y + fader_h, 0x1A1A1AFF, 3)

                    -- Fader fill from bottom (gain setting)
                    local fill_h = fader_h * gain_norm
                    if fill_h > 2 then
                        local fill_top = screen_y + fader_h - fill_h
                        ctx:draw_list_add_rect_filled(draw_list, fader_x + 2, fill_top, fader_x + fader_w - 2, screen_y + fader_h - 2, 0x5588AACC, 2)
                    end

                    -- Fader border
                    ctx:draw_list_add_rect(draw_list, fader_x, screen_y, fader_x + fader_w, screen_y + fader_h, 0x555555FF, 3)

                    -- 0dB line on fader
                    local zero_db_norm = 24 / 36  -- 0dB position
                    local zero_y = screen_y + fader_h - (fader_h * zero_db_norm)
                    ctx:draw_list_add_line(draw_list, fader_x, zero_y, fader_x + fader_w, zero_y, 0xFFFFFF44, 1)

                    -- Stereo level meters on right
                    local meter_l_x = meter_x
                    local meter_r_x = meter_x + meter_w / 2 + 1
                    local half_meter_w = meter_w / 2 - 1

                    -- Meter backgrounds
                    ctx:draw_list_add_rect_filled(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)
                    ctx:draw_list_add_rect_filled(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x111111FF, 1)

                    -- Get track peak levels (stereo)
                    if state.track and state.track.pointer then
                        local peak_l = r.Track_GetPeakInfo(state.track.pointer, 0)
                        local peak_r = r.Track_GetPeakInfo(state.track.pointer, 1)

                        -- Helper to draw a meter bar
                        local function draw_meter_bar(x, w, peak)
                            if peak > 0 then
                                local peak_db = 20 * math.log(peak, 10)
                                peak_db = math.max(-60, math.min(12, peak_db))
                                local peak_norm = (peak_db + 60) / 72

                                local meter_fill_h = fader_h * peak_norm
                                if meter_fill_h > 1 then
                                    local meter_top = screen_y + fader_h - meter_fill_h
                                    -- Color based on level
                                    local meter_color
                                    if peak_db > 0 then
                                        meter_color = 0xFF4444FF  -- Red
                                    elseif peak_db > -6 then
                                        meter_color = 0xFFAA44FF  -- Orange
                                    elseif peak_db > -18 then
                                        meter_color = 0x44FF44FF  -- Green
                                    else
                                        meter_color = 0x44AA44FF  -- Dark green
                                    end
                                    ctx:draw_list_add_rect_filled(draw_list, x, meter_top, x + w, screen_y + fader_h - 1, meter_color, 0)
                                end
                            end
                        end

                        draw_meter_bar(meter_l_x + 1, half_meter_w - 1, peak_l)
                        draw_meter_bar(meter_r_x + 1, half_meter_w - 1, peak_r)
                    end

                    -- Meter borders
                    ctx:draw_list_add_rect(draw_list, meter_l_x, screen_y, meter_l_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)
                    ctx:draw_list_add_rect(draw_list, meter_r_x, screen_y, meter_r_x + half_meter_w, screen_y + fader_h, 0x444444FF, 1)

                    -- Invisible slider for fader interaction
                    ctx:set_cursor_screen_pos(fader_x, screen_y)
                    ctx:push_style_color(imgui.Col.FrameBg(), 0x00000000)
                    ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x00000000)
                    ctx:push_style_color(imgui.Col.FrameBgActive(), 0x00000000)
                    ctx:push_style_color(imgui.Col.SliderGrab(), 0xAAAAAAFF)
                    ctx:push_style_color(imgui.Col.SliderGrabActive(), 0xFFFFFFFF)

                    local gain_changed, new_gain_db = ctx:v_slider_double("##master_gain_v", fader_w, fader_h, gain_db, -24, 12, "")
                    if gain_changed then
                        pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
                    end
                    -- Double-click to reset to 0 dB
                    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                        pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
                    end

                    ctx:pop_style_color(5)

                    -- dB value label at bottom with background (centered under fader+meter)
                    local label_w = fader_w + meter_w + 2
                    local label_x = fader_x
                    local label_y = screen_y + fader_h + 2

                    -- Background
                    ctx:draw_list_add_rect_filled(draw_list, label_x, label_y, label_x + label_w, label_y + text_label_h - 2, 0x222222FF, 2)

                    -- Text centered
                    local db_text_w, _ = ctx:calc_text_size(gain_format)
                    ctx:draw_list_add_text(draw_list, label_x + (label_w - db_text_w) / 2, label_y + 2, 0xCCCCCCFF, gain_format)

                    -- Invisible button for click to edit
                    ctx:set_cursor_screen_pos(label_x, label_y)
                    ctx:invisible_button("##gain_label_btn", label_w, text_label_h - 2)

                    -- Double-click to type value
                    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                        ctx:open_popup("##gain_edit_popup")
                    end

                    -- Edit popup
                    if ctx:begin_popup("##gain_edit_popup") then
                        ctx:set_next_item_width(60)
                        ctx:set_keyboard_focus_here()
                        local input_changed, input_val = ctx:input_double("##gain_input", gain_db, 0, 0, "%.1f")
                        if input_changed then
                            local new_db = math.max(-24, math.min(12, input_val))
                            pcall(function() mixer:set_param_normalized(0, (new_db + 24) / 36) end)
                        end
                        if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
                            ctx:close_current_popup()
                        end
                        ctx:end_popup()
                    end

                    -- Advance cursor past the whole control
                    ctx:set_cursor_screen_pos(screen_x, label_y + text_label_h)
                    ctx:dummy(total_w, 0)
                end
            else
                ctx:text_disabled("No mixer")
            end
        end

        if is_expanded then
            ctx:separator()

            -- Master output controls (mixer already fetched above)
            if mixer then
                if ctx:begin_table("master_controls", 3, imgui.TableFlags.SizingStretchProp()) then
                    ctx:table_setup_column("label", imgui.TableColumnFlags.WidthFixed(), 50)
                    ctx:table_setup_column("gain", imgui.TableColumnFlags.WidthStretch(), 1)
                    ctx:table_setup_column("pan", imgui.TableColumnFlags.WidthFixed(), 70)
                    ctx:table_next_row()

                    ctx:table_set_column_index(0)
                    ctx:text_colored(0xAAAAAAFF, "Master")

                    ctx:table_set_column_index(1)
                    local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
                    if ok_gain and gain_norm then
                        local gain_db = -24 + gain_norm * 36
                        local gain_format = gain_db >= 0 and string.format("+%.1f", gain_db) or string.format("%.1f", gain_db)
                        ctx:set_next_item_width(-1)
                        local gain_changed, new_gain_db = ctx:slider_double("##master_gain", gain_db, -24, 12, gain_format)
                        if gain_changed then
                            pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
                        end
                        if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                            pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
                        end
                    else
                        ctx:text_disabled("--")
                    end

                    ctx:table_set_column_index(2)
                    local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(1) end)
                    if ok_pan and pan_norm then
                        local pan_val = -100 + pan_norm * 200
                        local pan_changed, new_pan = draw_pan_slider(ctx, "##master_pan", pan_val, 60)
                        if pan_changed then
                            pcall(function() mixer:set_param_normalized(1, (new_pan + 100) / 200) end)
                        end
                    else
                        ctx:text_disabled("C")
                    end

                    ctx:end_table()
                end
            end

            ctx:separator()

            -- Chains area header
            ctx:text_colored(0xAAAAAAFF, "Chains:")
            ctx:same_line()
            ctx:push_style_color(imgui.Col.Button(), 0x446688FF)
            if ctx:small_button("+ Chain") then
                -- TODO: Open plugin selector
            end
            ctx:pop_style_color()

            if #chains == 0 then
                ctx:spacing()
                ctx:text_disabled("No chains yet")
                ctx:text_disabled("Drag plugins here to create chains")
            else
                -- Chains table
                if ctx:begin_table("chains_table", 5, imgui.TableFlags.SizingStretchProp()) then
                    ctx:table_setup_column("name", imgui.TableColumnFlags.WidthFixed(), 80)
                    ctx:table_setup_column("enable", imgui.TableColumnFlags.WidthFixed(), 28)
                    ctx:table_setup_column("delete", imgui.TableColumnFlags.WidthFixed(), 24)
                    ctx:table_setup_column("volume", imgui.TableColumnFlags.WidthStretch(), 1)
                    ctx:table_setup_column("pan", imgui.TableColumnFlags.WidthFixed(), 60)

                    for j, chain in ipairs(chains) do
                        ctx:table_next_row()
                        ctx:push_id("chain_" .. j)
                        local ok_guid, chain_guid = pcall(function() return chain:get_guid() end)
                        if not ok_guid or not chain_guid then
                            -- Chain has been deleted, skip this row
                            ctx:pop_id()
                            goto continue_chain
                        end
                        -- Check selection based on whether this is a nested rack
                        -- For nested racks, use the rack's GUID to look up the expanded chain
                        -- Check if this chain is selected (works for both top-level and nested)
                            local rack_guid = rack:get_guid()
                        local is_selected = (state.expanded_nested_chains[rack_guid] == chain_guid)
                        rack_ui.draw_chain_row(ctx, chain, j, rack, mixer, is_selected, is_nested, state, get_fx_display_name, {
                            on_chain_select = function(chain_guid, is_selected, is_nested_rack, rack_guid)
                                -- Track chain selection (works for both top-level and nested)
                                if is_selected then
                                    state.expanded_nested_chains[rack_guid] = nil
                                else
                                    state.expanded_nested_chains[rack_guid] = chain_guid
                                end
                                state_module.save_expansion_state()
                            end,
                            on_add_device_to_chain = add_device_to_chain,
                            on_reorder_chain = reorder_chain_in_rack,
                            on_rename_chain = function(chain_guid, custom_name)
                                state.renaming_fx = chain_guid
                                state.rename_text = custom_name or ""
                            end,
                            on_delete_chain = function(chain, is_selected, is_nested_rack, rack_guid)
                                -- Clear chain selection when deleting (works for both top-level and nested)
                                if is_selected then
                                    state.expanded_nested_chains[rack_guid] = nil
                                end
                            end,
                            on_refresh = refresh_fx_list,
                        })
                        ctx:pop_id()
                        ::continue_chain::
                    end

                    ctx:end_table()
                end
            end

            -- Drop zone for creating new chains or nested racks
            ctx:spacing()
            local drop_h = 40
            local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
            local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
            local has_drop_payload = has_plugin or has_rack
            if has_drop_payload then
                ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
                ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
            else
                ctx:push_style_color(imgui.Col.Button(), 0x33333344)
                ctx:push_style_color(imgui.Col.ButtonHovered(), 0x44444466)
            end
            ctx:button("+ Drop plugin or rack##rack_drop", -1, drop_h)
            ctx:pop_style_color(2)

            if ctx:begin_drag_drop_target() then
                -- Accept plugin drops -> create new chain
                local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                if accepted and plugin_name then
                    local plugin = { full_name = plugin_name, name = plugin_name }
                    add_chain_to_rack(rack, plugin)
                end
                -- Accept rack drops -> create nested rack as new chain
                local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
                if rack_accepted then
                    add_nested_rack_to_rack(rack)
                end
                ctx:end_drag_drop_target()
            end
        end

        ctx:end_child()
    end
    ctx:pop_style_color()

    -- Return data needed for chain column
    return {
        is_expanded = is_expanded,
        chains = chains,
        rack_h = rack_h,
    }
end

local function draw_device_chain(ctx, fx_list, avail_width, avail_height)
    -- Lazy load UI components
    if not device_panel then
        local ok, mod = pcall(require, 'ui.device_panel')
        if ok then device_panel = mod end
    end
    if not rack_panel then
        local ok, mod = pcall(require, 'ui.rack_panel')
        if ok then rack_panel = mod end
    end

    -- Build display list - handles D-containers and legacy FX
    local display_fx = {}
    for i, fx in ipairs(fx_list) do
        if is_device_container(fx) then
            -- D-container: extract main FX and utility from inside
            local main_fx = get_device_main_fx(fx)
            local utility = get_device_utility(fx)
            if main_fx then
                table.insert(display_fx, {
                    fx = main_fx,
                    utility = utility,
                    container = fx,  -- Reference to the container
                    original_idx = fx.pointer,
                    is_device = true,
                })
            end
        elseif is_rack_container(fx) then
            -- R-container (rack) - handle differently
            table.insert(display_fx, {
                fx = fx,
                container = fx,
                original_idx = fx.pointer,
                is_rack = true,
            })
        elseif not is_utility_fx(fx) and not fx:is_container() then
            -- Legacy FX (not in container) - show with paired utility if exists
            local utility = nil
            if i < #fx_list and is_utility_fx(fx_list[i + 1]) then
                utility = fx_list[i + 1]
            end
            table.insert(display_fx, {
                fx = fx,
                utility = utility,
                original_idx = fx.pointer,
                is_legacy = true,
            })
        end
        -- Skip standalone utilities (they're shown in sidebar)
        -- Skip unknown containers
    end

    if #display_fx == 0 then
        -- Empty chain - full height drop zone (always visible)
        local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
        local has_fx = ctx:get_drag_drop_payload("FX_GUID")
        local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
        local is_dragging = has_plugin or has_fx or has_rack
        local drop_h = avail_height - 10

        if is_dragging then
            ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
            ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
            ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)
        else
            ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A44)
            ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8A88)
            ctx:push_style_color(imgui.Col.ButtonActive(), 0x5A8ABAAA)
        end

        ctx:button("+ Drop plugin or rack##empty_drop", 200, drop_h)
        ctx:pop_style_color(3)

        if ctx:is_item_hovered() then
            ctx:set_tooltip("Drag plugin or rack here")
        end

        if ctx:begin_drag_drop_target() then
            -- Accept plugin drops
            local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted and plugin_name then
                add_plugin_by_name(plugin_name, 0)
            end
            -- Accept rack drops
            local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
            if rack_accepted then
                add_rack_to_track(0)
            end
            ctx:end_drag_drop_target()
        end
        return
    end

    -- Note: No drop zone before first device - drop ON the first device to insert before it
    -- This prevents layout shifts that cause scroll jumping

    -- Draw each FX as a device panel, horizontally
    local display_idx = 0
    for _, item in ipairs(display_fx) do
        local fx = item.fx
        local utility = item.utility
        local original_idx = item.original_idx
        display_idx = display_idx + 1
        ctx:push_id("device_" .. display_idx)

        local guid = fx:get_guid()
        local is_container = fx:is_container()

        if display_idx > 1 then
            ctx:same_line()
        end

        if item.is_rack then
            -- Draw rack using helper function (top-level rack, explicitly not nested)
            local rack_data = draw_rack_panel(ctx, fx, avail_height, false)

            -- If a chain is selected, show chain column
            -- Use the rack's GUID to look up which chain is selected for this specific rack
            local rack_guid = fx:get_guid()
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
        elseif is_container then
            -- Unknown container type - show basic view
            ctx:push_style_color(imgui.Col.ChildBg(), 0x252530FF)
            if ctx:begin_child("container_" .. guid, 180, 100, imgui.ChildFlags.Border()) then
                ctx:text(get_fx_display_name(fx):sub(1, 15))
                if ctx:small_button("Open") then
                    fx:show(3)
                end
                ctx:end_child()
            end
            ctx:pop_style_color()
        else
            -- Regular FX - draw as device panel
            if device_panel then
                -- Determine what to use for drag/delete operations
                local container = item.container  -- D-container if exists
                local drag_target = container or fx

                device_panel.draw(ctx, fx, {
                    avail_height = avail_height - 10,
                    utility = utility,  -- Paired SideFX_Utility for gain/pan
                    container = container,  -- Pass container reference
                    container_name = container and container:get_name() or nil,
                    on_delete = function(fx_to_delete)
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
                        refresh_fx_list()
                    end,
                    on_drop = function(dragged_guid, target_guid)
                        -- Handle FX/container reordering
                        local dragged = state.track:find_fx_by_guid(dragged_guid)
                        local target = state.track:find_fx_by_guid(target_guid)
                        if dragged and target then
                            r.TrackFX_CopyToTrack(
                                state.track.pointer, dragged.pointer,
                                state.track.pointer, target.pointer,
                                true  -- move
                            )
                            refresh_fx_list()
                        end
                    end,
                    on_plugin_drop = function(plugin_name, insert_before_idx)
                        -- Add plugin before this FX/container
                        local insert_pos = container and container.pointer or insert_before_idx
                        add_plugin_by_name(plugin_name, insert_pos)
                    end,
                    on_rack_drop = function(insert_before_idx)
                        -- Add rack before this FX/container
                        local insert_pos = container and container.pointer or insert_before_idx
                        add_rack_to_track(insert_pos)
                    end,
                })
            else
                -- Fallback if device_panel not loaded
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
        end

        ctx:pop_id()
    end

    -- Always show add button at end of chain (full height drop zone)
    ctx:same_line()

    local add_btn_h = avail_height - 10
    local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_fx = ctx:get_drag_drop_payload("FX_GUID")
    local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
    local is_dragging = has_plugin or has_fx or has_rack

    if is_dragging then
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x3A4A5A44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x4A6A8A88)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x5A8ABAAA)
    end

    ctx:button("+##add_end", 40, add_btn_h)
    ctx:pop_style_color(3)

    if ctx:is_item_hovered() then
        ctx:set_tooltip("Drag plugin or rack here")
    end

    -- Drop target for plugins and racks
    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            add_plugin_by_name(plugin_name, nil)  -- nil = add at end
        end
        -- Accept rack drops
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            add_rack_to_track(nil)  -- nil = add at end
        end
        ctx:end_drag_drop_target()
    end

    -- Extra padding at end to ensure scrolling doesn't cut off the + button
    ctx:same_line()
    ctx:dummy(20, 1)
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

    Window.run({
        title = "SideFX",
        width = 1400,
        height = 800,
        dockable = true,
        
        on_close = function(self)
            -- Save expansion state and display names when window closes
            if state.track then
                state_module.save_expansion_state()
                state_module.save_display_names()
            end
        end,

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
                ctx:push_font(default_font, 14)
            end

            -- Load icon font on first frame
            if not icon_font then
                icon_font = EmojImGui.Asset.Font(ctx.ctx, "OpenMoji")
            end

            -- Track change detection
            local track, name = get_selected_track()
            
            -- Check if current state.track is still valid (not deleted)
            local state_track_valid = false
            if state.track then
                local ok = pcall(function() 
                    -- Try to access track info to validate pointer
                    return state.track:get_info_value("IP_TRACKNUMBER")
                end)
                state_track_valid = ok
                if not ok then
                    -- Track was deleted, clear all related state
                    state.track = nil
                    state.top_level_fx = {}
                    state.last_fx_count = 0
                    state.expanded_path = {}
                    state.expanded_racks = {}
                    state.expanded_nested_chains = {}
                    state.selected_fx = nil
                    clear_multi_select()
                end
            end
            
            local track_changed = (track and state.track and track.pointer ~= state.track.pointer)
                or (track and not state.track)
                or (not track and state.track)
            if track_changed then
                -- Save expansion state for previous track before switching
                -- (save_expansion_state will handle invalid tracks safely)
                if state_track_valid then
                    state_module.save_expansion_state()
                    state_module.save_display_names()
                end
                
                state.track, state.track_name = track, name
                state.expanded_path = {}
                state.expanded_racks = {}
                state.expanded_nested_chains = {}
                state.display_names = {}  -- Clear display names for new track
                state.selected_fx = nil
                clear_multi_select()
                refresh_fx_list()
                
                -- Load expansion state for new track
            if state.track then
                state_module.load_expansion_state()
                state_module.load_display_names()
            end
            else
                -- Check for external FX changes (e.g. user deleted FX in REAPER)
                check_fx_changes()
            end

            -- Toolbar
            draw_toolbar(ctx)
            ctx:separator()

            -- Layout dimensions
            local browser_w = 260
            local modulator_w = 240
            local avail_w, avail_h = ctx:get_content_region_avail()
            local chain_w = avail_w - browser_w - modulator_w - 20

            -- Plugin Browser (fixed left)
            ctx:push_style_color(imgui.Col.ChildBg(), 0x1E1E22FF)
            if ctx:begin_child("Browser", browser_w, 0, imgui.ChildFlags.Border()) then
                ctx:text("Plugins")
                ctx:separator()
                draw_plugin_browser(ctx)
                ctx:end_child()
            end
            ctx:pop_style_color()

            ctx:same_line()

            -- Device Chain (horizontal scroll, center area)
            ctx:push_style_color(imgui.Col.ChildBg(), 0x1A1A1EFF)
            local chain_flags = imgui.WindowFlags.HorizontalScrollbar()
            if ctx:begin_child("DeviceChain", chain_w, 0, imgui.ChildFlags.Border(), chain_flags) then

                -- Filter out modulators from top_level_fx
                -- Also filter out invalid FX (from deleted tracks)
                local filtered_fx = {}
                for _, fx in ipairs(state.top_level_fx) do
                    -- Validate FX is still accessible (track may have been deleted)
                    local ok = pcall(function()
                        return fx:get_name()
                    end)
                    if ok and not is_modulator_fx(fx) then
                        table.insert(filtered_fx, fx)
                    end
                end

                -- Draw the horizontal device chain
                draw_device_chain(ctx, filtered_fx, chain_w, avail_h)

                ctx:end_child()
            end
            ctx:pop_style_color()

            ctx:same_line()

            -- Modulator column (fixed right)
            draw_modulator_column(ctx, modulator_w)

            reaper_theme:unapply(ctx)

            -- Pop default font if we pushed it
            if default_font then
                ctx:pop_font()
            end
            
            -- Periodically save state (every 60 frames ~= 1 second at 60fps)
            -- Only save if there are actual display names to avoid clearing saved data
            if state.track and (not state.last_save_frame or (ctx.frame_count - state.last_save_frame) > 60) then
                state_module.save_expansion_state()
                -- Only save display names if there are any (don't clear saved data)
                local has_display_names = false
                for _ in pairs(state.display_names) do
                    has_display_names = true
                    break
                end
                if has_display_names then
                    state_module.save_display_names()
                end
                state.last_save_frame = ctx.frame_count
            end
        end,
    })
end

main()


