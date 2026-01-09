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

M.UTILITY_JSFX = "JS:SideFX/SideFX_Utility"
M.MODULATOR_JSFX = "JS:SideFX/SideFX_Modulator"

--------------------------------------------------------------------------------
-- Device Creation
--------------------------------------------------------------------------------

--- Add a plugin to the track wrapped in a D-container.
-- @param plugin table Plugin info {full_name, name}
-- @param position number|nil Insert position (nil = end of chain)
-- @return TrackFX|nil Device container (or raw FX for modulators)
function M.add_plugin_to_track(plugin, position)
    if not state.track then return end

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

return M
