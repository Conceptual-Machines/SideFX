--- SideFX State Management.
-- Centralized state and track/FX helper functions.
-- @module state
-- @author Nomad Monad
-- @license MIT

local r = reaper
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

--------------------------------------------------------------------------------
-- State Persistence
--------------------------------------------------------------------------------

--- Save expansion state to project.
function M.save_expansion_state()
    if not state.track then return end
    
    local track_guid = state.track:get_guid()
    if not track_guid then return end
    
    -- Serialize expansion state
    local data = {
        expanded_path = state.expanded_path,
        expanded_racks = state.expanded_racks,
        expanded_nested_chains = state.expanded_nested_chains,
    }
    
    -- Convert to JSON-like string (simple serialization)
    local function serialize_table(t, indent)
        indent = indent or 0
        local spaces = string.rep(" ", indent)
        local result = {}
        if type(t) == "table" then
            table.insert(result, "{\n")
            for k, v in pairs(t) do
                local key_str = type(k) == "string" and ('"' .. k .. '"') or tostring(k)
                if type(v) == "table" then
                    table.insert(result, spaces .. "  " .. key_str .. " = ")
                    table.insert(result, serialize_table(v, indent + 2))
                    table.insert(result, ",\n")
                else
                    local val_str = type(v) == "string" and ('"' .. v .. '"') or tostring(v)
                    table.insert(result, spaces .. "  " .. key_str .. " = " .. val_str .. ",\n")
                end
            end
            table.insert(result, spaces .. "}")
            return table.concat(result)
        else
            return tostring(t)
        end
    end
    
    -- Use a simpler approach: serialize as key-value pairs
    local parts = {}
    -- Save expanded_path as comma-separated GUIDs
    if #state.expanded_path > 0 then
        table.insert(parts, "expanded_path:" .. table.concat(state.expanded_path, ","))
    end
    -- Save expanded_racks as comma-separated GUIDs
    local rack_guids = {}
    for guid in pairs(state.expanded_racks) do
        table.insert(rack_guids, guid)
    end
    if #rack_guids > 0 then
        table.insert(parts, "expanded_racks:" .. table.concat(rack_guids, ","))
    end
    -- Save expanded_nested_chains as rack_guid:chain_guid pairs
    local chain_pairs = {}
    for rack_guid, chain_guid in pairs(state.expanded_nested_chains) do
        table.insert(chain_pairs, rack_guid .. "=" .. chain_guid)
    end
    if #chain_pairs > 0 then
        table.insert(parts, "expanded_nested_chains:" .. table.concat(chain_pairs, ","))
    end
    
    local serialized = table.concat(parts, "|")
    if serialized ~= "" then
        r.SetProjExtState(0, "SideFX", "Expansion_" .. track_guid, serialized)
    end
end

--- Load expansion state from project.
function M.load_expansion_state()
    if not state.track then return end
    
    local track_guid = state.track:get_guid()
    if not track_guid then return end
    
    local ok, serialized = r.GetProjExtState(0, "SideFX", "Expansion_" .. track_guid)
    if not ok or not serialized or serialized == "" then return end
    
    -- Parse serialized data
    local parts = {}
    for part in serialized:gmatch("([^|]+)") do
        table.insert(parts, part)
    end
    
    for _, part in ipairs(parts) do
        local key, value = part:match("^([^:]+):(.+)$")
        if key == "expanded_path" then
            state.expanded_path = {}
            for guid in value:gmatch("([^,]+)") do
                table.insert(state.expanded_path, guid)
            end
        elseif key == "expanded_racks" then
            state.expanded_racks = {}
            for guid in value:gmatch("([^,]+)") do
                state.expanded_racks[guid] = true
            end
        elseif key == "expanded_nested_chains" then
            state.expanded_nested_chains = {}
            for pair in value:gmatch("([^,]+)") do
                local rack_guid, chain_guid = pair:match("^([^=]+)=(.+)$")
                if rack_guid and chain_guid then
                    state.expanded_nested_chains[rack_guid] = chain_guid
                end
            end
        end
    end
end

return M
