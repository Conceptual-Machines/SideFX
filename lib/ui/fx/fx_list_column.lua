--- FX List Column UI Component
-- Draws a column of FX items with drag/drop, renaming, and controls
-- @module ui.fx_list_column
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local helpers = require('helpers')
local icons = require('lib.ui.common.icons')

local M = {}

--------------------------------------------------------------------------------
-- FX List Column
--------------------------------------------------------------------------------

--- Draw FX list column
-- @param ctx ImGui context wrapper
-- @param fx_list table Array of FX objects
-- @param column_title string Title for the column
-- @param depth number Depth in hierarchy
-- @param width number Column width
-- @param parent_container_guid string|nil GUID of parent container
-- @param opts table Options:
--   - state: State table
--   - state_module: State module (for save_display_names)
--   - track: ReaWrap track object
--   - icon_font: ImGui font handle for icons (optional)
--   - icon_size: number Size of icon font
--   - icon_text: function (icon_id) -> string
--   - Icons: Icons table
--   - get_fx_display_name: function (fx) -> string
--   - move_fx_to_track_level: function (guid) -> nil
--   - move_fx_to_container: function (guid, target_guid) -> nil
--   - refresh_fx_list: function () -> nil
--   - handle_fx_drop_target: function (ctx, fx, guid, is_container) -> nil
--   - draw_fx_context_menu: function (ctx, fx, guid, i, enabled, is_container, depth) -> nil
--   - toggle_container: function (guid, depth) -> nil
--   - toggle_fx_detail: function (guid) -> nil
--   - clear_multi_select: function () -> nil
--   - get_multi_select_count: function () -> number
function M.draw(ctx, fx_list, column_title, depth, width, parent_container_guid, opts)
    local state = opts.state
    local state_module = opts.state_module
    local track = opts.track
    -- icon_font, icon_size, icon_text, Icons are no longer used (using icons module directly)
    local get_fx_display_name = opts.get_fx_display_name
    local move_fx_to_track_level = opts.move_fx_to_track_level
    local move_fx_to_container = opts.move_fx_to_container
    local refresh_fx_list = opts.refresh_fx_list
    local handle_fx_drop_target = opts.handle_fx_drop_target
    local draw_fx_context_menu = opts.draw_fx_context_menu
    local toggle_container = opts.toggle_container
    local toggle_fx_detail = opts.toggle_fx_detail
    local clear_multi_select = opts.clear_multi_select
    local get_multi_select_count = opts.get_multi_select_count

    if ctx:begin_child("Column" .. depth, width, 0, imgui.ChildFlags.Border()) then
        ctx:text(column_title)
        ctx:separator()

        -- Drop zone for this column
        local has_payload = ctx:get_drag_drop_payload("FX_GUID")
        if has_payload then
            local drop_label = depth == 1 and "Drop to move to track" or ("Drop to add to " .. column_title)
            ctx:push_style_color(imgui.Col.Button(), 0x4488FF88)
            ctx:button(drop_label .. "##drop" .. depth, -1, 24)
            ctx:pop_style_color()
            if ctx:begin_drag_drop_target() then
                local accepted, guid = ctx:accept_drag_drop_payload("FX_GUID")
                if accepted and guid then
                    local fx = track:find_fx_by_guid(guid)
                    if fx then
                        local fx_parent = fx:get_parent_container()
                        local fx_parent_guid = fx_parent and fx_parent:get_guid() or nil

                        if depth == 1 then
                            -- Move to track level (only if FX is in a container)
                            if fx_parent then
                                move_fx_to_track_level(guid)
                                refresh_fx_list()
                            end
                        elseif parent_container_guid and fx_parent_guid ~= parent_container_guid then
                            -- Move into this column's container
                            move_fx_to_container(guid, parent_container_guid)
                            refresh_fx_list()
                        end
                    end
                end
                ctx:end_drag_drop_target()
            end
        end

        if #fx_list == 0 then
            ctx:text_disabled("Empty")
            ctx:end_child()
            return
        end

        local i = 0
        for fx in helpers.iter(fx_list) do
            i = i + 1
            local guid = fx:get_guid()
            if not guid then goto continue end

            -- Use depth + index for unique IDs across columns
            ctx:push_id(depth * 1000 + i)

            local is_container = fx:is_container()
            local is_expanded = state.expanded_path[depth] == guid
            local is_selected = state.selected_fx == guid
            local is_multi = state.multi_select[guid] ~= nil
            local enabled = fx:get_enabled()

            -- Layout constants (relative to column width)
            local icon_w = 24
            local btn_w = 34
            local wet_w = 52
            local controls_w = btn_w + wet_w + 8
            local name_w = width - icon_w - controls_w - 30  -- 30px gap
            local controls_x = width - controls_w - 8

            -- Icon
            local icon_name = is_container
                and (is_expanded and icons.Names.folder_open or icons.Names.folder_closed)
                or icons.Names.plug
            icons.image(ctx, icon_name, 16)

            -- Name as selectable (or input text if renaming)
            ctx:same_line()
            local highlight = is_expanded or is_selected or is_multi
            local is_renaming = state.renaming_fx == guid

            if is_renaming then
                -- Inline rename input
                ctx:set_next_item_width(name_w)
                local changed, new_text = ctx:input_text("##rename" .. i, state.rename_text, imgui.InputTextFlags.EnterReturnsTrue())
                if changed then
                    state.rename_text = new_text
                    -- If Enter was pressed (EnterReturnsTrue flag), save and finish
                    if state.rename_text ~= "" then
                        -- Store custom display name in state (SideFX-only, doesn't change REAPER name)
                        state.display_names[guid] = state.rename_text
                        state_module.save_display_names()
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Check if item was deactivated after edit (clicked away)
                if ctx:is_item_deactivated_after_edit() then
                    if state.rename_text ~= "" then
                        -- Store custom display name in state (SideFX-only, doesn't change REAPER name)
                        state.display_names[guid] = state.rename_text
                        state_module.save_display_names()
                    end
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
                -- Cancel on Escape
                if ctx:is_key_pressed(imgui.Key.Escape()) then
                    -- Cancel rename
                    state.renaming_fx = nil
                    state.rename_text = ""
                end
            else
                local name = get_fx_display_name(fx)
                -- Truncate based on available width (approx 7px per char)
                local max_chars = math.floor(name_w / 7)
                if #name > max_chars then
                    name = string.sub(name, 1, max_chars - 2) .. ".."
                end

                if ctx:selectable(name .. "##sel" .. i, highlight, 0, name_w, 0) then
                    if ctx:is_shift_down() then
                        if state.selected_fx and get_multi_select_count() == 0 then
                            state.multi_select[state.selected_fx] = true
                        end
                        if state.multi_select[guid] then
                            state.multi_select[guid] = nil
                        else
                            state.multi_select[guid] = true
                        end
                        state.selected_fx = nil
                    else
                        clear_multi_select()
                        if is_container then
                            toggle_container(guid, depth)
                        else
                            toggle_fx_detail(guid)
                        end
                    end
                end
            end

            -- Drag source for moving FX (must be right after selectable)
            if ctx:begin_drag_drop_source() then
                ctx:set_drag_drop_payload("FX_GUID", guid)
                ctx:text("Moving: " .. get_fx_display_name(fx))
                ctx:end_drag_drop_source()
            end

            -- Drop target for reordering and container drops
            handle_fx_drop_target(ctx, fx, guid, is_container)

            -- Right-click context menu
            draw_fx_context_menu(ctx, fx, guid, i, enabled, is_container, depth)

            if ctx:is_item_hovered() then ctx:set_tooltip(get_fx_display_name(fx)) end

            -- Controls on the right
            ctx:same_line_ex(controls_x)

            -- Wet/Dry slider
            local wet_idx = fx:get_param_from_ident(":wet")
            if wet_idx >= 0 then
                local wet_val = fx:get_param(wet_idx)
                ctx:set_next_item_width(wet_w - 5)
                local wet_changed, new_wet = ctx:slider_double("##wet" .. i, wet_val, 0, 1, "%.0f%%")
                if wet_changed then
                    fx:set_param(wet_idx, new_wet)
                end
                if ctx:is_item_hovered() then ctx:set_tooltip("Wet: " .. string.format("%.0f%%", wet_val * 100)) end
                ctx:same_line()
            end

            -- Bypass button (colored)
            if enabled then
                ctx:push_style_color(imgui.Col.Button(), 0x44AA44FF)
            else
                ctx:push_style_color(imgui.Col.Button(), 0xAA4444FF)
            end
            if ctx:small_button(enabled and "ON##" .. i or "OFF##" .. i) then
                fx:set_enabled(not enabled)
            end
            ctx:pop_style_color()

            ctx:pop_id()
            ::continue::
        end

        ctx:end_child()
    end
end

return M
