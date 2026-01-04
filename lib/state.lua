--- SideFX State Management.
-- Centralized state and track/FX helper functions.
-- @module state
-- @author Nomad Monad
-- @license MIT

local Project = require('project')

local M = {}

--------------------------------------------------------------------------------
-- State Table
--------------------------------------------------------------------------------

M.state = {
    track = nil,
    track_name = "No track selected",

    -- FX data
    top_level_fx = {},
    last_fx_count = 0,  -- For detecting external FX changes

    -- Column navigation: list of expanded container GUIDs (breadcrumb trail)
    expanded_path = {},  -- e.g. {container1_guid, container2_guid, ...}
    
    -- Expanded racks: set of rack GUIDs that are expanded (for nested racks)
    expanded_racks = {},  -- {[rack_guid] = true}
    
    -- Expanded chains in nested racks: track which chain is expanded per nested rack
    -- Keyed by rack GUID to avoid conflicts between multiple nested racks
    expanded_nested_chains = {},  -- {[rack_guid] = chain_guid}

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

-- Alias for convenience
local state = M.state

--------------------------------------------------------------------------------
-- Project Instance
--------------------------------------------------------------------------------

local project = Project:new()

--------------------------------------------------------------------------------
-- Callbacks (set by main script)
--------------------------------------------------------------------------------

-- Called after refresh_fx_list to renumber devices
M.on_refresh = nil

--------------------------------------------------------------------------------
-- Track Selection
--------------------------------------------------------------------------------

--- Get the currently selected track.
-- @return Track|nil Track object or nil
-- @return string Track name or error message
function M.get_selected_track()
    if not project:has_selected_tracks() then
        return nil, "No track selected"
    end
    local track = project:get_selected_track(0)
    return track, track:get_name()
end

--------------------------------------------------------------------------------
-- FX List Management
--------------------------------------------------------------------------------

--- Refresh the top-level FX list from current track.
function M.refresh_fx_list()
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
    
    -- Call refresh callback (e.g., renumber_device_chain)
    if M.on_refresh then
        M.on_refresh()
    end
end

--- Clear multi-selection.
function M.clear_multi_select()
    state.multi_select = {}
end

--- Check if FX chain changed externally and refresh if needed.
function M.check_fx_changes()
    if not state.track then return end
    local current_count = state.track:get_track_fx_count()
    if current_count ~= state.last_fx_count then
        M.refresh_fx_list()
        -- Clear invalid selections
        M.clear_multi_select()
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

--------------------------------------------------------------------------------
-- Container Navigation
--------------------------------------------------------------------------------

--- Get children of a container by GUID.
-- @param container_guid string Container GUID
-- @return table Array of child FX objects
function M.get_container_children(container_guid)
    if not state.track or not container_guid then return {} end

    local container = state.track:find_fx_by_guid(container_guid)
    if not container or not container:is_container() then return {} end

    local children = {}
    for child in container:iter_container_children() do
        children[#children + 1] = child
    end
    return children
end

--- Collapse all columns from a certain depth onwards.
-- @param depth number Depth to collapse from
function M.collapse_from_depth(depth)
    while #state.expanded_path >= depth do
        table.remove(state.expanded_path)
    end
    state.selected_fx = nil
end

--- Toggle container expansion at a specific depth.
-- @param guid string Container GUID
-- @param depth number Depth level
function M.toggle_container(guid, depth)
    if state.expanded_path[depth] == guid then
        M.collapse_from_depth(depth)
    else
        M.collapse_from_depth(depth)
        state.expanded_path[depth] = guid
    end
    state.selected_fx = nil
end

--- Toggle FX selection for detail panel.
-- @param guid string FX GUID
function M.toggle_fx_detail(guid)
    if state.selected_fx == guid then
        state.selected_fx = nil
    else
        state.selected_fx = guid
    end
end

--------------------------------------------------------------------------------
-- Multi-Selection
--------------------------------------------------------------------------------

--- Get list of multi-selected FX objects.
-- @return table Array of FX objects
function M.get_multi_selected_fx()
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

--- Get count of multi-selected FX.
-- @return number Count
function M.get_multi_select_count()
    local count = 0
    for _ in pairs(state.multi_select) do count = count + 1 end
    return count
end

--- Toggle multi-selection for an FX.
-- @param guid string FX GUID
function M.toggle_multi_select(guid)
    if state.multi_select[guid] then
        state.multi_select[guid] = nil
    else
        state.multi_select[guid] = true
    end
end

--- Add FX to multi-selection.
-- @param guid string FX GUID
function M.add_to_multi_select(guid)
    state.multi_select[guid] = true
end

return M
