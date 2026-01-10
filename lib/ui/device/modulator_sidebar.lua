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
                    
                    -- Define editor key (used by preset/UI and curve editor)
                    local editor_key = "curve_" .. guid .. "_" .. expanded_slot_idx
                    
                    -- Preset and UI icon row (above editor)
                    local preset_idx, num_presets = r.TrackFX_GetPresetIndex(
                        state.track.pointer,
                        expanded_modulator.pointer
                    )
                    
                    if num_presets and num_presets > 0 then
                        local mod_guid = expanded_modulator:get_guid()
                        if not state.cached_preset_names[mod_guid] then
                            state.cached_preset_names[mod_guid] = {}
                            local original_idx = preset_idx
                            for i = 0, num_presets - 1 do
                                r.TrackFX_SetPresetByIndex(state.track.pointer, expanded_modulator.pointer, i)
                                local name = expanded_modulator:get_preset() or ("Preset " .. (i + 1))
                                state.cached_preset_names[mod_guid][i] = name
                            end
                            if original_idx >= 0 then
                                r.TrackFX_SetPresetByIndex(state.track.pointer, expanded_modulator.pointer, original_idx)
                            end
                        end
                        
                        local cached_names = state.cached_preset_names[mod_guid]
                        local current_preset_name = cached_names[preset_idx] or "—"
                        
                        local full_width = cfg.mod_sidebar_width - 16
                        ctx:set_next_item_width(full_width - 32)
                        if ctx:begin_combo("##preset_" .. guid, current_preset_name) then
                            for i = 0, num_presets - 1 do
                                local preset_name = cached_names[i] or ("Preset " .. (i + 1))
                                if ctx:selectable(preset_name, i == preset_idx) then
                                    r.TrackFX_SetPresetByIndex(state.track.pointer, expanded_modulator.pointer, i)
                                    interacted = true
                                end
                            end
                            ctx:end_combo()
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Waveform Preset")
                        end
                        
                        ctx:same_line()
                        
                        -- UI icon
                        if drawing.draw_ui_icon(ctx, "##ui_" .. guid, 24, 20, opts.icon_font) then
                            state.curve_editor_popup = state.curve_editor_popup or {}
                            state.curve_editor_popup[editor_key] = state.curve_editor_popup[editor_key] or {}
                            state.curve_editor_popup[editor_key].open_requested = true
                            interacted = true
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Open Curve Editor")
                        end
                    end
                    
                    ctx:spacing()
                    
                    -- Curve Editor (main visual element)
                    state.curve_editor_state = state.curve_editor_state or {}
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

                    -- All main controls on one line: Free/Sync | Rate | Phase
                    local tempo_mode = expanded_modulator:get_param(PARAM.PARAM_TEMPO_MODE)

                    -- Free/Sync segmented buttons
                    if tempo_mode then
                        local is_free = tempo_mode < 0.5
                        
                        -- Free button
                        if is_free then
                            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                        end
                        if ctx:button("Free##tempo_" .. guid, 52, 0) then
                            expanded_modulator:set_param(PARAM.PARAM_TEMPO_MODE, 0)
                            interacted = true
                        end
                        if is_free then
                            ctx:pop_style_color()
                        end
                        
                        ctx:same_line(0, 0)  -- No gap
                        
                        -- Sync button
                        if not is_free then
                            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                        end
                        if ctx:button("Sync##tempo_" .. guid, 52, 0) then
                            expanded_modulator:set_param(PARAM.PARAM_TEMPO_MODE, 1)
                            interacted = true
                        end
                        if not is_free then
                            ctx:pop_style_color()
                        end
                        
                        ctx:same_line()
                        
                        -- Rate slider/dropdown
                        if tempo_mode < 0.5 then
                            -- Free mode - show Hz slider (slider2)
                            local ok_rate, rate_norm = pcall(function() return expanded_modulator:get_param_normalized(1) end)
                            if ok_rate then
                                local rate_hz = 0.01 + rate_norm * 9.99
                                ctx:set_next_item_width(80)
                                local changed, new_rate = ctx:slider_double("##rate_" .. guid, rate_hz, 0.01, 10, "%.1f Hz")
                                if changed then
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
                                ctx:set_next_item_width(80)
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
                        
                        -- Phase slider
                        local ok_phase, phase = pcall(function() return expanded_modulator:get_param_normalized(4) end)
                        if ok_phase then
                            ctx:set_next_item_width(70)
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
                    end

                    ctx:spacing()

                    -- Trigger Mode dropdown
                    local ok_trig, trigger_mode_val = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_TRIGGER_MODE) end)
                    local trig_idx = nil  -- Declare outside so it's accessible in Advanced section
                    if ok_trig then
                        local trigger_modes = {"Free", "Transport", "MIDI", "Audio"}
                        trig_idx = math.floor(trigger_mode_val * 3 + 0.5)
                        ctx:set_next_item_width(80)
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
                    
                    -- Advanced button
                    local advanced_popup_id = "Advanced##adv_popup_" .. guid
                    if ctx:button("⚙##adv_btn_" .. guid, 24, 0) then
                        r.ImGui_OpenPopup(ctx.ctx, advanced_popup_id)
                    end
                    if ctx:is_item_hovered() then
                        ctx:set_tooltip("Advanced Settings")
                    end
                    
                    ctx:same_line()

                    -- Calculate parameter links section
                    local existing_links = {}
                    local expected_mod_idx = nil
                    local my_parent = fx:get_parent_container()
                    if my_parent then
                        local children = my_parent:get_container_children()
                        local mod_guid = expanded_modulator:get_guid()
                        for i, child in ipairs(children) do
                            if child:get_guid() == mod_guid then
                                expected_mod_idx = i - 1
                                break
                            end
                        end
                    end
                    
                    if expected_mod_idx ~= nil then
                        local ok_params, param_count = pcall(function() return fx:get_num_params() end)
                        if ok_params and param_count then
                            for param_idx = 0, param_count - 1 do
                                local link_info = fx:get_param_link_info(param_idx)
                                if link_info and link_info.effect == expected_mod_idx and link_info.param == PARAM.PARAM_OUTPUT then
                                    local ok_pname, param_name = pcall(function() return fx:get_param_name(param_idx) end)
                                    if ok_pname and param_name then
                                        table.insert(existing_links, {
                                            param_idx = param_idx,
                                            param_name = param_name,
                                            scale = link_info.scale or 1.0,
                                            offset = link_info.offset or 0  -- Stored initial value
                                        })
                                    end
                                end
                            end
                        end
                    end
                    
                    ctx:same_line()
                    
                    -- Link Parameter dropdown (on same line as Trigger)
                    local target_device = fx
                    if target_device then
                        local ok_params, param_count = pcall(function() return target_device:get_num_params() end)
                        if ok_params and param_count and param_count > 0 then
                            local current_param_name = "Link..."
                            ctx:set_next_item_width(158)
                            if ctx:begin_combo("##link_param_" .. guid, current_param_name) then
                                for param_idx = 0, param_count - 1 do
                                    local ok_pname, param_name = pcall(function() return target_device:get_param_name(param_idx) end)
                                    if ok_pname and param_name then
                                        local is_linked = false
                                        for _, link in ipairs(existing_links) do
                                            if link.param_idx == param_idx then
                                                is_linked = true
                                                break
                                            end
                                        end
                                        if ctx:selectable(param_name .. (is_linked and " ✓" or ""), false) then
                                            -- Capture current param value BEFORE linking
                                            local initial_value = target_device:get_param_normalized(param_idx) or 0
                                            
                                            local success = target_device:create_param_link(
                                                expanded_modulator,
                                                PARAM.PARAM_OUTPUT,
                                                param_idx,
                                                1.0
                                            )
                                            if success then
                                                -- Store initial value as plink offset
                                                local plink_prefix = string.format("param.%d.plink.", param_idx)
                                                target_device:set_named_config_param(plink_prefix .. "offset", tostring(initial_value))
                                                interacted = true
                                            end
                                        end
                                    end
                                end
                                ctx:end_combo()
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Link to parameter")
                            end
                        end
                    end
                    
                    -- Advanced popup modal (defined earlier on same line)
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

                    -- Show existing links with visualization
                    ctx:spacing()
                    if #existing_links > 0 then
                        -- Track bipolar state per link (stored in state table)
                        state.link_bipolar = state.link_bipolar or {}
                        
                        for i, link in ipairs(existing_links) do
                            local link_key = guid .. "_" .. link.param_idx
                            local is_bipolar = state.link_bipolar[link_key] or false
                            
                            -- Row 1: Parameter name and visualization bar
                            local short_name = link.param_name:sub(1, 16)
                            if #link.param_name > 16 then short_name = short_name .. ".." end
                            ctx:text(short_name)
                            
                            ctx:same_line()
                            
                            -- Visualization bar: static param value + moving modulated indicator
                            local bar_width = 120
                            local bar_height = 14
                            local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                            local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                            
                            -- Get current modulated value
                            local ok_target, current_val = pcall(function() return target_device:get_param_normalized(link.param_idx) end)
                            if not ok_target or not current_val then current_val = 0 end
                            
                            local offset = link.offset or 0  -- Initial/base value (static)
                            local depth = link.scale
                            
                            -- Draw background track
                            r.ImGui_DrawList_AddRectFilled(draw_list,
                                cursor_x, cursor_y,
                                cursor_x + bar_width, cursor_y + bar_height,
                                0x222222FF)
                            
                            -- Draw static filled bar showing initial param value (offset)
                            r.ImGui_DrawList_AddRectFilled(draw_list,
                                cursor_x, cursor_y + 2,
                                cursor_x + offset * bar_width, cursor_y + bar_height - 2,
                                0x4466AAFF)  -- Static blue fill
                            
                            -- Draw modulation range overlay (semi-transparent)
                            local min_mod, max_mod
                            if is_bipolar then
                                min_mod = math.max(0, offset - math.abs(depth))
                                max_mod = math.min(1, offset + math.abs(depth))
                            else
                                if depth >= 0 then
                                    min_mod = offset
                                    max_mod = math.min(1, offset + depth)
                                else
                                    min_mod = math.max(0, offset + depth)
                                    max_mod = offset
                                end
                            end
                            r.ImGui_DrawList_AddRectFilled(draw_list,
                                cursor_x + min_mod * bar_width, cursor_y,
                                cursor_x + max_mod * bar_width, cursor_y + bar_height,
                                0x88CCFF33)  -- Semi-transparent range
                            
                            -- Draw moving indicator (current modulated value)
                            local indicator_x = cursor_x + current_val * bar_width
                            r.ImGui_DrawList_AddRectFilled(draw_list,
                                indicator_x - 2, cursor_y,
                                indicator_x + 2, cursor_y + bar_height,
                                0xFFFFFFFF)  -- White indicator
                            
                            -- Draw border
                            r.ImGui_DrawList_AddRect(draw_list,
                                cursor_x, cursor_y,
                                cursor_x + bar_width, cursor_y + bar_height,
                                0x555555FF)
                            
                            -- Capture mouse on bar
                            ctx:invisible_button("##bar_" .. link.param_idx .. "_" .. guid, bar_width, bar_height)
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip(string.format("%s\nBase: %.0f%%  Current: %.0f%%  Depth: %.0f%%", 
                                    link.param_name, offset * 100, current_val * 100, depth * 100))
                            end
                            
                            ctx:same_line()
                            
                            -- Remove button
                            if ctx:button("X##rm_" .. i .. "_" .. guid, 18, 0) then
                                local restore_value = link.offset or 0
                                if fx:remove_param_link(link.param_idx) then
                                    fx:set_param_normalized(link.param_idx, restore_value)
                                    interacted = true
                                end
                            end
                            if ctx:is_item_hovered() then
                                ctx:set_tooltip("Remove link")
                            end
                            
                            -- Row 2: Uni/Bi buttons + Depth slider
                            -- Uni button
                            if not is_bipolar then
                                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                            end
                            if ctx:button("Uni##bi_" .. link.param_idx .. "_" .. guid, 32, 0) then
                                state.link_bipolar[link_key] = false
                                interacted = true
                            end
                            if not is_bipolar then
                                ctx:pop_style_color()
                            end
                            
                            ctx:same_line(0, 0)
                            
                            -- Bi button
                            if is_bipolar then
                                ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                            end
                            if ctx:button("Bi##bi_" .. link.param_idx .. "_" .. guid, 24, 0) then
                                state.link_bipolar[link_key] = true
                                interacted = true
                            end
                            if is_bipolar then
                                ctx:pop_style_color()
                            end
                            
                            ctx:same_line()
                            
                            -- Depth/Amount slider
                            ctx:set_next_item_width(100)
                            local depth_pct = link.scale * 100
                            local changed, new_depth_pct = ctx:slider_double("##depth_" .. link.param_idx .. "_" .. guid, depth_pct, -200, 200, "Depth %.0f%%")
                            if changed then
                                local plink_prefix = string.format("param.%d.plink.", link.param_idx)
                                local new_scale = new_depth_pct / 100
                                if fx:set_named_config_param(plink_prefix .. "scale", tostring(new_scale)) then
                                    interacted = true
                                end
                            end
                            
                            ctx:spacing()
                        end
                    end
                end
            end
        end
    end

    return interacted
end

return M
