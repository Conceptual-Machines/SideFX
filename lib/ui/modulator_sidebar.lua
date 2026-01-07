-- Modulator Sidebar UI Module
-- Renders the modulator grid, controls, and parameter links

local M = {}

local r = reaper
local imgui = require('imgui')
local state_module = require('lib.state')

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

-- Helper function to add a modulator to device
local function add_modulator_to_device(device_container, modulator_type, track)
    if not track or not device_container then return nil end
    if not device_container:is_container() then return nil end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Get container GUID before operations (GUID is stable)
    local container_guid = device_container:get_guid()
    if not container_guid then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (failed)", -1)
        return nil
    end

    -- Add modulator JSFX at track level first
    local modulator = track:add_fx_by_name(modulator_type.jsfx, false, -1)
    if not modulator or modulator.pointer < 0 then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (failed)", -1)
        return nil
    end

    local mod_guid = modulator:get_guid()

    -- Refind container by GUID (important for nested containers)
    local fresh_container = track:find_fx_by_guid(container_guid)
    if not fresh_container then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (container lost)", -1)
        return nil
    end

    -- Refresh pointer for deeply nested containers
    if fresh_container.pointer and fresh_container.pointer >= 0x2000000 and fresh_container.refresh_pointer then
        fresh_container:refresh_pointer()
    end

    -- Refind modulator by GUID
    modulator = track:find_fx_by_guid(mod_guid)
    if not modulator then
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (modulator lost)", -1)
        return nil
    end

    -- Get insert position (append to end of container)
    local insert_pos = fresh_container:get_container_child_count()

    -- Move modulator into container
    local success = fresh_container:add_fx_to_container(modulator, insert_pos)

    if not success then
        if modulator then modulator:delete() end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("SideFX: Add Modulator to Device (move failed)", -1)
        return nil
    end

    -- Refind modulator after move (pointer changed)
    local moved_modulator = track:find_fx_by_guid(mod_guid)

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("SideFX: Add Modulator to Device", -1)

    return moved_modulator
end

