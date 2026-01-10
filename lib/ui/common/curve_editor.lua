-- Curve Editor Component
-- Full curve editor for SideFX modulators, rendered with ImGui
-- Replaces the JSFX @gfx editor

local M = {}

local r = reaper
local imgui = require('imgui')
local PARAM = require('lib.modulator.modulator_constants')

-- Constants
local MAX_POINTS = 16
local MAX_SEGMENTS = 15
local CURVE_RESOLUTION = 100  -- Number of line segments to draw curve

-- Colors (RGBA as 0xRRGGBBAA)
local COLORS = {
    background = 0x1E1E22FF,
    grid = 0x383840FF,
    grid_major = 0x484850FF,
    curve = 0x33E680FF,
    curve_segment_selected = 0x66AAFFFF,
    node = 0xFF8822FF,
    node_hover = 0xFFBB66FF,
    node_endpoint = 0xFF6644FF,
    playhead = 0xFF8844AA,
    output_dot = 0x33E680FF,
    text = 0xAAAAAAFF,
    segment_handle = 0x6688AAFF,
    segment_handle_hover = 0x88AACCFF,
}

--------------------------------------------------------------------------------
-- Math: Port from JSFX
--------------------------------------------------------------------------------

-- Sort points by X and return sorted arrays
local function sort_points_by_x(points)
    local sorted = {}
    for i, pt in ipairs(points) do
        sorted[i] = {x = pt.x, y = pt.y, orig_idx = i}
    end
    table.sort(sorted, function(a, b) return a.x < b.x end)
    return sorted
end

-- Apply curve shape to normalized t (0-1)
-- curve_shape: -1 = ease-out, 0 = linear, +1 = ease-in
local function apply_curve(t, curve_shape)
    if curve_shape == 0 then
        return t
    end
    -- Convert curve_shape to power: -1 gives 0.5 (sqrt), +1 gives 2 (square)
    local power = 2 ^ curve_shape
    return t ^ power
end

-- Evaluate curve at position x (0-1)
-- points: array of {x, y}
-- segment_curves: array of curve values per segment (optional, defaults to 0)
-- global_curve: global curve offset (optional, defaults to 0)
function M.eval_curve(points, x, segment_curves, global_curve)
    if #points < 2 then return 0 end
    
    segment_curves = segment_curves or {}
    global_curve = global_curve or 0
    
    -- Sort points by X
    local sorted = sort_points_by_x(points)
    local n = #sorted
    
    -- Clamp x
    x = math.max(0, math.min(1, x))
    
    -- Find which segment we're in
    local seg_idx = 1
    while seg_idx < n and sorted[seg_idx + 1].x < x do
        seg_idx = seg_idx + 1
    end
    seg_idx = math.min(seg_idx, n - 1)
    
    -- Get segment boundaries
    local seg_start = sorted[seg_idx].x
    local seg_end = sorted[seg_idx + 1].x
    local seg_len = seg_end - seg_start
    if seg_len < 0.0001 then seg_len = 0.0001 end
    
    -- Y values at segment endpoints
    local y_start = sorted[seg_idx].y
    local y_end = sorted[seg_idx + 1].y
    
    -- Normalized position within segment (0-1)
    local t_norm = (x - seg_start) / seg_len
    t_norm = math.max(0, math.min(1, t_norm))
    
    -- Get per-segment curve and combine with global
    local seg_curve = segment_curves[seg_idx] or 0
    local final_curve = math.max(-1, math.min(1, seg_curve + global_curve))
    
    -- Apply curve shape
    local t_curved = apply_curve(t_norm, final_curve)
    
    -- Linear interpolation with curved t
    local out = y_start + (y_end - y_start) * t_curved
    return math.max(0, math.min(1, out))
end

--------------------------------------------------------------------------------
-- Data sync with JSFX
--------------------------------------------------------------------------------

