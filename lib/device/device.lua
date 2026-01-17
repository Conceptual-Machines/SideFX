--- SideFX Device Operations.
-- Functions for adding plugins wrapped in D-containers.
-- @module device
-- @author Nomad Monad
-- @license MIT

local r = reaper

local naming = require('lib.utils.naming')
local fx_utils = require('lib.fx.fx_utils')
local state_module = require('lib.core.state')

local M = {}

-- Local reference to state singleton
local state = state_module.state

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

M.UTILITY_JSFX = "JS:SideFX/Utils/SideFX_Utility"
M.MODULATOR_JSFX = "JS:SideFX/Utils/SideFX_Modulator"

--------------------------------------------------------------------------------
-- Device Creation
--------------------------------------------------------------------------------

--- Add a plugin to the track wrapped in a D-container.
-- @param plugin table Plugin info {full_name, name}
-- @param position number|nil Insert position (nil = end of chain)
-- @param opts table|nil Options: {bare = true} to skip adding utility (for analyzers)
-- @return TrackFX|nil Device container (or raw FX for modulators)
function M.add_plugin_to_track(plugin, position, opts)
    if not state.track then return end
    opts = opts or {}

    local name_lower = plugin.full_name:lower()

    -- Don't wrap modulators in containers
    if name_lower:find("sidefx_modulator") then
        r.Undo_BeginBlock()
        local fx_position = position and (-1000 - position) or -1
        local fx = state.track:add_fx_by_name(plugin.full_name, false, fx_position)
        r.Undo_EndBlock("SideFX: Add Modulator", -1)
        return fx
    end

    -- Don't wrap utilities in containers (shouldn't be added directly anyway)
    if name_lower:find("sidefx_utility") then
        return nil
    end

    -- Don't wrap mixer in containers (it should only be added by rack creation)
    if name_lower:find("sidefx_mixer") or name_lower:find("sidefx chain mixer") then
        return nil
    end

    -- Bare mode: add raw plugin without D-container (for analyzers, etc.)
    if opts.bare then
        r.Undo_BeginBlock()
        local fx_position = position and (-1000 - position) or -1
        local fx = state.track:add_fx_by_name(plugin.full_name, false, fx_position)
        if fx and fx.pointer >= 0 then
            local short_name = naming.get_short_plugin_name(plugin.full_name)
            local device_name
            if opts.post then
                -- Post FX device (at end of chain)
                local post_idx = fx_utils.get_next_post_device_index(state.track)
                device_name = naming.build_post_device_name(post_idx, short_name)
            else
                -- Regular bare device
                local bare_idx = fx_utils.get_next_bare_device_index(state.track)
                device_name = naming.build_bare_device_name(bare_idx, short_name)
            end
            fx:set_named_config_param("renamed_name", device_name)
        end
        r.Undo_EndBlock(opts.post and "SideFX: Add Post FX" or "SideFX: Add Plugin (bare)", -1)
        return fx
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get next device index
    local device_idx = fx_utils.get_next_device_index(state.track)
    local short_name = naming.get_short_plugin_name(plugin.full_name)
    local container_name = naming.build_device_name(device_idx, short_name)

    -- Position for the container
    local container_position = position and (-1000 - position) or -1

    -- Create the container first
    local container = state.track:add_fx_by_name("Container", false, container_position)

    if container and container.pointer >= 0 then
        -- Rename the container
        container:set_named_config_param("renamed_name", container_name)

        -- Add the main FX at track level first
        local main_fx = state.track:add_fx_by_name(plugin.full_name, false, -1)

        if main_fx and main_fx.pointer >= 0 then
            -- Move the FX into the container
            container:add_fx_to_container(main_fx, 0)

            -- Re-find the FX inside the container (pointer changed after move)
            local fx_inside = fx_utils.get_device_main_fx(container)

            if fx_inside then
                -- Store the original plugin name by GUID for later lookup
                local fx_guid = fx_inside:get_guid()
                if fx_guid then
                    local state_mod = require('lib.core.state')
                    state_mod.set_fx_original_name(fx_guid, plugin.full_name)
                end

                -- Set wet/dry to 100% by default
                local wet_idx = fx_inside:get_param_from_ident(":wet")
                if wet_idx >= 0 then
                    fx_inside:set_param_normalized(wet_idx, 1.0)
                end
                -- Rename FX with _FX suffix to distinguish from container
                local fx_name = naming.build_device_fx_name(device_idx, short_name)
                fx_inside:set_named_config_param("renamed_name", fx_name)
            end

            -- Add utility at track level, then move into container
            local util_fx = state.track:add_fx_by_name(M.UTILITY_JSFX, false, -1)

            if not util_fx or util_fx.pointer < 0 then
                r.ShowConsoleMsg("SideFX: Could not add utility JSFX. Make sure SideFX_Utility.jsfx is installed.\n")
            else
                -- Move utility into container at position 1
                container:add_fx_to_container(util_fx, 1)

                -- Re-find utility inside container and rename it
                local util_inside = fx_utils.get_device_utility(container)
                if util_inside then
                    local util_name = naming.build_device_util_name(device_idx)
                    util_inside:set_named_config_param("renamed_name", util_name)
                    -- Initialize gain to 0dB
                    util_inside:set_param(0, 0)
                end
            end
        else
            r.ShowConsoleMsg("SideFX: Could not add FX.\n")
        end
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Device", -1)

    -- Mark track as SideFX track
    if state.track then
        state_module.mark_track_as_sidefx(state.track)
    end

    return container
