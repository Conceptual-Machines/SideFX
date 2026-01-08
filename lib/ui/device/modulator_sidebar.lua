-- Modulator Sidebar UI Module
-- Renders the modulator grid, controls, and parameter links

local M = {}

local r = reaper
local imgui = require('imgui')
local state_module = require('lib.core.state')
local PARAM = require('lib.modulator.modulator_constants')
local drawing = require('lib.ui.common.drawing')
local modulator_module = require('lib.modulator.modulator')

-- Modulator types
local MODULATOR_TYPES = {
    {name = "Bezier LFO", jsfx = "SideFX_Modulator"}
}

-- Helper function to get modulators for a device
local function get_device_modulators(device_container)
    local modulators = {}
    if not device_container then return modulators end

    -- Refresh container pointer to ensure we get latest children
    if device_container.refresh_pointer then
        pcall(function() device_container:refresh_pointer() end)
    end

    local ok, iter = pcall(function() return device_container:iter_container_children() end)
    if not ok or not iter then return modulators end

    for child in iter do
        local ok_name, name = pcall(function() return child:get_name() end)
        if ok_name and name and (name:match("SideFX_Modulator") or name:match("SideFX Modulator")) then
            table.insert(modulators, child)
        end
    end

    return modulators
end

-- Main draw function for modulator sidebar
function M.draw(ctx, fx, container, guid, state_guid, cfg, opts)
    local state = state_module.state
    local interacted = false
    opts = opts or {}

    -- Initialize state tables if needed
    state.mod_sidebar_collapsed = state.mod_sidebar_collapsed or {}
    state.expanded_mod_slot = state.expanded_mod_slot or {}

    local is_mod_sidebar_collapsed = state.mod_sidebar_collapsed[state_guid] or false

    if is_mod_sidebar_collapsed then
        -- Collapsed: button is now in header, show nothing here
    else
        -- Expanded: show grid (header now handled by parent device_panel)

        -- Get modulators for this device
        local modulators = get_device_modulators(container)
        local expanded_slot_idx = state.expanded_mod_slot[state_guid]

        -- Use fixed square dimensions for slots
        local slot_width = cfg.mod_slot_width
        local slot_height = cfg.mod_slot_height

        -- 4×2 grid of modulator slots
        ctx:dummy(8, 1)  -- Left padding

        -- Use basic table - let button sizes control column width
        if ctx:begin_table("mod_grid_" .. guid, 4) then
            -- Draw 2 rows
            for row = 0, 1 do
                ctx:table_next_row(0, slot_height)

                for col = 0, 3 do
                    ctx:table_set_column_index(col)

                    local slot_idx = row * 4 + col
                    local modulator = modulators[slot_idx + 1]  -- Lua 1-based
                    local slot_id = "slot_" .. slot_idx .. "_" .. guid

                    if modulator then
                        -- Slot has modulator - show short name (LFO1, LFO2, etc.)
                        local display_name = "LFO" .. (slot_idx + 1)

                        local is_expanded = (expanded_slot_idx == slot_idx)
                        if is_expanded then
                            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                        end

                        if ctx:button(display_name .. "##" .. slot_id, slot_width, slot_height) then
                            -- Toggle expansion
                            if state.expanded_mod_slot[state_guid] == slot_idx then
                                state.expanded_mod_slot[state_guid] = nil
                            else
                                state.expanded_mod_slot[state_guid] = slot_idx
                            end
                            interacted = true
                        end

                        -- Right-click context menu for modulator
                        if ctx:begin_popup_context_item("mod_ctx_" .. slot_id) then
                            if ctx:selectable("Delete Modulator") then
                                -- Delete modulator
                                local ok_del = pcall(function()
                                    modulator:delete()
                                end)
                                if ok_del then
                                    -- Clear expansion state for this slot
                                    state.expanded_mod_slot[state_guid] = nil
                                    -- Refresh FX list
                                    if opts.refresh_fx_list then
                                        opts.refresh_fx_list()
                                    end
                                    interacted = true
                                end
                            end
                            ctx:end_popup()
                        end

                        if is_expanded then
                            ctx:pop_style_color()
                        end
                    else
                        -- Empty slot - show + button
                        if ctx:button("+##" .. slot_id, slot_width, slot_height) then
                            -- Show modulator type dropdown (simplified for now - just add Bezier LFO)
                            local track = opts.track or state.track
                            if track and container then
                                local new_mod = modulator_module.add_modulator_to_device(container, MODULATOR_TYPES[1], track)
                                if new_mod then
                                    -- Refresh container pointer after adding (important for UI to update)
                                    if container.refresh_pointer then
                                        container:refresh_pointer()
                                    end

                                    if opts.refresh_fx_list then
                                        opts.refresh_fx_list()
                                    end

                                    -- Auto-select the newly added modulator
                                    local new_mod_guid = new_mod:get_guid()
                                    local updated_modulators = get_device_modulators(container)
                                    for idx, mod in ipairs(updated_modulators) do
                                        if mod:get_guid() == new_mod_guid then
                                            state.expanded_mod_slot[state_guid] = idx - 1  -- 0-based slot index
                                            break
                                        end
                                    end
                                end
                            end
                            interacted = true
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Add Modulator")
                        end
                    end
                end
            end

            ctx:end_table()
        end

        -- Show expanded modulator parameters
        if expanded_slot_idx ~= nil then
            local expanded_modulator = modulators[expanded_slot_idx + 1]
            if expanded_modulator then
                -- Get parameter values safely (ReaWrap uses get_num_params, not get_param_count)
                local ok, param_count = pcall(function() return expanded_modulator:get_num_params() end)
                if ok and param_count and param_count > 0 then
                    ctx:separator()
                    ctx:spacing()
                    -- Set control width shorter for compact layout
                    local control_width = 180

                    -- Rate section: Free/Sync buttons | UI icon (no label)
                    -- Read tempo mode BEFORE table so it's accessible inside and outside
                    local tempo_mode = expanded_modulator:get_param(PARAM.PARAM_TEMPO_MODE)

                    if ctx:begin_table("##rate_table_" .. guid, 2, imgui.TableFlags.SizingStretchProp()) then
                        ctx:table_setup_column("Mode", imgui.TableColumnFlags.WidthStretch())
                        ctx:table_setup_column("UI", imgui.TableColumnFlags.WidthFixed(), 30)

                        ctx:table_next_row()

                        -- Column 1: Free/Sync buttons
                        ctx:table_set_column_index(0)
                        if tempo_mode then
                            if ctx:radio_button("Free##tempo_" .. guid, tempo_mode < 0.5) then
                                expanded_modulator:set_param(PARAM.PARAM_TEMPO_MODE, 0)
                                interacted = true
                            end
                            ctx:same_line()
                            if ctx:radio_button("Sync##tempo_" .. guid, tempo_mode >= 0.5) then
                                expanded_modulator:set_param(PARAM.PARAM_TEMPO_MODE, 1)
                                interacted = true
                            end
                        end

                        -- Column 2: UI icon
                        ctx:table_set_column_index(1)
                        if drawing.draw_ui_icon(ctx, "##ui_" .. guid, 24, 20) then
                            expanded_modulator:show(3)
                            interacted = true
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Open Curve Editor")
                        end

                        ctx:end_table()
                    end
                    ctx:spacing()

                    -- Rate slider/dropdown (narrower width)
                    local rate_width = 120
                    if tempo_mode and tempo_mode < 0.5 then
                        -- Free mode - show Hz slider (slider2)
                        local ok_rate, rate_hz = pcall(function() return expanded_modulator:get_param_normalized(1) end)
                        if ok_rate then
                            ctx:set_next_item_width(rate_width)
                            local changed, new_rate = ctx:slider_double("Hz##rate_" .. guid, rate_hz, 0.01, 20, "%.2f")
                            if changed then
                                expanded_modulator:set_param_normalized(1, new_rate)
                                interacted = true
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Rate (Hz)")
                            end
                        end
                    else
                        -- Sync mode - show sync rate dropdown (slider3)
                        local ok_sync, sync_rate_idx = pcall(function() return expanded_modulator:get_param_normalized(2) end)
                        if ok_sync then
                            local sync_rates = {"8 bars", "4 bars", "2 bars", "1 bar", "1/2", "1/4", "1/4T", "1/4.", "1/8", "1/8T", "1/8.", "1/16", "1/16T", "1/16.", "1/32", "1/32T", "1/32.", "1/64"}
                            local current_idx = math.floor(sync_rate_idx * 17 + 0.5)
                            ctx:set_next_item_width(rate_width)
                            if ctx:begin_combo("##sync_rate_" .. guid, sync_rates[current_idx + 1] or "1/4") then
                                for i, rate_name in ipairs(sync_rates) do
                                    if ctx:selectable(rate_name, i - 1 == current_idx) then
                                        expanded_modulator:set_param_normalized(2, (i - 1) / 17)
                                        interacted = true
                                    end
                                end
                                ctx:end_combo()
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Sync Rate")
                            end
                        end
                    end

                    ctx:spacing()

                    -- Phase and Depth on same line (no labels)
                    local param_width = 88
                    local ok_phase, phase = pcall(function() return expanded_modulator:get_param_normalized(4) end)
                    if ok_phase then
                        ctx:set_next_item_width(param_width)
                        local phase_deg = phase * 360
                        local changed, new_phase_deg = ctx:slider_double("##phase_" .. guid, phase_deg, 0, 360, "%.0f°")
                        if changed then
                            expanded_modulator:set_param_normalized(4, new_phase_deg / 360)
                            interacted = true
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Phase")
                        end
                    end

                    ctx:same_line()

                    local ok_depth, depth = pcall(function() return expanded_modulator:get_param_normalized(5) end)
                    if ok_depth then
                        ctx:set_next_item_width(param_width)
                        local depth_pct = depth * 100
                        local changed, new_depth_pct = ctx:slider_double("##depth_" .. guid, depth_pct, 0, 100, "%.0f%%")
                        if changed then
                            expanded_modulator:set_param_normalized(5, new_depth_pct / 100)
                            interacted = true
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Depth")
                        end
                    end

                    ctx:spacing()

                    -- Trigger and Mode on same line (no labels)
                    local trigger_width = 100

                    -- Trigger Mode dropdown
                    local ok_trig, trigger_mode_val = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_TRIGGER_MODE) end)
                    local trig_idx = nil  -- Declare outside so it's accessible in Advanced section
                    if ok_trig then
                        local trigger_modes = {"Free", "Transport", "MIDI", "Audio"}
                        trig_idx = math.floor(trigger_mode_val * 3 + 0.5)
                        ctx:set_next_item_width(trigger_width)
                        if ctx:begin_combo("##trigger_mode_" .. guid, trigger_modes[trig_idx + 1] or "Free") then
                            for i, mode_name in ipairs(trigger_modes) do
                                if ctx:selectable(mode_name, i - 1 == trig_idx) then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_TRIGGER_MODE, (i - 1) / 3)
                                    interacted = true
                                end
                            end
                            ctx:end_combo()
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Trigger Mode")
                        end
                    end

                    ctx:same_line()

                    -- LFO Mode: Loop/One Shot (discrete parameter)
                    local lfo_mode = expanded_modulator:get_param(PARAM.PARAM_LFO_MODE)
                    if lfo_mode then
                        if ctx:radio_button("Loop##lfo_" .. guid, lfo_mode < 0.5) then
                            expanded_modulator:set_param(PARAM.PARAM_LFO_MODE, 0)
                            interacted = true
                        end
                        ctx:same_line()
                        if ctx:radio_button("One Shot##lfo_" .. guid, lfo_mode >= 0.5) then
                            expanded_modulator:set_param(PARAM.PARAM_LFO_MODE, 1)
                            interacted = true
                        end
                    end

                    ctx:spacing()

                    -- Advanced section (collapsible)
                    local advanced_key = "mod_advanced_" .. guid .. "_" .. expanded_slot_idx
                    local is_advanced_open = state.modulator_advanced[advanced_key] or false

                    if ctx:tree_node("Advanced##adv_" .. guid) then
                        state.modulator_advanced[advanced_key] = true

                        -- Show additional params based on trigger mode
                        if ok_trig and trig_idx == 2 then
                            -- MIDI trigger mode
                            -- MIDI Source (slider21 - discrete parameter)
                            local midi_src = expanded_modulator:get_param(PARAM.PARAM_MIDI_SOURCE)
                            if midi_src then
                                if ctx:radio_button("This Track##midi_src_" .. guid, midi_src < 0.5) then
                                    expanded_modulator:set_param(PARAM.PARAM_MIDI_SOURCE, 0)
                                    interacted = true
                                end
                                ctx:same_line()
                                if ctx:radio_button("MIDI Bus##midi_src_" .. guid, midi_src >= 0.5) then
                                    expanded_modulator:set_param(PARAM.PARAM_MIDI_SOURCE, 1)
                                    interacted = true
                                end
                            end

                            -- MIDI Note (slider22)
                            local ok_note, midi_note = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_MIDI_NOTE) end)
                            if ok_note then
                                ctx:set_next_item_width(control_width)
                                local note_val = math.floor(midi_note * 127 + 0.5)
                                local changed, new_note_val = ctx:slider_int("MIDI Note##note_" .. guid, note_val, 0, 127, note_val == 0 and "Any" or tostring(note_val))
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_MIDI_NOTE, new_note_val / 127)
                                    interacted = true
                                end
                            end
                        elseif ok_trig and trig_idx == 3 then
                            -- Audio trigger mode
                            -- Audio Threshold (slider23)
                            local ok_thresh, audio_thresh = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_AUDIO_THRESHOLD) end)
                            if ok_thresh then
                                ctx:set_next_item_width(control_width)
                                local changed, new_thresh = ctx:slider_double("Threshold##thresh_" .. guid, audio_thresh, 0, 1, "%.2f")
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_AUDIO_THRESHOLD, new_thresh)
                                    interacted = true
                                end
                            end
                        end

                        -- Attack/Release (always show in advanced)
                        if ok_trig and trig_idx and trig_idx > 0 then
                            -- Attack (slider24)
                            local ok_atk, attack_ms = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_ATTACK) end)
                            if ok_atk then
                                local atk_val = attack_ms * 1999 + 1  -- 1-2000ms
                                ctx:set_next_item_width(control_width)
                                local changed, new_atk_val = ctx:slider_double("Attack##atk_" .. guid, atk_val, 1, 2000, "%.0f ms")
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_ATTACK, (new_atk_val - 1) / 1999)
                                    interacted = true
                                end
                            end

                            -- Release (slider25)
                            local ok_rel, release_ms = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_RELEASE) end)
                            if ok_rel then
                                local rel_val = release_ms * 4999 + 1  -- 1-5000ms
                                ctx:set_next_item_width(control_width)
                                local changed, new_rel_val = ctx:slider_double("Release##rel_" .. guid, rel_val, 1, 5000, "%.0f ms")
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_RELEASE, (new_rel_val - 1) / 4999)
                                    interacted = true
                                end
                            end
                        end

                        ctx:tree_pop()
                    else
                        state.modulator_advanced[advanced_key] = false
                    end

                    ctx:spacing()
                    ctx:separator()
                    ctx:spacing()

                    -- Parameter Links section
                    ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                    ctx:text("PARAMETER LINKS")
                    ctx:pop_style_color()
                    ctx:spacing()

                    -- Find existing links for this modulator on the parent device
                    local existing_links = {}

                    -- Calculate what the modulator's index would be in the link
                    -- (local index within container)
                    local expected_mod_idx = nil
                    local my_parent = fx:get_parent_container()
                    if my_parent then
                        local children = my_parent:get_container_children()
                        local mod_guid = expanded_modulator:get_guid()
                        for i, child in ipairs(children) do
                            if child:get_guid() == mod_guid then
                                expected_mod_idx = i - 1  -- 0-based
                                break
                            end
                        end
                    end

                    if expected_mod_idx ~= nil then
                        -- Check each parameter using ReaWrap's get_param_link_info
                        local ok_params, param_count = pcall(function() return fx:get_num_params() end)
                        if ok_params and param_count then
                            for param_idx = 0, param_count - 1 do
                                local link_info = fx:get_param_link_info(param_idx)
                                -- Check if linked to our modulator AND using the Output parameter
                                if link_info and
                                   link_info.effect == expected_mod_idx and
                                   link_info.param == PARAM.PARAM_OUTPUT then
                                    -- This parameter is linked to our modulator's output
                                    local ok_pname, param_name = pcall(function() return fx:get_param_name(param_idx) end)
                                    if ok_pname and param_name then
                                        table.insert(existing_links, {
                                            param_idx = param_idx,
                                            param_name = param_name
                                        })
                                    end
                                end
                            end
                        end
                    end

                    -- Show existing links
                    if #existing_links > 0 then
                        ctx:push_style_color(imgui.Col.Text(), 0x88FF88FF)
                        ctx:text(string.format("Active Links: %d", #existing_links))
                        ctx:pop_style_color()
                        ctx:spacing()

                        for i, link in ipairs(existing_links) do
                            ctx:text("• " .. link.param_name)
                            ctx:same_line()
                            if ctx:button("X##remove_link_" .. i .. "_" .. guid, 20, 0) then
                                -- Remove this link using ReaWrap's high-level API
                                if fx:remove_param_link(link.param_idx) then
                                    interacted = true
                                end
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Remove link")
                            end
                        end

                        ctx:spacing()
                        ctx:separator()
                        ctx:spacing()
                    end

                    -- Modulator can only modulate its parent device (fx parameter)
                    -- No device selector needed - use the device that owns this container
                    local target_device = fx  -- The device being displayed

                    -- Parameter selector for parent device
                    if target_device then
                        local ok_params, param_count = pcall(function() return target_device:get_num_params() end)

                        if ok_params and param_count and param_count > 0 then
                            local current_param_name = "Select Parameter..."
                            ctx:set_next_item_width(control_width)
                            if ctx:begin_combo("##link_param_" .. guid, current_param_name) then
                                for param_idx = 0, param_count - 1 do
                                    local ok_pname, param_name = pcall(function() return target_device:get_param_name(param_idx) end)
                                    if ok_pname and param_name then
                                        -- Check if already linked
                                        local is_linked = false
                                        for _, link in ipairs(existing_links) do
                                            if link.param_idx == param_idx then
                                                is_linked = true
                                                break
                                            end
                                        end

                                        if ctx:selectable(param_name .. (is_linked and " ✓" or ""), false) then
                                            -- Auto-create link immediately when parameter is selected
                                            local success = target_device:create_param_link(
                                                expanded_modulator,
                                                PARAM.PARAM_OUTPUT,  -- Modulator output parameter
                                                param_idx,
                                                1.0  -- 100% modulation scale
                                            )
                                            if success then
                                                interacted = true
                                            end
                                        end
                                    end
                                end
                                ctx:end_combo()
                            end
                        end
                    else
                        ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                        ctx:text("No target device")
                        ctx:pop_style_color()
                    end
                end
            end
        end
    end

    return interacted
end

return M
