-- Modulator Sidebar UI Module
-- Renders the modulator grid, controls, and parameter links

local M = {}

local r = reaper
local imgui = require('imgui')
local state_module = require('lib.core.state')
local PARAM = require('lib.modulator.modulator_constants')
local drawing = require('lib.ui.common.drawing')
local modulator_module = require('lib.modulator.modulator')
local curve_editor = require('lib.ui.common.curve_editor')

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

    state.cached_preset_names = state.cached_preset_names or {}

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
                    
                    -- Curve Editor (main visual element)
                    state.curve_editor_state = state.curve_editor_state or {}
                    local editor_key = "curve_" .. guid .. "_" .. expanded_slot_idx
                    state.curve_editor_state[editor_key] = state.curve_editor_state[editor_key] or {}
                    
                    local editor_width = ctx:get_content_region_avail_width()  -- Use actual available width
                    local editor_height = 120  -- Compact height for sidebar
                    
                    local editor_interacted, new_state = curve_editor.draw(
                        ctx, expanded_modulator, editor_width, editor_height,
                        state.curve_editor_state[editor_key]
                    )
                    state.curve_editor_state[editor_key] = new_state
                    if editor_interacted then
                        interacted = true
                    end
                    
                    -- Popup curve editor window
                    state.curve_editor_popup = state.curve_editor_popup or {}
                    state.curve_editor_popup[editor_key] = state.curve_editor_popup[editor_key] or {}
                    local popup_id = "Curve Editor##" .. editor_key
                    local popup_interacted, popup_state = curve_editor.draw_popup(
                        ctx, expanded_modulator, state.curve_editor_popup[editor_key], popup_id
                    )
                    state.curve_editor_popup[editor_key] = popup_state
                    if popup_interacted then
                        interacted = true
                    end
                    
                    ctx:spacing()
                    
                    -- Consistent control widths for symmetry
                    local half_width = (cfg.mod_sidebar_width - 32) / 2  -- Two columns with padding
                    local full_width = cfg.mod_sidebar_width - 16

                    -- Rate section: Free/Sync buttons | Preset | UI icon (no label)
                    -- Read tempo mode BEFORE table so it's accessible inside and outside
                    local tempo_mode = expanded_modulator:get_param(PARAM.PARAM_TEMPO_MODE)

                    if ctx:begin_table("##rate_table_" .. guid, 3) then
                        ctx:table_setup_column("Mode", imgui.TableColumnFlags.WidthFixed(), 105)
                        ctx:table_setup_column("Preset", imgui.TableColumnFlags.WidthFixed(), 85)
                        ctx:table_setup_column("UI", imgui.TableColumnFlags.WidthFixed(), 28)

                        ctx:table_next_row()

                        -- Column 1: Free/Sync icon buttons
                        ctx:table_set_column_index(0)
                        if tempo_mode then
                            local is_free = tempo_mode < 0.5
                            
                            -- Free button (♪)
                            if is_free then
                                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                            end
                            if ctx:button("♪##tempo_" .. guid, 50, 0) then
                                expanded_modulator:set_param(PARAM.PARAM_TEMPO_MODE, 0)
                                interacted = true
                            end
                            if is_free then
                                ctx:pop_style_color()
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Free")
                            end
                            
                            ctx:same_line(0, 0)  -- No gap between buttons
                            
                            -- Sync button (⏱)
                            if not is_free then
                                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                            end
                            if ctx:button("⏱##tempo_" .. guid, 50, 0) then
                                expanded_modulator:set_param(PARAM.PARAM_TEMPO_MODE, 1)
                                interacted = true
                            end
                            if not is_free then
                                ctx:pop_style_color()
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Sync")
                            end
                        end

                        -- Column 2: Preset dropdown (cached, read-only)
                        ctx:table_set_column_index(1)

                        -- Get current preset info from JSFX
                        local preset_idx, num_presets = r.TrackFX_GetPresetIndex(
                            state.track.pointer,
                            expanded_modulator.pointer
                        )

                        if num_presets and num_presets > 0 then
                            -- Check if we need to cache preset names for this modulator
                            local mod_guid = expanded_modulator:get_guid()
                            if not state.cached_preset_names[mod_guid] then
                                -- Cache preset names by reading them once
                                state.cached_preset_names[mod_guid] = {}
                                local original_idx = preset_idx

                                for i = 0, num_presets - 1 do
                                    r.TrackFX_SetPresetByIndex(state.track.pointer, expanded_modulator.pointer, i)
                                    local name = expanded_modulator:get_preset() or ("Preset " .. (i + 1))
                                    state.cached_preset_names[mod_guid][i] = name
                                end

                                -- Restore original preset
                                if original_idx >= 0 then
                                    r.TrackFX_SetPresetByIndex(state.track.pointer, expanded_modulator.pointer, original_idx)
                                end
                            end

                            -- Display preset dropdown using cached names
                            local cached_names = state.cached_preset_names[mod_guid]
                            local current_preset_name = cached_names[preset_idx] or "—"

                            ctx:set_next_item_width(80)
                            if ctx:begin_combo("##preset_" .. guid, current_preset_name) then
                                for i = 0, num_presets - 1 do
                                    local preset_name = cached_names[i] or ("Preset " .. (i + 1))

                                    if ctx:selectable(preset_name, i == preset_idx) then
                                        -- User selected a preset - apply it
                                        r.TrackFX_SetPresetByIndex(state.track.pointer, expanded_modulator.pointer, i)
                                        interacted = true
                                    end
                                end
                                ctx:end_combo()
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Load waveform preset")
                            end
                        end

                        -- Column 3: UI icon
                        ctx:table_set_column_index(2)
                        if drawing.draw_ui_icon(ctx, "##ui_" .. guid, 24, 20, opts.icon_font) then
                            -- Open popup curve editor instead of JSFX UI
                            state.curve_editor_popup = state.curve_editor_popup or {}
                            state.curve_editor_popup[editor_key] = state.curve_editor_popup[editor_key] or {}
                            state.curve_editor_popup[editor_key].open_requested = true
                            interacted = true
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Open Curve Editor")
                        end

                        ctx:end_table()
                    end
                    ctx:spacing()

                    -- Rate and Phase on same line (matching widths from top row)
                    -- Rate slider/dropdown
                    if tempo_mode and tempo_mode < 0.5 then
                        -- Free mode - show Hz slider (slider2)
                        -- Range: 0.01 - 10 Hz (linear, matching JSFX slider)
                        local ok_rate, rate_norm = pcall(function() return expanded_modulator:get_param_normalized(1) end)
                        if ok_rate then
                            -- Linear conversion: norm (0-1) -> Hz (0.01-10)
                            local rate_hz = 0.01 + rate_norm * 9.99

                            ctx:set_next_item_width(105)
                            -- TODO: Make slider logarithmic feel when ImGui supports it
                            local changed, new_rate = ctx:slider_double("##rate_" .. guid, rate_hz, 0.01, 10, "%.2f Hz")
                            if changed then
                                -- Convert Hz back to normalized 0-1 (linear)
                                local norm_val = (new_rate - 0.01) / 9.99
                                expanded_modulator:set_param_normalized(1, norm_val)
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
                            ctx:set_next_item_width(105)
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

                    ctx:same_line()

                    -- Phase slider (matching Preset column width for symmetry)
                    local ok_phase, phase = pcall(function() return expanded_modulator:get_param_normalized(4) end)
                    if ok_phase then
                        ctx:set_next_item_width(85)
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

                    ctx:spacing()

                    -- Trigger Mode dropdown (matching Rate column width for symmetry)
                    local ok_trig, trigger_mode_val = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_TRIGGER_MODE) end)
                    local trig_idx = nil  -- Declare outside so it's accessible in Advanced section
                    if ok_trig then
                        local trigger_modes = {"Free", "Transport", "MIDI", "Audio"}
                        trig_idx = math.floor(trigger_mode_val * 3 + 0.5)
                        ctx:set_next_item_width(105)
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

                    -- Advanced button (opens popup)
                    local advanced_popup_id = "Advanced##adv_popup_" .. guid
                    if ctx:button("⚙##adv_btn_" .. guid, 24, 0) then
                        r.ImGui_OpenPopup(ctx.ctx, advanced_popup_id)
                    end
                    if ctx:is_item_hovered() then
                        ctx:set_tooltip("Advanced Settings")
                    end
                    
                    -- Advanced popup modal
                    r.ImGui_SetNextWindowSize(ctx.ctx, 250, 0, imgui.Cond.FirstUseEver())
                    if r.ImGui_BeginPopup(ctx.ctx, advanced_popup_id) then
                        ctx:text("Advanced Settings")
                        ctx:separator()
                        
                        -- Show additional params based on trigger mode
                        if ok_trig and trig_idx == 2 then
                            -- MIDI trigger mode
                            ctx:text("MIDI Source")
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
                                ctx:set_next_item_width(150)
                                local note_val = math.floor(midi_note * 127 + 0.5)
                                local changed, new_note_val = ctx:slider_int("MIDI Note##note_" .. guid, note_val, 0, 127, note_val == 0 and "Any" or tostring(note_val))
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_MIDI_NOTE, new_note_val / 127)
                                    interacted = true
                                end
                            end
                        elseif ok_trig and trig_idx == 3 then
                            -- Audio trigger mode
                            local ok_thresh, audio_thresh = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_AUDIO_THRESHOLD) end)
                            if ok_thresh then
                                ctx:set_next_item_width(150)
                                local changed, new_thresh = ctx:slider_double("Threshold##thresh_" .. guid, audio_thresh, 0, 1, "%.2f")
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_AUDIO_THRESHOLD, new_thresh)
                                    interacted = true
                                end
                            end
                        end

                        -- Attack/Release (show when trigger mode is not Free)
                        if ok_trig and trig_idx and trig_idx > 0 then
                            ctx:spacing()
                            ctx:text("Envelope")
                            
                            -- Attack (slider24)
                            local ok_atk, attack_ms = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_ATTACK) end)
                            if ok_atk then
                                local atk_val = attack_ms * 1999 + 1  -- 1-2000ms
                                ctx:set_next_item_width(150)
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
                                ctx:set_next_item_width(150)
                                local changed, new_rel_val = ctx:slider_double("Release##rel_" .. guid, rel_val, 1, 5000, "%.0f ms")
                                if changed then
                                    expanded_modulator:set_param_normalized(PARAM.PARAM_RELEASE, (new_rel_val - 1) / 4999)
                                    interacted = true
                                end
                            end
                        end
                        
                        -- Show message if trigger mode is Free
                        if ok_trig and trig_idx == 0 then
                            ctx:text_colored(0x888888FF, "Select a trigger mode")
                            ctx:text_colored(0x888888FF, "to see more options")
                        end
                        
                        r.ImGui_EndPopup(ctx.ctx)
                    end

                    ctx:spacing()
                    ctx:separator()
                    ctx:spacing()

                    -- Parameter Links section (no label, tooltip on controls)
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
                                            param_name = param_name,
                                            scale = link_info.scale or 1.0
                                        })
                                    end
                                end
                            end
                        end
                    end

                    -- Modulator can only modulate its parent device (fx parameter)
                    -- No device selector needed - use the device that owns this container
                    local target_device = fx  -- The device being displayed

                    -- Parameter selector dropdown at TOP
                    if target_device then
                        local ok_params, param_count = pcall(function() return target_device:get_num_params() end)

                        if ok_params and param_count and param_count > 0 then
                            local current_param_name = "Link Parameter..."
                            ctx:set_next_item_width(full_width)
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
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Link modulator to parameter")
                            end
                        end
                    else
                        ctx:push_style_color(imgui.Col.Text(), 0x888888FF)
                        ctx:text("No target device")
                        ctx:pop_style_color()
                    end

                    ctx:spacing()

                    -- Show existing links with individual amount sliders
                    if #existing_links > 0 then
                        for i, link in ipairs(existing_links) do
                            -- Parameter name
                            ctx:text("• " .. link.param_name)

                            -- Amount slider (narrower, on same line)
                            ctx:same_line()
                            local amount_width = 80
                            ctx:set_next_item_width(amount_width)
                            local amount_pct = link.scale * 100
                            local changed, new_amount_pct = ctx:slider_double("##amount_" .. link.param_idx .. "_" .. guid, amount_pct, -200, 200, "%.0f%%")
                            if changed then
                                -- Update the scale using set_named_config_param
                                local plink_prefix = string.format("param.%d.plink.", link.param_idx)
                                local new_scale = new_amount_pct / 100
                                if fx:set_named_config_param(plink_prefix .. "scale", tostring(new_scale)) then
                                    interacted = true
                                end
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Modulation amount")
                            end

                            -- Remove button
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
                    end
                end
            end
        end
    end

    return interacted
end

return M
