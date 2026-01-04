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
    
    -- Modulator state
    modulators = {},  -- List of {fx_idx, links = {{target_fx_idx, param_idx}, ...}}
    mod_link_selecting = nil,  -- {mod_idx, selecting = true} when choosing target
    mod_selected_target = {},  -- {[mod_fx_idx] = {fx_idx, fx_name}} for two-dropdown linking
}

-- Create dynamic REAPER theme (reads actual theme colors)
local reaper_theme = theme.from_reaper_theme("REAPER Dynamic")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local project = Project:new()

-- Forward declarations for functions defined later
local renumber_device_chain
local get_device_utility
local renumber_chains_in_rack

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
    
    -- Renumber D-containers after any chain change
    renumber_device_chain()
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
-- Strips internal prefixes (R1_C1_D1_FX:, D1:, etc.) for clean UI display
local function get_fx_display_name(fx)
    if not fx then return "Unknown" end
    local ok, renamed = pcall(function() return fx:get_named_config_param("renamed_name") end)
    local name
    if ok and renamed and renamed ~= "" then
        name = renamed
    else
        name = fx:get_name()
    end
    
    -- Strip SideFX internal prefixes for clean UI display
    -- Patterns from most specific to least specific
    name = name:gsub("^R%d+_C%d+_D%d+_FX:%s*", "")  -- R1_C1_D1_FX: prefix
    name = name:gsub("^R%d+_C%d+_D%d+:%s*", "")     -- R1_C1_D1: prefix
    name = name:gsub("^R%d+_C%d+:%s*", "")          -- R1_C1: prefix
    name = name:gsub("^D%d+_FX:%s*", "")            -- D1_FX: prefix
    name = name:gsub("^D%d+:%s*", "")               -- D1: prefix
    name = name:gsub("^R%d+:%s*", "")               -- R1: prefix
    
    return name
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

-- JSFX name - when installed via ReaPack, this will be in the SideFX folder
-- Use just the name and let REAPER find it, or use full path for dev
local UTILITY_JSFX = "JS:SideFX/SideFX_Utility"

local function is_utility_fx(fx)
    if not fx then return false end
    local name = fx:get_name()
    if not name then return false end
    -- Check for original JSFX name or renamed utility formats:
    -- D{n}_Util (top-level device)
    -- R{n}_C{m}_D{p}_Util (device inside chain inside rack)
    return name:find("SideFX_Utility") or name:find("SideFX Utility") or 
           name:match("^D%d+_Util$") or name:match("_Util$")
end

local function find_paired_utility(track, fx)
    -- Find the SideFX_Utility immediately after this FX
    if not track or not fx then return nil end
    
    local fx_idx = fx.pointer
    local next_idx = fx_idx + 1
    local total = track:get_track_fx_count()
    
    if next_idx < total then
        local next_fx = track:get_track_fx(next_idx)
        if next_fx and is_utility_fx(next_fx) then
            return next_fx
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- D-Container (Device) Helpers
--------------------------------------------------------------------------------

-- Check if a container is a SideFX device container (D-prefix for top-level)
local function is_device_container(fx)
    if not fx then return false end
    local ok, is_cont = pcall(function() return fx:is_container() end)
    if not ok or not is_cont then return false end
    
    local ok2, name = pcall(function() return fx:get_name() end)
    if not ok2 or not name then return false end
    
    return name:match("^D%d") ~= nil
end

-- Check if a container is a SideFX chain container (R{n}_C{n} pattern for chains inside racks)
local function is_chain_container(fx)
    if not fx then return false end
    local ok, is_cont = pcall(function() return fx:is_container() end)
    if not ok or not is_cont then return false end
    
    local ok2, name = pcall(function() return fx:get_name() end)
    if not ok2 or not name then return false end
    
    -- Match R{n}_C{n}: pattern (e.g., R1_C1: ReaComp)
    return name:match("^R%d+_C%d+") ~= nil
end

-- Check if a container is a SideFX rack container (R-prefix, not a chain)
local function is_rack_container(fx)
    if not fx then return false end
    local ok, is_cont = pcall(function() return fx:is_container() end)
    if not ok or not is_cont then return false end
    
    local ok2, name = pcall(function() return fx:get_name() end)
    if not ok2 or not name then return false end
    
    -- Match R{n}: pattern but NOT R{n}_C{n} (which is a chain)
    return name:match("^R%d+:") ~= nil and not name:match("^R%d+_C%d+")
end

-- Get the main FX from a D-container (first non-utility child)
local function get_device_main_fx(container)
    if not container then return nil end
    for child in container:iter_container_children() do
        if not is_utility_fx(child) then
            return child
        end
    end
    return nil
end

-- Get the utility FX from a D-container
get_device_utility = function(container)
    if not container then return nil end
    for child in container:iter_container_children() do
        if is_utility_fx(child) then
            return child
        end
    end
    return nil
end

-- Count D-containers at top level to get next index
local function get_next_device_index()
    if not state.track then return 1 end
    local max_idx = 0
    for fx in state.track:iter_track_fx_chain() do
        local parent = fx:get_parent_container()
        if not parent then  -- Top level only
            local name = fx:get_name()
            local idx = name:match("^D(%d+)")
            if idx then
                max_idx = math.max(max_idx, tonumber(idx))
            end
        end
    end
    return max_idx + 1
end

-- Get short name from plugin full name (strip prefixes)
local function get_short_plugin_name(full_name)
    local name = full_name
    -- Strip common prefixes
    name = name:gsub("^VST3?: ", "")
    name = name:gsub("^AU: ", "")
    name = name:gsub("^JS: ", "")
    name = name:gsub("^CLAP: ", "")
    name = name:gsub("^VSTi: ", "")
    -- Strip path for JS
    name = name:gsub("^.+/", "")
    return name
end

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
                    r.TrackFX_SetNamedConfigParm(state.track.pointer, fx.pointer, "renamed_name", new_name)
                    
                    -- Also rename FX inside (has _FX suffix)
                    local main_fx = get_device_main_fx(fx)
                    if main_fx then
                        local main_fx_name = string.format("D%d_FX: %s", device_idx, fx_name)
                        r.TrackFX_SetNamedConfigParm(state.track.pointer, main_fx.pointer, "renamed_name", main_fx_name)
                    end
                    
                    -- Also rename utility inside
                    local utility = get_device_utility(fx)
                    if utility then
                        local util_name = string.format("D%d_Util", device_idx)
                        r.TrackFX_SetNamedConfigParm(state.track.pointer, utility.pointer, "renamed_name", util_name)
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

