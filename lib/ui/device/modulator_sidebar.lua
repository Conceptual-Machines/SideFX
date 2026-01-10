-- Modulator Sidebar UI Module
-- Renders the modulator grid, controls, and parameter links

local M = {}

local r = reaper
local imgui = require('imgui')
local state_module = require('lib.core.state')
local PARAM = require('lib.modulator.modulator_constants')
local param_indices = require('lib.modulator.param_indices')
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

-- Helper function to draw the modulator slot grid (4x2 grid)
local function draw_modulator_grid(ctx, guid, modulators, expanded_slot_idx, slot_width, slot_height, state, state_guid, container, opts)
    local interacted = false
    
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
    
    return interacted
end

-- Helper: Draw preset dropdown, save button, and UI icon
local function draw_preset_and_ui_controls(ctx, guid, expanded_modulator, editor_key, cfg, state, opts)
    local interacted = false
    local preset_idx, num_presets = r.TrackFX_GetPresetIndex(
        state.track.pointer,
        expanded_modulator.pointer
    )

    local mod_guid = expanded_modulator:get_guid()
    num_presets = num_presets or 0

    -- Cache preset names if presets exist and not already cached
    if num_presets > 0 and not state.cached_preset_names[mod_guid] then
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

    local cached_names = state.cached_preset_names[mod_guid] or {}
    local current_preset_name = (num_presets > 0 and cached_names[preset_idx]) or "—"

    -- Calculate widths: preset dropdown + save button + UI icon
    local full_width = cfg.mod_sidebar_width - 16
    local save_btn_width = 32
    local ui_icon_width = 28
    local combo_width = full_width - save_btn_width - ui_icon_width - 8  -- 8 for spacing

    ctx:set_next_item_width(combo_width)
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

    -- Save button with icon
    local constants = require('lib.core.constants')
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
    local save_icon = constants.icon_text(emojimgui, constants.Icons.floppy_disk)

    if opts.icon_font then
        ctx:push_font(opts.icon_font, 14)
    end
    if ctx:button(save_icon .. "##save_" .. guid, save_btn_width, 0) then
        -- Open REAPER's save preset dialog
        r.TrackFX_SetPreset(state.track.pointer, expanded_modulator.pointer, "+")
        -- Clear cache to reload presets after save
        state.cached_preset_names[mod_guid] = nil
        interacted = true
    end
    if opts.icon_font then
        ctx:pop_font()
    end
    if ctx:is_item_hovered() then
        ctx:set_tooltip("Save Preset")
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

    return interacted
end

-- Helper: Draw curve editor section (inline and popup)
local function draw_curve_editor_section(ctx, expanded_modulator, editor_key, state, track)
    local interacted = false

    state.curve_editor_state = state.curve_editor_state or {}
    state.curve_editor_state[editor_key] = state.curve_editor_state[editor_key] or {}

    local editor_width = ctx:get_content_region_avail_width()
    local editor_height = 120

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
        ctx, expanded_modulator, state.curve_editor_popup[editor_key], popup_id, track
    )
    state.curve_editor_popup[editor_key] = popup_state
    if popup_interacted then
        interacted = true
    end

    return interacted
end

-- Helper: Draw Free/Sync and Rate controls
local function draw_rate_controls(ctx, guid, expanded_modulator)
    local interacted = false
    local tempo_mode = expanded_modulator:get_param(PARAM.PARAM_TEMPO_MODE)

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

        ctx:same_line(0, 0)

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

        -- Rate slider/dropdown - fill remaining width
        if tempo_mode < 0.5 then
            -- Free mode - show Hz slider
            local ok_rate, rate_norm = pcall(function() return expanded_modulator:get_param_normalized(1) end)
            if ok_rate then
                local rate_hz = 0.01 + rate_norm * 9.99
                ctx:set_next_item_width(-1)
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
            -- Sync mode - show sync rate dropdown
            local ok_sync, sync_rate_idx = pcall(function() return expanded_modulator:get_param_normalized(2) end)
            if ok_sync then
                local sync_rates = {"8 bars", "4 bars", "2 bars", "1 bar", "1/2", "1/4", "1/4T", "1/4.", "1/8", "1/8T", "1/8.", "1/16", "1/16T", "1/16.", "1/32", "1/32T", "1/32.", "1/64"}
                local current_idx = math.floor(sync_rate_idx * 17 + 0.5)
                ctx:set_next_item_width(-1)
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
    end

    return interacted
end

-- Helper: Draw trigger mode dropdown and advanced button
local function draw_trigger_and_advanced_button(ctx, guid, expanded_modulator, opts)
    local interacted = false
    local ok_trig, trigger_mode_val = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_TRIGGER_MODE) end)
    local trig_idx = nil
    
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

    -- Advanced button with gear icon
    local constants = require('lib.core.constants')
    local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
    local gear_icon = constants.icon_text(emojimgui, constants.Icons.gear)

    local advanced_popup_id = "Advanced##adv_popup_" .. guid
    if opts.icon_font then
        ctx:push_font(opts.icon_font, 14)
    end
    if ctx:button(gear_icon .. "##adv_btn_" .. guid, 24, 0) then
        r.ImGui_OpenPopup(ctx.ctx, advanced_popup_id)
    end
    if opts.icon_font then
        ctx:pop_font()
    end
    if ctx:is_item_hovered() then
        ctx:set_tooltip("Advanced Settings")
    end
    
    return interacted, ok_trig, trig_idx, advanced_popup_id
