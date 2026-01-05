--- FX Detail Panel UI Component
-- Shows detailed parameter controls for a selected FX
-- @module ui.fx_detail_panel
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')

local M = {}

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
                    local half = math.ceil(param_count / 2)

                    if ctx:begin_table("ParamTable", 2) then
                        ctx:table_setup_column("Col1", imgui.TableColumnFlags.WidthStretch())
                        ctx:table_setup_column("Col2", imgui.TableColumnFlags.WidthStretch())

                        for row = 0, half - 1 do
                            ctx:table_next_row()

                            ctx:table_set_column_index(0)
                            local i = row
                            if i < param_count then
                                local name = fx:get_param_name(i)
                                local val = fx:get_param_normalized(i) or 0
                                local display_name = (name and name ~= "") and name or ("P" .. (i + 1))

                                ctx:push_id(i)
                                ctx:text(display_name)
                                ctx:set_next_item_width(-1)
                                local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, "%.2f")
                                if changed then
                                    fx:set_param_normalized(i, new_val)
                                end
                                ctx:pop_id()
                            end

                            ctx:table_set_column_index(1)
                            local j = row + half
                            if j < param_count then
                                local name = fx:get_param_name(j)
                                local val = fx:get_param_normalized(j) or 0
                                local display_name = (name and name ~= "") and name or ("P" .. (j + 1))

                                ctx:push_id(j)
                                ctx:text(display_name)
                                ctx:set_next_item_width(-1)
                                local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, "%.2f")
                                if changed then
                                    fx:set_param_normalized(j, new_val)
                                end
                                ctx:pop_id()
                            end
                        end

                        ctx:end_table()
                    end
                else
                    for i = 0, param_count - 1 do
                        local name = fx:get_param_name(i)
                        local val = fx:get_param_normalized(i) or 0
                        local display_name = (name and name ~= "") and name or ("Param " .. (i + 1))

                        ctx:push_id(i)
                        ctx:text(display_name)
                        ctx:set_next_item_width(-1)
                        local changed, new_val = ctx:slider_double("##p", val, 0.0, 1.0, "%.3f")
                        if changed then
                            fx:set_param_normalized(i, new_val)
                        end
                        ctx:spacing()
                        ctx:pop_id()
                    end
                end
                ctx:end_child()
            end
        end

        ctx:end_child()
    end
end

return M


