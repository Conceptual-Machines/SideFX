-- Modulator Sidebar UI Module
-- Renders the modulator grid, controls, and parameter links

local M = {}

local r = reaper
local imgui = require('imgui')
local state_module = require('lib.core.state')
local config = require('lib.core.config')
local PARAM = require('lib.modulator.modulator_constants')
local drawing = require('lib.ui.common.drawing')
local modulator_module = require('lib.modulator.modulator')
local curve_editor = require('lib.ui.common.curve_editor')
local modulator_presets = require('lib.modulator.modulator_presets')
local modulator_bake = require('lib.modulator.modulator_bake')

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

    -- Add padding around the grid
    ctx:spacing()
    ctx:indent(8)  -- Left padding

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
                        -- CRITICAL: Don't add modulator immediately - it changes FX indices mid-render!
                        -- Instead, defer the addition to next frame to avoid stale pointer errors.
                        local track = opts.track or state.track
                        if track and container then
                            -- Store container GUID (stable across FX changes)
                            local ok_guid, container_guid = pcall(function() return container:get_guid() end)
                            if ok_guid and container_guid then
                                -- Queue the modulator addition for next frame
                                state.pending_modulator_add = state.pending_modulator_add or {}
                                table.insert(state.pending_modulator_add, {
                                    container_guid = container_guid,
                                    modulator_type = MODULATOR_TYPES[1],
                                    state_guid = state_guid,  -- For selecting after add
                                })
                                -- Invalidate FX list to bail out of current render
                                state_module.invalidate_fx_list()
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
    local mod_guid = expanded_modulator:get_guid()

    -- Cache preset names and sources by reading from .rpl files (non-destructive)
    if not state.cached_preset_names[mod_guid] then
        local names, sources = modulator_presets.get_preset_names()
        state.cached_preset_names[mod_guid] = {}
        state.cached_preset_sources = state.cached_preset_sources or {}
        state.cached_preset_sources[mod_guid] = {}
        for i, name in ipairs(names) do
            state.cached_preset_names[mod_guid][i - 1] = name  -- 0-indexed
            state.cached_preset_sources[mod_guid][i - 1] = sources[i]
        end
    end

    local cached_names = state.cached_preset_names[mod_guid] or {}
    local cached_sources = (state.cached_preset_sources and state.cached_preset_sources[mod_guid]) or {}

    -- Get current preset name from REAPER's index, or use our tracked name after save/select
    state.current_preset_name = state.current_preset_name or {}
    local current_preset_name
    local preset_idx = r.TrackFX_GetPresetIndex(state.track.pointer, expanded_modulator.pointer)

    if state.current_preset_name[mod_guid] then
        -- Use our tracked name (set after save or select)
        current_preset_name = state.current_preset_name[mod_guid]
    elseif preset_idx >= 0 and cached_names[preset_idx] then
        -- Use REAPER's index to look up name
        current_preset_name = cached_names[preset_idx]
    else
        -- Fallback to first preset name
        current_preset_name = cached_names[0] or "Sine"
    end

    -- Use table for preset row: Preset (stretch) | Save (fixed) | UI (fixed)
    local table_flags = r.ImGui_TableFlags_SizingFixedFit()
    local icon_btn_size = 24
    if ctx:begin_table("preset_row_" .. guid, 3, table_flags) then
        r.ImGui_TableSetupColumn(ctx.ctx, "Preset", r.ImGui_TableColumnFlags_WidthStretch(), 1)
        r.ImGui_TableSetupColumn(ctx.ctx, "Save", r.ImGui_TableColumnFlags_WidthFixed(), icon_btn_size)
        r.ImGui_TableSetupColumn(ctx.ctx, "UI", r.ImGui_TableColumnFlags_WidthFixed(), icon_btn_size)

        ctx:table_next_row()

        -- Column 1: Preset dropdown
        ctx:table_set_column_index(0)
        ctx:set_next_item_width(-1)
        -- Count presets from our cache (more reliable than REAPER's count after .ini deletion)
        local cache_count = 0
        for _ in pairs(cached_names) do cache_count = cache_count + 1 end
        if ctx:begin_combo("##preset_" .. guid, current_preset_name) then
            local shown_user_header = false
            for i = 0, cache_count - 1 do
                local preset_name = cached_names[i] or ("Preset " .. (i + 1))
                local source = cached_sources[i] or "factory"

                -- Show "User Presets" header before first user preset
                if source == "user" and not shown_user_header then
                    ctx:separator()
                    r.ImGui_PushStyleColor(ctx.ctx, r.ImGui_Col_Text(), 0x888888FF)
                    ctx:text("User Presets")
                    r.ImGui_PopStyleColor(ctx.ctx)
                    ctx:separator()
                    shown_user_header = true
                end

                local is_selected = (preset_name == current_preset_name)
                if ctx:selectable(preset_name .. "##preset_item_" .. i, is_selected) then
                    -- Load preset directly from .rpl file (bypasses REAPER's potentially stale index)
                    local loaded = modulator_presets.load_preset_by_name(
                        state.track.pointer,
                        expanded_modulator.pointer,
                        preset_name
                    )
                    if loaded then
                        state.current_preset_name[mod_guid] = preset_name
                    end
                    interacted = true
                end
            end
            ctx:end_combo()
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Waveform Preset")
        end

        -- Column 2: Save button with icon
        ctx:table_set_column_index(1)
        local constants = require('lib.core.constants')
        local emojimgui = package.loaded['emojimgui'] or require('emojimgui')
        local save_icon = constants.icon_text(emojimgui, constants.Icons.floppy_disk)

        if opts.icon_font then
            ctx:push_font(opts.icon_font, 14)
        end
        if ctx:button(save_icon .. "##save_" .. guid, icon_btn_size, 0) then
            -- Open save preset popup, pre-fill with current preset name
            state.save_preset_popup = state.save_preset_popup or {}
            state.save_preset_popup[mod_guid] = {
                open = true,
                name = current_preset_name or "",
                modulator = expanded_modulator
            }
            interacted = true
        end
        if opts.icon_font then
            ctx:pop_font()
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Save Preset")
        end

        -- Column 3: UI icon
        ctx:table_set_column_index(2)
        if drawing.draw_ui_icon(ctx, "##ui_" .. guid, icon_btn_size, icon_btn_size, opts.icon_font) then
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
            -- Free mode - show Hz slider using normalized 0-1 range for fine control
            local ok_rate, rate_norm = pcall(function() return expanded_modulator:get_param_normalized(1) end)
            if ok_rate then
                -- Get slider position BEFORE drawing
                local slider_x, slider_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                ctx:set_next_item_width(-1)

                -- Use normalized 0-1 for slider (like FX params), display as space, overlay Hz text
                -- Default: 1Hz = (1 - 0.01) / 9.99 ≈ 0.099
                local default_norm = (1.0 - 0.01) / 9.99
                local changed, new_norm = drawing.slider_double_fine(ctx, "##rate_" .. guid, rate_norm, 0.0, 1.0, " ", nil, 1, default_norm)

                -- Overlay Hz value on slider
                local rate_hz = 0.01 + rate_norm * 9.99
                local hz_text = string.format("%.2f Hz", rate_hz)
                local text_w = r.ImGui_CalcTextSize(ctx.ctx, hz_text)
                local slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
                local text_x = slider_x + (avail_w - text_w) / 2
                local text_y = slider_y + (slider_h - r.ImGui_GetTextLineHeight(ctx.ctx)) / 2
                local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0xFFFFFFFF, hz_text)

                if changed then
                    expanded_modulator:set_param_normalized(1, new_norm)
                    interacted = true
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
            ctx:set_next_item_width(-1)
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
                -- Default threshold: 0.5
                local changed, new_thresh = drawing.slider_double_fine(ctx, "Threshold##thresh_" .. guid, audio_thresh, 0, 1, "%.2f", 0.01, nil, 0.5)
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
                -- Default attack: 10ms
                local changed, new_atk_val = drawing.slider_double_fine(ctx, "Attack##atk_" .. guid, atk_val, 1, 2000, "%.0f ms", nil, nil, 10)
                if changed then
                    expanded_modulator:set_param_normalized(PARAM.PARAM_ATTACK, (new_atk_val - 1) / 1999)
                    interacted = true
                end
            end

            local ok_rel, release_ms = pcall(function() return expanded_modulator:get_param_normalized(PARAM.PARAM_RELEASE) end)
            if ok_rel then
                local rel_val = release_ms * 4999 + 1
                ctx:set_next_item_width(150)
                -- Default release: 100ms
                local changed, new_rel_val = drawing.slider_double_fine(ctx, "Release##rel_" .. guid, rel_val, 1, 5000, "%.0f ms", nil, nil, 100)
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
local function draw_existing_links(ctx, guid, fx, existing_links, state, expanded_modulator, opts)
    local interacted = false

    if #existing_links > 0 then
        state.link_bipolar = state.link_bipolar or {}
        state.link_disabled = state.link_disabled or {}
        state.link_saved_scale = state.link_saved_scale or {}

        -- Visual separator before linked params
        ctx:separator()
        ctx:spacing()

        -- Use table for consistent column alignment
        -- Columns: Name | U/B | Depth | Disable | Bake | Remove
        local table_flags = r.ImGui_TableFlags_SizingFixedFit()
        if ctx:begin_table("links_" .. guid, 6, table_flags) then
            r.ImGui_TableSetupColumn(ctx.ctx, "Name", r.ImGui_TableColumnFlags_WidthFixed(), 55)
            r.ImGui_TableSetupColumn(ctx.ctx, "Mode", r.ImGui_TableColumnFlags_WidthFixed(), 42)
            r.ImGui_TableSetupColumn(ctx.ctx, "Depth", r.ImGui_TableColumnFlags_WidthStretch(), 1)
            r.ImGui_TableSetupColumn(ctx.ctx, "Dis", r.ImGui_TableColumnFlags_WidthFixed(), 18)
            r.ImGui_TableSetupColumn(ctx.ctx, "Bake", r.ImGui_TableColumnFlags_WidthFixed(), 18)
            r.ImGui_TableSetupColumn(ctx.ctx, "Del", r.ImGui_TableColumnFlags_WidthFixed(), 18)

            for i, link in ipairs(existing_links) do
                local link_key = guid .. "_" .. link.param_idx
                local is_bipolar = state.link_bipolar[link_key] or false
                local plink_prefix = string.format("param.%d.plink.", link.param_idx)
                local actual_depth = link.scale

                -- Check if link is disabled (scale ~= 0 or we have saved scale)
                local is_disabled = state.link_disabled[link_key] or false
                -- Also detect if scale is 0 but we don't have it tracked
                if math.abs(actual_depth) < 0.001 and state.link_saved_scale[link_key] then
                    is_disabled = true
                    state.link_disabled[link_key] = true
                end

                ctx:table_next_row()

                -- Grey out disabled links
                if is_disabled then
                    ctx:push_style_color(imgui.Col.Text(), 0x666666FF)
                end

                -- Column 1: Parameter name
                ctx:table_set_column_index(0)
                if not is_disabled then
                    ctx:push_style_color(imgui.Col.Text(), 0x88CCFFFF)
                end
                local short_name = link.param_name:sub(1, 7)
                if #link.param_name > 7 then short_name = short_name .. ".." end
                ctx:text(short_name)
                if not is_disabled then
                    ctx:pop_style_color()
                end

                -- Column 2: Uni/Bi buttons
                ctx:table_set_column_index(1)
                if not is_bipolar and not is_disabled then
                    ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                end
                if ctx:button("U##bi_" .. link.param_idx .. "_" .. guid, 20, 0) then
                    if is_bipolar then
                        state.link_bipolar[link_key] = false
                        fx:set_named_config_param(plink_prefix .. "offset", "0")
                        interacted = true
                    end
                end
                if not is_bipolar and not is_disabled then
                    ctx:pop_style_color()
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Unipolar")
                end

                ctx:same_line(0, 0)

                if is_bipolar and not is_disabled then
                    ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
                end
                if ctx:button("B##bi_" .. link.param_idx .. "_" .. guid, 20, 0) then
                    if not is_bipolar then
                        state.link_bipolar[link_key] = true
                        fx:set_named_config_param(plink_prefix .. "offset", "-0.5")
                        interacted = true
                    end
                end
                if is_bipolar and not is_disabled then
                    ctx:pop_style_color()
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Bipolar")
                end

                -- Column 3: Depth slider (use 0-1 internal range, scale to -1 to 1)
                ctx:table_set_column_index(2)
                -- Get slider position BEFORE drawing
                local depth_slider_x, depth_slider_y = r.ImGui_GetCursorScreenPos(ctx.ctx)
                local depth_avail_w = r.ImGui_GetContentRegionAvail(ctx.ctx)
                ctx:set_next_item_width(-1)

                local depth_value = is_disabled and (state.link_saved_scale[link_key] or 0) or actual_depth
                -- Convert -1 to 1 range to 0-1 for slider (better granularity)
                local depth_norm = (depth_value + 1) / 2

                if is_disabled then
                    r.ImGui_BeginDisabled(ctx.ctx)
                end
                -- Default depth: 0.5 = 0.75 normalized ((0.5 + 1) / 2)
                local changed, new_depth_norm = drawing.slider_double_fine(ctx, "##depth_" .. link.param_idx .. "_" .. guid, depth_norm, 0.0, 1.0, " ", nil, 1, 0.75)

                -- Overlay depth value on slider
                local display_depth = depth_norm * 2 - 1
                local depth_text = string.format("%.2f", display_depth)
                local depth_text_w = r.ImGui_CalcTextSize(ctx.ctx, depth_text)
                local depth_slider_h = r.ImGui_GetFrameHeight(ctx.ctx)
                local depth_text_x = depth_slider_x + (depth_avail_w - depth_text_w) / 2
                local depth_text_y = depth_slider_y + (depth_slider_h - r.ImGui_GetTextLineHeight(ctx.ctx)) / 2
                local depth_draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
                r.ImGui_DrawList_AddText(depth_draw_list, depth_text_x, depth_text_y, 0xFFFFFFFF, depth_text)

                if changed and not is_disabled then
                    local new_depth = new_depth_norm * 2 - 1  -- Convert back to -1 to 1
                    if is_bipolar then
                        fx:set_named_config_param(plink_prefix .. "offset", "-0.5")
                    end
                    fx:set_named_config_param(plink_prefix .. "scale", tostring(new_depth))
                    interacted = true
                end
                if is_disabled then
                    r.ImGui_EndDisabled(ctx.ctx)
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Modulation depth")
                end

                -- Column 4: Disable/Enable toggle button
                ctx:table_set_column_index(3)
                local disable_icon = is_disabled and ">" or "||"
                if is_disabled then
                    ctx:push_style_color(imgui.Col.Button(), 0x444444FF)
                end
                if ctx:button(disable_icon .. "##dis_" .. i .. "_" .. guid, 18, 0) then
                    if is_disabled then
                        -- Re-enable: restore saved scale
                        local saved = state.link_saved_scale[link_key] or 0.5
                        fx:set_named_config_param(plink_prefix .. "scale", tostring(saved))
                        state.link_disabled[link_key] = false
                    else
                        -- Disable: save current scale, set to 0
                        state.link_saved_scale[link_key] = actual_depth
                        fx:set_named_config_param(plink_prefix .. "scale", "0")
                        state.link_disabled[link_key] = true
                    end
                    interacted = true
                end
                if is_disabled then
                    ctx:pop_style_color()
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip(is_disabled and "Enable link" or "Disable link")
                end

                -- Column 5: Bake button
                ctx:table_set_column_index(4)
                if ctx:button("B##bake_" .. i .. "_" .. guid, 18, 0) then
                    -- Check config: show picker or use default?
                    if config.get('bake_show_range_picker') then
                        -- Open bake modal for this specific link
                        state.bake_modal = state.bake_modal or {}
                        state.bake_modal[guid] = {
                            open = true,
                            link = link,
                            modulator = expanded_modulator,
                            fx = fx
                        }
                    else
                        -- Use default range directly
                        local bake_options = {
                            range_mode = config.get('bake_default_range_mode'),
                            disable_link = config.get('bake_disable_link_after')
                        }
                        local ok, result, msg = pcall(function()
                            return modulator_bake.bake_to_automation(state.track, expanded_modulator, fx, link.param_idx, bake_options)
                        end)
                        if ok and result then
                            r.ShowConsoleMsg("SideFX: " .. (msg or "Baked") .. "\n")
                        elseif not ok then
                            r.ShowConsoleMsg("SideFX Bake Error: " .. tostring(result) .. "\n")
                        else
                            r.ShowConsoleMsg("SideFX: " .. tostring(msg or "No automation created") .. "\n")
                        end
                    end
                    interacted = true
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Bake to automation")
                end

                -- Column 6: Remove button
                ctx:table_set_column_index(5)
                if ctx:button("X##rm_" .. i .. "_" .. guid, 18, 0) then
                    local lk = guid .. "_" .. link.param_idx
                    local restore_value = (state.link_baselines and state.link_baselines[lk]) or link.baseline or 0
                    if fx:remove_param_link(link.param_idx) then
                        fx:set_param_normalized(link.param_idx, restore_value)
                        if state.link_baselines then state.link_baselines[lk] = nil end
                        if state.link_bipolar then state.link_bipolar[lk] = nil end
                        if state.link_disabled then state.link_disabled[lk] = nil end
                        if state.link_saved_scale then state.link_saved_scale[lk] = nil end
                        interacted = true
                    end
                end
                if ctx:is_item_hovered() then
                    ctx:set_tooltip("Remove link")
                end

                if is_disabled then
                    ctx:pop_style_color()
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

    -- Process pending modulator selection (from previous frame's add operation)
    if state.pending_mod_selection and state.pending_mod_selection[state_guid] then
        local pending = state.pending_mod_selection[state_guid]
        local container_guid = pending.container_guid
        local mod_guid = pending.mod_guid

        -- Only process if this is the right container (safely get GUID)
        local ok_container_guid, current_guid = pcall(function()
            return container and container:get_guid()
        end)
        if ok_container_guid and current_guid == container_guid then
            local modulators = get_device_modulators(container)
            for idx, mod in ipairs(modulators) do
                local ok_guid, m_guid = pcall(function() return mod:get_guid() end)
                if ok_guid and m_guid == mod_guid then
                    state.expanded_mod_slot[state_guid] = idx - 1  -- 0-based slot index
                    break
                end
            end
            -- Clear the pending selection
            state.pending_mod_selection[state_guid] = nil
        end
    end

    state.cached_preset_names = state.cached_preset_names or {}

    local is_mod_sidebar_collapsed = state.mod_sidebar_collapsed[state_guid] or false

    if is_mod_sidebar_collapsed then
        -- Collapsed: show 8 vertical buttons for mod slots
        local modulators = get_device_modulators(container)
        local btn_size = 20

        for slot_idx = 0, 7 do
            local mod = modulators[slot_idx + 1]
            local has_mod = mod ~= nil

            -- Green highlight if slot has a modulator
            if has_mod then
                ctx:push_style_color(imgui.Col.Button(), 0x3A5A3AFF)
            end

            local label = tostring(slot_idx + 1) .. "##mod_slot_" .. slot_idx .. "_" .. guid
            if ctx:button(label, btn_size, btn_size) then
                if has_mod then
                    -- Select this mod and expand sidebar
                    state.expanded_mod_slot[state_guid] = slot_idx
                    state.mod_sidebar_collapsed[state_guid] = false
                    interacted = true
                end
            end

            if has_mod then
                ctx:pop_style_color()
            end

            if ctx:is_item_hovered() then
                if has_mod then
                    ctx:set_tooltip("LFO " .. (slot_idx + 1))
                else
                    ctx:set_tooltip("Empty slot " .. (slot_idx + 1))
                end
            end
        end
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
                    if draw_existing_links(ctx, guid, fx, existing_links, state, expanded_modulator, opts) then
                        interacted = true
                    end

                    -- Bake All button (opens modal or uses default range)
                    if #existing_links > 0 then
                        ctx:spacing()
                        ctx:separator()
                        ctx:spacing()

                        local can_bake = state.track ~= nil
                        if not can_bake then
                            r.ImGui_BeginDisabled(ctx.ctx)
                        end
                        if ctx:button("Bake All##bake_all_" .. guid, -1, 0) then
                            if can_bake then
                                -- Check config: show picker or use default?
                                if config.get('bake_show_range_picker') then
                                    -- Open bake modal for all links
                                    state.bake_modal = state.bake_modal or {}
                                    state.bake_modal[guid] = {
                                        open = true,
                                        link = nil,  -- nil = all links
                                        links = existing_links,
                                        modulator = expanded_modulator,
                                        fx = fx
                                    }
                                else
                                    -- Use default range directly
                                    local bake_options = {
                                        range_mode = config.get('bake_default_range_mode'),
                                        disable_link = config.get('bake_disable_link_after')
                                    }
                                    local ok, result, msg = pcall(function()
                                        return modulator_bake.bake_all_links(state.track, expanded_modulator, fx, existing_links, bake_options)
                                    end)
                                    if ok and result then
                                        r.ShowConsoleMsg("SideFX: " .. (msg or "Baked") .. "\n")
                                    elseif not ok then
                                        r.ShowConsoleMsg("SideFX Bake Error: " .. tostring(result) .. "\n")
                                    else
                                        r.ShowConsoleMsg("SideFX: " .. tostring(msg or "No parameters to bake") .. "\n")
                                    end
                                end
                                interacted = true
                            end
                        end
                        if not can_bake then
                            r.ImGui_EndDisabled(ctx.ctx)
                        end
                        if ctx:is_item_hovered() then
                            ctx:set_tooltip("Bake all linked parameters to automation")
                        end
                    end
                end
            end
        end
    end

    -- Draw save preset popup (regular popup, no grey background)
    state.save_preset_popup = state.save_preset_popup or {}
    for mod_guid, popup_state in pairs(state.save_preset_popup) do
        if popup_state.open then
            local popup_id = "Save Preset##save_preset_" .. mod_guid
            if not popup_state.opened_frame then
                r.ImGui_OpenPopup(ctx.ctx, popup_id)
                popup_state.opened_frame = true
            end

            local popup_flags = r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoMove()
            local visible = r.ImGui_BeginPopup(ctx.ctx, popup_id, popup_flags)
            local p_open = visible  -- For regular popups, visible means open
            if visible then
                ctx:text("Enter preset name:")
                ctx:spacing()

                ctx:set_next_item_width(200)
                local changed, new_name = ctx:input_text("##preset_name_" .. mod_guid, popup_state.name or "")
                if changed then
                    popup_state.name = new_name
                end

                ctx:spacing()
                ctx:separator()
                ctx:spacing()

                local can_save = popup_state.name and #popup_state.name > 0

                if not can_save then
                    r.ImGui_BeginDisabled(ctx.ctx)
                end
                if ctx:button("Save##save_" .. mod_guid, 80, 0) then
                    -- Save the preset using our backend
                    local mod = popup_state.modulator
                    if mod and state.track then
                        local should_save = true
                        local preset_name = popup_state.name

                        -- Check if preset already exists
                        if modulator_presets.preset_exists(preset_name) then
                            -- Ask user for confirmation (6 = Yes, 7 = No)
                            local result = r.ShowMessageBox(
                                "A preset named '" .. preset_name .. "' already exists.\n\nDo you want to overwrite it?",
                                "SideFX - Preset Exists",
                                4  -- MB_YESNO
                            )
                            if result == 6 then  -- Yes
                                -- Delete old preset first
                                modulator_presets.delete_preset(preset_name)
                            else
                                should_save = false
                            end
                        end

                        if should_save then
                            local success, err = modulator_presets.save_current_shape(
                                state.track.pointer,
                                mod.pointer,
                                preset_name
                            )
                            if success then
                                -- Refresh cache by re-reading from .rpl files (non-destructive)
                                local names, sources = modulator_presets.get_preset_names()
                                state.cached_preset_names[mod_guid] = {}
                                state.cached_preset_sources = state.cached_preset_sources or {}
                                state.cached_preset_sources[mod_guid] = {}
                                for i, name in ipairs(names) do
                                    state.cached_preset_names[mod_guid][i - 1] = name
                                    state.cached_preset_sources[mod_guid][i - 1] = sources[i]
                                end
                                -- Update current preset name to the newly saved one
                                state.current_preset_name = state.current_preset_name or {}
                                state.current_preset_name[mod_guid] = preset_name
                                r.ShowMessageBox("Preset saved: " .. preset_name, "SideFX", 0)
                            else
                                local debug_info = modulator_presets.debug_paths()
                                r.ShowMessageBox("Failed to save preset.\n\n" .. (err or "Unknown error") .. "\n\nDebug:\n" .. debug_info, "SideFX", 0)
                            end
                        end
                    else
                        r.ShowMessageBox("No modulator or track selected", "SideFX", 0)
                    end
                    popup_state.open = false
                    popup_state.opened_frame = nil
                    r.ImGui_CloseCurrentPopup(ctx.ctx)
                end
                if not can_save then
                    r.ImGui_EndDisabled(ctx.ctx)
                end

                ctx:same_line()
                if ctx:button("Cancel##cancel_" .. mod_guid, 80, 0) then
                    popup_state.open = false
                    popup_state.opened_frame = nil
                    r.ImGui_CloseCurrentPopup(ctx.ctx)
                end

                r.ImGui_EndPopup(ctx.ctx)
            end

            if not p_open then
                popup_state.open = false
                popup_state.opened_frame = nil
            end
        end
    end

    -- Draw bake modal popup
    state.bake_modal = state.bake_modal or {}
    for modal_guid, modal_state in pairs(state.bake_modal) do
        if modal_state.open then
            local popup_id = "Bake to Automation##bake_modal_" .. modal_guid
            if not modal_state.opened_frame then
                r.ImGui_OpenPopup(ctx.ctx, popup_id)
                modal_state.opened_frame = true
            end

            local popup_flags = r.ImGui_WindowFlags_AlwaysAutoResize()
            local visible = r.ImGui_BeginPopup(ctx.ctx, popup_id, popup_flags)
            if visible then
                local is_all_links = modal_state.link == nil
                local title = is_all_links and "Bake All Parameters" or ("Bake: " .. (modal_state.link and modal_state.link.param_name or ""))
                ctx:text(title)
                ctx:separator()
                ctx:spacing()

                ctx:text("Select range:")
                ctx:spacing()

                -- Range mode buttons (one per line for clarity)
                local default_range = config.get('bake_default_range_mode')
                for mode_val = 1, 4 do
                    local mode_label = modulator_bake.RANGE_MODE_LABELS[mode_val]
                    if mode_label then
                        local is_default = mode_val == default_range
                        local btn_label = mode_label .. (is_default and " *" or "")

                        if ctx:button(btn_label .. "##range_" .. mode_val, -1, 0) then
                            -- Perform the bake
                            local bake_options = {
                                range_mode = mode_val,
                                disable_link = config.get('bake_disable_link_after')
                            }

                            local ok, result, msg
                            if is_all_links then
                                ok, result, msg = pcall(function()
                                    return modulator_bake.bake_all_links(
                                        state.track,
                                        modal_state.modulator,
                                        modal_state.fx,
                                        modal_state.links,
                                        bake_options
                                    )
                                end)
                            else
                                ok, result, msg = pcall(function()
                                    return modulator_bake.bake_to_automation(
                                        state.track,
                                        modal_state.modulator,
                                        modal_state.fx,
                                        modal_state.link.param_idx,
                                        bake_options
                                    )
                                end)
                            end

                            if ok and result then
                                r.ShowConsoleMsg("SideFX: " .. (msg or "Baked") .. "\n")
                            elseif not ok then
                                r.ShowConsoleMsg("SideFX Bake Error: " .. tostring(result) .. "\n")
                            else
                                r.ShowConsoleMsg("SideFX: " .. tostring(msg or "Bake failed") .. "\n")
                            end

                            modal_state.open = false
                            modal_state.opened_frame = nil
                            r.ImGui_CloseCurrentPopup(ctx.ctx)
                            interacted = true
                        end
                    end
                end

                ctx:spacing()
                ctx:separator()
                ctx:spacing()

                if ctx:button("Cancel##cancel_bake", -1, 0) then
                    modal_state.open = false
                    modal_state.opened_frame = nil
                    r.ImGui_CloseCurrentPopup(ctx.ctx)
                end

                r.ImGui_EndPopup(ctx.ctx)
            else
                -- Popup was closed externally
                modal_state.open = false
                modal_state.opened_frame = nil
            end
        end
    end

    return interacted
end

return M
