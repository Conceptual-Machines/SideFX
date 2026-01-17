--[[
Click vs Drag Interaction Handler

Provides clean separation between click and drag operations:
- Click: Mouse down + up on same item without significant movement
- Drag: Mouse down + movement beyond threshold

Usage:
    local cod = require('lib.ui.common.click_or_drag')

    -- In your draw loop:
    cod.begin_item(ctx, item_id)
    -- Draw your item (button, selectable, image, etc.)
    local action = cod.end_item(ctx, item_id)

    if action == "click" then
        -- Handle click
    elseif action == "drag_start" then
        -- Begin drag-drop source
    end
]]

local M = {}

-- Track interaction state per item
-- {[item_id] = {mouse_down_pos = {x, y}, is_dragging = bool}}
local item_states = {}

-- Drag threshold in pixels (movement beyond this = drag, not click)
local DRAG_THRESHOLD = 4

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Begin tracking an item for click/drag detection
-- Call this BEFORE drawing the interactive item
-- @param ctx ImGui context wrapper
-- @param item_id Unique identifier for this item
function M.begin_item(ctx, item_id)
    -- Initialize state if needed
    if not item_states[item_id] then
        item_states[item_id] = {
            mouse_down_pos = nil,
            is_dragging = false,
            was_active = false,
        }
    end
end

--- End tracking and determine action
-- Call this AFTER drawing the interactive item
-- @param ctx ImGui context wrapper
-- @param item_id Unique identifier for this item
-- @return string|nil "click", "drag_start", "dragging", or nil
function M.end_item(ctx, item_id)
    local r = reaper
    local state = item_states[item_id]
    if not state then return nil end

    local is_hovered = r.ImGui_IsItemHovered(ctx.ctx)
    local is_active = r.ImGui_IsItemActive(ctx.ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx.ctx, 0)  -- Left mouse button
    local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx.ctx)

    local result = nil

    -- Mouse just pressed on this item
    if is_active and mouse_down and not state.was_active then
        state.mouse_down_pos = {mouse_x, mouse_y}
        state.is_dragging = false
    end

    -- Check for drag (mouse moved beyond threshold while held)
    if state.mouse_down_pos and mouse_down then
        local dx = mouse_x - state.mouse_down_pos[1]
        local dy = mouse_y - state.mouse_down_pos[2]
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > DRAG_THRESHOLD then
            if not state.is_dragging then
                state.is_dragging = true
                result = "drag_start"
            else
                result = "dragging"
            end
        end
    end

    -- Mouse released
    if state.was_active and not is_active then
        if not state.is_dragging and state.mouse_down_pos then
            -- Released without dragging = click
            result = "click"
        end
        -- Reset state
        state.mouse_down_pos = nil
        state.is_dragging = false
    end

    state.was_active = is_active

    return result
end

--- Check if an item is currently being dragged
-- @param item_id Unique identifier for the item
-- @return boolean
function M.is_dragging(item_id)
    local state = item_states[item_id]
    return state and state.is_dragging or false
end

--- Clear state for an item (call when item is removed)
-- @param item_id Unique identifier for the item
function M.clear_item(item_id)
    item_states[item_id] = nil
end

--- Clear all tracked state
function M.clear_all()
    item_states = {}
end

--------------------------------------------------------------------------------
-- Convenience function for simple cases
--------------------------------------------------------------------------------

--- Draw an invisible button that handles click vs drag
-- @param ctx ImGui context wrapper
-- @param item_id Unique identifier
-- @param width Button width
-- @param height Button height
-- @return string|nil "click", "drag_start", "dragging", or nil
function M.invisible_button(ctx, item_id, width, height)
    local r = reaper

    M.begin_item(ctx, item_id)
    r.ImGui_InvisibleButton(ctx.ctx, "##" .. item_id, width, height)
    return M.end_item(ctx, item_id)
end

return M