local function add_plugin_to_track(plugin, position)
    if not state.track then return end
    
    local name_lower = plugin.full_name:lower()
    
    -- Don't wrap modulators in containers
    if name_lower:find("sidefx_modulator") then
        r.Undo_BeginBlock()
        local fx_position = position and (-1000 - position) or -1
        local fx = state.track:add_fx_by_name(plugin.full_name, false, fx_position)
        r.Undo_EndBlock("SideFX: Add Modulator", -1)
        refresh_fx_list()
        return fx
    end
    
    -- Don't wrap utilities in containers (shouldn't be added directly anyway)
    if name_lower:find("sidefx_utility") then
        return nil
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get next device index
    local device_idx = get_next_device_index()
    local short_name = get_short_plugin_name(plugin.full_name)
    local container_name = string.format("D%d: %s", device_idx, short_name)
    
    -- Position for the container
    local container_position = position and (-1000 - position) or -1
    
    -- Create the container first
    local container = state.track:add_fx_by_name("Container", false, container_position)
    
    if container and container.pointer >= 0 then
        -- Rename the container using ReaWrap
        container:set_named_config_param("renamed_name", container_name)
        
        -- Add the main FX at track level first
        local main_fx = state.track:add_fx_by_name(plugin.full_name, false, -1)
        
        if main_fx and main_fx.pointer >= 0 then
            -- Move the FX into the container using ReaWrap
            container:add_fx_to_container(main_fx, 0)
            
            -- Re-find the FX inside the container (pointer changed after move)
            local fx_inside = get_device_main_fx(container)
            
            if fx_inside then
                -- Set wet/dry to 100% by default
                local wet_idx = fx_inside:get_param_from_ident(":wet")
                if wet_idx >= 0 then
                    fx_inside:set_param_normalized(wet_idx, 1.0)
                end
                -- Rename FX with _FX suffix to distinguish from container
                local fx_name = string.format("D%d_FX: %s", device_idx, short_name)
                fx_inside:set_named_config_param("renamed_name", fx_name)
            end
            
            -- Add utility at track level, then move into container
            local util_fx = state.track:add_fx_by_name(UTILITY_JSFX, false, -1)
            
            if not util_fx or util_fx.pointer < 0 then
                r.ShowConsoleMsg("SideFX: Could not add utility JSFX. Make sure SideFX_Utility.jsfx is installed in REAPER's Effects/SideFX folder.\n")
            else
                -- Move utility into container at position 1
                container:add_fx_to_container(util_fx, 1)
                
                -- Re-find utility inside container and rename it
                local util_inside = get_device_utility(container)
                if util_inside then
                    local util_name = string.format("D%d_Util", device_idx)
                    util_inside:set_named_config_param("renamed_name", util_name)
                end
            end
        else
            r.ShowConsoleMsg("SideFX: Could not add FX.\n")
        end
        
        refresh_fx_list()
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Device", -1)
    
    return container
end

-- Add plugin by name at a specific position
local function add_plugin_by_name(plugin_name, position)
    if not state.track or not plugin_name then return end
    
    -- Create a minimal plugin object for add_plugin_to_track
    local plugin = { full_name = plugin_name, name = plugin_name }
    return add_plugin_to_track(plugin, position)
end

--------------------------------------------------------------------------------
-- R-Container (Rack) Functions
--------------------------------------------------------------------------------

local MIXER_JSFX = "JS:SideFX/SideFX_Mixer"

-- Get next rack index for R-naming
local function get_next_rack_index()
    if not state.track then return 1 end
    local max_idx = 0
    for fx in state.track:iter_track_fx_chain() do
        local parent = fx:get_parent_container()
        if not parent then  -- Top level only
            local name = fx:get_name()
            -- Check for R-containers
            local idx = name:match("^R(%d+)")
            if idx then
                max_idx = math.max(max_idx, tonumber(idx))
            end
            -- Also count D-containers for overall numbering
            local d_idx = name:match("^D(%d+)")
            if d_idx then
                max_idx = math.max(max_idx, tonumber(d_idx))
            end
        end
    end
    return max_idx + 1
end

-- Get the mixer FX from a rack container
local function get_rack_mixer(rack)
    if not rack then return nil end
    for child in rack:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name then
            -- Mixer is named _R{n}_M or contains "Mixer"
            if name:match("^_R%d+_M$") or (name:find("SideFX") and name:find("Mixer")) then
                return child
            end
        end
    end
    return nil
end

-- Get the parameter index for chain volume in the mixer
-- Parameter index is based on DECLARATION ORDER in JSFX, not slider number!
-- slider1 (Master Gain) = param 0
-- slider2 (Master Pan) = param 1
-- slider10-25 (Chain 1-16 Vol) = param 2-17
-- slider30-45 (Chain 1-16 Pan) = param 18-33
local function get_mixer_chain_volume_param(chain_index)
    return 1 + chain_index  -- Chain 1 = param 2, Chain 2 = param 3, etc.
end

-- Get the parameter index for chain pan in the mixer
local function get_mixer_chain_pan_param(chain_index)
    return 17 + chain_index  -- Chain 1 Pan = param 18, Chain 2 Pan = param 19, etc.
end

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
    
    local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    
    -- Background track
    r.ImGui_DrawList_AddRectFilled(draw_list, screen_x, screen_y, screen_x + width, screen_y + slider_h, 0x333333FF, 2)
    
    -- Center line (vertical tick)
    local center_x = screen_x + width / 2
    r.ImGui_DrawList_AddLine(draw_list, center_x, screen_y - 1, center_x, screen_y + slider_h + 1, 0x666666FF, 1)
    
    -- Pan indicator line from center
    local pan_norm = (pan_val + 100) / 200  -- 0 to 1
    local pan_x = screen_x + pan_norm * width
    
    -- Draw filled region from center to pan position
    if pan_val < -1 then
        r.ImGui_DrawList_AddRectFilled(draw_list, pan_x, screen_y + 1, center_x, screen_y + slider_h - 1, 0x5588AAFF, 1)
    elseif pan_val > 1 then
        r.ImGui_DrawList_AddRectFilled(draw_list, center_x, screen_y + 1, pan_x, screen_y + slider_h - 1, 0x5588AAFF, 1)
    end
    
    -- Pan position indicator (small line)
    r.ImGui_DrawList_AddLine(draw_list, pan_x, screen_y, pan_x, screen_y + slider_h, 0xAADDFFFF, 2)
    
    -- Text label background (full width)
    local text_y = screen_y + slider_h + gap
    r.ImGui_DrawList_AddRectFilled(draw_list, screen_x, text_y, screen_x + width, text_y + text_h, 0x222222FF, 2)
    
    -- Invisible button for slider dragging (only covers slider area)
    r.ImGui_SetCursorScreenPos(ctx.ctx, screen_x, screen_y)
    r.ImGui_InvisibleButton(ctx.ctx, label .. "_slider_btn", width, slider_h)
    
    -- Handle dragging
    if r.ImGui_IsItemActive(ctx.ctx) then
        local mouse_x = r.ImGui_GetMousePos(ctx.ctx)
        local new_norm = (mouse_x - screen_x) / width
        new_norm = math.max(0, math.min(1, new_norm))
        new_val = -100 + new_norm * 200
        changed = true
    end
    
    -- Double-click on slider to reset to center
    if r.ImGui_IsItemHovered(ctx.ctx) and r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
        new_val = 0
        changed = true
    end
    
    -- Draw formatted text centered
    local text_w = r.ImGui_CalcTextSize(ctx.ctx, pan_format)
    r.ImGui_DrawList_AddText(draw_list, screen_x + (width - text_w) / 2, text_y + 2, 0xCCCCCCFF, pan_format)
    
    -- Invisible button for text label (separate from slider)
    r.ImGui_SetCursorScreenPos(ctx.ctx, screen_x, text_y)
    r.ImGui_InvisibleButton(ctx.ctx, label .. "_text_btn", width, text_h)
    
    -- Double-click on text to edit value
    if r.ImGui_IsItemHovered(ctx.ctx) and r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
        r.ImGui_OpenPopup(ctx.ctx, label .. "_edit_popup")
    end
    
    -- Edit popup
    if r.ImGui_BeginPopup(ctx.ctx, label .. "_edit_popup") then
        ctx:set_next_item_width(60)
        r.ImGui_SetKeyboardFocusHere(ctx.ctx)
        local input_changed, input_val = r.ImGui_InputDouble(ctx.ctx, "##" .. label .. "_input", pan_val, 0, 0, "%.0f")
        if input_changed then
            new_val = math.max(-100, math.min(100, input_val))
            changed = true
        end
        if r.ImGui_IsKeyPressed(ctx.ctx, r.ImGui_Key_Enter()) or r.ImGui_IsKeyPressed(ctx.ctx, r.ImGui_Key_Escape()) then
            r.ImGui_CloseCurrentPopup(ctx.ctx)
        end
        r.ImGui_EndPopup(ctx.ctx)
    end
    
    -- Advance cursor
    r.ImGui_SetCursorScreenPos(ctx.ctx, screen_x, screen_y + total_h)
    r.ImGui_Dummy(ctx.ctx, width, 0)
    
    return changed, new_val
