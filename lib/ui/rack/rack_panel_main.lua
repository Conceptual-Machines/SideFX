--- Rack Panel Main UI Component
-- Draws the main rack panel with expand/collapse, master controls, and chains table
-- @module ui.rack_panel_main
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper

local M = {}

-- Lazy-loaded modules
local rack_ui = nil
local rack_module = nil
local drawing = nil

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Draw collapsed fader control (full vertical fader with meters and scale)
-- @param ctx ImGui context
-- @param mixer ReaWrap mixer FX
-- @param rack_guid string Rack GUID (for popup ID)
-- @param state table State table
-- @param drawing module Drawing module
local function draw_collapsed_fader_control(ctx, mixer, rack_guid, state, drawing)
    local fader_w = 32
    local meter_w = 12
    local scale_w = 20

    local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
    if not ok_gain or not gain_norm then return end

    local gain_db = -24 + gain_norm * 36
    local gain_format = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.0f", gain_db) or string.format("%.0f", gain_db))

    local _, remaining_h = ctx:get_content_region_avail()
    local fader_h = remaining_h - 22
    fader_h = math.max(50, fader_h)

    local avail_w, _ = ctx:get_content_region_avail()
    local total_w = scale_w + fader_w + meter_w + 4
    local offset_x = math.max(0, (avail_w - total_w) / 2 - 8)
    ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + offset_x)

    local screen_x, screen_y = ctx:get_cursor_screen_pos()
    local draw_list = ctx:get_window_draw_list()

    local scale_x = screen_x
    local fader_x = screen_x + scale_w + 2
    local meter_x = fader_x + fader_w + 2

    -- Draw scale, fader, and meters
    drawing.draw_db_scale_marks(ctx, draw_list, scale_x, screen_y, fader_h, scale_w)
    drawing.draw_fader_visualization(ctx, draw_list, fader_x, screen_y, fader_w, fader_h, gain_norm)
    drawing.draw_stereo_meters_visualization(ctx, draw_list, meter_x, screen_y, meter_w, fader_h)

    -- Draw peak meter bars if track available
    if state.track and state.track.pointer then
        local peak_l = r.Track_GetPeakInfo(state.track.pointer, 0)
        local peak_r = r.Track_GetPeakInfo(state.track.pointer, 1)
        local half_meter_w = meter_w / 2 - 1
        local meter_l_x = meter_x
        local meter_r_x = meter_x + meter_w / 2 + 1
        drawing.draw_peak_meters(ctx, draw_list, meter_l_x, meter_r_x, screen_y, fader_h, half_meter_w, peak_l, peak_r)
    end

    -- Interactive slider
    ctx:set_cursor_screen_pos(fader_x, screen_y)
    ctx:push_style_color(imgui.Col.FrameBg(), 0x00000000)
    ctx:push_style_color(imgui.Col.FrameBgHovered(), 0x00000000)
    ctx:push_style_color(imgui.Col.FrameBgActive(), 0x00000000)
    ctx:push_style_color(imgui.Col.SliderGrab(), 0xAAAAAAFF)
    ctx:push_style_color(imgui.Col.SliderGrabActive(), 0xFFFFFFFF)
    local gain_changed, new_gain_db = ctx:v_slider_double("##master_gain_v", fader_w, fader_h, gain_db, -24, 12, "")
    if gain_changed then
        pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
    end
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
    end
    ctx:pop_style_color(5)

    -- dB label
    local label_y = screen_y + fader_h + 2
    local db_text_w, _ = ctx:calc_text_size(gain_format)
    local label_x = fader_x + (fader_w - db_text_w) / 2
    ctx:set_cursor_screen_pos(label_x, label_y)
    ctx:text(gain_format)

    -- Edit popup
    if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
        ctx:open_popup("##gain_edit_popup_" .. rack_guid)
    end
    if ctx:begin_popup("##gain_edit_popup_" .. rack_guid) then
        ctx:set_next_item_width(60)
        ctx:set_keyboard_focus_here()
        local input_changed, input_val = ctx:input_double("##gain_input", gain_db, 0, 0, "%.1f")
        if input_changed then
            local new_db = math.max(-24, math.min(12, input_val))
            pcall(function() mixer:set_param_normalized(0, (new_db + 24) / 36) end)
        end
        if ctx:is_key_pressed(imgui.Key.Enter()) or ctx:is_key_pressed(imgui.Key.Escape()) then
            ctx:close_current_popup()
        end
        ctx:end_popup()
    end
end

