--- SideFX State Management.
-- Centralized state and track/FX helper functions.
-- @module state
-- @author Nomad Monad
-- @license MIT

local r = reaper
local Project = require('project')
local config_mod = require('lib.core.config')
local json = require('lib.utils.json')

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
    
    -- Missing utilities: track devices with missing utility FX
    missing_utilities = {},  -- {[container_guid] = true}

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
    

    -- Plugin browser state
    browser = {
        search = "",
        filter = "all",
        plugins = {},
        filtered = {},
        scanned = false,
        visible = true,  -- Browser panel visibility
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

    -- Parameter unit overrides (keyed by plugin full_name, then param_idx)
    -- nil or "auto" = auto-detect, otherwise specific unit ID
    param_unit_overrides = {},  -- {[plugin_full_name] = {[param_idx] = "dB", ...}}

    -- Original plugin names (keyed by FX GUID)
    -- Used to look up the original name when FX has been renamed
    fx_original_names = {},  -- {[fx_guid] = "VST3i: Serum 2 (Xfer Records)"}
    
    -- Analyzer popout state
    scope_popout = false,     -- Oscilloscope in separate window
    spectrum_popout = false,  -- Spectrum in separate window

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

--- Mark FX list as needing refresh (deferred to next frame).
-- Use this when adding/removing FX during render to avoid stale pointer issues.
function M.invalidate_fx_list()
    state.fx_list_invalid = true
end

--- Check if FX list is invalid and refresh if so.
-- Call this at the start of each frame.
-- @return boolean True if list was refreshed
function M.check_fx_list_validity()
    if state.fx_list_invalid then
        state.fx_list_invalid = false
        M.refresh_fx_list()
        return true
    end
    return false
end

--- Process any pending modulator additions.
-- Called at the start of each frame, before rendering.
-- Modulator additions are deferred to avoid stale pointer issues during render.
function M.process_pending_modulator_adds()
    if not state.pending_modulator_add or #state.pending_modulator_add == 0 then
        return
    end

    local track = state.track
    if not track then
        state.pending_modulator_add = nil
        return
    end

    -- Copy and clear pending list FIRST to prevent re-entrancy issues
    local pending_list = state.pending_modulator_add
    state.pending_modulator_add = nil

    -- Process all pending additions (wrapped in pcall for safety)
    local ok, err = pcall(function()
        local modulator_module = require('lib.modulator.modulator')

        for _, pending in ipairs(pending_list) do
            -- Find container by GUID (safe - returns nil if not found)
            local container = track:find_fx_by_guid(pending.container_guid)
            if container then
                local new_mod = modulator_module.add_modulator_to_device(container, pending.modulator_type, track)
                if new_mod then
                    -- Store selection for after refresh (safely get GUID)
                    local ok_guid, new_mod_guid = pcall(function() return new_mod:get_guid() end)
                    if ok_guid and new_mod_guid then
                        state.pending_mod_selection = state.pending_mod_selection or {}
                        state.pending_mod_selection[pending.state_guid] = {
                            container_guid = pending.container_guid,
                            mod_guid = new_mod_guid
                        }
                    end
                end
            end
        end
    end)

    if not ok then
        reaper.ShowConsoleMsg("SideFX: Error adding modulator: " .. tostring(err) .. "\n")
    end

    -- Always refresh FX list after attempting additions
    M.refresh_fx_list()
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
-- Breadcrumb Selection Path
--------------------------------------------------------------------------------

--- Set selection to a rack (clears deeper selections).
-- @param rack_guid string Rack GUID
function M.select_rack(rack_guid)
    state.expanded_path = { rack_guid }
end

--- Set selection to a chain within a rack.
-- @param rack_guid string Rack GUID
-- @param chain_guid string Chain GUID
function M.select_chain(rack_guid, chain_guid)
    state.expanded_path = { rack_guid, chain_guid }
end

--- Set selection to a device within a chain.
-- @param rack_guid string Rack GUID
-- @param chain_guid string Chain GUID
-- @param device_guid string Device GUID
function M.select_device(rack_guid, chain_guid, device_guid)
    state.expanded_path = { rack_guid, chain_guid, device_guid }
end

--- Set selection to a standalone device (not in a rack/chain).
-- @param device_guid string Device GUID
function M.select_standalone_device(device_guid)
    state.expanded_path = { device_guid }
end

--- Clear the selection path (back to top level).
function M.clear_selection()
    state.expanded_path = {}
end

--- Get the current selection path.
-- @return table Array of GUIDs representing the selection hierarchy
function M.get_selection_path()
    return state.expanded_path
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
-- Syncs state.config to config module and persists
function M.save_config()
    -- Sync state.config to config module
    config_mod.set_many({
        max_visible_params = state.config.max_visible_params,
        show_track_name = state.config.show_track_name,
        show_breadcrumbs = state.config.show_breadcrumbs,
        icon_font_size = state.config.icon_font_size,
        auto_refresh = state.config.auto_refresh,
        remember_window_pos = state.config.remember_window_pos,
        gain_target_db = state.config.gain_target_db,
        gain_tolerance_db = state.config.gain_tolerance_db,
    })
end

--- Load user configuration from ExtState
-- Loads from config module and syncs to state.config
function M.load_config()
    config_mod.load()
    -- Sync config module values to state.config
    state.config.max_visible_params = config_mod.get('max_visible_params')
    state.config.show_track_name = config_mod.get('show_track_name')
    state.config.show_breadcrumbs = config_mod.get('show_breadcrumbs')
    state.config.icon_font_size = config_mod.get('icon_font_size')
    state.config.auto_refresh = config_mod.get('auto_refresh')
    state.config.remember_window_pos = config_mod.get('remember_window_pos')
    state.config.gain_target_db = config_mod.get('gain_target_db')
    state.config.gain_tolerance_db = config_mod.get('gain_tolerance_db')
end

--------------------------------------------------------------------------------
-- Parameter Selections Persistence
--------------------------------------------------------------------------------

--- Save parameter selections to ExtState (global, not per-project)
function M.save_param_selections()
    if not state.param_selections or next(state.param_selections) == nil then
        r.SetExtState("SideFX", "ParamSelections", "", true)
        return
    end

    local json_str = json.encode(state.param_selections)
    if json_str then
        r.SetExtState("SideFX", "ParamSelections", json_str, true)
    end
end

--- Load parameter selections from ExtState
function M.load_param_selections()
    local json_str = r.GetExtState("SideFX", "ParamSelections")
    if json_str and json_str ~= "" then
        local parsed = json.decode(json_str)
        if parsed and type(parsed) == "table" then
            state.param_selections = parsed
        end
    end
end

--------------------------------------------------------------------------------
-- Parameter Unit Overrides Persistence
--------------------------------------------------------------------------------

--- Save parameter unit overrides to ExtState (global, not per-project)
function M.save_param_unit_overrides()
    if not state.param_unit_overrides or next(state.param_unit_overrides) == nil then
        -- Clear storage if no overrides
        r.SetExtState("SideFX", "ParamUnitOverrides", "", true)
        return
    end

    local json_str = json.encode(state.param_unit_overrides)
    if json_str then
        r.SetExtState("SideFX", "ParamUnitOverrides", json_str, true)
    end
end

--- Load parameter unit overrides from ExtState
function M.load_param_unit_overrides()
    local json_str = r.GetExtState("SideFX", "ParamUnitOverrides")
    if json_str and json_str ~= "" then
        local parsed = json.decode(json_str)
        if parsed and type(parsed) == "table" then
            -- Convert string keys back to numbers (JSON serializes numeric keys as strings)
            state.param_unit_overrides = {}
            for plugin_name, overrides in pairs(parsed) do
                state.param_unit_overrides[plugin_name] = {}
                for param_idx_str, unit_id in pairs(overrides) do
                    local param_idx = tonumber(param_idx_str) or param_idx_str
                    state.param_unit_overrides[plugin_name][param_idx] = unit_id
                end
            end
        end
    end
end

--- Get unit override for a specific parameter
-- Tries multiple name variations (exact match, clean name, prefix variations)
-- @param plugin_name string The plugin name
-- @param param_idx number The parameter index
-- @return string|nil Unit ID or nil for auto-detect
function M.get_param_unit_override(plugin_name, param_idx)
    if not plugin_name or not param_idx then return nil end
    if not state.param_unit_overrides then return nil end

    -- Try exact match first
    if state.param_unit_overrides[plugin_name] then
        local override = state.param_unit_overrides[plugin_name][param_idx]
        if override then return override end
    end

    -- Try with stripped prefixes
    local naming = require('lib.utils.naming')
    local clean_name = naming.strip_sidefx_prefixes(plugin_name)

    if clean_name ~= plugin_name and state.param_unit_overrides[clean_name] then
        local override = state.param_unit_overrides[clean_name][param_idx]
        if override then return override end
    end

    -- Try matching stored keys against clean name
    for key, overrides in pairs(state.param_unit_overrides) do
        local key_clean = naming.strip_sidefx_prefixes(key)
        if key_clean == clean_name and overrides[param_idx] then
            return overrides[param_idx]
        end
    end

    return nil
end

--- Set unit override for a specific parameter
-- @param plugin_name string The plugin full name
-- @param param_idx number The parameter index
-- @param unit_id string|nil Unit ID or nil/auto for auto-detect
function M.set_param_unit_override(plugin_name, param_idx, unit_id)
    if not plugin_name or not param_idx then return end

    -- Normalize "auto" to nil (no override)
    if unit_id == "auto" then unit_id = nil end

    -- Initialize plugin table if needed
    if not state.param_unit_overrides then
        state.param_unit_overrides = {}
    end
    if not state.param_unit_overrides[plugin_name] then
        state.param_unit_overrides[plugin_name] = {}
    end

    -- Set or clear the override
    state.param_unit_overrides[plugin_name][param_idx] = unit_id

    -- Clean up empty plugin tables
    if next(state.param_unit_overrides[plugin_name]) == nil then
        state.param_unit_overrides[plugin_name] = nil
    end

    -- Save immediately
    M.save_param_unit_overrides()
end

--------------------------------------------------------------------------------
-- FX Original Name Storage
--------------------------------------------------------------------------------

--- Store the original plugin name for an FX by GUID
-- @param fx_guid string The FX GUID
-- @param original_name string The original plugin name (e.g., "VST3i: Serum 2 (Xfer Records)")
function M.set_fx_original_name(fx_guid, original_name)
    if not fx_guid or not original_name then return end
    if not state.fx_original_names then
        state.fx_original_names = {}
    end
    state.fx_original_names[fx_guid] = original_name
end

--- Get the original plugin name for an FX by GUID
-- @param fx_guid string The FX GUID
-- @return string|nil The original plugin name or nil
function M.get_fx_original_name(fx_guid)
    if not fx_guid then return nil end
    if not state.fx_original_names then return nil end
    return state.fx_original_names[fx_guid]
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
