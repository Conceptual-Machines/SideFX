-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.5.0
-- @provides
--   [nomain] lib/*.lua
--   [nomain] lib/ui/*.lua
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

-- Custom pan slider with center line indicator
-- Returns: changed (bool), new_value (-100 to +100)
local function draw_pan_slider(ctx, label, pan_val, width)
    width = width or 50
    local slider_h = 12
    local text_h = 16
    local gap = 2
    local total_h = slider_h + gap + text_h

    local changed = false
    local new_val = pan_val

    -- Format label
    local pan_format
    if pan_val <= -1 then
        pan_format = string.format("%.0fL", -pan_val)
    elseif pan_val >= 1 then
        pan_format = string.format("%.0fR", pan_val)
    else
        pan_format = "C"
    end

    local screen_x, screen_y = ctx:get_cursor_screen_pos()
    local draw_list = ctx:get_window_draw_list()

    -- Background track
    ctx:draw_list_add_rect_filled(draw_list, screen_x, screen_y, screen_x + width, screen_y + slider_h, 0x333333FF, 2)

    -- Center line (vertical tick)
    local center_x = screen_x + width / 2
    ctx:draw_list_add_line(draw_list, center_x, screen_y - 1, center_x, screen_y + slider_h + 1, 0x666666FF, 1)

    -- Pan indicator line from center
    local pan_norm = (pan_val + 100) / 200  -- 0 to 1
    local pan_x = screen_x + pan_norm * width

    -- Draw filled region from center to pan position
    if pan_val < -1 then
        ctx:draw_list_add_rect_filled(draw_list, pan_x, screen_y + 1, center_x, screen_y + slider_h - 1, 0x5588AAFF, 1)
    elseif pan_val > 1 then
        ctx:draw_list_add_rect_filled(draw_list, center_x, screen_y + 1, pan_x, screen_y + slider_h - 1, 0x5588AAFF, 1)
    end

    -- Pan position indicator (small line)
    ctx:draw_list_add_line(draw_list, pan_x, screen_y, pan_x, screen_y + slider_h, 0xAADDFFFF, 2)

    -- Text label background (full width)
    local text_y = screen_y + slider_h + gap
    ctx:draw_list_add_rect_filled(draw_list, screen_x, text_y, screen_x + width, text_y + text_h, 0x222222FF, 2)

    -- Invisible button for slider dragging (only covers slider area)
    ctx:set_cursor_screen_pos(screen_x, screen_y)
    ctx:invisible_button(label .. "_slider_btn", width, slider_h)

    -- Handle dragging
    if ctx:is_item_active() then
        local mouse_x = ctx:get_mouse_pos()
        local new_norm = (mouse_x - screen_x) / width
        new_norm = math.max(0, math.min(1, new_norm))
        new_val = -100 + new_norm * 200
        changed = true
    end

    -- Double-click on slider to reset to center
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        new_val = 0
        changed = true
    end

    -- Draw formatted text centered
    local text_w = ctx:calc_text_size(pan_format)
    ctx:draw_list_add_text(draw_list, screen_x + (width - text_w) / 2, text_y + 2, 0xCCCCCCFF, pan_format)

    -- Invisible button for text label (separate from slider)
    ctx:set_cursor_screen_pos(screen_x, text_y)
    ctx:invisible_button(label .. "_text_btn", width, text_h)

    -- Double-click on text to edit value
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        ctx:open_popup(label .. "_edit_popup")
    end

    -- Edit popup
    if ctx:begin_popup(label .. "_edit_popup") then
        ctx:set_next_item_width(60)
        ctx:set_keyboard_focus_here()
        local input_changed, input_val = ctx:input_double("##" .. label .. "_input", pan_val, 0, 0, "%.0f")
        if input_changed then
            new_val = math.max(-100, math.min(100, input_val))
            changed = true
        end
        if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
            ctx:close_current_popup()
        end
        ctx:end_popup()
    end

    -- Advance cursor
    ctx:set_cursor_screen_pos(screen_x, screen_y + total_h)
    ctx:dummy(width, 0)

    return changed, new_val
end

-- Draw a vertical fader with fill and dB display
-- Similar style to draw_pan_slider but vertical orientation
local function draw_fader(ctx, label, db_val, width, height, min_db, max_db)
    width = width or 30
    height = height or 120
    min_db = min_db or -24
    max_db = max_db or 12

    local changed = false
    local new_val = db_val

    local screen_x, screen_y = ctx:get_cursor_screen_pos()
    local draw_list = ctx:get_window_draw_list()

    -- Background track
    ctx:draw_list_add_rect_filled(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, 0x1A1A1AFF, 3)

    -- Calculate fill height based on dB value
    local normalized = (db_val - min_db) / (max_db - min_db)
    normalized = math.max(0, math.min(1, normalized))
    local fill_height = height * normalized

    -- Draw fill from bottom
    if fill_height > 2 then
        local fill_top = screen_y + height - fill_height
        -- Color gradient based on level
        local fill_color
        if db_val > 0 then
            fill_color = 0xDD8844CC  -- Orange for above 0dB
        elseif db_val > -6 then
            fill_color = 0x66AA88CC  -- Green-ish for normal
        else
            fill_color = 0x5588AACC  -- Blue for lower levels
        end
        ctx:draw_list_add_rect_filled(draw_list, screen_x + 2, fill_top, screen_x + width - 2, screen_y + height - 2, fill_color, 2)
    end

    -- Border
    ctx:draw_list_add_rect(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, 0x555555FF, 3)

    -- Draw dB tick marks on the right side
    local tick_dbs = {12, 6, 0, -6, -12, -18, -24}
    for _, tick_db in ipairs(tick_dbs) do
        if tick_db >= min_db and tick_db <= max_db then
            local tick_norm = (tick_db - min_db) / (max_db - min_db)
            local tick_y = screen_y + height - (tick_norm * height)
            local tick_len = (tick_db == 0) and 6 or 3
            local tick_color = (tick_db == 0) and 0x888888FF or 0x444444FF
            ctx:draw_list_add_line(draw_list, screen_x + width - tick_len, tick_y, screen_x + width, tick_y, tick_color, 1)
        end
    end

    -- Zero line indicator (horizontal across the full width at 0dB)
    local zero_norm = (0 - min_db) / (max_db - min_db)
    local zero_y = screen_y + height - (zero_norm * height)
    ctx:draw_list_add_line(draw_list, screen_x, zero_y, screen_x + width, zero_y, 0x666666AA, 1)

    -- Invisible button for dragging
    ctx:set_cursor_screen_pos(screen_x, screen_y)
    ctx:invisible_button(label .. "_fader_btn", width, height)

    -- Handle dragging (inverted because Y increases downward)
    if ctx:is_item_active() then
        local _, mouse_y = ctx:get_mouse_pos()
        local new_norm = 1 - ((mouse_y - screen_y) / height)
        new_norm = math.max(0, math.min(1, new_norm))
        new_val = min_db + new_norm * (max_db - min_db)
        changed = true
    end

    -- Double-click to reset to 0dB
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        new_val = 0
        changed = true
    end

    -- Draw dB value label below fader
    local label_h = 16
    local label_y = screen_y + height + 2
    ctx:draw_list_add_rect_filled(draw_list, screen_x, label_y, screen_x + width, label_y + label_h, 0x222222FF, 2)

    local db_label = db_val >= 0 and string.format("+%.0f", db_val) or string.format("%.0f", db_val)
    local text_w, _ = ctx:calc_text_size(db_label)
    ctx:draw_list_add_text(draw_list, screen_x + (width - text_w) / 2, label_y + 1, 0xCCCCCCFF, db_label)

    -- Advance cursor
    ctx:set_cursor_screen_pos(screen_x, label_y + label_h)
    ctx:dummy(width, 0)

    return changed, new_val
end

-- Rack operations (uses state singleton via rack_module)
local function add_rack_to_track(position)
    local rack = rack_module.add_rack_to_track(position)
    if rack then
        state.expanded_path = { rack:get_guid() }
        refresh_fx_list()
    end
    return rack
end

local function add_chain_to_rack(rack, plugin)
    local chain = rack_module.add_chain_to_rack(rack, plugin)
    if chain then refresh_fx_list() end
    return chain
end

local function add_nested_rack_to_rack(parent_rack)
    local nested_rack = rack_module.add_nested_rack_to_rack(parent_rack)
    if nested_rack then refresh_fx_list() end
    return nested_rack
end

local function add_device_to_chain(chain, plugin)
    local device = rack_module.add_device_to_chain(chain, plugin)
    if device then refresh_fx_list() end
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
        state.expanded_path = { container:get_guid() }
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
            local icon = plugin.is_instrument and icon_text(Icons.musical_keyboard) or icon_text(Icons.wrench)
            ctx:text(icon)
            if icon_font then ctx:pop_font() end

            -- Text with default font
            ctx:same_line()
            if ctx:selectable(plugin.name, false) then
                add_plugin_to_track(plugin)
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

--------------------------------------------------------------------------------
-- UI: FX Context Menu
--------------------------------------------------------------------------------

local function draw_fx_context_menu(ctx, fx, guid, i, enabled, is_container, depth)
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
end

--- Handle drop target for FX reordering and container drops.
local function handle_fx_drop_target(ctx, fx, guid, is_container)
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
end

--- Move FX to track level (out of all containers).
local function move_fx_to_track_level(guid)
                    local fx = state.track:find_fx_by_guid(guid)
    if not fx then return end

                                while fx:get_parent_container() do
                                    fx:move_out_of_container()
                                    fx = state.track:find_fx_by_guid(guid)
                                    if not fx then break end
                                end
end

--- Move FX to a target container by navigating through hierarchy.
local function move_fx_to_container(guid, target_container_guid)
    local target_container = state.track:find_fx_by_guid(target_container_guid)
    if not target_container then return end

    -- Build path from root to target container
    local target_path = {}
                                    local container = target_container
                                    while container do
                                        table.insert(target_path, 1, container:get_guid())
                                        container = container:get_parent_container()
                                    end

                                    -- Move FX through each level
                                    for _, container_guid in ipairs(target_path) do
        local fx = state.track:find_fx_by_guid(guid)
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
                        -- Save renamed name
                        fx:set_named_config_param("renamed_name", state.rename_text)
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Check if item was deactivated after edit (clicked away)
                if ctx:is_item_deactivated_after_edit() then
                    if state.rename_text ~= "" then
                        -- Save renamed name
                        fx:set_named_config_param("renamed_name", state.rename_text)
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

                    if ctx:begin_table("ParamTable", 2) then
                        ctx:table_setup_column("Col1", imgui.TableColumnFlags.WidthStretch())
                        ctx:table_setup_column("Col2", imgui.TableColumnFlags.WidthStretch())

                        for row = 0, half - 1 do
                            ctx:table_next_row()

                            ctx:table_set_column_index(0)
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

                            ctx:table_set_column_index(1)
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

                        ctx:end_table()
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
    if ctx:begin_child("Modulators", width, 0, imgui.ChildFlags.Border()) then
    ctx:text("Modulators")
    ctx:same_line()
    if ctx:small_button("+ Add") then
            add_modulator()
    end
    ctx:separator()

    if not state.track then
        ctx:text_colored(0x888888FF, "Select a track")
            ctx:end_child()
        return
    end

        local modulators = find_modulators_on_track()

    if #modulators == 0 then
        ctx:text_colored(0x888888FF, "No modulators")
            ctx:text_colored(0x666666FF, "Click '+ Add'")
    else
            local linkable_fx = get_linkable_fx()

        for i, mod in ipairs(modulators) do
                ctx:push_id("mod_" .. mod.fx_idx)

                -- Header row: buttons first, then name
                -- Show UI button
                if ctx:small_button("UI##ui_" .. mod.fx_idx) then
                    mod.fx:show(3)
                end
                ctx:same_line()

                -- Delete button
                ctx:push_style_color(imgui.Col.Button(), 0x993333FF)
                if ctx:small_button("X##del_" .. mod.fx_idx) then
                    ctx:pop_style_color()
                    ctx:pop_id()
                    delete_modulator(mod.fx_idx)
                    ctx:end_child()
                    return
                end
                ctx:pop_style_color()
                ctx:same_line()

                -- Modulator name as collapsing header
                ctx:push_style_color(imgui.Col.Header(), 0x445566FF)
                ctx:push_style_color(imgui.Col.HeaderHovered(), 0x556677FF)
                local header_open = ctx:collapsing_header(mod.name, imgui.TreeNodeFlags.DefaultOpen())
                ctx:pop_style_color(2)

                if header_open then
                    -- Show existing links
                    local links = get_modulator_links(mod.fx_idx)
                    if #links > 0 then
                        ctx:text_colored(0xAAAAAAFF, "Links:")
                        for _, link in ipairs(links) do
                            ctx:push_id("link_" .. link.target_fx_idx .. "_" .. link.target_param_idx)

                            -- Truncate names to fit
                            local fx_short = link.target_fx_name:sub(1, 15)
                            local param_short = link.target_param_name:sub(1, 12)

                            ctx:text_colored(0x88CC88FF, "→")
                            ctx:same_line()
                            ctx:text_wrapped(fx_short .. " : " .. param_short)
                            ctx:same_line(width - 30)

                            -- Remove link button
                            ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
                            if ctx:small_button("×") then
                                remove_param_link(link.target_fx_idx, link.target_param_idx)
            end
            ctx:pop_style_color()

            ctx:pop_id()
        end
                        ctx:spacing()
                    end

                    -- Two dropdowns to add new link
                    ctx:text_colored(0xAAAAAAFF, "+ Add link:")

                    -- Get current selection for this modulator
                    local selected_target = state.mod_selected_target[mod.fx_idx]
                    local fx_preview = selected_target and selected_target.name or "Select FX..."

                    -- Dropdown 1: Select target FX
                    ctx:set_next_item_width(width - 20)
                    if ctx:begin_combo("##targetfx_" .. i, fx_preview) then
                        for _, fx in ipairs(linkable_fx) do
                            if ctx:selectable(fx.name .. "##fx_" .. fx.fx_idx) then
                                state.mod_selected_target[mod.fx_idx] = {fx_idx = fx.fx_idx, name = fx.name, params = fx.params}
                            end
                        end
                        ctx:end_combo()
                    end

                    -- Dropdown 2: Select parameter (only if FX is selected)
                    if selected_target then
                        ctx:set_next_item_width(width - 20)
                        if ctx:begin_combo("##targetparam_" .. i, "Select param...") then
                            for _, param in ipairs(selected_target.params) do
                                if ctx:selectable(param.name .. "##p_" .. param.idx) then
                                    create_param_link(mod.fx_idx, selected_target.fx_idx, param.idx)
                                    -- Clear selection after linking
                                    state.mod_selected_target[mod.fx_idx] = nil
                                end
                            end
                            ctx:end_combo()
                        end
                    end
                end

                ctx:spacing()
                ctx:separator()
                ctx:pop_id()
            end
        end

        ctx:end_child()
    end
end

--------------------------------------------------------------------------------
-- UI: Toolbar (v2 - horizontal layout)
--------------------------------------------------------------------------------

local function draw_toolbar(ctx)
    -- Refresh button
    if icon_font then ctx:push_font(icon_font, icon_size) end
    if ctx:button(icon_text(Icons.arrows_counterclockwise)) then
        refresh_fx_list()
    end
    if icon_font then ctx:pop_font() end
    if ctx:is_item_hovered() then ctx:set_tooltip("Refresh FX list") end

    ctx:same_line()

    -- Add Rack button (also draggable)
    ctx:push_style_color(imgui.Col.Button(), 0x446688FF)
    if ctx:button("+ Rack") then
        if state.track then
            add_rack_to_track()
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
            -- For now, just focus the plugin browser
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
                    collapse_from_depth(i + 1)
                end
            end
            if i < #state.expanded_path then
                ctx:same_line()
                ctx:text_disabled(">")
            end
        end
    end
end

--------------------------------------------------------------------------------
-- UI: Horizontal Device Chain (v2)
--------------------------------------------------------------------------------

local device_panel = nil  -- Lazy loaded
local rack_panel = nil    -- Lazy loaded

-- Helper to draw a drop zone for adding plugins
-- Always reserves space to prevent scroll jumping, but only shows visual when dragging
local function draw_drop_zone(ctx, position, is_empty, avail_height)
    local has_plugin_payload = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_fx_payload = ctx:get_drag_drop_payload("FX_GUID")
    local is_dragging = has_plugin_payload or has_fx_payload

    local zone_w = 24
    local zone_h = math.min(avail_height - 20, 80)
    local label = is_empty and "+ Drop here" or "+"
    local btn_w = is_empty and 100 or zone_w

    if is_dragging then
        -- Show visible drop indicator when dragging
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF44)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
        ctx:push_style_color(imgui.Col.ButtonActive(), 0x88CCFFAA)

        ctx:button(label .. "##drop_" .. position, btn_w, zone_h)
        ctx:pop_style_color(3)

        if ctx:begin_drag_drop_target() then
            -- Accept plugin drops
            local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted and plugin_name then
                add_plugin_by_name(plugin_name, position)
            end

            -- Accept FX reorder drops
            local accepted_fx, fx_guid = ctx:accept_drag_drop_payload("FX_GUID")
            if accepted_fx and fx_guid then
                local fx = state.track:find_fx_by_guid(fx_guid)
                if fx then
                    -- Move FX to new position
                    r.TrackFX_CopyToTrack(
                        state.track.pointer, fx.pointer,
                        state.track.pointer, position,
                        true  -- move
                    )
                    refresh_fx_list()
                end
            end

            ctx:end_drag_drop_target()
        end
    else
        -- Reserve space with invisible element to prevent scroll jumping
        -- Don't show between items when not dragging (only at end)
        if not is_empty then
            return false  -- Don't reserve space between items when not dragging
        end
        ctx:dummy(btn_w, zone_h)
    end
    return true
end

--------------------------------------------------------------------------------
-- Rack Drawing Helpers (extracted from draw_device_chain)
--------------------------------------------------------------------------------

-- Draw a single chain row in the chains table
local function draw_chain_row(ctx, chain, chain_idx, rack, mixer, is_selected, is_nested_rack)
    -- Explicitly check if is_nested_rack is true (not just truthy)
    is_nested_rack = (is_nested_rack == true)
    local ok_name, chain_raw_name = pcall(function() return chain:get_name() end)
    local chain_name = ok_name and get_fx_display_name(chain) or "Unknown"
    local ok_en, chain_enabled = pcall(function() return chain:get_enabled() end)
    chain_enabled = ok_en and chain_enabled or false
    local chain_guid = chain:get_guid()

    -- Column 1: Chain name button
    ctx:table_set_column_index(0)

    -- Check if dragging for visual feedback
    local has_plugin_drag = ctx:get_drag_drop_payload("PLUGIN_ADD")
    local has_chain_drag = ctx:get_drag_drop_payload("CHAIN_REORDER")

    local row_color = chain_enabled and 0x3A4A5AFF or 0x2A2A35FF
    if is_selected then
        row_color = 0x5588AAFF
    elseif has_plugin_drag then
        row_color = 0x4488AA88  -- Blue tint when plugin dragging
    elseif has_chain_drag then
        row_color = 0x44AA4488  -- Green tint when chain dragging
    end

    ctx:push_style_color(imgui.Col.Button(), row_color)
    if ctx:button(chain_name .. "##chain_btn", -1, 20) then
        if is_nested_rack then
            -- Nested rack chain: use expanded_nested_chain instead of expanded_path[2]
            if is_selected then
                state.expanded_nested_chain = nil
            else
                state.expanded_nested_chain = chain_guid
            end
        else
            -- Top-level rack chain: use expanded_path[2] as before
            if is_selected then
                state.expanded_path[2] = nil
            else
                state.expanded_path[2] = chain_guid
            end
        end
    end
    ctx:pop_style_color()

    -- Drag source for chain reordering
    if ctx:begin_drag_drop_source() then
        ctx:set_drag_drop_payload("CHAIN_REORDER", chain_guid)
        ctx:text("Moving: " .. chain_name)
        ctx:end_drag_drop_source()
    end

    -- Drop target for chain reordering AND plugin adding
    if ctx:begin_drag_drop_target() then
        -- Handle chain reorder
        local accepted_chain, dragged_guid = ctx:accept_drag_drop_payload("CHAIN_REORDER")
        if accepted_chain and dragged_guid then
            reorder_chain_in_rack(rack, dragged_guid, chain_guid)
        end
        -- Handle plugin drop onto chain
        local accepted_plugin, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted_plugin and plugin_name then
            local plugin = { full_name = plugin_name, name = plugin_name }
            add_device_to_chain(chain, plugin)
        end
        ctx:end_drag_drop_target()
    end

    -- Tooltip
    if ctx:is_item_hovered() then
        if has_plugin_drag then
            ctx:set_tooltip("Drop to add FX to " .. chain_name)
        elseif has_chain_drag then
            ctx:set_tooltip("Drop to reorder chain")
        else
            ctx:set_tooltip("Click to " .. (is_selected and "collapse" or "expand"))
        end
    end

    -- Column 2: Enable button
    ctx:table_set_column_index(1)
    if chain_enabled then
        ctx:push_style_color(imgui.Col.Button(), 0x44AA44FF)
    else
        ctx:push_style_color(imgui.Col.Button(), 0xAA4444FF)
    end
    if ctx:small_button(chain_enabled and "ON" or "OF") then
        pcall(function() chain:set_enabled(not chain_enabled) end)
    end
    ctx:pop_style_color()

    -- Column 3: Delete button
    ctx:table_set_column_index(2)
    ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
    if ctx:small_button("×") then
        chain:delete()
        if is_selected then
            if is_nested_rack then
                state.expanded_nested_chain = nil
            else
                state.expanded_path[2] = nil
            end
        end
        refresh_fx_list()
    end
    ctx:pop_style_color()

    -- Column 4: Volume slider
    ctx:table_set_column_index(3)
    if mixer then
        local vol_param = 2 + (chain_idx - 1)  -- Params 2-17 are channel volumes
        local ok_vol, vol_norm = pcall(function() return mixer:get_param_normalized(vol_param) end)
        if ok_vol and vol_norm then
            local vol_db = -24 + vol_norm * 36
            local vol_format = vol_db >= 0 and string.format("+%.0f", vol_db) or string.format("%.0f", vol_db)
            ctx:set_next_item_width(-1)
            local vol_changed, new_vol_db = ctx:slider_double("##vol_" .. chain_idx, vol_db, -24, 12, vol_format)
            if vol_changed then
                local new_norm = (new_vol_db + 24) / 36
                pcall(function() mixer:set_param_normalized(vol_param, new_norm) end)
            end
            if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                pcall(function() mixer:set_param_normalized(vol_param, (0 + 24) / 36) end)
            end
        else
            ctx:text_disabled("--")
        end
    else
        ctx:text_disabled("--")
    end

    -- Column 5: Pan slider
    ctx:table_set_column_index(4)
    if mixer then
        local pan_param = 18 + (chain_idx - 1)  -- Params 18-33 are channel pans
        local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(pan_param) end)
        if ok_pan and pan_norm then
            local pan_val = -100 + pan_norm * 200
            local pan_changed, new_pan = draw_pan_slider(ctx, "##pan_" .. chain_idx, pan_val, 50)
            if pan_changed then
                pcall(function() mixer:set_param_normalized(pan_param, (new_pan + 100) / 200) end)
            end
        else
            ctx:text_disabled("C")
        end
    else
        ctx:text_disabled("C")
    end
end

-- Draw expanded chain column with devices
local function draw_chain_column(ctx, selected_chain, rack_h)
    local selected_chain_guid = selected_chain:get_guid()
    local chain_display_name = get_fx_display_name(selected_chain)

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
            ctx:text(chain_display_name)
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
                    local dev_name = get_fx_display_name(dev)
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
                        
                        -- If a chain in the nested rack is selected, show its chain column
                        if rack_data.is_expanded and state.expanded_nested_chain then
                            local nested_chain_guid = state.expanded_nested_chain
                            local nested_chain = nil
                            for _, chain in ipairs(rack_data.chains) do
                                if chain:get_guid() == nested_chain_guid then
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
    local rack_name = get_fx_display_name(rack)
    
    -- STRICT separation: nested racks use expanded_racks, top-level use expanded_path
    -- NEVER mix them to avoid conflicts
    local is_expanded
    if is_nested then
        -- Nested rack: ONLY check expanded_racks
        is_expanded = (state.expanded_racks[rack_guid] == true)
    else
        -- Top-level rack: ONLY check expanded_path[1]
        is_expanded = (state.expanded_path[1] == rack_guid)
    end

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

        -- Rack header
        local expand_icon = is_expanded and "▼" or "▶"
        -- Use unique button ID that includes nested flag AND guid to avoid conflicts
        local button_id = is_nested and ("rack_toggle_nested_" .. rack_guid) or ("rack_toggle_top_" .. rack_guid)
        if ctx:button(expand_icon .. " " .. rack_name:sub(1, 20) .. "##" .. button_id, -60, 24) then
            -- STRICT separation: NEVER mix state between nested and top-level
            if is_nested then
                -- Nested rack: ONLY modify expanded_racks, NEVER touch expanded_path
                if is_expanded then
                    state.expanded_racks[rack_guid] = nil
                else
                    state.expanded_racks[rack_guid] = true
                end
                -- Ensure we don't accidentally clear top-level rack state
                -- (expanded_path stays untouched)
            else
                -- Top-level rack: ONLY modify expanded_path, NEVER touch expanded_racks
                if is_expanded then
                    state.expanded_path = {}
                else
                    state.expanded_path = { rack_guid }
                end
                -- Ensure we don't accidentally clear nested rack state
                -- (expanded_racks stays untouched)
            end
        end

        ctx:same_line()
        local rack_enabled = rack:get_enabled()
        ctx:push_style_color(imgui.Col.Button(), rack_enabled and 0x44AA44FF or 0xAA4444FF)
        if ctx:small_button(rack_enabled and "ON" or "OF") then
            rack:set_enabled(not rack_enabled)
        end
        ctx:pop_style_color()

        ctx:same_line()
        ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
        if ctx:small_button("×##rack_del") then
            rack:delete()
            refresh_fx_list()
        end
        ctx:pop_style_color()

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
                        local chain_guid = chain:get_guid()
                        -- Check selection based on whether this is a nested rack
                        local is_selected
                        if is_nested then
                            is_selected = (state.expanded_nested_chain == chain_guid)
                        else
                            is_selected = (state.expanded_path[2] == chain_guid)
                        end
                        draw_chain_row(ctx, chain, j, rack, mixer, is_selected, is_nested)
                        ctx:pop_id()
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
            if rack_data.is_expanded and state.expanded_path[2] then
                local selected_chain_guid = state.expanded_path[2]
                local selected_chain = nil
                for _, chain in ipairs(rack_data.chains) do
                    if chain:get_guid() == selected_chain_guid then
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

    Window.run({
        title = "SideFX",
        width = 1400,
        height = 800,
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
                ctx:push_font(default_font, 14)
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
                local filtered_fx = {}
                for _, fx in ipairs(state.top_level_fx) do
                    if not is_modulator_fx(fx) then
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
        end,
    })
end

main()