--- Draw master controls table (gain + pan sliders)
-- @param ctx ImGui context
-- @param mixer ReaWrap mixer FX
-- @param draw_pan_slider function (ctx, id, pan_val, width) -> (changed, new_pan)
local function draw_master_controls_table(ctx, mixer, draw_pan_slider)
    if ctx:begin_table("master_controls", 3, imgui.TableFlags.SizingStretchProp()) then
        ctx:table_setup_column("label", imgui.TableColumnFlags.WidthFixed(), 50)
        ctx:table_setup_column("gain", imgui.TableColumnFlags.WidthStretch(), 1)
        ctx:table_setup_column("pan", imgui.TableColumnFlags.WidthFixed(), 70)
        ctx:table_next_row()

        ctx:table_set_column_index(0)
        ctx:text_colored(0xAAAAAAFF, "Master")

        ctx:table_set_column_index(1)
        local ok_gain, gain_norm = pcall(function() return mixer:get_param_normalized(0) end)
        if ok_gain and gain_norm then
            local gain_db = -24 + gain_norm * 36
            local gain_format = (math.abs(gain_db) < 0.1) and "0" or (gain_db > 0 and string.format("+%.1f", gain_db) or string.format("%.1f", gain_db))
            ctx:set_next_item_width(-1)
            local gain_changed, new_gain_db = ctx:slider_double("##master_gain", gain_db, -24, 12, gain_format)
            if gain_changed then
                pcall(function() mixer:set_param_normalized(0, (new_gain_db + 24) / 36) end)
            end
            if ctx:is_item_hovered() and ctx:is_mouse_double_clicked(0) then
                pcall(function() mixer:set_param_normalized(0, (0 + 24) / 36) end)
            end
        else
            ctx:text_disabled("--")
        end

        ctx:table_set_column_index(2)
        local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(1) end)
        if ok_pan and pan_norm then
            local pan_val = -100 + pan_norm * 200
            local pan_changed, new_pan = draw_pan_slider(ctx, "##master_pan", pan_val, 60)
            if pan_changed then
                pcall(function() mixer:set_param_normalized(1, (new_pan + 100) / 200) end)
            end
        else
            ctx:text_disabled("C")
        end

        ctx:end_table()
    end
end

--- Draw chains table header and loop
-- @param ctx ImGui context
-- @param chains table Array of chain FX
-- @param rack ReaWrap rack container
-- @param mixer ReaWrap mixer FX
-- @param is_nested boolean Whether rack is nested
-- @param state table State table
-- @param get_fx_display_name function (fx) -> string
-- @param state_module module State module
-- @param refresh_fx_list function () -> nil
-- @param add_device_to_chain function (chain, plugin) -> nil
-- @param reorder_chain_in_rack function (rack, from_idx, to_idx) -> nil
-- @param add_chain_to_rack function (rack, plugin) -> nil
-- @param add_nested_rack_to_rack function (rack) -> nil
local function draw_chains_table(ctx, chains, rack, mixer, is_nested, state, get_fx_display_name, state_module, refresh_fx_list, add_device_to_chain, reorder_chain_in_rack, add_chain_to_rack, add_nested_rack_to_rack)
    if not rack_ui then
        local ok, mod = pcall(require, 'lib.ui.rack_ui')
        if ok then rack_ui = mod end
    end

    if #chains == 0 then
        ctx:spacing()
        ctx:text_disabled("No chains yet")
        ctx:text_disabled("Drag plugins here to create chains")
    else
        if ctx:begin_table("chains_table", 5, imgui.TableFlags.SizingStretchProp()) then
            ctx:table_setup_column("name", imgui.TableColumnFlags.WidthFixed(), 80)
            ctx:table_setup_column("enable", imgui.TableColumnFlags.WidthFixed(), 24)
            ctx:table_setup_column("delete", imgui.TableColumnFlags.WidthFixed(), 24)
            ctx:table_setup_column("volume", imgui.TableColumnFlags.WidthStretch(), 1)
            ctx:table_setup_column("pan", imgui.TableColumnFlags.WidthFixed(), 60)

            for j, chain in ipairs(chains) do
                ctx:table_next_row()
                ctx:push_id("chain_" .. j)
                local ok_guid, chain_guid = pcall(function() return chain:get_guid() end)
                if not ok_guid or not chain_guid then
                    ctx:pop_id()
                    goto continue_chain
                end
                local rack_guid = rack:get_guid()
                local is_selected = (state.expanded_nested_chains[rack_guid] == chain_guid)
                rack_ui.draw_chain_row(ctx, chain, j, rack, mixer, is_selected, is_nested, state, get_fx_display_name, {
                    on_chain_select = function(chain_guid, is_selected, is_nested_rack, rack_guid)
                        if is_selected then
                            state.expanded_nested_chains[rack_guid] = nil
                        else
                            state.expanded_nested_chains[rack_guid] = chain_guid
                        end
                        state_module.save_expansion_state()
                    end,
                    on_add_device_to_chain = add_device_to_chain,
                    on_reorder_chain = reorder_chain_in_rack,
                    on_move_chain_between_racks = move_chain_between_racks,
                    on_rename_chain = function(chain_guid, custom_name)
                        state.renaming_fx = chain_guid
                        state.rename_text = custom_name or ""
                    end,
                    on_delete_chain = function(chain, is_selected, is_nested_rack, rack_guid)
                        if is_selected then
                            state.expanded_nested_chains[rack_guid] = nil
                        end
                    end,
                    on_refresh = refresh_fx_list,
                })
                ctx:pop_id()
                ::continue_chain::
            end

            ctx:end_table()
        end
    end