end

--- Add a plugin by name to the track.
-- @param plugin_name string Full plugin name
-- @param position number|nil Insert position (nil = end of chain)
-- @return TrackFX|nil Device container
function M.add_plugin_by_name(plugin_name, position)
    if not state.track or not plugin_name then return end

    -- Create a minimal plugin object
    local plugin = { full_name = plugin_name, name = plugin_name }
    return M.add_plugin_to_track(plugin, position)
end

--------------------------------------------------------------------------------
-- Track Conversion Helpers
--------------------------------------------------------------------------------

--- Collect all top-level FX that can be converted to SideFX devices.
-- @param track Track object to scan
-- @return table, boolean, boolean {top_level_fx, has_containers, has_nested_fx}
local function collect_top_level_fx_for_conversion(track)
    local top_level_fx = {}
    local has_containers = false
    local has_nested_fx = false

    local ok_iter = pcall(function()
        for fx in track:iter_track_fx_chain() do
            local parent = fx:get_parent_container()
            if not parent then
                -- Get FX info before we start moving things
                local ok_name, fx_name = pcall(function() return fx:get_name() end)
                local ok_guid, fx_guid = pcall(function() return fx:get_guid() end)
                local ok_is_container, is_container = pcall(function() return fx:is_container() end)

                if ok_name and ok_guid and fx_name and fx_guid then
                    -- Check if it's a container (could be non-SideFX container)
                    if ok_is_container and is_container then
                        has_containers = true
                        -- Check if container has children (nested structure)
                        local ok_children, children = pcall(function()
                            local children_list = {}
                            for child in fx:iter_container_children() do
                                table.insert(children_list, child)
                            end
                            return children_list
                        end)
                        if ok_children and children and #children > 0 then
                            has_nested_fx = true
                        end
                    end

                    -- Skip SideFX JSFX plugins (they shouldn't be top-level anyway)
                    local name_lower = fx_name:lower()
                    if not name_lower:find("sidefx_mixer") and
                       not name_lower:find("sidefx_utility") and
                       not name_lower:find("sidefx_modulator") then
                        -- Skip if already in a SideFX container (check naming pattern)
                        local is_sidefx_container = fx_name:match("^D%d+") or
                                                   fx_name:match("^R%d+") or
                                                   fx_name:match("^C%d+")
                        if not is_sidefx_container then
                            table.insert(top_level_fx, {
                                fx = fx,
                                guid = fx_guid,
                                name = fx_name,
                                is_container = ok_is_container and is_container or false,
                            })
                        end
                    end
                end
            else
                -- FX is nested in a container - this is a complicated case
                has_nested_fx = true
            end
        end
    end)

    if not ok_iter then
        return nil, false, false
    end

    return top_level_fx, has_containers, has_nested_fx
end

--- Check if a container FX has children.
-- @param fx TrackFX object (must be a container)
-- @return boolean True if container has children
local function container_has_children(fx)
    local ok, has_children = pcall(function()
        local child_count = 0
        for _ in fx:iter_container_children() do
            child_count = child_count + 1
            if child_count > 0 then
                return true
            end
        end
        return false
    end)
    return ok and has_children or false
end

--- Convert a single FX to a SideFX device container.
-- @param fx_info table FX info {fx, guid, name, is_container}
-- @param device_idx number Device index to use
-- @return boolean True if conversion succeeded
local function convert_single_fx_to_device(fx_info, device_idx)
    -- Re-find FX by GUID (indices may have shifted)
    local fx = state.track:find_fx_by_guid(fx_info.guid)
    if not fx then
        -- FX was deleted or moved, skip
        return false
    end

    -- Check if this is a container with children (complicated case)
    if fx_info.is_container then
        if container_has_children(fx) then
            -- Container with children - can't convert easily
            return false
        end
    end

    -- Get FX name and short name
    local ok_name, fx_name = pcall(function() return fx:get_name() end)
    if not ok_name or not fx_name then
        return false
    end

    local short_name = naming.get_short_plugin_name(fx_name)
    local container_name = naming.build_device_name(device_idx, short_name)
    local fx_name_renamed = naming.build_device_fx_name(device_idx, short_name)
    local util_name = naming.build_device_util_name(device_idx)

    -- Get original position (before we create container)
    local original_idx = fx.pointer
    local container_position = original_idx >= 0 and (-1000 - original_idx) or -1

    -- Create container at the original position
    local container = state.track:add_fx_by_name("Container", false, container_position)
    if not container or container.pointer < 0 then
        return false
    end

    -- Rename container
    container:set_named_config_param("renamed_name", container_name)

    -- Re-find FX by GUID (indices shifted after container creation)
    fx = state.track:find_fx_by_guid(fx_info.guid)
    if not fx then
        -- FX disappeared, clean up container
        container:delete()
        return false
    end

    -- Move FX into container
    local ok_move = pcall(function()
        container:add_fx_to_container(fx, 0)
    end)

    if not ok_move then
        container:delete()
        return false
    end

    -- Re-find FX inside container and rename it
    local fx_inside = fx_utils.get_device_main_fx(container)
    if fx_inside then
        -- Set wet/dry to 100% by default
        local wet_idx = fx_inside:get_param_from_ident(":wet")
        if wet_idx and wet_idx >= 0 then
            fx_inside:set_param_normalized(wet_idx, 1.0)
        end
        -- Rename FX
        fx_inside:set_named_config_param("renamed_name", fx_name_renamed)
    end

    -- Add utility to container
    local util_fx = state.track:add_fx_by_name(M.UTILITY_JSFX, false, -1)
    if util_fx and util_fx.pointer >= 0 then
        container:add_fx_to_container(util_fx, 1)

        local util_inside = fx_utils.get_device_utility(container)
        if util_inside then
            util_inside:set_named_config_param("renamed_name", util_name)
            -- Initialize gain to 0dB (use raw dB value, not normalized)
            util_inside:set_param(0, 0)
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Track Conversion
--------------------------------------------------------------------------------

--- Convert a non-SideFX track to a SideFX track by wrapping existing FX in D-containers.
-- @return boolean True if conversion was successful
function M.convert_track_to_sidefx()
    if not state.track then
        r.ShowMessageBox("No track selected for conversion.", "SideFX", 0)
        return false
    end

    -- Check if track already is a SideFX track
    if state_module.is_sidefx_track(state.track) then
        r.ShowMessageBox("Track is already a SideFX track.", "SideFX", 0)
        return false
    end

    -- Get all top-level FX
    local top_level_fx, has_containers, has_nested_fx = collect_top_level_fx_for_conversion(state.track)

    if not top_level_fx then
        r.ShowMessageBox("Can't convert to SideFX - error reading track FX.", "SideFX", 0)
        return false
    end

    -- Handle edge cases where conversion is not straightforward
    if has_nested_fx and has_containers then
        r.ShowMessageBox("Can't convert to SideFX - track has nested containers.", "SideFX", 0)
        return false
    end

    if #top_level_fx == 0 then
        r.ShowMessageBox("No FX to convert on this track.", "SideFX", 0)
        return false
    end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local converted_count = 0
    local device_idx = fx_utils.get_next_device_index(state.track)

    -- Convert each FX
    for _, fx_info in ipairs(top_level_fx) do
        local success = convert_single_fx_to_device(fx_info, device_idx)

        if not success then
            -- Check if it was a container with children (specific error case)
            if fx_info.is_container then
                local fx = state.track:find_fx_by_guid(fx_info.guid)
                if fx and container_has_children(fx) then
                    r.PreventUIRefresh(-1)
                    r.Undo_EndBlock("SideFX: Convert Track to SideFX (failed)", -1)
                    r.ShowMessageBox("Can't convert to SideFX - track has containers with nested FX.", "SideFX", 0)
                    return false
                end
            end

            -- Generic failure - clean up and abort
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("SideFX: Convert Track to SideFX (failed)", -1)
            r.ShowMessageBox("Can't convert to SideFX - failed to convert FX.", "SideFX", 0)
            return false
        end

        converted_count = converted_count + 1
        device_idx = device_idx + 1
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock(string.format("SideFX: Convert Track to SideFX (%d FX converted)", converted_count), -1)

    -- Mark track as SideFX track
    if converted_count > 0 then
        state_module.mark_track_as_sidefx(state.track)
        -- Refresh FX list to show new structure
        state_module.refresh_fx_list()
        return true
    else
        r.ShowMessageBox("No FX were converted.", "SideFX", 0)
        return false
    end
end

return M
