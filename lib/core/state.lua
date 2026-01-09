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
    
    -- Render control: set true when FX deleted, prevents rendering stale data
    deletion_pending = false,

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

    -- Custom display names (SideFX-only, doesn't change REAPER FX names)
    display_names = {},  -- {[fx_guid] = "custom display name"}

    -- Save timing
    last_save_frame = nil,  -- Frame count of last save

    show_debug = false,  -- Disabled to prevent console spam
    
    -- FX Chain Protection: snapshot of FX chain when window opened
    fx_chain_snapshot = nil,  -- {count, guids = {}, names = {}, timestamp}
    fx_chain_changed = false,  -- True if external changes detected
    last_chain_check_time = 0,  -- Last time we checked for changes (ms)

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
    modulator_expanded = {},  -- {[mod_fx_idx] = true} -- which modulators show params
    modulator_advanced = {},  -- {[mod_fx_idx] = true} -- advanced section expanded
    modulator_section_collapsed = {},  -- {[device_guid] = true} -- device modulator section collapsed
    
    -- Parameter visibility selections (keyed by plugin full_name)
    param_selections = {},  -- {[plugin_full_name] = {param_idx1, param_idx2, ...}}
    
    -- User configuration
    config = {
        max_visible_params = 64,  -- Maximum parameters to display (default 64, max 128)
        -- Display settings
        show_track_name = true,
        show_breadcrumbs = true,
        icon_font_size = 1,  -- 0=Small, 1=Medium, 2=Large
        -- Behavior settings
        auto_refresh = true,
        remember_window_pos = true,
        -- Gain staging settings
        gain_target_db = -12.0,
        gain_tolerance_db = 1.0,
    },
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

    -- Safely access track (may have been deleted)
    local ok, err = pcall(function()
        for fx in state.track:iter_track_fx_chain() do
            local parent = fx:get_parent_container()
            if not parent then
                state.top_level_fx[#state.top_level_fx + 1] = fx
            end
        end
        state.last_fx_count = state.track:get_track_fx_count()
    end)

    -- If track was deleted, clear state
    if not ok then
        state.track = nil
        state.last_fx_count = 0
        return
    end

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
    if not state.track then
        -- Clear FX list if track is gone
        state.top_level_fx = {}
        state.last_fx_count = 0
        return
    end

    -- Safely check track FX count (track may have been deleted)
    local ok, current_count = pcall(function()
        return state.track:get_track_fx_count()
    end)

    if not ok then
        -- Track was deleted, clear state
        state.track = nil
        state.top_level_fx = {}
        state.last_fx_count = 0
        return
    end

    if current_count ~= state.last_fx_count then
        M.refresh_fx_list()
        -- Clear invalid selections
        M.clear_multi_select()
        state.selected_fx = nil
        -- Validate expanded_path - remove any GUIDs that no longer exist
        if state.track then
            local valid_path = {}
            for _, guid in ipairs(state.expanded_path) do
                local fx = state.track:find_fx_by_guid(guid)
                if fx then
                    valid_path[#valid_path + 1] = guid
                else
                    break  -- Stop at first invalid - rest would be children
                end
            end
            state.expanded_path = valid_path
        end
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

    -- Safely get track GUID (track may have been deleted)
    local ok, track_guid = pcall(function() return state.track:get_guid() end)
    if not ok or not track_guid then
        -- Track was deleted or invalid, clear state
        state.track = nil
        return
    end

    -- Serialize expansion state
    local data = {
        expanded_path = state.expanded_path,
        expanded_racks = state.expanded_racks,
        expanded_nested_chains = state.expanded_nested_chains,
        modulator_section_collapsed = state.modulator_section_collapsed,
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
    -- Save modulator_section_collapsed as comma-separated GUIDs
    local mod_collapsed_guids = {}
    for guid in pairs(state.modulator_section_collapsed) do
        table.insert(mod_collapsed_guids, guid)
    end
    if #mod_collapsed_guids > 0 then
        table.insert(parts, "modulator_section_collapsed:" .. table.concat(mod_collapsed_guids, ","))
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
        elseif key == "modulator_section_collapsed" then
            state.modulator_section_collapsed = {}
            for guid in value:gmatch("([^,]+)") do
                state.modulator_section_collapsed[guid] = true
            end
        end
    end
end

--- Save display names to project.
function M.save_display_names()
    if not state.track then return end

    -- Safely get track GUID (track may have been deleted)
    local ok, track_guid = pcall(function() return state.track:get_guid() end)
    if not ok or not track_guid then
        state.track = nil
        return
    end

    -- Serialize display_names as guid=name pairs
    local name_pairs = {}
    local count = 0
    for guid, name in pairs(state.display_names) do
        if name and name ~= "" then
            -- Escape special characters in name (replace | and = with placeholders)
            local escaped_name = name:gsub("|", "%%PIPE%%"):gsub("=", "%%EQ%%")
            table.insert(name_pairs, guid .. "=" .. escaped_name)
            count = count + 1
        end
    end

    local key = "DisplayNames_" .. track_guid
    local ok_save, err = pcall(function()
        if count > 0 then
            local serialized = table.concat(name_pairs, "|")
            r.SetProjExtState(0, "SideFX", key, serialized)
        end
        -- Don't clear saved data when count is 0 - might be temporary empty state
        -- Only clear explicitly when needed (e.g., on track deletion)
    end)

    if not ok_save then
        r.ShowConsoleMsg(string.format("SideFX: Error saving display names: %s\n", tostring(err)))
    end
end

--- Load display names from project.
function M.load_display_names()
    if not state.track then return end

    local ok_guid, track_guid = pcall(function() return state.track:get_guid() end)
    if not ok_guid or not track_guid then return end

    local key = "DisplayNames_" .. track_guid
    local ok, serialized = r.GetProjExtState(0, "SideFX", key)

    -- ok is the length of the value (0 if not found), serialized is the actual value
    if ok == 0 or not serialized or serialized == "" then
        state.display_names = {}
        return
    end

    -- Parse serialized data
    state.display_names = {}
    for pair in serialized:gmatch("([^|]+)") do
        local guid, name = pair:match("^([^=]+)=(.+)$")
        if guid and name then
            -- Unescape special characters
            name = name:gsub("%%PIPE%%", "|"):gsub("%%EQ%%", "=")
            state.display_names[guid] = name
        end
    end
end

--------------------------------------------------------------------------------
-- Configuration Management
--------------------------------------------------------------------------------

--- Save user configuration to ExtState
function M.save_config()
    local parts = {}
    table.insert(parts, string.format("max_visible_params:%d", state.config.max_visible_params))
    table.insert(parts, string.format("show_track_name:%s", state.config.show_track_name and "true" or "false"))
    table.insert(parts, string.format("show_breadcrumbs:%s", state.config.show_breadcrumbs and "true" or "false"))
    table.insert(parts, string.format("icon_font_size:%d", state.config.icon_font_size or 1))
    table.insert(parts, string.format("auto_refresh:%s", state.config.auto_refresh and "true" or "false"))
    table.insert(parts, string.format("remember_window_pos:%s", state.config.remember_window_pos and "true" or "false"))
    table.insert(parts, string.format("gain_target_db:%.2f", state.config.gain_target_db or -12.0))
    table.insert(parts, string.format("gain_tolerance_db:%.2f", state.config.gain_tolerance_db or 1.0))
    
    local config_str = table.concat(parts, ",")
    r.SetProjExtState(0, "SideFX", "Config", config_str)
end

--- Load user configuration from ExtState
function M.load_config()
    local ok, config_str = r.GetProjExtState(0, "SideFX", "Config")
    if ok > 0 and config_str and config_str ~= "" then
        -- Parse config string (format: "key1:value1,key2:value2,...")
        for pair in config_str:gmatch("([^,]+)") do
            local key, value = pair:match("^([^:]+):(.+)$")
            if key == "max_visible_params" then
                local max = tonumber(value)
                if max and max >= 1 and max <= 128 then
                    state.config.max_visible_params = max
                end
            elseif key == "show_track_name" then
                state.config.show_track_name = (value == "true")
            elseif key == "show_breadcrumbs" then
                state.config.show_breadcrumbs = (value == "true")
            elseif key == "icon_font_size" then
                local size = tonumber(value)
                if size and size >= 0 and size <= 2 then
                    state.config.icon_font_size = size
                end
            elseif key == "auto_refresh" then
                state.config.auto_refresh = (value == "true")
            elseif key == "remember_window_pos" then
                state.config.remember_window_pos = (value == "true")
            elseif key == "gain_target_db" then
                local db = tonumber(value)
                if db and db >= -24.0 and db <= 0.0 then
                    state.config.gain_target_db = db
                end
            elseif key == "gain_tolerance_db" then
                local tol = tonumber(value)
                if tol and tol >= 0.5 and tol <= 3.0 then
                    state.config.gain_tolerance_db = tol
                end
            end
        end
    end
end

--- Get maximum visible parameters (capped at 128)
-- @return number Max params (1-128)
function M.get_max_visible_params()
    local max = state.config.max_visible_params or 64
    -- Ensure it's within valid range
    if max < 1 then max = 64
    elseif max > 128 then max = 128
    end
    return max
end

--- Set maximum visible parameters
-- @param max number Maximum params (1-128)
function M.set_max_visible_params(max)
    if max < 1 then max = 1
    elseif max > 128 then max = 128
    end
    state.config.max_visible_params = max
    M.save_config()
end

--------------------------------------------------------------------------------
-- SideFX Track Detection
--------------------------------------------------------------------------------

--- Check if a track is a SideFX track (has SideFX containers/plugins).
-- Uses ExtState cache for fast lookup, falls back to scanning FX chain.
-- @param track Track|MediaTrack Track object or MediaTrack pointer
-- @param cache_result boolean|nil If true, cache result in ExtState (default: true)
-- @return boolean True if track is a SideFX track
function M.is_sidefx_track(track, cache_result)
    if not track then return false end
    
    -- Get track GUID (stable identifier)
    local track_guid = nil
    if type(track) == "userdata" then
        -- Raw MediaTrack pointer - need to get GUID via ReaWrap
        local Track = require('track')
        local track_obj = Track:new(track)
        local ok, guid = pcall(function() return track_obj:get_guid() end)
        if ok and guid then track_guid = guid end
    else
        -- ReaWrap Track object
        local ok, guid = pcall(function() return track:get_guid() end)
        if ok and guid then track_guid = guid end
    end
    
    if not track_guid then return false end
    
    -- Check ExtState cache first (fast lookup)
    local cache_key = "SideFX_Track_" .. track_guid
    local ok, cached = r.GetProjExtState(0, "SideFX", cache_key)
    if ok > 0 and cached == "1" then
        return true
    elseif ok > 0 and cached == "0" then
        return false
    end
    
    -- Cache miss - scan FX chain for SideFX plugins
    local is_sidefx = false
    
    -- Get Track object for iteration
    local track_obj = track
    if type(track) == "userdata" then
        local Track = require('track')
        track_obj = Track:new(track)
    end
    
    -- Check for SideFX JSFX plugins (definitive markers)
    local track_detection = require('lib.utils.track_detection')
    local ok_scan = pcall(function()
        for entry in track_obj:iter_all_fx_flat() do
            local fx = entry.fx
            local ok_name, name = pcall(function() return fx:get_name() end)
            if ok_name and name then
                -- Use track_detection utility for consistent detection
                if track_detection.is_sidefx_fx_name(name) then
                    is_sidefx = true
                    break
                end
            end
        end
    end)
    
    -- Cache result if requested (default: true)
    if cache_result ~= false then
        r.SetProjExtState(0, "SideFX", cache_key, is_sidefx and "1" or "0")
    end
    
    return is_sidefx
end

--------------------------------------------------------------------------------
-- FX Chain Protection
--------------------------------------------------------------------------------

--- Capture a snapshot of the current FX chain state.
-- Called when window opens to detect external modifications.
function M.capture_fx_chain_snapshot()
    if not state.track then
        state.fx_chain_snapshot = nil
        state.fx_chain_changed = false
        return
    end
    
    local snapshot = {
        count = 0,
        guids = {},
        names = {},
        timestamp = r.time_precise(),
    }
    
    -- Safely capture all top-level FX
    local ok = pcall(function()
        for fx in state.track:iter_track_fx_chain() do
            local parent = fx:get_parent_container()
            if not parent then
                local guid = fx:get_guid()
                local name = fx:get_name()
                snapshot.count = snapshot.count + 1
                snapshot.guids[snapshot.count] = guid
                snapshot.names[snapshot.count] = name
            end
        end
    end)
    
    if ok and snapshot.count > 0 then
        state.fx_chain_snapshot = snapshot
        state.fx_chain_changed = false
        -- Debug: log snapshot capture
        if state.show_debug then
            r.ShowConsoleMsg(string.format("SideFX: Captured FX chain snapshot (%d FX)\n", snapshot.count))
        end
    else
        state.fx_chain_snapshot = nil
        state.fx_chain_changed = false
        if state.show_debug then
            r.ShowConsoleMsg("SideFX: No snapshot captured (no FX or error)\n")
        end
    end
end

--- Check if FX chain has been modified externally (every 500ms).
-- @return boolean True if changes detected
function M.check_fx_chain_changes()
    -- Only check every 500ms to avoid performance issues
    local current_time = r.time_precise() * 1000  -- Convert to ms
    if current_time - state.last_chain_check_time < 500 then
        return state.fx_chain_changed
    end
    state.last_chain_check_time = current_time
    
    if not state.track or not state.fx_chain_snapshot then
        state.fx_chain_changed = false
        return false
    end
    
    -- Get current FX chain state
    local current = {
        count = 0,
        guids = {},
        names = {},
    }
    
    local ok = pcall(function()
        for fx in state.track:iter_track_fx_chain() do
            local parent = fx:get_parent_container()
            if not parent then
                local guid = fx:get_guid()
                local name = fx:get_name()
                current.count = current.count + 1
                current.guids[current.count] = guid
                current.names[current.count] = name
            end
        end
    end)
    
    if not ok then
        -- Track may have been deleted
        state.fx_chain_changed = false
        return false
    end
    
    local snapshot = state.fx_chain_snapshot
    
    -- Check for changes: count, order, or names
    if current.count ~= snapshot.count then
        state.fx_chain_changed = true
        if state.show_debug then
            r.ShowConsoleMsg(string.format("SideFX: FX count changed (%d -> %d)\n", snapshot.count, current.count))
        end
        return true
    end
    
    -- Check order and names
    for i = 1, current.count do
        if current.guids[i] ~= snapshot.guids[i] then
            -- Order changed
            state.fx_chain_changed = true
            if state.show_debug then
                r.ShowConsoleMsg(string.format("SideFX: FX order changed at index %d\n", i))
            end
            return true
        end
        if current.names[i] ~= snapshot.names[i] then
            -- Name changed (could be rename or replacement)
            state.fx_chain_changed = true
            if state.show_debug then
                r.ShowConsoleMsg(string.format("SideFX: FX name changed at index %d (%s -> %s)\n", i, snapshot.names[i], current.names[i]))
            end
            return true
        end
    end
    
    -- No changes detected
    state.fx_chain_changed = false
    return false
end

--- Revert FX chain to snapshot state.
-- This is a soft lock - we warn but don't actually prevent changes.
-- For now, we just refresh SideFX to match current state.
function M.revert_fx_chain_changes()
    -- For now, "revert" means refresh SideFX to match current REAPER state
    -- A true revert would require storing the full track chunk, which is complex
    -- So we just refresh and update the snapshot
    M.refresh_fx_list()
    M.capture_fx_chain_snapshot()
    state.fx_chain_changed = false
end

--- Refresh SideFX to match current REAPER state.
function M.refresh_sidefx_from_reaper()
    M.refresh_fx_list()
    M.capture_fx_chain_snapshot()
    state.fx_chain_changed = false
end

--- Refresh FX list and update snapshot (for SideFX operations).
-- Call this after SideFX makes changes to prevent false warnings.
function M.refresh_fx_list_and_update_snapshot()
    M.refresh_fx_list()
    M.capture_fx_chain_snapshot()
endr.SetProjExtState(0, "SideFX", cache_key, is_sidefx and "1" or "0")
    end
    
    return is_sidefx
end

--- Mark a track as a SideFX track in ExtState.
-- Call this when creating SideFX structures to update the cache.
-- @param track Track|MediaTrack Track object or MediaTrack pointer
function M.mark_track_as_sidefx(track)
    if not track then return end
    
    local track_guid = nil
    if type(track) == "userdata" then
        local Track = require('track')
        local track_obj = Track:new(track)
        local ok, guid = pcall(function() return track_obj:get_guid() end)
        if ok and guid then track_guid = guid end
    else
        local ok, guid = pcall(function() return track:get_guid() end)
        if ok and guid then track_guid = guid end
    end
    
    if track_guid then
        local cache_key = "SideFX_Track_" .. track_guid
        r.SetProjExtState(0, "SideFX", cache_key, "1")
    end
end

--- Clear SideFX track cache for a track (e.g., when converting away from SideFX).
-- @param track Track|MediaTrack Track object or MediaTrack pointer
function M.clear_sidefx_track_cache(track)
    if not track then return end
    
    local track_guid = nil
    if type(track) == "userdata" then
        local Track = require('track')
        local track_obj = Track:new(track)
        local ok, guid = pcall(function() return track_obj:get_guid() end)
        if ok and guid then track_guid = guid end
    else
        local ok, guid = pcall(function() return track:get_guid() end)
        if ok and guid then track_guid = guid end
    end
    
    if track_guid then
        local cache_key = "SideFX_Track_" .. track_guid
        r.SetProjExtState(0, "SideFX", cache_key, "")
    end
end

return M