end

--- Draw rack drop zone for plugins/racks
-- @param ctx ImGui context
-- @param rack ReaWrap rack container
-- @param has_payload boolean Whether there's a drag payload
-- @param add_chain_to_rack function (rack, plugin) -> nil
-- @param add_nested_rack_to_rack function (rack) -> nil
local function draw_rack_drop_zone(ctx, rack, has_payload, add_chain_to_rack, add_nested_rack_to_rack)
    ctx:spacing()
    local drop_h = 40
    if has_payload then
        ctx:push_style_color(imgui.Col.Button(), 0x4488FF66)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x66AAFF88)
    else
        ctx:push_style_color(imgui.Col.Button(), 0x33333344)
        ctx:push_style_color(imgui.Col.ButtonHovered(), 0x44444466)
    end
    ctx:button("+ Drop plugin or rack##rack_drop", -1, drop_h)
    ctx:pop_style_color(2)

    if ctx:begin_drag_drop_target() then
        local accepted, plugin_name = ctx:accept_drag_drop_payload("PLUGIN_ADD")
        if accepted and plugin_name then
            local plugin = { full_name = plugin_name, name = plugin_name }
            add_chain_to_rack(rack, plugin)
        end
        local rack_accepted = ctx:accept_drag_drop_payload("RACK_ADD")
        if rack_accepted then
            add_nested_rack_to_rack(rack)
        end
        ctx:end_drag_drop_target()
    end
end

--------------------------------------------------------------------------------
-- Main Drawing Function
--------------------------------------------------------------------------------

