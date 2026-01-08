--- FX Detail Panel UI Component
-- Shows detailed parameter controls for a selected FX
-- @module ui.fx_detail_panel
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')

local M = {}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Draw a single parameter control (label + slider)
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param param_idx number Parameter index (0-based)
-- @param precision string Format string for slider (e.g., "%.2f")
local function draw_param_control(ctx, fx, param_idx, precision)
    local name = fx:get_param_name(param_idx)
    local val = fx:get_param_normalized(param_idx) or 0
    local display_name = (name and name ~= "") and name or ("P" .. (param_idx + 1))

    ctx:push_id(param_idx)
    ctx:text(display_name)
    ctx:set_next_item_width(-1)
    local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, precision)
    if changed then
        fx:set_param_normalized(param_idx, new_val)
    end
    ctx:pop_id()
end

--- Draw parameters in two-column table layout
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param param_count number Total number of parameters
local function draw_params_two_columns(ctx, fx, param_count)
    local half = math.ceil(param_count / 2)

    if ctx:begin_table("ParamTable", 2) then
        ctx:table_setup_column("Col1", imgui.TableColumnFlags.WidthStretch())
        ctx:table_setup_column("Col2", imgui.TableColumnFlags.WidthStretch())

        for row = 0, half - 1 do
            ctx:table_next_row()

            -- Column 1
            ctx:table_set_column_index(0)
            if row < param_count then
                draw_param_control(ctx, fx, row, "%.2f")
            end

            -- Column 2
            ctx:table_set_column_index(1)
            local j = row + half
            if j < param_count then
                draw_param_control(ctx, fx, j, "%.2f")
            end
        end

        ctx:end_table()
    end
end

--- Draw parameters in single-column layout
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param param_count number Total number of parameters
local function draw_params_single_column(ctx, fx, param_count)
    for i = 0, param_count - 1 do
        draw_param_control(ctx, fx, i, "%.3f")
        ctx:spacing()
    end
end

--------------------------------------------------------------------------------
-- FX Detail Panel
--------------------------------------------------------------------------------

--- Draw FX detail panel
-- @param ctx ImGui context wrapper
-- @param width number Width of the panel
-- @param selected_fx_guid string GUID of selected FX (nil if none)
-- @param get_fx function Function to get FX by GUID: (guid) -> fx or nil
-- @param get_fx_display_name function Function to get display name: (fx) -> string
function M.draw(ctx, width, selected_fx_guid, get_fx, get_fx_display_name)
    if not selected_fx_guid then return end

    if ctx:begin_child("FXDetail", width, 0, imgui.ChildFlags.Border()) then
        local fx = get_fx(selected_fx_guid)
        if not fx then
            ctx:text_disabled("FX not found")
            ctx:end_child()
            return
        end

        -- Header
        ctx:text(get_fx_display_name(fx))
        ctx:separator()

        -- Bypass toggle + Open button on same line
        local enabled = fx:get_enabled()
        local button_w = (width - 20) / 2
        if ctx:button(enabled and "ON" or "OFF", button_w, 0) then
            fx:set_enabled(not enabled)
        end
        ctx:same_line()
        if ctx:button("Open FX", button_w, 0) then
            fx:show(3)
        end

        ctx:separator()

        -- Parameters header
        local param_count = fx:get_num_params()
        ctx:text(string.format("Parameters (%d)", param_count))

        if param_count == 0 then
            ctx:text_disabled("No parameters")
        else
            -- Scrollable parameter list with two columns for many params
            if ctx:begin_child("ParamList", 0, 0, imgui.ChildFlags.Border()) then
                local use_two_cols = param_count > 8 and width > 350

                if use_two_cols then
                    draw_params_two_columns(ctx, fx, param_count)
                else
                    draw_params_single_column(ctx, fx, param_count)
                end
                ctx:end_child()
            end
        end

        ctx:end_child()
    end
end

return M