end

-- Add a new rack (R-container) to the track
local function add_rack_to_track(position)
    if not state.track then return nil end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get next index
    local rack_idx = get_next_rack_index()
    local rack_name = string.format("R%d: Rack", rack_idx)
    
    -- Position for the container
    local container_position = position and (-1000 - position) or -1
    
    -- Create the rack container
    local rack = state.track:add_fx_by_name("Container", false, container_position)
    
    if rack and rack.pointer >= 0 then
        -- Rename the rack
        rack:set_named_config_param("renamed_name", rack_name)
        
        -- Set up for parallel routing (64 channels for up to 32 stereo chains)
        rack:set_container_channels(64)
        
        -- Add the mixer JSFX at track level, then move into rack
        local mixer_fx = state.track:add_fx_by_name(MIXER_JSFX, false, -1)
        
        if mixer_fx and mixer_fx.pointer >= 0 then
            -- Move mixer into rack
            rack:add_fx_to_container(mixer_fx, 0)
            
            -- Rename mixer
            local mixer_inside = nil
            for child in rack:iter_container_children() do
                local ok, name = pcall(function() return child:get_name() end)
                -- Match various mixer name patterns: original JSFX name or already renamed
                if ok and name and ((name:find("SideFX") and name:find("Mixer")) or name:match("^_R%d+_M$")) then
                    mixer_inside = child
                    break
                end
            end
            if mixer_inside then
                -- Use consistent naming: _R1_M (underscore = internal/hidden)
                mixer_inside:set_named_config_param("renamed_name", string.format("_R%d_M", rack_idx))
                
                -- Initialize master and chain params:
                -- Param 0 = Master Gain (0 dB = 0.667 in range -24 to +12)
                -- Param 1 = Master Pan (center = 0.5)
                -- Params 2-17 = Chain volumes (0 dB = 0.833 in range -60 to +12)
                -- Params 18-33 = Chain pans (center = 0.5)
                local master_0db_norm = (0 + 24) / 36  -- 0.667
                local pan_center_norm = 0.5
                local vol_0db_norm = (0 + 60) / 72  -- 0.833
                
                pcall(function() mixer_inside:set_param_normalized(0, master_0db_norm) end)  -- Master gain
                pcall(function() mixer_inside:set_param_normalized(1, pan_center_norm) end)  -- Master pan
                
                for i = 1, 16 do
                    pcall(function() mixer_inside:set_param_normalized(1 + i, vol_0db_norm) end)  -- Vol params 2-17
                    pcall(function() mixer_inside:set_param_normalized(17 + i, pan_center_norm) end)  -- Pan params 18-33
                end
            end
        else
            r.ShowConsoleMsg("SideFX: Could not add mixer JSFX. Make sure SideFX_Mixer.jsfx is installed in REAPER's Effects/SideFX folder.\n")
        end
        
        -- Expand the rack to show it
        state.expanded_path = { rack:get_guid() }
        
        refresh_fx_list()
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Rack", -1)
    
    return rack
end

