--- Reaper 7 Container API helpers.
-- Provides container utilities working with ReaWrap TrackFX objects.
-- @module container
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

--------------------------------------------------------------------------------
-- Container Query Functions (using ReaWrap TrackFX)
--------------------------------------------------------------------------------

--- Get a named config parameter from an FX.
-- @param fx TrackFX ReaWrap FX object
-- @param param_name string Parameter name
-- @return string|nil Value or nil if not found
function M.get_param(fx, param_name)
    local ok, value = pcall(function()
        return fx:get_named_config_param(param_name)
    end)
    return ok and value or nil
end

--- Set a named config parameter on an FX.
-- @param fx TrackFX ReaWrap FX object
-- @param param_name string Parameter name
-- @param value string Value to set
-- @return boolean Success
function M.set_param(fx, param_name, value)
    local ok = pcall(function()
        return fx:set_named_config_param(param_name, tostring(value))
    end)
    return ok
end

--- Check if an FX is a container.
-- @param fx TrackFX ReaWrap FX object
-- @return boolean
function M.is_container(fx)
    local ok, is_cont = pcall(function() return fx:is_container() end)
    return ok and is_cont
end

--- Get the number of FX in a container.
-- @param container TrackFX Container FX object
-- @return number Count (0 if not a container)
function M.get_child_count(container)
    local ok, count = pcall(function() return container:get_container_child_count() end)
    return ok and count or 0
end

--- Get child FX from a container.
-- @param container TrackFX Container FX object
-- @return table Array of TrackFX objects
function M.get_children(container)
    local children = {}
    local ok = pcall(function()
        for child in container:iter_container_children() do
            children[#children + 1] = child
        end
    end)
    return children
end

--- Get the parent container of an FX.
-- @param fx TrackFX ReaWrap FX object
-- @return TrackFX|nil Parent container, or nil if top-level
function M.get_parent(fx)
    local ok, parent = pcall(function() return fx:get_parent_container() end)
    return ok and parent or nil
end

--- Get FX type string.
-- @param fx TrackFX ReaWrap FX object
-- @return string|nil FX type (e.g., "VST", "VST3", "JS", "Container")
function M.get_fx_type(fx)
    return M.get_param(fx, "fx_type")
end

--- Get FX name.
-- @param fx TrackFX ReaWrap FX object
-- @return string FX name
function M.get_fx_name(fx)
    local ok, name = pcall(function() return fx:get_name() end)
    return ok and name or "Unknown"
end

--------------------------------------------------------------------------------
-- Container Channel Routing
--------------------------------------------------------------------------------

--- Get container internal channel count.
-- @param container TrackFX Container FX object
-- @return number Channel count
function M.get_channel_count(container)
    local ok, nch = pcall(function() return container:get_container_channels() end)
    return ok and nch or 2
end

--- Set container internal channel count.
-- @param container TrackFX Container FX object
-- @param channels number Channel count (2, 4, 6, 8, etc.)
-- @return boolean Success
function M.set_channel_count(container, channels)
    local ok = pcall(function()
        return container:set_container_channels(channels)
    end)
    return ok
end

--- Get container input pin count.
-- @param container TrackFX Container FX object
-- @return number Input pin count
function M.get_input_pins(container)
    local val = M.get_param(container, "container_nch_in")
    return val and tonumber(val) or 2
end

--- Set container input pin count.
-- @param container TrackFX Container FX object
-- @param pins number Input pin count
-- @return boolean Success
function M.set_input_pins(container, pins)
    return M.set_param(container, "container_nch_in", pins)
end

--- Get container output pin count.
-- @param container TrackFX Container FX object
-- @return number Output pin count
function M.get_output_pins(container)
    local val = M.get_param(container, "container_nch_out")
    return val and tonumber(val) or 2
end

--- Set container output pin count.
-- @param container TrackFX Container FX object
-- @param pins number Output pin count
-- @return boolean Success
function M.set_output_pins(container, pins)
    return M.set_param(container, "container_nch_out", pins)
end

--------------------------------------------------------------------------------
-- Container Creation & Manipulation (using ReaWrap Track)
--------------------------------------------------------------------------------

--- Create an empty container on a track.
-- @param track Track ReaWrap Track object
-- @param position number|nil Insert position (nil = end of chain)
-- @return TrackFX|nil Container FX object, or nil on failure
function M.create(track, position)
    local ok, container = pcall(function()
        return track:add_fx_by_name("Container", false, position or -1)
    end)
    return ok and container or nil
end

--- Move an FX into a container.
-- @param fx TrackFX FX to move
-- @param container TrackFX Destination container
-- @param position number|nil Position within container (nil = end)
-- @return boolean Success
function M.move_fx_to_container(fx, container, position)
    local ok = pcall(function()
        return container:add_fx_to_container(fx, position)
    end)
    return ok
end

--- Move an FX out of its container to track level.
-- @param fx TrackFX FX to move
-- @param position number|nil Position at track level (nil = end)
-- @return boolean Success
function M.move_fx_out_of_container(fx, position)
    local ok = pcall(function()
        return fx:move_out_of_container(position)
    end)
    return ok
end

--------------------------------------------------------------------------------
-- Container Traversal
--------------------------------------------------------------------------------

--- Iterate over all FX in a container (non-recursive).
-- @param container TrackFX Container FX object
-- @return function Iterator yielding (fx, position)
function M.iter_children(container)
    local children = M.get_children(container)
    local i = 0
    return function()
        i = i + 1
        if children[i] then
            return children[i], i
        end
    end
end

--- Get container hierarchy info for an FX.
-- @param fx TrackFX ReaWrap FX object
-- @return table {depth: number, path: table of parent FX objects}
function M.get_hierarchy(fx)
    local path = {}
    local current = fx
    local depth = 0
    
    while true do
        local parent = M.get_parent(current)
        if not parent then
            break
        end
        depth = depth + 1
        table.insert(path, 1, parent)
        current = parent
    end
    
    return {
        depth = depth,
        path = path
    }
end

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

--- Get a flat list of all FX on a track (including inside containers).
-- @param track Track ReaWrap Track object
-- @return table Array of {fx, name, is_container, depth}
function M.get_all_fx_flat(track)
    local result = {}
    
    local function add_fx(fx, depth)
        local name = M.get_fx_name(fx)
        local is_cont = M.is_container(fx)
        
        result[#result + 1] = {
            fx = fx,
            name = name,
            is_container = is_cont,
            depth = depth
        }
        
        if is_cont then
            for child in M.iter_children(fx) do
                add_fx(child, depth + 1)
            end
        end
    end
    
    for fx in track:iter_track_fx_chain() do
        -- Only add top-level FX (those without a parent)
        if not M.get_parent(fx) then
            add_fx(fx, 0)
        end
    end
    
    return result
end

--- Print container structure to console (debug).
-- @param track Track ReaWrap Track object
function M.debug_print_structure(track)
    local indent = "  "
    for _, item in ipairs(M.get_all_fx_flat(track)) do
        local prefix = string.rep(indent, item.depth)
        local suffix = item.is_container and " [Container]" or ""
        r.ShowConsoleMsg(string.format("%s%s%s\n", prefix, item.name, suffix))
    end
end

return M