end

-- Helper: Get existing parameter links for a modulator
local function get_existing_param_links(fx, expanded_modulator, PARAM)
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
                            offset = link_info.offset or 0
                        })
                    end
                end
            end
        end
    end
    
    return existing_links
end

-- Helper: Draw link parameter dropdown
local function draw_link_param_dropdown(ctx, guid, fx, expanded_modulator, existing_links, state, PARAM)
    local interacted = false
    
    ctx:same_line()
    
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
                            local initial_value = target_device:get_param_normalized(param_idx) or 0
                            local default_depth = 0.5
                            local success = target_device:create_param_link(
                                expanded_modulator,
                                PARAM.PARAM_OUTPUT,
                                param_idx,
                                default_depth
                            )
                            if success then
                                local plink_prefix = string.format("param.%d.plink.", param_idx)
                                local mod_prefix = string.format("param.%d.mod.", param_idx)
                                target_device:set_named_config_param(mod_prefix .. "baseline", tostring(initial_value))
                                target_device:set_named_config_param(plink_prefix .. "offset", "0")
                                
                                local link_key = guid .. "_" .. param_idx
                                state.link_baselines = state.link_baselines or {}
                                state.link_baselines[link_key] = initial_value
                                state.link_bipolar = state.link_bipolar or {}
                                state.link_bipolar[link_key] = false
                                
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
    
    return interacted
end

-- Helper: Draw advanced settings popup
local function draw_advanced_popup(ctx, guid, expanded_modulator, trig_idx, advanced_popup_id, ok_trig, PARAM)
    local interacted = false
    
    r.ImGui_SetNextWindowSize(ctx.ctx, 250, 0, imgui.Cond.FirstUseEver())
    if r.ImGui_BeginPopup(ctx.ctx, advanced_popup_id) then
        ctx:text("Advanced Settings")
        ctx:separator()
        
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
            
            local ok_atk, attack_ms = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_ATTACK) end)
            if ok_atk then
                local atk_val = attack_ms * 1999 + 1
                ctx:set_next_item_width(150)
                local changed, new_atk_val = ctx:slider_double("Attack##atk_" .. guid, atk_val, 1, 2000, "%.0f ms")
                if changed then
                    expanded_modulator:set_param_normalized(PARAM.PARAM_ATTACK, (new_atk_val - 1) / 1999)
                    interacted = true
                end
            end

            local ok_rel, release_ms = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_RELEASE) end)
            if ok_rel then
                local rel_val = release_ms * 4999 + 1
                ctx:set_next_item_width(150)
                local changed, new_rel_val = ctx:slider_double("Release##rel_" .. guid, rel_val, 1, 5000, "%.0f ms")
                if changed then
                    expanded_modulator:set_param_normalized(PARAM.PARAM_RELEASE, (new_rel_val - 1) / 4999)
                    interacted = true
                end
            end
        end
        
        if ok_trig and trig_idx == 0 then
            ctx:text_colored(0x888888FF, "Select a trigger mode")
            ctx:text_colored(0x888888FF, "to see more options")
        end
        
        r.ImGui_EndPopup(ctx.ctx)
    end
    
    return interacted
end