-- Add a chain (C-container) to an existing rack (R-container)
local function add_chain_to_rack(rack, plugin)
    if not rack or not plugin then return nil end
    if not is_rack_container(rack) then return nil end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get rack name for prefix (e.g., "R1")
    local rack_name = rack:get_name()
    local rack_prefix = rack_name:match("^(R%d+)") or "R1"
    
    -- Count existing chains in this rack (exclude mixer)
    local chain_count = 0
    for child in rack:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name and not name:match("^_") and not name:find("Mixer") then
            chain_count = chain_count + 1
        end
    end
    
    -- Chain index (1-based)
    local chain_idx = chain_count + 1
    
    -- Max 31 chains (channels 3-64, since 1/2 reserved for dry signal)
    if chain_idx > 31 then
        r.ShowConsoleMsg("SideFX: Maximum 31 chains per rack (channels 3-64, 1/2 reserved)\n")
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Chain to Rack (failed)", -1)
        return nil
    end
    
    -- Hierarchical naming (fully recursive):
    -- Chain container:  R1_C1 (routing only)
    -- Device container: R1_C1_D1: <name>
    -- FX inside device: R1_C1_D1_FX: <name>
    -- Utility:          R1_C1_D1_Util
    local short_name = get_short_plugin_name(plugin.full_name)
    local chain_prefix = string.format("%s_C%d", rack_prefix, chain_idx)
    local chain_name = chain_prefix  -- Chain container has no suffix, just the prefix
    local device_prefix = string.format("%s_D1", chain_prefix)  -- First device in chain
    local device_name = string.format("%s: %s", device_prefix, short_name)
    
    -- Build device container completely at track level first, then nest it
    -- This avoids issues with nested container addressing
    
    -- Step 1: Create device container at track level
    local device = state.track:add_fx_by_name("Container", false, -1)
    if not device or device.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Chain (failed)", -1)
        return nil
    end
    device:set_named_config_param("renamed_name", device_name)
    
    -- Step 2: Add FX to device container (while still at track level)
    local main_fx = state.track:add_fx_by_name(plugin.full_name, false, -1)
    if main_fx and main_fx.pointer >= 0 then
        device:add_fx_to_container(main_fx, 0)
        
        -- Re-find and configure FX
        local fx_inside = get_device_main_fx(device)
        if fx_inside then
            local wet_idx = fx_inside:get_param_from_ident(":wet")
            if wet_idx and wet_idx >= 0 then
                fx_inside:set_param_normalized(wet_idx, 1.0)
            end
            fx_inside:set_named_config_param("renamed_name", string.format("%s_FX: %s", device_prefix, short_name))
        end
    end
    
    -- Step 3: Add utility to device container (while still at track level)
    local util_fx = state.track:add_fx_by_name(UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        device:add_fx_to_container(util_fx, 1)
        
        local util_inside = get_device_utility(device)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", string.format("%s_Util", device_prefix))
        end
    end
    
    -- Step 4: Create chain container at track level
    local chain = state.track:add_fx_by_name("Container", false, -1)
    if chain and chain.pointer >= 0 then
        chain:set_named_config_param("renamed_name", chain_name)
        
        -- Step 5: Move device into chain (device is complete now)
        chain:add_fx_to_container(device, 0)
        
        -- Move the chain container into the rack (before the internal mixer)
        local mixer_pos = 0
        local pos = 0
        for child in rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name and (name:match("^_") or name:find("Mixer")) then
                mixer_pos = pos
                break
            end
            pos = pos + 1
        end
        
        rack:add_fx_to_container(chain, mixer_pos)
        
        -- Re-find chain inside rack to set pin mappings
        local chain_inside = nil
        for child in rack:iter_container_children() do
            local ok, name = pcall(function() return child:get_name() end)
            if ok and name == chain_name then
                chain_inside = child
                break
            end
        end
        
        if chain_inside then
            -- CRITICAL: Set chain container to have enough internal channels
            -- Without this, output pin mappings to channels 3+ have nowhere to go!
            chain_inside:set_container_channels(64)
            
            -- Set output channel routing for this chain
            -- All chains read from 1/2 (main signal), output to sideband channels:
            -- Chain 1 → 3/4, Chain 2 → 5/6, Chain 3 → 7/8, Chain 4 → 9/10, etc.
            -- Channels 1/2 are reserved for the dry signal pass-through
            -- Pin mappings use bitmask: bit N = channel N (0-indexed)
            local out_channel = chain_idx * 2  -- 2, 4, 6, 8... (0-indexed, so 3/4, 5/6, 7/8, 9/10...)
            
            -- Calculate bitmasks: 2^out_channel for left, 2^(out_channel+1) for right
            local left_bits = math.floor(2 ^ out_channel)      -- 4, 16, 64, 256...
            local right_bits = math.floor(2 ^ (out_channel + 1)) -- 8, 32, 128, 512...
            
            chain_inside:set_pin_mappings(1, 0, left_bits, 0)   -- output pin 0 (left)
            chain_inside:set_pin_mappings(1, 1, right_bits, 0)  -- output pin 1 (right)
            
            -- Input pins stay on 1/2 (default) so all chains process the same input
        end
        
        refresh_fx_list()
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Chain to Rack", -1)
    
    return chain
end

-- Add a device (D-container with FX + Utility) to an existing chain
local function add_device_to_chain(chain, plugin)
    if not chain or not plugin then return nil end
    if not is_chain_container(chain) then return nil end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get chain name to extract prefix (e.g., "R1_C1" from "R1_C1" or "R1_C1: Something")
    local chain_name = chain:get_name()
    local chain_prefix = chain_name:match("^(R%d+_C%d+)") or chain_name
    
    -- Count existing devices in this chain (non-hidden, non-utility children)
    local device_count = 0
    for child in chain:iter_container_children() do
        local ok, child_name = pcall(function() return child:get_name() end)
        if ok and child_name then
            -- Count device containers (D-prefix) or FX that aren't utilities/mixers
            if child_name:match("_D%d+") or (not child_name:match("^_") and not child_name:find("Util") and not child_name:find("Mixer")) then
                device_count = device_count + 1
            end
        end
    end
    
    -- Device index (1-based)
    local device_idx = device_count + 1
    
    -- Hierarchical naming:
    -- Device container: R1_C1_D2: <name>
    -- FX inside device: R1_C1_D2_FX: <name>
    -- Utility:          R1_C1_D2_Util
    local short_name = get_short_plugin_name(plugin.full_name)
    local device_prefix = string.format("%s_D%d", chain_prefix, device_idx)
    local device_name = string.format("%s: %s", device_prefix, short_name)
    
    -- Build device container completely at track level first, then move into chain
    -- This avoids issues with nested container addressing
    
    -- Step 1: Create device container at track level
    local device = state.track:add_fx_by_name("Container", false, -1)
    if not device or device.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Device to Chain (failed)", -1)
        return nil
    end
    device:set_named_config_param("renamed_name", device_name)
    
    -- Step 2: Add FX to device container (while still at track level)
    local main_fx = state.track:add_fx_by_name(plugin.full_name, false, -1)
    if main_fx and main_fx.pointer >= 0 then
        device:add_fx_to_container(main_fx, 0)
        
        -- Re-find and configure FX
        local fx_inside = get_device_main_fx(device)
        if fx_inside then
            local wet_idx = fx_inside:get_param_from_ident(":wet")
            if wet_idx and wet_idx >= 0 then
                fx_inside:set_param_normalized(wet_idx, 1.0)
            end
            fx_inside:set_named_config_param("renamed_name", string.format("%s_FX: %s", device_prefix, short_name))
        end
    end
    
    -- Step 3: Add utility to device container (while still at track level)
    local util_fx = state.track:add_fx_by_name(UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        device:add_fx_to_container(util_fx, 1)
        
        local util_inside = get_device_utility(device)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", string.format("%s_Util", device_prefix))
        end
    end
    
    -- Step 4: Move device into chain at the end
    -- Count children to find insertion position
    local insert_pos = 0
    for _ in chain:iter_container_children() do
        insert_pos = insert_pos + 1
    end
    
    chain:add_fx_to_container(device, insert_pos)
    
    refresh_fx_list()
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Device to Chain", -1)
    
    return device
end

-- Reorder a chain within a rack (move chain_guid to position before target_chain_guid)
-- If target_chain_guid is nil, move to end
local function reorder_chain_in_rack(rack, chain_guid, target_chain_guid)
    if not rack or not chain_guid then return false end
    if not is_rack_container(rack) then return false end
    
    local chain = state.track:find_fx_by_guid(chain_guid)
    if not chain then return false end
    
    -- Check chain is actually in this rack
    local parent = chain:get_parent_container()
    if not parent or parent:get_guid() ~= rack:get_guid() then return false end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Get list of children in rack (including mixer)
    local children = {}
    local chain_pos = nil
    local target_pos = nil
    local mixer_pos = nil
    
    local pos = 0
    for child in rack:iter_container_children() do
        local guid = child:get_guid()
        local ok, name = pcall(function() return child:get_name() end)
        
        children[#children + 1] = { guid = guid, fx = child }
        
        if guid == chain_guid then
            chain_pos = pos
        end
        if guid == target_chain_guid then
            target_pos = pos
        end
        -- Mixer is at the end (prefixed with _)
        if ok and name and (name:match("^_") or name:find("Mixer")) then
            mixer_pos = pos
        end
        
        pos = pos + 1
    end
    
    if chain_pos == nil then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain (failed)", -1)
        return false
    end
    
    -- Calculate destination position
    local dest_pos
    if target_chain_guid == nil then
        -- Move to end (before mixer if present)
        dest_pos = mixer_pos or #children
    else
        dest_pos = target_pos or mixer_pos or #children
    end
    
    -- Adjust destination if moving forward (position shifts after removal)
    if dest_pos > chain_pos then
        dest_pos = dest_pos - 1
    end
    
    -- No move needed if already in position
    if dest_pos == chain_pos then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Reorder Chain", -1)
        return true
    end
    
    -- Perform the move using ReaWrap container operations
    -- Move out first, then back in at new position
    chain:move_out_of_container()
    
    -- Re-find chain and rack (pointers may have changed)
    chain = state.track:find_fx_by_guid(chain_guid)
    rack = state.track:find_fx_by_guid(rack:get_guid())
    
    if chain and rack then
        rack:add_fx_to_container(chain, dest_pos)
        
        -- Renumber chain names to maintain sequential ordering
        renumber_chains_in_rack(rack)
    end
    
    refresh_fx_list()
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Reorder Chain", -1)
    
    return true
end

-- Renumber chains within a rack after reordering (R1_C1, R1_C2, etc.)
renumber_chains_in_rack = function(rack)
    if not rack then return end
    
    local rack_name = rack:get_name()
    local rack_prefix = rack_name:match("^(R%d+)") or "R1"
    
    local chain_idx = 0
    for child in rack:iter_container_children() do
        local ok, name = pcall(function() return child:get_name() end)
        if ok and name then
            -- Skip internal elements (mixer, prefixed with _)
            if not name:match("^_") and not name:find("Mixer") then
                chain_idx = chain_idx + 1
                local old_prefix = name:match("^(R%d+_C%d+)")
                if old_prefix then
                    local new_prefix = string.format("%s_C%d", rack_prefix, chain_idx)
                    if old_prefix ~= new_prefix then
                        -- Rename chain
                        local new_name = name:gsub("^R%d+_C%d+", new_prefix)
                        child:set_named_config_param("renamed_name", new_name)
                        
                        -- Also rename devices inside chain
                        for device in child:iter_container_children() do
                            local ok_d, device_name = pcall(function() return device:get_name() end)
                            if ok_d and device_name then
                                local new_device_name = device_name:gsub("^R%d+_C%d+", new_prefix)
                                if new_device_name ~= device_name then
                                    device:set_named_config_param("renamed_name", new_device_name)
                                    
                                    -- Rename FX and utility inside device
                                    for inner in device:iter_container_children() do
                                        local ok_i, inner_name = pcall(function() return inner:get_name() end)
                                        if ok_i and inner_name then
                                            local new_inner_name = inner_name:gsub("^R%d+_C%d+", new_prefix)
                                            if new_inner_name ~= inner_name then
                                                inner:set_named_config_param("renamed_name", new_inner_name)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
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
        local ok, guid = pcall(function() return child:get_guid() end)
        if ok and guid then
            children[#children + 1] = guid
        end
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
-- Modulators
--------------------------------------------------------------------------------

local MODULATOR_JSFX = "JS:SideFX/SideFX_Modulator"

local function find_modulators_on_track()
    if not state.track then return {} end
    local modulators = {}
    for fx in state.track:iter_track_fx_chain() do
        local name = fx:get_name()
        if name and (name:find(MODULATOR_JSFX) or name:find("SideFX Modulator")) then
            table.insert(modulators, {
                fx = fx,
                fx_idx = fx.pointer,
                name = "LFO " .. (#modulators + 1),
            })
        end
    end
    return modulators
end

local function add_modulator()
    if not state.track then return end
    r.Undo_BeginBlock()
    -- Add at position 0 (before instruments)
    local fx = state.track:add_fx_by_name(MODULATOR_JSFX, false, -1000)  -- -1000 = position 0
    r.Undo_EndBlock("Add SideFX Modulator", -1)
    refresh_fx_list()
end

local function delete_modulator(fx_idx)
    if not state.track then return end
    r.Undo_BeginBlock()
    r.TrackFX_Delete(state.track.pointer, fx_idx)
    r.Undo_EndBlock("Delete SideFX Modulator", -1)
    refresh_fx_list()
end

local function get_linkable_fx()
    -- Get list of FX that can be modulated (exclude modulators and containers)
    -- Uses iter_all_fx_flat to include FX inside containers
    if not state.track then return {} end
    local linkable = {}
    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local name = fx:get_name()
        -- Skip modulators and containers
        if name and not name:find(MODULATOR_JSFX) and not name:find("SideFX Modulator") and not name:find("Container") then
            local params = {}
            local param_count = fx:get_num_params()
            for p = 0, param_count - 1 do
                local pname = fx:get_param_name(p)
                table.insert(params, {idx = p, name = pname})
            end
            -- Add depth indicator to name for nested FX
            local display_name = fx_info.depth > 0 and string.rep("  ", fx_info.depth) .. "↳ " .. name or name
            table.insert(linkable, {fx = fx, fx_idx = fx.pointer, name = display_name, params = params})
        end
    end
    return linkable
end

local function create_param_link(mod_fx_idx, target_fx_idx, target_param_idx)
    -- Create parameter modulation link using REAPER API
    -- The modulator output is slider4 (param index 3, 0-indexed)
    if not state.track then return false end
    
    local MOD_OUTPUT_PARAM = 3  -- slider4 in JSFX
    
    -- Use TrackFX_SetNamedConfigParm to set up parameter modulation
    -- Format: "param.X.plink.active", "param.X.plink.effect", "param.X.plink.param"
    local plink_prefix = string.format("param.%d.plink.", target_param_idx)
    
    -- For FX in containers, we need the container-aware index
    -- mod_fx_idx should be simple top-level index
    -- target_fx_idx may be container-encoded (0x2000000+) for nested FX
    
    -- Enable parameter link
    local ok1 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "active", "1")
    -- Set source effect (modulator) - modulator must be at top level
    local ok2 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "effect", tostring(mod_fx_idx))
    -- Set source parameter (modulator output)
    local ok3 = r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "param", tostring(MOD_OUTPUT_PARAM))
    
    if not (ok1 and ok2 and ok3) then
        r.ShowConsoleMsg(string.format("Plink failed: mod=%d target=%d param=%d (ok: %s %s %s)\n", 
            mod_fx_idx, target_fx_idx, target_param_idx, 
            tostring(ok1), tostring(ok2), tostring(ok3)))
    end
    
    return ok1 and ok2 and ok3
end

local function remove_param_link(target_fx_idx, target_param_idx)
    if not state.track then return end
    local plink_prefix = string.format("param.%d.plink.", target_param_idx)
    r.TrackFX_SetNamedConfigParm(state.track.pointer, target_fx_idx, plink_prefix .. "active", "0")
end

local function get_modulator_links(mod_fx_idx)
    -- Find all parameters linked to this modulator (including FX in containers)
    if not state.track then return {} end
    local links = {}
    local MOD_OUTPUT_PARAM = 3
    
    for fx_info in state.track:iter_all_fx_flat() do
        local fx = fx_info.fx
        local fx_name = fx:get_name()
        local fx_idx = fx.pointer
        -- Skip modulators and containers
        if fx_name and not (fx_name:find(MODULATOR_JSFX) or fx_name:find("SideFX Modulator") or fx_name:find("Container")) then
            local param_count = fx:get_num_params()
            for param_idx = 0, param_count - 1 do
                local plink_prefix = string.format("param.%d.plink.", param_idx)
                local rv, active = r.TrackFX_GetNamedConfigParm(state.track.pointer, fx_idx, plink_prefix .. "active")
                if rv and active == "1" then
                    local _, effect = r.TrackFX_GetNamedConfigParm(state.track.pointer, fx_idx, plink_prefix .. "effect")
                    local _, param = r.TrackFX_GetNamedConfigParm(state.track.pointer, fx_idx, plink_prefix .. "param")
                    if tonumber(effect) == mod_fx_idx and tonumber(param) == MOD_OUTPUT_PARAM then
                        local param_name = fx:get_param_name(param_idx)
                        table.insert(links, {
                            target_fx_idx = fx_idx,
                            target_fx_name = fx_name,
                            target_param_idx = param_idx,
                            target_param_name = param_name,
                        })
                    end
                end
            end
        end
    end
    return links
end

--------------------------------------------------------------------------------
-- Presets
--------------------------------------------------------------------------------

local presets_folder = script_path .. "presets/"

local function ensure_presets_folder()
    r.RecursiveCreateDirectory(presets_folder, 0)
    r.RecursiveCreateDirectory(presets_folder .. "chains/", 0)
end

local function save_chain_preset(preset_name)
    -- Save the full FX chain with modulator links
    if not state.track or not preset_name or preset_name == "" then return false end
    
    ensure_presets_folder()
    
    -- Use REAPER's native FX chain preset system
    local path = presets_folder .. "chains/" .. preset_name .. ".RfxChain"
    r.TrackFX_SavePresetBank(state.track.pointer, path)
    return true
end

local function load_chain_preset(preset_name)
    if not state.track or not preset_name then return false end
    
    local path = presets_folder .. "chains/" .. preset_name .. ".RfxChain"
    r.Undo_BeginBlock()
    -- Clear existing FX using ReaWrap
    while state.track:get_track_fx_count() > 0 do
        local fx = state.track:get_track_fx(0)
        fx:delete()
    end
    -- Load chain
    state.track:add_by_name(path, false, -1)
    r.Undo_EndBlock("Load FX Chain Preset", -1)
    refresh_fx_list()
    return true
end

local function is_modulator_fx(fx)
    if not fx then return false end
    local name = fx:get_name()
    return name and (name:find(MODULATOR_JSFX) or name:find("SideFX Modulator"))
end

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
                ctx:push_style_color(r.ImGui_Col_Button(), 0x993333FF)
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
                ctx:push_style_color(r.ImGui_Col_Header(), 0x445566FF)
                ctx:push_style_color(r.ImGui_Col_HeaderHovered(), 0x556677FF)
                local header_open = ctx:collapsing_header(mod.name, r.ImGui_TreeNodeFlags_DefaultOpen())
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
                            ctx:push_style_color(r.ImGui_Col_Button(), 0x664444FF)
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
                    if r.ImGui_BeginCombo(ctx.ctx, "##targetfx_" .. i, fx_preview) then
                        for _, fx in ipairs(linkable_fx) do
                            if r.ImGui_Selectable(ctx.ctx, fx.name .. "##fx_" .. fx.fx_idx) then
                                state.mod_selected_target[mod.fx_idx] = {fx_idx = fx.fx_idx, name = fx.name, params = fx.params}
                            end
                        end
                        r.ImGui_EndCombo(ctx.ctx)
                    end
                    
                    -- Dropdown 2: Select parameter (only if FX is selected)
                    if selected_target then
                        ctx:set_next_item_width(width - 20)
                        if r.ImGui_BeginCombo(ctx.ctx, "##targetparam_" .. i, "Select param...") then
                            for _, param in ipairs(selected_target.params) do
                                if r.ImGui_Selectable(ctx.ctx, param.name .. "##p_" .. param.idx) then
                                    create_param_link(mod.fx_idx, selected_target.fx_idx, param.idx)
                                    -- Clear selection after linking
                                    state.mod_selected_target[mod.fx_idx] = nil
                                end
                            end
                            r.ImGui_EndCombo(ctx.ctx)
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
    if icon_font then r.ImGui_PushFont(ctx.ctx, icon_font, icon_size) end
    if ctx:button(icon_text(Icons.arrows_counterclockwise)) then
        refresh_fx_list()
    end
    if icon_font then r.ImGui_PopFont(ctx.ctx) end
    if ctx:is_item_hovered() then ctx:set_tooltip("Refresh FX list") end

    ctx:same_line()

    -- Add Rack button
    ctx:push_style_color(r.ImGui_Col_Button(), 0x446688FF)
    if ctx:button("+ Rack") then
        if state.track then
            add_rack_to_track()
        end
    end
    ctx:pop_style_color()
    if ctx:is_item_hovered() then ctx:set_tooltip("Add new parallel rack") end

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
    ctx:push_style_color(r.ImGui_Col_Text(), 0xAADDFFFF)
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
        ctx:push_style_color(r.ImGui_Col_Button(), 0x4488FF44)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x66AAFF88)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x88CCFFAA)
        
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
        r.ImGui_Dummy(ctx.ctx, btn_w, zone_h)
    end
    return true