--- Draw the rack panel (main rack UI without chain column)
-- @param ctx ImGui context
-- @param rack ReaWrap rack container
-- @param avail_height number Available height
-- @param is_nested boolean Whether rack is nested
-- @param opts table Options:
--   - state: State table
--   - icon_font: ImGui font handle
--   - state_module: State module
--   - refresh_fx_list: function () -> nil
--   - get_rack_mixer: function (rack) -> TrackFX|nil
--   - draw_pan_slider: function (ctx, id, pan_val, width) -> (changed, new_pan)
--   - dissolve_container: function (rack) -> nil
--   - get_fx_display_name: function (fx) -> string
--   - add_device_to_chain: function (chain, plugin) -> nil
--   - reorder_chain_in_rack: function (rack, from_idx, to_idx) -> nil
--   - add_chain_to_rack: function (rack, plugin) -> nil
--   - add_nested_rack_to_rack: function (rack) -> nil
--   - drawing: Drawing module
-- @return table {is_expanded, chains, rack_h}
function M.draw(ctx, rack, avail_height, is_nested, opts)
    -- Lazy load modules
    if not rack_ui then
        local ok, mod = pcall(require, 'lib.ui.rack.rack_ui')
        if ok then rack_ui = mod end
    end
    if not rack_module then
        local ok, mod = pcall(require, 'lib.rack')
        if ok then rack_module = mod end
    end
    if not drawing then
        local ok, mod = pcall(require, 'lib.ui.common.drawing')
        if ok then drawing = mod end
    end

    local state = opts.state
    local icon_font = opts.icon_font
    local state_module = opts.state_module
    local refresh_fx_list = opts.refresh_fx_list
    local get_rack_mixer = opts.get_rack_mixer
    local draw_pan_slider = opts.draw_pan_slider
    local dissolve_container = opts.dissolve_container
    local get_fx_display_name = opts.get_fx_display_name
    local add_device_to_chain = opts.add_device_to_chain
    local reorder_chain_in_rack = opts.reorder_chain_in_rack
    local move_chain_between_racks = opts.move_chain_between_racks
    local add_chain_to_rack = opts.add_chain_to_rack
    local add_empty_chain_to_rack = opts.add_empty_chain_to_rack
    local add_nested_rack_to_rack = opts.add_nested_rack_to_rack
    local drawing_module = opts.drawing or drawing

    -- Explicitly check if is_nested is true (not just truthy)
    is_nested = (is_nested == true)
    local rack_guid = rack:get_guid()

    -- Safety check: if rack was deleted, guid may be nil
    if not rack_guid then
        return { is_expanded = false, chains = {}, rack_h = 0 }
    end

    -- Use expanded_racks for ALL racks (both top-level and nested)
    -- This allows multiple top-level racks to be expanded independently
    local is_expanded = (state.expanded_racks[rack_guid] == true)

    -- Get chains from rack (filter out internal mixer)
    local chains = {}
    for child in rack:iter_container_children() do
        local ok, child_name = pcall(function() return child:get_name() end)
        if ok and child_name and not child_name:match("^_") and not child_name:find("Mixer") then
            table.insert(chains, child)
        end
    end

    local rack_w = is_expanded and 350 or 150
    local rack_h = avail_height - 10

    ctx:push_style_color(imgui.Col.ChildBg(), 0x252535FF)
    -- Use unique child ID that includes nested flag to ensure no state conflicts
    local child_id = is_nested and ("rack_nested_" .. rack_guid) or ("rack_" .. rack_guid)
    local rack_window_flags = imgui.WindowFlags.NoScrollbar()
    if ctx:begin_child(child_id, rack_w, rack_h, imgui.ChildFlags.Border(), rack_window_flags) then

        -- Draw rack header using widget
        rack_ui.draw_rack_header(ctx, rack, is_nested, state, {
            icon_font = icon_font,
            on_toggle_expand = function(rack_guid, is_expanded)
                if is_expanded then
                    state.expanded_racks[rack_guid] = nil
                    state.expanded_nested_chains[rack_guid] = nil
                else
                    state.expanded_racks[rack_guid] = true
                end
                state_module.save_expansion_state()
            end,
            on_rename = function(rack_guid, display_name)
                state.renaming_fx = rack_guid
                state.rename_text = display_name or ""
            end,
            on_dissolve = function(rack)
                dissolve_container(rack)
            end,
            on_delete = function(rack)
                rack:delete()
                refresh_fx_list()
            end,
            on_drop = opts.on_drop,  -- Pass through on_drop for rack swapping
        })

        -- Get mixer for controls
        local mixer = get_rack_mixer(rack)

        if not is_expanded then
            -- Collapsed view - separate tables without dummy() calls
            if mixer then
                -- Chain count
                ctx:text_disabled(string.format("%d chains", #chains))

                -- Pan slider
                local ok_pan, pan_norm = pcall(function() return mixer:get_param_normalized(1) end)
                if ok_pan and pan_norm then
                    local pan_val = -100 + pan_norm * 200
                    local avail_w, _ = ctx:get_content_region_avail()
                    local pan_w = math.min(avail_w - 4, 80)
                    local pan_offset = math.max(0, (avail_w - pan_w) / 2)
                    ctx:set_cursor_pos_x(ctx:get_cursor_pos_x() + pan_offset)
                    local pan_changed, new_pan = draw_pan_slider(ctx, "##master_pan_c", pan_val, pan_w)
                    if pan_changed then
                        pcall(function() mixer:set_param_normalized(1, (new_pan + 100) / 200) end)
                    end
                end

                ctx:spacing()

                -- Draw collapsed fader control
                draw_collapsed_fader_control(ctx, mixer, rack_guid, state, drawing_module)
            else
                ctx:text_disabled("No mixer")
            end
        end

        if is_expanded then
            ctx:separator()

            -- Master output controls
            if mixer then
                draw_master_controls_table(ctx, mixer, draw_pan_slider)
            end

            ctx:separator()

            -- Chains area header and table
            ctx:text_colored(0xAAAAAAFF, "Chains:")
            ctx:same_line()
            ctx:push_style_color(imgui.Col.Button(), 0x446688FF)
            if ctx:small_button("+ Chain") then
                if add_empty_chain_to_rack then
                    add_empty_chain_to_rack(rack)
                end
            end
            ctx:pop_style_color()

            -- Draw chains table or empty state
            draw_chains_table(ctx, chains, rack, mixer, is_nested, state, get_fx_display_name, state_module, refresh_fx_list, add_device_to_chain, reorder_chain_in_rack, add_chain_to_rack, add_nested_rack_to_rack)

            -- Drop zone for creating new chains or nested racks
            local has_plugin = ctx:get_drag_drop_payload("PLUGIN_ADD")
            local has_rack = ctx:get_drag_drop_payload("RACK_ADD")
            draw_rack_drop_zone(ctx, rack, has_plugin or has_rack, add_chain_to_rack, add_nested_rack_to_rack)
        end

        ctx:end_child()
    end
    ctx:pop_style_color()

    -- Return data needed for chain column
    return {
        is_expanded = is_expanded,
        chains = chains,
        rack_h = rack_h,
    }
end

return M