-- Helper: Draw existing parameter links
local function draw_existing_links(ctx, guid, fx, existing_links, state)
    local interacted = false

    if #existing_links > 0 then
        state.link_bipolar = state.link_bipolar or {}

        -- Visual separator before linked params
        ctx:separator()
        ctx:spacing()

        -- Use table for consistent column alignment
        local table_flags = r.ImGui_TableFlags_SizingFixedFit()
        if ctx:begin_table("links_" .. guid, 4, table_flags) then
            -- Setup columns: Name (fixed), U/B (fixed), Depth (stretch), X (fixed)
            r.ImGui_TableSetupColumn(ctx.ctx, "Name", r.ImGui_TableColumnFlags_WidthFixed(), 60)
            r.ImGui_TableSetupColumn(ctx.ctx, "Mode", r.ImGui_TableColumnFlags_WidthFixed(), 42)
            r.ImGui_TableSetupColumn(ctx.ctx, "Depth", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx.ctx, "Del", r.ImGui_TableColumnFlags_WidthFixed(), 20)

            for i, link in ipairs(existing_links) do
                local link_key = guid .. "_" .. link.param_idx
                local is_bipolar = state.link_bipolar[link_key] or false
                local plink_prefix = string.format("param.%d.plink.", link.param_idx)
                local actual_depth = link.scale

                ctx:table_next_row()

                -- Column 1: Parameter name
                ctx:table_set_column_index(0)
                ctx:push_style_color(imgui.Col.Text(), 0x88CCFFFF)
                local short_name = link.param_name:sub(1, 8)
                if #link.param_name > 8 then short_name = short_name .. ".." end
                ctx:text(short_name)
                ctx:pop_style_color()

                -- Column 2: Uni/Bi buttons
                ctx:table_set_column_index(1)
                if not is_bipolar then
                    ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                end
                if ctx:button("U##bi_" .. link.param_idx .. "_" .. guid, 20, 0) then
                    if is_bipolar then
                        state.link_bipolar[link_key] = false
                        fx:set_named_config_param(plink_prefix .. "offset", "0")
                        interacted = true
                    end
                end
                if not is_bipolar then
                    ctx:pop_style_color()
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Unipolar")
                end

                ctx:same_line(0, 0)

                if is_bipolar then
                    ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                end
                if ctx:button("B##bi_" .. link.param_idx .. "_" .. guid, 20, 0) then
                    if not is_bipolar then
                        state.link_bipolar[link_key] = true
                        fx:set_named_config_param(plink_prefix .. "offset", "-0.5")
                        interacted = true
                    end
                end
                if is_bipolar then
                    ctx:pop_style_color()
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Bipolar")
                end

                -- Column 3: Depth slider
                ctx:table_set_column_index(2)
                ctx:set_next_item_width(-1)
                local depth_pct = actual_depth * 100
                local changed, new_depth_pct = ctx:slider_double("##depth_" .. link.param_idx .. "_" .. guid, depth_pct, -100, 100, "%.0f%%")
                if changed then
                    local new_depth = new_depth_pct / 100
                    if is_bipolar then
                        fx:set_named_config_param(plink_prefix .. "offset", "-0.5")
                    end
                    fx:set_named_config_param(plink_prefix .. "scale", tostring(new_depth))
                    interacted = true
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Modulation depth")
                end

                -- Column 4: Remove button
                ctx:table_set_column_index(3)
                if ctx:button("X##rm_" .. i .. "_" .. guid, 18, 0) then
                    local lk = guid .. "_" .. link.param_idx
                    local restore_value = (state.link_baselines and state.link_baselines[lk]) or link.baseline or 0
                    if fx:remove_param_link(link.param_idx) then
                        fx:set_param_normalized(link.param_idx, restore_value)
                        if state.link_baselines then state.link_baselines[lk] = nil end
                        if state.link_bipolar then state.link_bipolar[lk] = nil end
                        interacted = true
                    end
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Remove link")
                end
            end

            ctx:end_table()
        end
    end
    
    return interacted
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
        if draw_modulator_grid(ctx, guid, modulators, expanded_slot_idx, slot_width, slot_height, state, state_guid, container, opts) then
            interacted = true
        end

        -- Show expanded modulator parameters
        if expanded_slot_idx ~= nil then
            local expanded_modulator = modulators[expanded_slot_idx + 1]
            if expanded_modulator then
                local ok, param_count = pcall(function() return expanded_modulator:get_num_params() end)
                if ok and param_count and param_count > 0 then
                    ctx:separator()
                    ctx:spacing()
                    
                    local editor_key = "curve_" .. guid .. "_" .. expanded_slot_idx
                    
                    -- Preset and UI icon row
                    if draw_preset_and_ui_controls(ctx, guid, expanded_modulator, editor_key, cfg, state, opts) then
                        interacted = true
                    end
                    
                    ctx:spacing()

                    -- Curve Editor section
                    if draw_curve_editor_section(ctx, expanded_modulator, editor_key, state, state.track) then
                        interacted = true
                    end
                    
                    ctx:spacing()
                    
                    -- Rate controls: Free/Sync, Rate, Phase
                    if draw_rate_controls(ctx, guid, expanded_modulator) then
                        interacted = true
                    end
                    
                    ctx:spacing()
                    
                    -- Trigger and Advanced controls
                    local trig_interacted, ok_trig, trig_idx, advanced_popup_id = draw_trigger_and_advanced_button(ctx, guid, expanded_modulator, opts)
                    if trig_interacted then
                        interacted = true
                    end
                    
                    -- Get existing parameter links
                    local existing_links = get_existing_param_links(fx, expanded_modulator, PARAM)
                    
                    -- Link Parameter dropdown
                    if draw_link_param_dropdown(ctx, guid, fx, expanded_modulator, existing_links, state, PARAM) then
                        interacted = true
                    end
                    
                    -- Advanced popup modal
                    if draw_advanced_popup(ctx, guid, expanded_modulator, trig_idx, advanced_popup_id, ok_trig, PARAM) then
                        interacted = true
                    end
                    
                    -- Show existing parameter links
                    ctx:spacing()
                    if draw_existing_links(ctx, guid, fx, existing_links, state) then
                        interacted = true
                    end
                end
            end
        end
    end

    return interacted
end

return M