end

--------------------------------------------------------------------------------
-- Rack Drawing Helpers (extracted from draw_device_chain)
--------------------------------------------------------------------------------

-- Draw a single chain row in the chains table
local function draw_chain_row(ctx, chain, chain_idx, rack, mixer, is_selected)
    local ok_name, chain_raw_name = pcall(function() return chain:get_name() end)
    local chain_name = ok_name and get_fx_display_name(chain) or "Unknown"
    local ok_en, chain_enabled = pcall(function() return chain:get_enabled() end)
    chain_enabled = ok_en and chain_enabled or false
    local chain_guid = chain:get_guid()
    
    -- Column 1: Chain name button
    r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
    
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
    
    ctx:push_style_color(r.ImGui_Col_Button(), row_color)
    if ctx:button(chain_name .. "##chain_btn", -1, 20) then
        if is_selected then
            state.expanded_path[2] = nil
        else
            state.expanded_path[2] = chain_guid
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
    r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
    if chain_enabled then
        ctx:push_style_color(r.ImGui_Col_Button(), 0x44AA44FF)
    else
        ctx:push_style_color(r.ImGui_Col_Button(), 0xAA4444FF)
    end
    if ctx:small_button(chain_enabled and "ON" or "OF") then
        pcall(function() chain:set_enabled(not chain_enabled) end)
    end
    ctx:pop_style_color()
    
    -- Column 3: Delete button
    r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
    ctx:push_style_color(r.ImGui_Col_Button(), 0x664444FF)
    if ctx:small_button("×") then
        chain:delete()
        if is_selected then
            state.expanded_path[2] = nil
        end
        refresh_fx_list()
    end
    ctx:pop_style_color()
    
    -- Column 4: Volume slider
    r.ImGui_TableSetColumnIndex(ctx.ctx, 3)
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
            if r.ImGui_IsItemHovered(ctx.ctx) and r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
                pcall(function() mixer:set_param_normalized(vol_param, (0 + 24) / 36) end)
            end
        else
            ctx:text_disabled("--")
        end
    else
        ctx:text_disabled("--")
    end
    
    -- Column 5: Pan slider
    r.ImGui_TableSetColumnIndex(ctx.ctx, 4)
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
    
    -- Calculate chain column width based on number of devices (min 650px)
    local device_width = 450  -- Approximate width per device panel
    local min_width = 650
    local chain_col_w = math.max(min_width, #devices * device_width + 100)
    
    ctx:push_style_color(r.ImGui_Col_ChildBg(), 0x252530FF)
    if ctx:begin_child("chain_wrapper_" .. selected_chain_guid, chain_col_w, rack_h, imgui.ChildFlags.Border()) then
        -- Header
        ctx:text_colored(0xAAAAAAFF, "Chain:")
        ctx:same_line()
        ctx:text(chain_display_name)
        ctx:separator()
        
        -- Chain contents with horizontal scroll
        ctx:push_style_color(r.ImGui_Col_ChildBg(), 0x2A2A35FF)
        local chain_scroll_flags = r.ImGui_WindowFlags_HorizontalScrollbar()
        if ctx:begin_child("chain_contents_" .. selected_chain_guid, 0, chain_content_h, imgui.ChildFlags.Border(), chain_scroll_flags) then
            
            if #devices == 0 then
                -- Empty chain - show drop zone
                if has_plugin_payload then
                    ctx:push_style_color(r.ImGui_Col_Button(), 0x4488FF66)
                else
                    ctx:push_style_color(r.ImGui_Col_Button(), 0x33333344)
                end
                ctx:button("+ Drop plugin to add first device", 200, chain_content_h - 20)
                ctx:pop_style_color()
                
                if ctx:begin_drag_drop_target() then
                    local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                    if accepted and plugin_name then
                        local plugin = { full_name = plugin_name, name = plugin_name }
                        add_device_to_chain(selected_chain, plugin)
                    end
                    ctx:end_drag_drop_target()
                end
            else
                -- Draw each device HORIZONTALLY with arrows
                r.ImGui_BeginGroup(ctx.ctx)
                
                for k, dev in ipairs(devices) do
                    local dev_name = get_fx_display_name(dev)
                    local dev_enabled = dev:get_enabled()
                    
                    -- Arrow connector between devices
                    if k > 1 then
                        ctx:same_line()
                        ctx:push_style_color(r.ImGui_Col_Text(), 0x555555FF)
                        ctx:text("→")
                        ctx:pop_style_color()
                        ctx:same_line()
                    end
                    
                    -- Find the actual FX inside the device container
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
                        ctx:push_style_color(r.ImGui_Col_Button(), btn_color)
                        if ctx:button(dev_name:sub(1, 20) .. "##dev_" .. k, 120, chain_content_h - 20) then
                            dev:show(3)
                        end
                        ctx:pop_style_color()
                    end
                end
                
                -- Drop zone / add button at end of chain
                ctx:same_line(0, 4)
                local add_btn_h = chain_content_h - 20
                if has_plugin_payload then
                    ctx:push_style_color(r.ImGui_Col_Button(), 0x4488FF66)
                    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x66AAFF88)
                    ctx:button("+##chain_drop", 40, add_btn_h)
                    ctx:pop_style_color(2)
                else
                    ctx:push_style_color(r.ImGui_Col_Button(), 0x3A4A5A88)
                    ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x4A6A8AAA)
                    ctx:button("+##chain_add", 40, add_btn_h)
                    ctx:pop_style_color(2)
                end
                
                if ctx:begin_drag_drop_target() then
                    local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                    if accepted and plugin_name then
                        local plugin = { full_name = plugin_name, name = plugin_name }
                        add_device_to_chain(selected_chain, plugin)
                    end
                    ctx:end_drag_drop_target()
                end
                
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Drag plugin here to add device")
                end
                
                r.ImGui_EndGroup(ctx.ctx)
            end
            
            ctx:end_child()
        end
        ctx:pop_style_color()
        
        ctx:end_child()
    end
    ctx:pop_style_color()
