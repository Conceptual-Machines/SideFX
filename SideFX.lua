-- @description SideFX - Smart FX Container Manager
-- @author Nomad Monad
-- @version 0.2.0
-- @provides
--   [nomain] lib/*.lua
-- @link https://github.com/Conceptual-Machines/SideFX
-- @about
--   # SideFX
--
--   Smart FX container management for Reaper 7+.
--
--   Features:
--   - Visual rack-style FX chain view
--   - One-click parallel chain creation
--   - Instrument layer routing (fix multi-instrument container issues)
--   - Container routing diagnostics
--
-- @changelog
--   v0.2.0 - ReaWrap integration
--     + Using ReaWrap ImGui wrapper
--     + Cleaner code structure
--   v0.1.0 - Initial release
--     + Container visualization
--     + Parallel rack creation
--     + Instrument layer creation
--     + Routing diagnostics

local r = reaper

--------------------------------------------------------------------------------
-- Path Setup
--------------------------------------------------------------------------------

local script_path = ({ r.get_action_context() })[2]:match('^.+[\\//]')

-- Find REAPER Scripts folder
local scripts_folder = r.GetResourcePath() .. "/Scripts/"

-- ReaWrap paths (try ReaPack install first, then local dev)
local reawrap_reapack = scripts_folder .. "ReaWrap/lua/"
-- Local dev path (same parent folder structure as ReaScript workspace)
local sidefx_parent = script_path:match("^(.+[/\\])SideFX[/\\]")
local reawrap_dev = sidefx_parent and (sidefx_parent .. "ReaWrap/lua/") or ""

-- Add paths
package.path = script_path .. "?.lua;"
    .. script_path .. "lib/?.lua;"
    .. reawrap_reapack .. "?.lua;"
    .. reawrap_reapack .. "?/init.lua;"
    .. reawrap_dev .. "?.lua;"
    .. reawrap_dev .. "?/init.lua;"
    .. package.path

--------------------------------------------------------------------------------
-- Imports
--------------------------------------------------------------------------------

local imgui = require('imgui')
local Window = require('imgui.window').Window
local theme = require('imgui.theme')
local container = require('container')
local routing = require('routing')

--------------------------------------------------------------------------------
-- UI State
--------------------------------------------------------------------------------

local state = {
    track = nil,
    track_name = "No track selected",
    fx_list = {},
    selected_fx = {},  -- Set of selected FX indices
    show_debug = false,
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function get_selected_track()
    local track = r.GetSelectedTrack(0, 0)
    if track then
        local _, name = r.GetTrackName(track)
        return track, name
    end
    return nil, "No track selected"
end

local function refresh_fx_list()
    state.fx_list = {}
    if not state.track then
        return
    end
    state.fx_list = container.get_all_fx_flat(state.track)
end

local function toggle_fx_selection(fx_idx)
    if state.selected_fx[fx_idx] then
        state.selected_fx[fx_idx] = nil
    else
        state.selected_fx[fx_idx] = true
    end
end

local function get_selected_fx_indices()
    local indices = {}
    for idx, _ in pairs(state.selected_fx) do
        indices[#indices + 1] = idx
    end
    table.sort(indices)
    return indices
end

local function clear_selection()
    state.selected_fx = {}
end

local function get_selected_count()
    local count = 0
    for _ in pairs(state.selected_fx) do
        count = count + 1
    end
    return count
end

--------------------------------------------------------------------------------
-- UI Components
--------------------------------------------------------------------------------

local function draw_fx_item(ctx, fx_info)
    local indent = string.rep("  ", fx_info.depth)
    local icon = fx_info.is_container and "📦 " or "🔌 "
    local label = indent .. icon .. fx_info.name

    local is_selected = state.selected_fx[fx_info.fx_idx] == true

    if ctx:selectable(label, is_selected) then
        -- Shift+click for multi-select
        if ctx:is_key_down(imgui.Key.Shift()) then
            toggle_fx_selection(fx_info.fx_idx)
        else
            clear_selection()
            state.selected_fx[fx_info.fx_idx] = true
        end
    end

    -- Double-click to open FX window
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        r.TrackFX_Show(state.track, fx_info.fx_idx, 3) -- Show floating window
    end
end

local function draw_fx_list(ctx)
    if ctx:begin_child("FXList", 0, -80, imgui.ChildFlags.Border()) then
        if #state.fx_list == 0 then
            ctx:text_disabled("No FX on track")
        else
            for _, fx_info in ipairs(state.fx_list) do
                draw_fx_item(ctx, fx_info)
            end
        end
        ctx:end_child()
    end
end

local function draw_action_buttons(ctx)
    local selected_count = get_selected_count()
    local has_selection = selected_count >= 2

    -- Parallel Rack button
    ctx:with_disabled(not has_selection, function()
        if ctx:button("⫴ Parallel Rack", 120, 0) then
            local indices = get_selected_fx_indices()
            if #indices >= 2 then
                routing.create_parallel_rack(state.track, indices)
                clear_selection()
                refresh_fx_list()
            end
        end
    end)
    ctx:help_marker("Create parallel chain from selected FX (select 2+)")

    ctx:same_line()

    -- Instrument Layer button
    ctx:with_disabled(not has_selection, function()
        if ctx:button("🎹 Instrument Layer", 120, 0) then
            local indices = get_selected_fx_indices()
            if #indices >= 2 then
                routing.create_instrument_layer(state.track, indices)
                clear_selection()
                refresh_fx_list()
            end
        end
    end)
    ctx:help_marker("Create instrument layer with proper routing (select 2+)")

    ctx:same_line()

    -- Serial Chain button
    ctx:with_disabled(not has_selection, function()
        if ctx:button("→ Chain", 80, 0) then
            local indices = get_selected_fx_indices()
            if #indices >= 1 then
                routing.create_serial_chain(state.track, indices)
                clear_selection()
                refresh_fx_list()
            end
        end
    end)
    ctx:help_marker("Group selected FX into a container")
end

local function draw_toolbar(ctx)
    if ctx:button("🔄 Refresh") then
        refresh_fx_list()
    end

    ctx:same_line()

    if ctx:button("🔍 Diagnose") then
        -- Find containers and diagnose them
        for _, fx_info in ipairs(state.fx_list) do
            if fx_info.is_container then
                local issues = routing.diagnose_container(state.track, fx_info.fx_idx)
                if #issues > 0 then
                    for _, issue in ipairs(issues) do
                        r.ShowConsoleMsg("SideFX: " .. issue.message .. "\n")
                    end
                end
            end
        end
    end
    ctx:help_marker("Check containers for routing issues")

    ctx:same_line()

    if ctx:button("🔧 Auto-Fix") then
        for _, fx_info in ipairs(state.fx_list) do
            if fx_info.is_container then
                local fixed = routing.auto_fix_container(state.track, fx_info.fx_idx)
                if fixed > 0 then
                    r.ShowConsoleMsg(string.format("SideFX: Fixed %d issues in %s\n", fixed, fx_info.name))
                end
            end
        end
        refresh_fx_list()
    end
    ctx:help_marker("Automatically fix detected routing issues")

    ctx:same_line()
    ctx:spacing()
    ctx:same_line()

    local _, show_debug = ctx:checkbox("Debug", state.show_debug)
    state.show_debug = show_debug
end

local function draw_debug_panel(ctx)
    if not state.show_debug then
        return
    end

    if ctx:collapsing_header("Debug Info") then
        ctx:text_fmt("Track: %s", state.track_name)
        ctx:text_fmt("FX Count: %d", #state.fx_list)
        ctx:text_fmt("Selected: %d", get_selected_count())

        if ctx:button("Print Structure to Console") then
            if state.track then
                r.ShowConsoleMsg("\n=== SideFX: FX Structure ===\n")
                container.debug_print_structure(state.track)
                r.ShowConsoleMsg("============================\n")
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Main Window
--------------------------------------------------------------------------------

local function main()
    -- Check for ReaImGui
    if not imgui.is_available() then
        r.ShowMessageBox(
            "SideFX requires the ReaImGui extension.\n\nPlease install it via ReaPack.",
            "SideFX - Missing Dependency",
            0
        )
        return
    end

    -- Initialize state
    state.track, state.track_name = get_selected_track()
    refresh_fx_list()

    -- Create and run the main window
    Window.run({
        title = "SideFX",
        width = 400,
        height = 500,
        data = state,

        on_draw = function(self, ctx)
            -- Apply theme
            theme.Reaper:apply(ctx)

            -- Check for track changes
            local track, name = get_selected_track()
            if track ~= state.track then
                state.track = track
                state.track_name = name
                clear_selection()
                refresh_fx_list()
            end

            -- Header
            ctx:text("Track: " .. state.track_name)
            ctx:separator()

            -- Toolbar
            draw_toolbar(ctx)
            ctx:separator()

            -- FX List
            draw_fx_list(ctx)

            -- Action buttons
            draw_action_buttons(ctx)

            -- Debug panel
            draw_debug_panel(ctx)

            -- Unapply theme
            theme.Reaper:unapply(ctx)
        end,
    })
end

-- Run
main()
