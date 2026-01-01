--- Reaper 7 Container API helpers.
-- Thin wrapper around TrackFX container functions.
-- @module container
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

--------------------------------------------------------------------------------
-- Container Query Functions
--------------------------------------------------------------------------------

--- Get a named config parameter from an FX.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @param param_name string Parameter name
-- @return string|nil Value or nil if not found
function M.get_param(track, fx_idx, param_name)
    local ok, value = r.TrackFX_GetNamedConfigParm(track, fx_idx, param_name)
    if ok then
        return value
    end
    return nil
end

--- Set a named config parameter on an FX.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @param param_name string Parameter name
-- @param value string Value to set
-- @return boolean Success
function M.set_param(track, fx_idx, param_name, value)
    return r.TrackFX_SetNamedConfigParm(track, fx_idx, param_name, tostring(value))
end

--- Check if an FX is a container.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @return boolean
function M.is_container(track, fx_idx)
    local count = M.get_param(track, fx_idx, "container_count")
    return count ~= nil
end

--- Get the number of FX in a container.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return number Count (0 if not a container)
function M.get_child_count(track, container_idx)
    local count = M.get_param(track, container_idx, "container_count")
    return count and tonumber(count) or 0
end

--- Get child FX indices from a container.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return table Array of child FX indices
function M.get_children(track, container_idx)
    local count = M.get_child_count(track, container_idx)
    local children = {}
    for i = 0, count - 1 do
        local child_id = M.get_param(track, container_idx, "container_item." .. i)
        if child_id then
            children[#children + 1] = tonumber(child_id)
        end
    end
    return children
end

--- Get the parent container of an FX.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @return number|nil Parent container index, or nil if top-level
function M.get_parent(track, fx_idx)
    local parent = M.get_param(track, fx_idx, "parent_container")
    return parent and tonumber(parent) or nil
end

--- Get FX type string.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @return string|nil FX type (e.g., "VST", "VST3", "JS", "Container")
function M.get_fx_type(track, fx_idx)
    return M.get_param(track, fx_idx, "fx_type")
end

--- Get FX name.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @return string FX name
function M.get_fx_name(track, fx_idx)
    local ok, name = r.TrackFX_GetFXName(track, fx_idx)
    return ok and name or "Unknown"
end

--- Check if an FX is an instrument (VSTi, etc).
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @return boolean
function M.is_instrument(track, fx_idx)
    local instrument_idx = r.TrackFX_GetInstrument(track)
    if instrument_idx < 0 then
        return false
    end
    -- Check if this FX or any of its parents is the instrument
    -- For now, simple check - could be enhanced
    return fx_idx == instrument_idx
end

--------------------------------------------------------------------------------
-- Container Channel Routing
--------------------------------------------------------------------------------

--- Get container internal channel count.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return number Channel count
function M.get_channel_count(track, container_idx)
    local nch = M.get_param(track, container_idx, "container_nch")
    return nch and tonumber(nch) or 2
end

--- Set container internal channel count.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @param channels number Channel count (2, 4, 6, 8, etc.)
-- @return boolean Success
function M.set_channel_count(track, container_idx, channels)
    return M.set_param(track, container_idx, "container_nch", channels)
end

--- Get container input pin count.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return number Input pin count
function M.get_input_pins(track, container_idx)
    local pins = M.get_param(track, container_idx, "container_nch_in")
    return pins and tonumber(pins) or 2
end

--- Set container input pin count.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @param pins number Input pin count
-- @return boolean Success
function M.set_input_pins(track, container_idx, pins)
    return M.set_param(track, container_idx, "container_nch_in", pins)
end

--- Get container output pin count.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return number Output pin count
function M.get_output_pins(track, container_idx)
    local pins = M.get_param(track, container_idx, "container_nch_out")
    return pins and tonumber(pins) or 2
end

--- Set container output pin count.
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @param pins number Output pin count
-- @return boolean Success
function M.set_output_pins(track, container_idx, pins)
    return M.set_param(track, container_idx, "container_nch_out", pins)
end

--------------------------------------------------------------------------------
-- Container Creation & Manipulation
--------------------------------------------------------------------------------

--- Create an empty container on a track.
-- @param track MediaTrack* Track pointer
-- @param position number|nil Insert position (nil = end of chain)
-- @return number Container FX index, or -1 on failure
function M.create(track, position)
    local insert_pos = position or -1
    return r.TrackFX_AddByName(track, "Container", false, insert_pos)
end

--- Move an FX into a container.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX to move
-- @param container_idx number Destination container
-- @param position number|nil Position within container (nil = end)
-- @return boolean Success
function M.move_fx_to_container(track, fx_idx, container_idx, position)
    -- Calculate the destination index within the container
    local child_count = M.get_child_count(track, container_idx)
    local dest_pos = position or child_count
    
    -- The destination FX index format for containers: container_idx + 0x2000000 + child_position
    local dest_idx = container_idx + 0x2000000 + dest_pos
    
    return r.TrackFX_CopyToTrack(track, fx_idx, track, dest_idx, true) -- true = move
end

--- Copy an FX into a container.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX to copy
-- @param container_idx number Destination container
-- @param position number|nil Position within container (nil = end)
-- @return boolean Success
function M.copy_fx_to_container(track, fx_idx, container_idx, position)
    local child_count = M.get_child_count(track, container_idx)
    local dest_pos = position or child_count
    local dest_idx = container_idx + 0x2000000 + dest_pos
    
    return r.TrackFX_CopyToTrack(track, fx_idx, track, dest_idx, false) -- false = copy
end

--------------------------------------------------------------------------------
-- Container Traversal
--------------------------------------------------------------------------------

--- Iterate over all FX in a container (non-recursive).
-- @param track MediaTrack* Track pointer
-- @param container_idx number Container FX index
-- @return function Iterator yielding (fx_idx, position)
function M.iter_children(track, container_idx)
    local children = M.get_children(track, container_idx)
    local i = 0
    return function()
        i = i + 1
        if children[i] then
            return children[i], i
        end
    end
end

--- Get container hierarchy info for an FX.
-- @param track MediaTrack* Track pointer
-- @param fx_idx number FX index
-- @return table {depth: number, path: table of parent indices}
function M.get_hierarchy(track, fx_idx)
    local path = {}
    local current = fx_idx
    local depth = 0
    
    while true do
        local parent = M.get_parent(track, current)
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
-- @param track MediaTrack* Track pointer
-- @return table Array of {fx_idx, name, is_container, depth}
function M.get_all_fx_flat(track)
    local result = {}
    local fx_count = r.TrackFX_GetCount(track)
    
    local function add_fx(fx_idx, depth)
        local name = M.get_fx_name(track, fx_idx)
        local is_cont = M.is_container(track, fx_idx)
        
        result[#result + 1] = {
            fx_idx = fx_idx,
            name = name,
            is_container = is_cont,
            depth = depth
        }
        
        if is_cont then
            for child_idx in M.iter_children(track, fx_idx) do
                add_fx(child_idx, depth + 1)
            end
        end
    end
    
    for i = 0, fx_count - 1 do
        -- Only add top-level FX (those without a parent)
        if not M.get_parent(track, i) then
            add_fx(i, 0)
        end
    end
    
    return result
end

--- Print container structure to console (debug).
-- @param track MediaTrack* Track pointer
function M.debug_print_structure(track)
    local indent = "  "
    for _, fx in ipairs(M.get_all_fx_flat(track)) do
        local prefix = string.rep(indent, fx.depth)
        local suffix = fx.is_container and " [Container]" or ""
        reaper.ShowConsoleMsg(string.format("%s%s%s\n", prefix, fx.name, suffix))
    end
end

return M