-- Read all curve points from modulator FX
function M.read_points_from_fx(modulator)
    local points = {}
    local ok, num_points = pcall(function()
        return math.floor(modulator:get_param(PARAM.PARAM_NUM_POINTS) + 0.5)
    end)
    if not ok then num_points = 4 end
    num_points = math.max(2, math.min(MAX_POINTS, num_points))
    
    for i = 1, num_points do
        local param_x = PARAM.PARAM_POINT_START + (i - 1) * 2
        local param_y = PARAM.PARAM_POINT_START + (i - 1) * 2 + 1
        local ok_x, x = pcall(function() return modulator:get_param_normalized(param_x) end)
        local ok_y, y = pcall(function() return modulator:get_param_normalized(param_y) end)
        points[i] = {
            x = ok_x and x or 0.5,
            y = ok_y and y or 0.5
        }
    end
    return points, num_points
end

-- Write point to modulator FX
function M.write_point_to_fx(modulator, point_idx, x, y)
    local param_x = PARAM.PARAM_POINT_START + (point_idx - 1) * 2
    local param_y = PARAM.PARAM_POINT_START + (point_idx - 1) * 2 + 1
    pcall(function() modulator:set_param_normalized(param_x, x) end)
    pcall(function() modulator:set_param_normalized(param_y, y) end)
end

-- Read segment curve values from modulator FX
function M.read_segment_curves_from_fx(modulator, num_points)
    local curves = {}
    local num_segments = num_points - 1
    for i = 1, num_segments do
        local param_idx = PARAM.PARAM_SEGMENT_CURVE_START + (i - 1)
        local ok, val = pcall(function() return modulator:get_param_normalized(param_idx) end)
        -- Convert 0-1 normalized to -1 to +1
        curves[i] = ok and (val * 2 - 1) or 0
    end
    return curves
end

-- Write segment curve value to modulator FX
function M.write_segment_curve_to_fx(modulator, segment_idx, curve_value)
    local param_idx = PARAM.PARAM_SEGMENT_CURVE_START + (segment_idx - 1)
    -- Convert -1 to +1 to normalized 0-1
    local norm = (curve_value + 1) / 2
    pcall(function() modulator:set_param_normalized(param_idx, norm) end)
end

-- Read global curve offset
function M.read_global_curve_from_fx(modulator)
    local ok, val = pcall(function() return modulator:get_param_normalized(PARAM.PARAM_CURVE_SHAPE) end)
    return ok and (val * 2 - 1) or 0
end

-- Read current LFO playhead position and output
function M.read_lfo_state_from_fx(modulator)
    -- PARAM_PLAYHEAD_POSITION is the actual current phase (slider87)
    -- Use get_param since slider range is already 0-1
    local ok_phase, phase = pcall(function() return modulator:get_param(PARAM.PARAM_PLAYHEAD_POSITION) end)
    local ok_out, output = pcall(function() return modulator:get_param(PARAM.PARAM_OUTPUT) end)
    return ok_phase and phase or 0, ok_out and output or 0
end

-- Set number of points
function M.write_num_points_to_fx(modulator, num_points)
    -- PARAM_NUM_POINTS range is 2-16, need to convert to normalized 0-1
    local norm = (num_points - 2) / 14
    pcall(function() modulator:set_param_normalized(PARAM.PARAM_NUM_POINTS, norm) end)
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------

