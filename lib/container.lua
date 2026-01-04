--- SideFX Container Operations.
-- High-level container operations that use the state singleton.
-- Low-level container methods are provided by ReaWrap's TrackFX class.
-- @module container
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

-- Lazy load state module to avoid circular dependency
local _state_module = nil
local function get_state()
    if not _state_module then
        _state_module = require('lib.state')
    end
    return _state_module.state
end

--------------------------------------------------------------------------------
-- Container Operations
--------------------------------------------------------------------------------

--- Add FX to a new container.
-- @param fx_list table Array of FX objects to add
-- @return TrackFX|nil New container or nil
function M.add_to_new_container(fx_list)
    local state = get_state()
    if #fx_list == 0 then return end
    if not state.track then return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    local container = state.track:add_fx_to_new_container(fx_list)

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add to Container", -1)

    return container
end

--- Dissolve a container, moving all children out.
-- @param container TrackFX Container to dissolve
-- @return boolean Success
function M.dissolve_container(container)
    local state = get_state()
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

    -- Move all children out of the container
    local container_guid = container:get_guid()
    for _, child_guid in ipairs(children) do
        local child = state.track:find_fx_by_guid(child_guid)
        if child then
            -- Move out of container
            while child:get_parent_container() and child:get_parent_container():get_guid() == container_guid do
                child:move_out_of_container()
                child = state.track:find_fx_by_guid(child_guid)
                if not child then break end
            end
        end
    end

    -- Re-lookup container (pointer may have changed after moves)
    container = state.track:find_fx_by_guid(container_guid)
    
    -- Delete the now-empty container
    if container then
        container:delete()
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Dissolve Container", -1)

    return true
end

return M