-- Helper function to find track-level FX index by GUID
local function get_track_fx_index_by_guid(track_ptr, fx_guid)
    local fx_count = r.TrackFX_GetCount(track_ptr)
    for i = 0, fx_count - 1 do
        local guid = r.TrackFX_GetFXGUID(track_ptr, i)
        if guid and guid == fx_guid then
            return i
        end
    end
    return nil
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
        -- Collapsed: show expand button
        if ctx:button("▶##expand_mod_" .. guid, 20, 30) then
            state.mod_sidebar_collapsed[state_guid] = false
            interacted = true
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Expand Modulators")
        end
    else
        -- Expanded: show grid
        if ctx:button("◀##collapse_mod_" .. guid, 24, 20) then
            state.mod_sidebar_collapsed[state_guid] = true
            interacted = true
        end
        if ctx:is_item_hovered() then
            ctx:set_tooltip("Collapse Modulators")
        end
        ctx:same_line()
        ctx:text("Modulators")
        ctx:separator()

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
                                local new_mod = add_modulator_to_device(container, MODULATOR_TYPES[1], track)
                                if new_mod then
                                    -- Refresh container pointer after adding (important for UI to update)
                                    if container.refresh_pointer then
                                        container:refresh_pointer()
                                    end

                                    if opts.refresh_fx_list then
                                        opts.refresh_fx_list()
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

                    -- Rate section
                    ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                    ctx:text("RATE")
                    ctx:pop_style_color()
                    ctx:spacing()

                    -- Tempo Mode: Free/Sync (slider1)
                    local ok_tempo, tempo_mode = pcall(function() return expanded_modulator:get_param_normalized(0) end)
                    if ok_tempo then
                        if ctx:radio_button("Free##tempo_" .. guid, tempo_mode < 0.5) then
                            expanded_modulator:set_param_normalized(0, 0)
                            interacted = true
                        end
                        ctx:same_line()
                        if ctx:radio_button("Sync##tempo_" .. guid, tempo_mode >= 0.5) then
                            expanded_modulator:set_param_normalized(0, 1)
                            interacted = true
                        end
                    end

                    -- Show Hz slider when Free mode, Sync Rate dropdown when Sync mode
                    if ok_tempo and tempo_mode < 0.5 then
                        -- Free mode - show Hz slider (slider2)
                        local ok_rate, rate_hz = pcall(function() return expanded_modulator:get_param_normalized(1) end)
                        if ok_rate then
                            ctx:set_next_item_width(control_width)
                            local changed, new_rate = ctx:slider_double("Hz##rate_" .. guid, rate_hz, 0.01, 20, "%.2f")
                            if changed then
                                expanded_modulator:set_param_normalized(1, new_rate)
                                interacted = true
                            end
                        end
                    else
                        -- Sync mode - show sync rate dropdown (slider3)
                        local ok_sync, sync_rate_idx = pcall(function() return expanded_modulator:get_param_normalized(2) end)
                        if ok_sync then
                            local sync_rates = {"8 bars", "4 bars", "2 bars", "1 bar", "1/2", "1/4", "1/4T", "1/4.", "1/8", "1/8T", "1/8.", "1/16", "1/16T", "1/16.", "1/32", "1/32T", "1/32.", "1/64"}
                            local current_idx = math.floor(sync_rate_idx * 17 + 0.5)
                            ctx:set_next_item_width(control_width)
                            if ctx:begin_combo("##sync_rate_" .. guid, sync_rates[current_idx + 1] or "1/4") then
                                for i, rate_name in ipairs(sync_rates) do
                                    if ctx:selectable(rate_name, i - 1 == current_idx) then
                                        expanded_modulator:set_param_normalized(2, (i - 1) / 17)
                                        interacted = true
                                    end
                                end
                                ctx:end_combo()
                            end
                        end
                    end

                    ctx:spacing()

                    -- Phase (slider5)
                    local ok_phase, phase = pcall(function() return expanded_modulator:get_param_normalized(4) end)
                    if ok_phase then
                        ctx:set_next_item_width(control_width)
                        local phase_deg = phase * 360
                        local changed, new_phase_deg = ctx:slider_double("Phase##phase_" .. guid, phase_deg, 0, 360, "%.0f°")
                        if changed then
                            expanded_modulator:set_param_normalized(4, new_phase_deg / 360)
                            interacted = true
                        end
                    end

                    -- Depth (slider6)
                    local ok_depth, depth = pcall(function() return expanded_modulator:get_param_normalized(5) end)
                    if ok_depth then
                        ctx:set_next_item_width(control_width)
                        local depth_pct = depth * 100
                        local changed, new_depth_pct = ctx:slider_double("Depth##depth_" .. guid, depth_pct, 0, 100, "%.0f%%")
                        if changed then
                            expanded_modulator:set_param_normalized(5, new_depth_pct / 100)
                            interacted = true
                        end
                    end

                    ctx:spacing()

                    -- Trigger Mode section
                    ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                    ctx:text("TRIGGER")
                    ctx:pop_style_color()
                    ctx:spacing()

                    -- Trigger Mode dropdown (slider20)
                    local ok_trig, trigger_mode_val = pcall(function() return expanded_modulator:get_param_normalized(19) end)
                    if ok_trig then
                        local trigger_modes = {"Free", "Transport", "MIDI", "Audio"}
                        local trig_idx = math.floor(trigger_mode_val * 3 + 0.5)
                        ctx:set_next_item_width(control_width)
                        if ctx:begin_combo("##trigger_mode_" .. guid, trigger_modes[trig_idx + 1] or "Free") then
                            for i, mode_name in ipairs(trigger_modes) do
                                if ctx:selectable(mode_name, i - 1 == trig_idx) then
                                    expanded_modulator:set_param_normalized(19, (i - 1) / 3)
                                    interacted = true
                                end
                            end
                            ctx:end_combo()
                        end
                    end

                    ctx:spacing()

                    -- LFO Mode section
                    ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
                    ctx:text("MODE")
                    ctx:pop_style_color()
                    ctx:spacing()

                    -- LFO Mode: Loop/One Shot (slider28)
                    local ok_lfo_mode, lfo_mode = pcall(function() return expanded_modulator:get_param_normalized(27) end)
                    if ok_lfo_mode then
                        if ctx:radio_button("Loop##lfo_" .. guid, lfo_mode < 0.5) then
                            expanded_modulator:set_param_normalized(27, 0)
                            interacted = true
                        end
                        ctx:same_line()
                        if ctx:radio_button("One Shot##lfo_" .. guid, lfo_mode >= 0.5) then
                            expanded_modulator:set_param_normalized(27, 1)
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
                            -- MIDI Source (slider21)
                            local ok_midi_src, midi_src = pcall(function() return expanded_modulator:get_param_normalized(20) end)
                            if ok_midi_src then
                                if ctx:radio_button("This Track##midi_src_" .. guid, midi_src < 0.5) then
                                    expanded_modulator:set_param_normalized(20, 0)
                                    interacted = true
                                end
                                ctx:same_line()
                                if ctx:radio_button("MIDI Bus##midi_src_" .. guid, midi_src >= 0.5) then
                                    expanded_modulator:set_param_normalized(20, 1)
                                    interacted = true
                                end
                            end

                            -- MIDI Note (slider22)
                            local ok_note, midi_note = pcall(function() return expanded_modulator:get_param_normalized(21) end)
                            if ok_note then
                                ctx:set_next_item_width(control_width)
                                local note_val = math.floor(midi_note * 127 + 0.5)
                                local changed, new_note_val = ctx:slider_int("MIDI Note##note_" .. guid, note_val, 0, 127, note_val == 0 and "Any" or tostring(note_val))
                                if changed then
                                    expanded_modulator:set_param_normalized(21, new_note_val / 127)
                                    interacted = true
                                end
                            end
                        elseif ok_trig and trig_idx == 3 then
                            -- Audio trigger mode
                            -- Audio Threshold (slider23)
                            local ok_thresh, audio_thresh = pcall(function() return expanded_modulator:get_param_normalized(22) end)
                            if ok_thresh then
                                ctx:set_next_item_width(control_width)
                                local changed, new_thresh = ctx:slider_double("Threshold##thresh_" .. guid, audio_thresh, 0, 1, "%.2f")
                                if changed then
                                    expanded_modulator:set_param_normalized(22, new_thresh)
                                    interacted = true
                                end
                            end
                        end

                        -- Attack/Release (always show in advanced)
                        if ok_trig and trig_idx > 0 then
                            -- Attack (slider24)
                            local ok_atk, attack_ms = pcall(function() return expanded_modulator:get_param_normalized(23) end)
                            if ok_atk then
                                local atk_val = attack_ms * 1999 + 1  -- 1-2000ms
                                ctx:set_next_item_width(control_width)
                                local changed, new_atk_val = ctx:slider_double("Attack##atk_" .. guid, atk_val, 1, 2000, "%.0f ms")
                                if changed then
                                    expanded_modulator:set_param_normalized(23, (new_atk_val - 1) / 1999)
                                    interacted = true
                                end
                            end

                            -- Release (slider25)
                            local ok_rel, release_ms = pcall(function() return expanded_modulator:get_param_normalized(24) end)
                            if ok_rel then
                                local rel_val = release_ms * 4999 + 1  -- 1-5000ms
                                ctx:set_next_item_width(control_width)
                                local changed, new_rel_val = ctx:slider_double("Release##rel_" .. guid, rel_val, 1, 5000, "%.0f ms")
                                if changed then
                                    expanded_modulator:set_param_normalized(24, (new_rel_val - 1) / 4999)
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
                    local track = opts.track or state.track
                    if track and track.pointer then
                        local track_ptr = track.pointer
                        local mod_track_idx = get_track_fx_index_by_guid(track_ptr, expanded_modulator:get_guid())
                        local target_track_idx = get_track_fx_index_by_guid(track_ptr, fx:get_guid())

                        if mod_track_idx and target_track_idx then
                            -- Check each parameter of parent device for links to this modulator
                            local ok_params, param_count = pcall(function() return fx:get_num_params() end)
                            if ok_params and param_count then
                                for param_idx = 0, param_count - 1 do
                                    -- Query if this param is linked (check plink.active first)
                                    local retval, active_str = r.TrackFX_GetNamedConfigParm(track_ptr, target_track_idx,
                                        string.format("param.%d.plink.active", param_idx))

                                    if retval and active_str == "1" then
                                        -- Link is active, check if it's from our modulator
                                        local _, effect_str = r.TrackFX_GetNamedConfigParm(track_ptr, target_track_idx,
                                            string.format("param.%d.plink.effect", param_idx))

                                        local link_fx_idx = tonumber(effect_str)
                                        if link_fx_idx == mod_track_idx then
                                            -- This parameter is linked to our modulator
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
                                -- Remove this link using track-level API
                                local track_remove = opts.track or state.track
                                if track_remove and track_remove.pointer then
                                    local ok_remove = pcall(function()
                                        local track_ptr = track_remove.pointer
                                        local target_track_idx = get_track_fx_index_by_guid(track_ptr, fx:get_guid())
                                        if target_track_idx then
                                            -- Set plink.active to "0" to disable the link
                                            r.TrackFX_SetNamedConfigParm(track_ptr, target_track_idx,
                                                string.format("param.%d.plink.active", link.param_idx),
                                                "0")
                                        end
                                    end)
                                    if ok_remove then
                                        interacted = true
                                    end
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

                    -- Link selection state (parameter only - device is implicit)
                    local link_state_key = "mod_link_" .. guid .. "_" .. expanded_slot_idx
                    state.mod_selected_target[link_state_key] = state.mod_selected_target[link_state_key] or {}
                    local link_state = state.mod_selected_target[link_state_key]

                    -- Modulator can only modulate its parent device (fx parameter)
                    -- No device selector needed - use the device that owns this container
                    local target_device = fx  -- The device being displayed

                    -- DEBUG: Show what we have
                    ctx:text(string.format("DEBUG: target_device=%s", target_device and "OK" or "NIL"))

                    -- Parameter selector for parent device
                    if target_device then
                        local ok_params, param_count = pcall(function() return target_device:get_num_params() end)
                        ctx:text(string.format("DEBUG: params=%s (ok=%s)", tostring(param_count), tostring(ok_params)))

                        if ok_params and param_count and param_count > 0 then
                            -- More verbose debug
                            ctx:text(string.format("DEBUG: param_idx=%s", tostring(link_state.param_idx)))
                            ctx:text(string.format("DEBUG: param_name=%s", tostring(link_state.param_name)))
                            ctx:text(string.format("DEBUG: Button visible=%s", link_state.param_idx ~= nil and "YES" or "NO"))

                            local current_param_name = link_state.param_name or "Select Parameter..."
                            ctx:set_next_item_width(control_width)
                            if ctx:begin_combo("##link_param_" .. guid, current_param_name) then
                                for param_idx = 0, param_count - 1 do
                                    local ok_pname, param_name = pcall(function() return target_device:get_param_name(param_idx) end)
                                    if ok_pname and param_name then
                                        if ctx:selectable(param_name, link_state.param_idx == param_idx) then
                                            link_state.param_idx = param_idx
                                            link_state.param_name = param_name
                                            r.ShowConsoleMsg(string.format(">>> Parameter selected: idx=%d name=%s\n", param_idx, param_name))
                                            interacted = true
                                        end
                                    end
                                end
                                ctx:end_combo()
                            end

                            -- Add Link button
                            if link_state.param_idx ~= nil then
                                if ctx:button("Add Link##" .. guid, control_width, 0) then
                                    r.ShowConsoleMsg("=== Add Link button clicked ===\n")
                                    r.ShowConsoleMsg(string.format("  Target param idx: %d\n", link_state.param_idx))
                                    r.ShowConsoleMsg(string.format("  Target param name: %s\n", link_state.param_name or "nil"))

                                    -- Debug: Check what track objects we have
                                    r.ShowConsoleMsg(string.format("  opts.track: %s\n", opts.track and "exists" or "nil"))
                                    r.ShowConsoleMsg(string.format("  state.track: %s\n", state.track and "exists" or "nil"))
                                    if opts.track then
                                        r.ShowConsoleMsg(string.format("  opts.track.pointer: %s\n", tostring(opts.track.pointer)))
                                    end
                                    if state.track then
                                        r.ShowConsoleMsg(string.format("  state.track.pointer: %s\n", tostring(state.track.pointer)))
                                    end

                                    -- Create modulation link using REAPER's param.X.plink API
                                    local target_param = link_state.param_idx

                                    -- Get track and FX indices
                                    local track_link = opts.track or state.track
                                    r.ShowConsoleMsg(string.format("  Track link: %s\n", track_link and "found" or "nil"))

                                    if track_link and track_link.pointer then
                                        local ok_link, err = pcall(function()
                                            -- Get track-level FX indices (not container-relative)
                                            local track_ptr = track_link.pointer

                                            local mod_guid = expanded_modulator:get_guid()
                                            local target_guid = target_device:get_guid()

                                            r.ShowConsoleMsg(string.format("  Modulator GUID: %s\n", mod_guid))
                                            r.ShowConsoleMsg(string.format("  Target GUID: %s\n", target_guid))

                                            local mod_track_idx = get_track_fx_index_by_guid(track_ptr, mod_guid)
                                            local target_track_idx = get_track_fx_index_by_guid(track_ptr, target_guid)

                                            r.ShowConsoleMsg(string.format("  Modulator track idx: %s\n", tostring(mod_track_idx)))
                                            r.ShowConsoleMsg(string.format("  Target track idx: %s\n", tostring(target_track_idx)))

                                            if mod_track_idx and target_track_idx then
                                                -- Enable parameter link from modulator output to target parameter
                                                -- REAPER plink format:
                                                -- - plink.active = "1" to enable
                                                -- - plink.effect = modulator FX index (track-level)
                                                -- - plink.param = modulator output parameter index (slider4 = param 3)

                                                local ok1 = r.TrackFX_SetNamedConfigParm(track_ptr, target_track_idx,
                                                    string.format("param.%d.plink.active", target_param),
                                                    "1")

                                                local ok2 = r.TrackFX_SetNamedConfigParm(track_ptr, target_track_idx,
                                                    string.format("param.%d.plink.effect", target_param),
                                                    tostring(mod_track_idx))

                                                local ok3 = r.TrackFX_SetNamedConfigParm(track_ptr, target_track_idx,
                                                    string.format("param.%d.plink.param", target_param),
                                                    "3")

                                                -- Debug output
                                                r.ShowConsoleMsg(string.format(
                                                    "Plink: target_fx=%d param=%d -> mod_fx=%d param=3\n  ok1=%s ok2=%s ok3=%s\n",
                                                    target_track_idx, target_param, mod_track_idx,
                                                    tostring(ok1), tostring(ok2), tostring(ok3)
                                                ))

                                                -- Verify what was set
                                                local _, verify_active = r.TrackFX_GetNamedConfigParm(track_ptr, target_track_idx,
                                                    string.format("param.%d.plink.active", target_param))
                                                local _, verify_effect = r.TrackFX_GetNamedConfigParm(track_ptr, target_track_idx,
                                                    string.format("param.%d.plink.effect", target_param))
                                                local _, verify_param = r.TrackFX_GetNamedConfigParm(track_ptr, target_track_idx,
                                                    string.format("param.%d.plink.param", target_param))

                                                r.ShowConsoleMsg(string.format(
                                                    "  Verify: active=%s effect=%s param=%s\n",
                                                    tostring(verify_active), tostring(verify_effect), tostring(verify_param)
                                                ))
                                            end
                                        end)

                                        if ok_link then
                                            -- Clear selection after adding link
                                            link_state.param_idx = nil
                                            link_state.param_name = nil
                                            interacted = true
                                        else
                                            r.ShowConsoleMsg(string.format("  ERROR in pcall: %s\n", tostring(err)))
                                        end
                                    else
                                        r.ShowConsoleMsg("  ERROR: No track pointer available\n")
                                    end
                                end
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