-- Draw the curve editor
-- Returns: interacted (bool), and updates state table with any changes
function M.draw(ctx, modulator, width, height, state)
    local interacted = false
    state = state or {}
    
    -- Initialize state
    state.hover_node = state.hover_node or -1
    state.drag_node = state.drag_node or -1
    state.selected_segment = state.selected_segment or -1
    state.drag_segment = state.drag_segment or -1  -- For curve shape dragging
    state.drag_start_x = state.drag_start_x or 0
    state.drag_start_y = state.drag_start_y or 0
    state.drag_start_curve = state.drag_start_curve or 0  -- Initial curve value when drag started
    
    -- Get draw list
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    
    -- Get cursor position for drawing area
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
    
    -- Reserve space
    ctx:dummy(width, height)
    
    -- Padding
    local pad = 4
    local area_x = cursor_x + pad
    local area_y = cursor_y + pad
    local area_w = width - pad * 2
    local area_h = height - pad * 2
    
    -- Background
    r.ImGui_DrawList_AddRectFilled(draw_list, area_x, area_y, 
        area_x + area_w, area_y + area_h, COLORS.background)
    
    -- Read data from FX
    local points, num_points = M.read_points_from_fx(modulator)
    local segment_curves = M.read_segment_curves_from_fx(modulator, num_points)
    local global_curve = M.read_global_curve_from_fx(modulator)
    local lfo_phase, lfo_output = M.read_lfo_state_from_fx(modulator)
    
    -- Read grid setting from FX (0=Off, 1=4, 2=8, 3=16, 4=32)
    local ok_grid, grid_norm = pcall(function() return modulator:get_param_normalized(PARAM.PARAM_GRID) end)
    local grid_idx = ok_grid and math.floor(grid_norm * 4 + 0.5) or 2  -- Default to 8
    local grid_divisions = {0, 4, 8, 16, 32}
    local grid_div = grid_divisions[grid_idx + 1] or 8
    
    -- Vertical grid lines (if grid enabled)
    if grid_div > 0 then
        for i = 0, grid_div do
            local gx = area_x + (i / grid_div) * area_w
            local color = (i == 0 or i == grid_div) and COLORS.grid_major or COLORS.grid
            r.ImGui_DrawList_AddLine(draw_list, gx, area_y, gx, area_y + area_h, color)
        end
    else
        -- Just draw border lines when grid is off
        r.ImGui_DrawList_AddLine(draw_list, area_x, area_y, area_x, area_y + area_h, COLORS.grid_major)
        r.ImGui_DrawList_AddLine(draw_list, area_x + area_w, area_y, area_x + area_w, area_y + area_h, COLORS.grid_major)
    end
    
    -- Horizontal grid lines (always 4 divisions for amplitude)
    for i = 0, 4 do
        local gy = area_y + (i / 4) * area_h
        local color = (i == 0 or i == 4) and COLORS.grid_major or COLORS.grid
        r.ImGui_DrawList_AddLine(draw_list, area_x, gy, area_x + area_w, gy, color)
    end
    
    -- Draw curve
    local sorted = sort_points_by_x(points)
    local prev_px, prev_py = nil, nil
    for i = 0, CURVE_RESOLUTION do
        local t = i / CURVE_RESOLUTION
        local y = M.eval_curve(points, t, segment_curves, global_curve)
        local px = area_x + t * area_w
        local py = area_y + area_h - y * area_h
        if prev_px then
            r.ImGui_DrawList_AddLine(draw_list, prev_px, prev_py, px, py, COLORS.curve, 2)
        end
        prev_px, prev_py = px, py
    end
    
    -- Mouse handling
    local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx.ctx)
    local mouse_in_area = mouse_x >= area_x and mouse_x <= area_x + area_w and
                          mouse_y >= area_y and mouse_y <= area_y + area_h
    
    -- Normalized mouse position
    local norm_mx = (mouse_x - area_x) / area_w
    local norm_my = 1.0 - (mouse_y - area_y) / area_h
    
    -- Modifier keys (check early for hover logic)
    local shift = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Key_LeftShift()) or 
                  r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Key_RightShift())
    local ctrl = r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Key_LeftCtrl()) or 
                 r.ImGui_IsKeyDown(ctx.ctx, r.ImGui_Key_RightCtrl())
    
    -- Find nearest node (only when not in Shift mode)
    local hover_node = -1
    local node_threshold = 0.06
    local min_dist = node_threshold * node_threshold
    if not shift then
        for i, pt in ipairs(points) do
            local dx = norm_mx - pt.x
            local dy = norm_my - pt.y
            local dist = dx * dx + dy * dy
            if dist < min_dist then
                min_dist = dist
                hover_node = i
            end
        end
    end
    state.hover_node = hover_node
    
    -- Find nearest segment (for Shift mode - curve adjustment)
    local hover_segment = -1
    if shift and mouse_in_area then
        local sorted_for_seg = sort_points_by_x(points)
        for i = 1, #sorted_for_seg - 1 do
            local p1 = sorted_for_seg[i]
            local p2 = sorted_for_seg[i + 1]
            if norm_mx >= p1.x and norm_mx <= p2.x then
                hover_segment = i
                break
            end
        end
    end
    state.hover_segment = hover_segment
    
    -- Mouse interaction
    -- Disable when any popup/combo is open (prevents clicking through menus)
    local any_popup_open = r.ImGui_IsPopupOpen(ctx.ctx, "", 1)  -- 1 = AnyPopup flag
    
    local left_down = r.ImGui_IsMouseDown(ctx.ctx, 0)
    local left_clicked = r.ImGui_IsMouseClicked(ctx.ctx, 0)
    local right_clicked = r.ImGui_IsMouseClicked(ctx.ctx, 1)
    
    if mouse_in_area and not any_popup_open then
        if left_clicked then
            if shift and hover_segment > 0 then
                -- Start dragging segment curve
                state.drag_segment = hover_segment
                state.drag_start_y = norm_my
                state.drag_start_curve = segment_curves[hover_segment] or 0
                interacted = true
            elseif hover_node > 0 then
                -- Start dragging existing node
                state.drag_node = hover_node
                state.drag_start_x = points[hover_node].x
                state.drag_start_y = points[hover_node].y
                interacted = true
            elseif num_points < MAX_POINTS and not shift then
                -- Add new node (only when not in Shift mode)
                local new_x = math.max(0.001, math.min(0.999, norm_mx))
                local new_y = math.max(0, math.min(1, norm_my))
                -- Add to end and write
                local new_idx = num_points + 1
                M.write_num_points_to_fx(modulator, new_idx)
                M.write_point_to_fx(modulator, new_idx, new_x, new_y)
                interacted = true
            end
        end
        
        if right_clicked and hover_node > 0 and num_points > 2 then
            -- Delete node (but not endpoints)
            local sorted_pts = sort_points_by_x(points)
            local is_endpoint = (sorted_pts[1].orig_idx == hover_node) or 
                               (sorted_pts[#sorted_pts].orig_idx == hover_node)
            if not is_endpoint then
                -- Shift points down
                for i = hover_node, num_points - 1 do
                    local next_pt = points[i + 1]
                    M.write_point_to_fx(modulator, i, next_pt.x, next_pt.y)
                end
                M.write_num_points_to_fx(modulator, num_points - 1)
                interacted = true
            end
        end
    end
    
    -- Continue dragging segment curve (Shift+drag) - only when no popup open
    if state.drag_segment > 0 and left_down and not any_popup_open then
        -- Vertical drag controls curve: drag DOWN = inward (negative), drag UP = outward (positive)
        local delta_y = norm_my - state.drag_start_y
        local new_curve = state.drag_start_curve + delta_y * 2  -- Drag up = outward, drag down = inward
        new_curve = math.max(-1, math.min(1, new_curve))
        M.write_segment_curve_to_fx(modulator, state.drag_segment, new_curve)
        interacted = true
    elseif not left_down or any_popup_open then
        state.drag_segment = -1
    end
    
    -- Continue dragging node - only when no popup open
    if state.drag_node > 0 and left_down and not any_popup_open then
        local new_x = math.max(0.001, math.min(0.999, norm_mx))
        local new_y = math.max(0, math.min(1, norm_my))
        
        -- Lock endpoints to x=0 or x=1
        if state.drag_start_x < 0.01 then new_x = 0 end
        if state.drag_start_x > 0.99 then new_x = 1 end
        
        -- Ctrl = X-only (lock Y)
        if ctrl then new_y = state.drag_start_y end
        
        M.write_point_to_fx(modulator, state.drag_node, new_x, new_y)
        interacted = true
    elseif not left_down or any_popup_open then
        state.drag_node = -1
    end
    
    -- Draw nodes
    for i, pt in ipairs(points) do
        local nx = area_x + pt.x * area_w
        local ny = area_y + area_h - pt.y * area_h
        local is_hover = (i == state.hover_node)
        local is_drag = (i == state.drag_node)
        local is_endpoint = (pt.x < 0.01 or pt.x > 0.99)
        
        local color = is_endpoint and COLORS.node_endpoint or 
                      (is_hover or is_drag) and COLORS.node_hover or COLORS.node
        local radius = (is_hover or is_drag) and 7 or 5
        
        r.ImGui_DrawList_AddCircleFilled(draw_list, nx, ny, radius, color)
        r.ImGui_DrawList_AddCircle(draw_list, nx, ny, radius, 0xFFFFFF80, 0, 1)
    end
    
    -- Draw segment curve handles (small diamonds at segment midpoints)
    -- Show when: Shift is held (curve edit mode), or segment has non-zero curve
    local sorted_for_handles = sort_points_by_x(points)
    for i = 1, #sorted_for_handles - 1 do
        local p1 = sorted_for_handles[i]
        local p2 = sorted_for_handles[i + 1]
        local mid_x = (p1.x + p2.x) / 2
        local mid_y = M.eval_curve(points, mid_x, segment_curves, global_curve)
        
        local hx = area_x + mid_x * area_w
        local hy = area_y + area_h - mid_y * area_h
        
        -- Small diamond handle
        local seg_curve = segment_curves[i] or 0
        local is_hover = (state.hover_segment == i)
        local is_drag = (state.drag_segment == i)
        local handle_color = (is_hover or is_drag) and COLORS.segment_handle_hover or COLORS.segment_handle
        
        -- Show if: Shift held (curve mode), segment has curve, or segment is being dragged
        local show_handle = shift or is_drag or math.abs(seg_curve) > 0.01
        if show_handle then
            local hs = (is_hover or is_drag) and 6 or 4  -- Larger when active
            r.ImGui_DrawList_AddQuadFilled(draw_list, 
                hx, hy - hs,
                hx + hs, hy,
                hx, hy + hs,
                hx - hs, hy,
                handle_color)
            
            -- Show curve value when hovering or dragging
            if is_hover or is_drag then
                local curve_text = string.format("%.2f", seg_curve)
                r.ImGui_DrawList_AddText(draw_list, hx + 10, hy - 6, COLORS.text, curve_text)
            end
        end
    end
    
    -- Draw LFO playhead (on top of everything)
    local playhead_x = area_x + lfo_phase * area_w
    -- Thick orange line for visibility
    r.ImGui_DrawList_AddLine(draw_list, playhead_x, area_y, playhead_x, area_y + area_h, COLORS.playhead, 2)
    
    -- Draw output dot on playhead (bright green, larger)
    local out_y = area_y + area_h - lfo_output * area_h
    r.ImGui_DrawList_AddCircleFilled(draw_list, playhead_x, out_y, 6, COLORS.output_dot)
    r.ImGui_DrawList_AddCircle(draw_list, playhead_x, out_y, 6, 0xFFFFFFFF, 0, 1)
    
    -- Border
    r.ImGui_DrawList_AddRect(draw_list, area_x, area_y, 
        area_x + area_w, area_y + area_h, COLORS.grid_major)
    
    return interacted, state
end

--------------------------------------------------------------------------------
-- Draw curve editor in a popup window
--------------------------------------------------------------------------------
function M.draw_popup(ctx, modulator, state, popup_id)
    state = state or {}
    state.is_open = state.is_open or false
    
    -- Check if popup should be opened
    if state.open_requested then
        r.ImGui_OpenPopup(ctx.ctx, popup_id)
        state.open_requested = false
        state.is_open = true
    end
    
    local interacted = false
    
    -- Larger size for popup
    local popup_width = 600
    local popup_height = 400
    
    -- Set window size before opening
    r.ImGui_SetNextWindowSize(ctx.ctx, popup_width, popup_height, imgui.Cond.FirstUseEver())
    
    -- Draw popup as a regular window (resizable, no collapse)
    local window_flags = imgui.WindowFlags.NoCollapse()
    if state.is_open then
        local visible, open = r.ImGui_Begin(ctx.ctx, popup_id, true, window_flags)
        
        -- Check if X button was clicked
        if not open then
            state.is_open = false
        end
        
        if visible then
            -- Get actual window size (may have been resized)
            local win_w, win_h = r.ImGui_GetWindowSize(ctx.ctx)
            local avail_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
            
            -- Draw editor first (takes most of the space)
            local control_bar_height = 35
            local editor_h = win_h - 55 - control_bar_height  -- Title bar + controls
            
            -- Create an invisible button to capture the editor area (prevents window dragging)
            local cursor_pos_x, cursor_pos_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
            r.ImGui_InvisibleButton(ctx.ctx, "editor_capture", avail_w, editor_h)
            
            -- Draw editor on top of the button (using same position)
            r.ImGui_SetCursorScreenPos(ctx.ctx, cursor_pos_x, cursor_pos_y)
            local editor_interacted, new_state = M.draw(ctx, modulator, avail_w, editor_h, state)
            if editor_interacted then
                interacted = true
            end
            state = new_state
            
            r.ImGui_Spacing(ctx.ctx)
            
            -- Control bar at bottom: Grid, Snap, Loop/OneShot
            -- Grid dropdown
            local grid_options = {"Off", "4", "8", "16", "32"}
            local ok_grid, grid_norm = pcall(function() return modulator:get_param_normalized(PARAM.PARAM_GRID) end)
            -- Discrete param with 5 values (0-4), normalized is 0-1
            local grid_idx = ok_grid and math.floor(grid_norm * 4 + 0.5) or 0
            
            r.ImGui_SetNextItemWidth(ctx.ctx, 60)
            if r.ImGui_BeginCombo(ctx.ctx, "Grid", grid_options[grid_idx + 1] or "Off") then
                for i, opt in ipairs(grid_options) do
                    if r.ImGui_Selectable(ctx.ctx, opt, i - 1 == grid_idx) then
                        modulator:set_param_normalized(PARAM.PARAM_GRID, (i - 1) / 4)
                        interacted = true
                    end
                end
                r.ImGui_EndCombo(ctx.ctx)
            end
            
            r.ImGui_SameLine(ctx.ctx)
            
            -- Snap checkbox
            local ok_snap, snap_val = pcall(function() return modulator:get_param(PARAM.PARAM_SNAP) end)
            local snap_on = ok_snap and snap_val >= 0.5
            local snap_changed, snap_new = r.ImGui_Checkbox(ctx.ctx, "Snap", snap_on)
            if snap_changed then
                modulator:set_param(PARAM.PARAM_SNAP, snap_new and 1 or 0)
                interacted = true
            end
            
            r.ImGui_SameLine(ctx.ctx)
            r.ImGui_Dummy(ctx.ctx, 20, 0)  -- Spacer
            r.ImGui_SameLine(ctx.ctx)
            
            -- Loop/OneShot icon buttons
            local ok_mode, lfo_mode = pcall(function() return modulator:get_param(PARAM.PARAM_LFO_MODE) end)
            local is_loop = ok_mode and lfo_mode < 0.5
            
            -- Loop icon: ↻
            if is_loop then
                r.ImGui_PushStyleColor(ctx.ctx, imgui.Col.Button(), 0x5588AAFF)
            end
            if r.ImGui_Button(ctx.ctx, "↻##loop", 28, 0) then
                modulator:set_param(PARAM.PARAM_LFO_MODE, 0)
                interacted = true
            end
            if is_loop then
                r.ImGui_PopStyleColor(ctx.ctx)
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                r.ImGui_SetTooltip(ctx.ctx, "Loop")
            end
            
            r.ImGui_SameLine(ctx.ctx)
            
            -- One Shot icon: →
            if not is_loop then
                r.ImGui_PushStyleColor(ctx.ctx, imgui.Col.Button(), 0x5588AAFF)
            end
            if r.ImGui_Button(ctx.ctx, "→##oneshot", 28, 0) then
                modulator:set_param(PARAM.PARAM_LFO_MODE, 1)
                interacted = true
            end
            if not is_loop then
                r.ImGui_PopStyleColor(ctx.ctx)
            end
            if r.ImGui_IsItemHovered(ctx.ctx) then
                r.ImGui_SetTooltip(ctx.ctx, "One Shot")
            end
            
            r.ImGui_End(ctx.ctx)
        end
    end
    
    return interacted, state
end

return M