end

-- Draw the rack panel (main rack UI without chain column)
local function draw_rack_panel(ctx, rack, avail_height)
    local rack_guid = rack:get_guid()
    local rack_name = get_fx_display_name(rack)
    local is_expanded = state.expanded_path[1] == rack_guid
    
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
    
    ctx:push_style_color(r.ImGui_Col_ChildBg(), 0x252535FF)
    if ctx:begin_child("rack_" .. rack_guid, rack_w, rack_h, imgui.ChildFlags.Border()) then
        
        -- Rack header
        local expand_icon = is_expanded and "▼" or "▶"
        if ctx:button(expand_icon .. " " .. rack_name:sub(1, 20) .. "##rack_toggle", -60, 24) then
            if is_expanded then
                state.expanded_path = {}
            else
                state.expanded_path = { rack_guid }
            end
        end
        
        ctx:same_line()
        local rack_enabled = rack:get_enabled()
        ctx:push_style_color(r.ImGui_Col_Button(), rack_enabled and 0x44AA44FF or 0xAA4444FF)
        if ctx:small_button(rack_enabled and "ON" or "OF") then
            rack:set_enabled(not rack_enabled)
        end
        ctx:pop_style_color()
        
        ctx:same_line()
        ctx:push_style_color(r.ImGui_Col_Button(), 0x664444FF)
        if ctx:small_button("×##rack_del") then
            rack:delete()
            refresh_fx_list()
        end
        ctx:pop_style_color()
        
        if is_expanded then
            ctx:separator()
            
            local mixer = get_rack_mixer(rack)
            
            -- Master output controls
            if mixer then
                if r.ImGui_BeginTable(ctx.ctx, "master_controls", 3, r.ImGui_TableFlags_SizingStretchProp()) then
                    r.ImGui_TableSetupColumn(ctx.ctx, "label", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                    r.ImGui_TableSetupColumn(ctx.ctx, "gain", r.ImGui_TableColumnFlags_WidthStretch(), 1)
                    r.ImGui_TableSetupColumn(ctx.ctx, "pan", r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    r.ImGui_TableNextRow(ctx.ctx)
                    
                    r.ImGui_TableSetColumnIndex(ctx.ctx, 0)
                    ctx:text_colored(0xAAAAAAFF, "Master")
                    
                    r.ImGui_TableSetColumnIndex(ctx.ctx, 1)
                    local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
                    if ok_gain and gain_norm then
                        local gain_db = -24 + gain_norm * 36
                        local gain_format = gain_db >= 0 and string.format("+%.1f", gain_db) or string.format("%.1f", gain_db)
                        ctx:set_next_item_width(-1)
                        local gain_changed, new_gain_db = ctx:slider_double("##master_gain", gain_db, -24, 12, gain_format)
                        if gain_changed then
                            pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
                        end
                        if r.ImGui_IsItemHovered(ctx.ctx) and r.ImGui_IsMouseDoubleClicked(ctx.ctx, 0) then
                            pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
                        end
                    else
                        ctx:text_disabled("--")
                    end
                    
                    r.ImGui_TableSetColumnIndex(ctx.ctx, 2)
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
                    
                    r.ImGui_EndTable(ctx.ctx)
                end
            end
            
            ctx:separator()
            
            -- Chains area header
            ctx:text_colored(0xAAAAAAFF, "Chains:")
            ctx:same_line()
            ctx:push_style_color(r.ImGui_Col_Button(), 0x446688FF)
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
                if r.ImGui_BeginTable(ctx.ctx, "chains_table", 5, r.ImGui_TableFlags_SizingStretchProp()) then
                    r.ImGui_TableSetupColumn(ctx.ctx, "name", r.ImGui_TableColumnFlags_WidthFixed(), 80)
                    r.ImGui_TableSetupColumn(ctx.ctx, "enable", r.ImGui_TableColumnFlags_WidthFixed(), 28)
                    r.ImGui_TableSetupColumn(ctx.ctx, "delete", r.ImGui_TableColumnFlags_WidthFixed(), 24)
                    r.ImGui_TableSetupColumn(ctx.ctx, "volume", r.ImGui_TableColumnFlags_WidthStretch(), 1)
                    r.ImGui_TableSetupColumn(ctx.ctx, "pan", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                    
                    for j, chain in ipairs(chains) do
                        r.ImGui_TableNextRow(ctx.ctx)
                        ctx:push_id("chain_" .. j)
                        local is_selected = state.expanded_path[2] == chain:get_guid()
                        draw_chain_row(ctx, chain, j, rack, mixer, is_selected)
                        ctx:pop_id()
                    end
                    
                    r.ImGui_EndTable(ctx.ctx)
                end
            end
            
            -- Drop zone for creating new chains
            ctx:spacing()
            local drop_h = 40
            local has_payload = ctx:get_drag_drop_payload("PLUGIN_ADD")
            if has_payload then
                ctx:push_style_color(r.ImGui_Col_Button(), 0x4488FF66)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x66AAFF88)
            else
                ctx:push_style_color(r.ImGui_Col_Button(), 0x33333344)
                ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x44444466)
            end
            ctx:button("+ Drop plugin to create new chain##rack_drop", -1, drop_h)
            ctx:pop_style_color(2)
            
            if ctx:begin_drag_drop_target() then
                local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
                if accepted and plugin_name then
                    local plugin = { full_name = plugin_name, name = plugin_name }
                    add_chain_to_rack(rack, plugin)
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
        -- Empty chain - show drop zone / placeholder
        local is_dragging = ctx:get_drag_drop_payload("PLUGIN_ADD") or ctx:get_drag_drop_payload("FX_GUID")
        if is_dragging then
            draw_drop_zone(ctx, 0, true, avail_height)
        else
            ctx:text_disabled("No FX on track")
            ctx:text_disabled("Drag plugins from browser →")
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
            -- Arrow connector between devices
            ctx:same_line()
            ctx:push_style_color(r.ImGui_Col_Text(), 0x555555FF)
            ctx:text("→")
            ctx:pop_style_color()
            ctx:same_line()
            -- Note: Drop-on-device panels handles insertion (no between-device zones to prevent scroll jumping)
        end
        
        if item.is_rack then
            -- Draw rack using helper function
            local rack_data = draw_rack_panel(ctx, fx, avail_height)
            
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
            ctx:push_style_color(r.ImGui_Col_ChildBg(), 0x252530FF)
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
                
                ctx:push_style_color(r.ImGui_Col_ChildBg(), enabled and 0x2A2A2AFF or 0x1A1A1AFF)
                if ctx:begin_child("fx_" .. guid, panel_w, panel_h, imgui.ChildFlags.Border()) then
                    ctx:text(name:sub(1, 35))
                    ctx:separator()
                    
                    -- Params area (left)
                    local params_w = col_w * num_cols
                    if ctx:begin_child("params_" .. guid, params_w, panel_h - 40, 0) then
                        if total_params > 0 and r.ImGui_BeginTable(ctx.ctx, "params_fb_" .. guid, num_cols, r.ImGui_TableFlags_SizingStretchSame()) then
                            for row = 0, params_per_col - 1 do
                                r.ImGui_TableNextRow(ctx.ctx)
                                for col = 0, num_cols - 1 do
                                    local p = col * params_per_col + row
                                    r.ImGui_TableSetColumnIndex(ctx.ctx, col)
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
                            r.ImGui_EndTable(ctx.ctx)
                        end
                        ctx:end_child()
                    end
                    
                    -- Sidebar (right)
                    ctx:same_line()
                    local sb_w = 60
                    if ctx:begin_child("sidebar_" .. guid, sb_w, panel_h - 40, 0) then
                        if ctx:button("UI", sb_w - 4, 24) then fx:show(3) end
                        ctx:push_style_color(r.ImGui_Col_Button(), enabled and 0x44AA44FF or 0xAA4444FF)
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
                            local wet_changed, new_wet = r.ImGui_VSliderDouble(ctx.ctx, "##wet", sb_w - 4, 60, wet_val, 0, 1, "")
                            if wet_changed then fx:set_param(wet_idx, new_wet) end
                        end
                        
                        -- Utility controls
                        if utility then
                            ctx:text("Gain")
                            local gain_val = utility:get_param_normalized(0) or 0.5
                            ctx:set_next_item_width(sb_w - 4)
                            local gain_changed, new_gain = r.ImGui_VSliderDouble(ctx.ctx, "##gain", sb_w - 4, 60, gain_val, 0, 1, "")
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
    
    -- Always show add button at end of chain (plus drop zone when dragging)
    ctx:same_line()
    ctx:push_style_color(r.ImGui_Col_Text(), 0x555555FF)
    ctx:text("→")
    ctx:pop_style_color()
    ctx:same_line()
    
    if is_dragging then
        -- Show drop zone when dragging
        draw_drop_zone(ctx, -1, false, avail_height)
    else
        -- Show permanent "+" button to add FX
        local add_btn_h = math.min(avail_height - 20, 80)
        ctx:push_style_color(r.ImGui_Col_Button(), 0x3A4A5A88)
        ctx:push_style_color(r.ImGui_Col_ButtonHovered(), 0x4A6A8AAA)
        ctx:push_style_color(r.ImGui_Col_ButtonActive(), 0x5A8ABACC)
        if ctx:button("+##add_end", 40, add_btn_h) then
            -- Open FX browser or add last used - for now just indicate where to drag from
            -- Could open a popup menu with recent FX here
        end
        ctx:pop_style_color(3)
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Drag plugin here to add\nor click to add FX")
        end
        
        -- Also make the + button a drop target
        if ctx:begin_drag_drop_target() then
            local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
            if accepted and plugin_name then
                add_plugin_by_name(plugin_name, nil)  -- nil = add at end
            end
            ctx:end_drag_drop_target()
        end
    end
    
    -- Extra padding at end to ensure scrolling doesn't cut off the + button
    ctx:same_line()
    r.ImGui_Dummy(ctx.ctx, 20, 1)
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

            -- Layout dimensions
            local browser_w = 260
            local modulator_w = 240
            local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx.ctx)
            local chain_w = avail_w - browser_w - modulator_w - 20

            -- Plugin Browser (fixed left)
            ctx:push_style_color(r.ImGui_Col_ChildBg(), 0x1E1E22FF)
            if ctx:begin_child("Browser", browser_w, 0, imgui.ChildFlags.Border()) then
                ctx:text("Plugins")
                ctx:separator()
                draw_plugin_browser(ctx)
                ctx:end_child()
            end
            ctx:pop_style_color()

            ctx:same_line()

            -- Device Chain (horizontal scroll, center area)
            ctx:push_style_color(r.ImGui_Col_ChildBg(), 0x1A1A1EFF)
            local chain_flags = r.ImGui_WindowFlags_HorizontalScrollbar()
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
                r.ImGui_PopFont(ctx.ctx)
            end
        end,
    })
end

main()
