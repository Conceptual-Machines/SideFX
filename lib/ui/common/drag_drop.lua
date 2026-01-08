--- Drag and Drop Helpers
-- Functions for handling FX drag-and-drop operations
-- @module ui.drag_drop
-- @author Nomad Monad
-- @license MIT

local r = reaper

local M = {}

--------------------------------------------------------------------------------
-- Drag and Drop Handlers
--------------------------------------------------------------------------------

--- Handle drop target for FX reordering and container drops
-- @param ctx ImGui context wrapper
-- @param fx ReaWrap FX object (target)
-- @param guid string Target FX GUID
-- @param is_container boolean Whether target is a container
-- @param track ReaWrap Track object
-- @param callbacks table Callbacks:
--   - on_refresh: () -> nil
function M.handle_fx_drop_target(ctx, fx, guid, is_container, track, callbacks)
    if ctx:begin_drag_drop_target() then
        local accepted, payload = ctx:accept_drag_drop_payload("FX_GUID")
        if accepted and payload and payload ~= guid then
            local drag_fx = track:find_fx_by_guid(payload)
            if drag_fx then
                if is_container then
                    -- Dropping onto a container: move into it
                    drag_fx:move_to_container(fx)
                else
                    -- Dropping onto a non-container FX: reorder
                    local drag_parent = drag_fx:get_parent_container()
                    local target_parent = fx:get_parent_container()
                    local drag_parent_guid = drag_parent and drag_parent:get_guid() or nil
                    local target_parent_guid = target_parent and target_parent:get_guid() or nil

                    if drag_parent_guid == target_parent_guid then
                        -- Same container: reorder using REAPER's swap
                        local drag_pos = drag_fx.pointer
                        local target_pos = fx.pointer

                        if target_parent then
                            -- Inside a container - use container child positions
                            local children = {}
                            for child in target_parent:iter_container_children() do
                                children[#children + 1] = child
                            end
                            for idx, child in ipairs(children) do
                                if child:get_guid() == payload then drag_pos = idx - 1 end
                                if child:get_guid() == guid then target_pos = idx - 1 end
                            end
                        end

                        -- Swap using TrackFX_CopyToTrack
                        if drag_pos ~= target_pos then
                            r.TrackFX_CopyToTrack(
                                track.pointer, drag_fx.pointer,
                                track.pointer, fx.pointer,
                                true
                            )
                        end
                    else
                        -- Different containers: move to target's container at target's position
                        if target_parent then
                            -- Find target's position in its container
                            local target_pos = 0
                            for child in target_parent:iter_container_children() do
                                if child:get_guid() == guid then break end
                                target_pos = target_pos + 1
                            end
                            target_parent:add_fx_to_container(drag_fx, target_pos)
                        else
                            -- Target is at track level
                            drag_fx:move_out_of_container()
                        end
                    end
                end
                callbacks.on_refresh()
            end
        end
        ctx:end_drag_drop_target()
    end
end

--- Move FX to track level (out of all containers)
-- @param guid string FX GUID
-- @param track ReaWrap Track object
function M.move_fx_to_track_level(guid, track)
    local fx = track:find_fx_by_guid(guid)
    if not fx then return end

    while fx:get_parent_container() do
        fx:move_out_of_container()
        fx = track:find_fx_by_guid(guid)
        if not fx then break end
    end
end

--- Move FX to a target container by navigating through hierarchy
-- @param guid string FX GUID to move
-- @param target_container_guid string Target container GUID
-- @param track ReaWrap Track object
function M.move_fx_to_container(guid, target_container_guid, track)
    local target_container = track:find_fx_by_guid(target_container_guid)
    if not target_container then return end

    -- Build path from root to target container
    local target_path = {}
    local container = target_container
    while container do
        table.insert(target_path, 1, container:get_guid())
        container = container:get_parent_container()
    end

    -- Move FX through each level
    for _, container_guid in ipairs(target_path) do
        local fx = track:find_fx_by_guid(guid)
        if not fx then break end

        local current_parent = fx:get_parent_container()
        local current_parent_guid = current_parent and current_parent:get_guid() or nil

        if current_parent_guid ~= container_guid then
            local c = track:find_fx_by_guid(container_guid)
            if c then
                c:add_fx_to_container(fx)
            end
        end
    end
end

return M
