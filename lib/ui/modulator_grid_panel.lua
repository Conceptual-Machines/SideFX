--- Modulator Grid Panel UI Component
-- Shows 2×4 grid of modulator slots for selected device (Bitwig-style)
-- @module ui.modulator_grid_panel
-- @author Nomad Monad
-- @license MIT

local r = reaper
local imgui = require('imgui')
local fx_utils = require('lib.fx_utils')

local M = {}

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

M.config = {
    grid_cols = 2,
    grid_rows = 4,
    slot_width = 110,
    slot_height = 50,
    slot_padding = 4,
    panel_padding = 8,
    collapsed_width = 40,  -- Width when collapsed
}

-- Available modulator types
local MODULATOR_TYPES = {
    {id = "bezier_lfo", name = "Bezier LFO", jsfx = "JS:SideFX/SideFX_Modulator"},
    -- Future: Classic LFO, ADSR, etc.
    -- {id = "classic_lfo", name = "Classic LFO", jsfx = "JS:..."},
    -- {id = "adsr", name = "ADSR", jsfx = "JS:..."},
}

-- Modulator parameter mapping (from device_panel.lua)
local MODULATOR_PARAMS = {
    tempo_mode = 0,
    rate_hz = 1,
    sync_rate = 2,
    phase = 4,
    depth = 5,
    trigger_mode = 6,
    midi_source = 7,
    midi_note = 8,
    audio_thresh = 9,
    attack_ms = 10,
    release_ms = 11,
    lfo_mode = 12,
}

local SYNC_RATES = {
    "8 bars", "4 bars", "2 bars", "1 bar",
    "1/2", "1/4", "1/4T", "1/4.",
    "1/8", "1/8T", "1/8.",
    "1/16", "1/16T", "1/16.",
    "1/32", "1/32T", "1/32.",
    "1/64"
}

local TRIGGER_MODES = {"Free", "Transport", "MIDI", "Audio"}
local MIDI_SOURCES = {"This Track", "MIDI Bus"}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Track which slot is expanded (by device GUID)
local expanded_slots = {}  -- {[device_guid] = slot_index} or nil

-- Track advanced section state for expanded modulators
local modulator_advanced = {}  -- {[modulator_guid] = true/false}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Get all modulators inside a device container
-- @param device_container TrackFX D-container
-- @return table Array of modulator FX objects
local function get_device_modulators(device_container)
    if not device_container then return {} end

    local modulators = {}
    local ok, children = pcall(function() return device_container:get_container_children() end)
    if not ok then return {} end

    for _, child in ipairs(children) do
        if fx_utils.is_modulator_fx(child) then
            table.insert(modulators, child)
        end
    end

    return modulators
end

--- Get the slot index for a modulator (0-7)
-- Modulators are stored with a naming pattern or we track them by order
-- @param modulator TrackFX Modulator FX object
-- @param modulators table Array of all modulators in device
-- @return number Slot index (0-7) or nil
local function get_modulator_slot(modulator, modulators)
    for i, mod in ipairs(modulators) do
        if mod:get_guid() == modulator:get_guid() then
            return i - 1  -- Convert to 0-based
        end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Modulator Controls Rendering (from device_panel.lua)
--------------------------------------------------------------------------------

--- Draw modulator controls (reused from device_panel.lua)
-- @param ctx ImGui context
-- @param fx Modulator FX object
-- @param guid string Modulator GUID
-- @param control_width number Available width for controls
local function draw_modulator_controls(ctx, fx, guid, control_width)
    -- Safely get parameters
    local ok_tempo, tempo_mode = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.tempo_mode) end)
    if not ok_tempo then return end

    local is_sync = tempo_mode > 0.5

    -- Rate Mode Toggle
    ctx:text("Rate:")
    ctx:same_line()
    local button_width = 50
    if not is_sync then
        ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
    end
    if ctx:button("Free##mode", button_width, 0) then
        pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.tempo_mode, 0) end)
    end
    if not is_sync then
        ctx:pop_style_color()
    end

    ctx:same_line()
    if is_sync then
        ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
    end
    if ctx:button("Sync##mode", button_width, 0) then
        pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.tempo_mode, 1) end)
    end
    if is_sync then
        ctx:pop_style_color()
    end

    -- LFO Mode Toggle
    local ok_lfo, lfo_mode = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.lfo_mode) end)
    if ok_lfo then
        local is_oneshot = lfo_mode > 0.5

        ctx:text("Mode:")
        ctx:same_line()

        if not is_oneshot then
            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
        end
        if ctx:button("Loop##lfo", button_width, 0) then
            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.lfo_mode, 0) end)
        end
        if not is_oneshot then
            ctx:pop_style_color()
        end

        ctx:same_line()
        if is_oneshot then
            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
        end
        if ctx:button("One Shot##lfo", button_width + 30, 0) then
            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.lfo_mode, 1) end)
        end
        if is_oneshot then
            ctx:pop_style_color()
        end
    end

    -- Rate Control (Hz or Sync)
    ctx:set_next_item_width(control_width)
    if not is_sync then
        -- Free mode: Hz slider
        local ok_rate, rate_hz = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.rate_hz) end)
        if ok_rate then
            local hz_val = 0.01 + rate_hz * 19.99
            local changed, new_hz = ctx:slider_double("##rate_hz", hz_val, 0.01, 20, "%.2f Hz")
            if changed then
                local norm_val = (new_hz - 0.01) / 19.99
                pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.rate_hz, norm_val) end)
            end
        end
    else
        -- Sync mode: dropdown
        local ok_sync, sync_rate = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.sync_rate) end)
        if ok_sync then
            local sync_idx = math.floor(sync_rate * 17 + 0.5)
            sync_idx = math.max(0, math.min(17, sync_idx))
            if ctx:begin_combo("##sync_rate", SYNC_RATES[sync_idx + 1]) then
                for i, label in ipairs(SYNC_RATES) do
                    if ctx:selectable(label, i - 1 == sync_idx) then
                        local norm_val = (i - 1) / 17
                        pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.sync_rate, norm_val) end)
                    end
                end
                ctx:end_combo()
            end
        end
    end

    ctx:spacing()

    -- Phase Slider
    local ok_phase, phase = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.phase) end)
    if ok_phase then
        ctx:text("Phase:")
        ctx:set_next_item_width(control_width)
        local phase_deg = phase * 360
        local changed, new_deg = ctx:slider_double("##phase", phase_deg, 0, 360, "%.0f°")
        if changed then
            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.phase, new_deg / 360) end)
        end
    end

    -- Depth Slider
    local ok_depth, depth = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.depth) end)
    if ok_depth then
        ctx:text("Depth:")
        ctx:set_next_item_width(control_width)
        local depth_pct = depth * 100
        local changed, new_pct = ctx:slider_double("##depth", depth_pct, 0, 100, "%.0f%%")
        if changed then
            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.depth, new_pct / 100) end)
        end
    end

    ctx:spacing()
    ctx:separator()
    ctx:spacing()

    -- Trigger Mode
    local ok_trig, trigger_mode = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.trigger_mode) end)
    if ok_trig then
        local trigger_idx = math.floor(trigger_mode * 3 + 0.5)
        trigger_idx = math.max(0, math.min(3, trigger_idx))

        ctx:text("Trigger:")
        ctx:set_next_item_width(control_width)
        if ctx:begin_combo("##trigger", TRIGGER_MODES[trigger_idx + 1]) then
            for i, label in ipairs(TRIGGER_MODES) do
                if ctx:selectable(label, i - 1 == trigger_idx) then
                    local norm_val = (i - 1) / 3
                    pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.trigger_mode, norm_val) end)
                end
            end
            ctx:end_combo()
        end

        -- Advanced section for MIDI/Audio parameters
        if trigger_idx == 2 or trigger_idx == 3 then
            local is_advanced = modulator_advanced[guid] or false
            if ctx:small_button(is_advanced and "▼ Advanced##adv" or "▶ Advanced##adv") then
                modulator_advanced[guid] = not is_advanced
            end

            if is_advanced then
                ctx:indent(10)

                -- MIDI controls (only if Trigger=MIDI)
                if trigger_idx == 2 then
                    local ok_src, midi_src = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.midi_source) end)
                    if ok_src then
                        local src_idx = midi_src > 0.5 and 1 or 0
                        ctx:text("MIDI Source:")
                        ctx:set_next_item_width(control_width - 30)
                        if ctx:begin_combo("##midi_src", MIDI_SOURCES[src_idx + 1]) then
                            for i, label in ipairs(MIDI_SOURCES) do
                                if ctx:selectable(label, i - 1 == src_idx) then
                                    pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.midi_source, i - 1) end)
                                end
                            end
                            ctx:end_combo()
                        end
                    end

                    local ok_note, midi_note = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.midi_note) end)
                    if ok_note then
                        local note_val = math.floor(midi_note * 127 + 0.5)
                        ctx:text("MIDI Note:")
                        ctx:set_next_item_width(control_width - 30)
                        local changed, new_note = ctx:slider_double("##midi_note", note_val, 0, 127, "%.0f")
                        if changed then
                            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.midi_note, new_note / 127) end)
                        end
                    end
                end

                -- Audio Threshold (only if Trigger=Audio)
                if trigger_idx == 3 then
                    local ok_thresh, audio_thresh = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.audio_thresh) end)
                    if ok_thresh then
                        local thresh_pct = audio_thresh * 100
                        ctx:text("Threshold:")
                        ctx:set_next_item_width(control_width - 30)
                        local changed, new_pct = ctx:slider_double("##audio_thresh", thresh_pct, 0, 100, "%.0f%%")
                        if changed then
                            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.audio_thresh, new_pct / 100) end)
                        end
                    end
                end

                -- Attack/Release (for both MIDI and Audio)
                if trigger_idx == 2 or trigger_idx == 3 then
                    local ok_atk, attack_ms = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.attack_ms) end)
                    if ok_atk then
                        local atk_val = 1 + attack_ms * 1999
                        ctx:text("Attack:")
                        ctx:set_next_item_width(control_width - 30)
                        local changed, new_atk = ctx:slider_double("##attack", atk_val, 1, 2000, "%.0f ms")
                        if changed then
                            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.attack_ms, (new_atk - 1) / 1999) end)
                        end
                    end

                    local ok_rel, release_ms = pcall(function() return fx:get_param_normalized(MODULATOR_PARAMS.release_ms) end)
                    if ok_rel then
                        local rel_val = 1 + release_ms * 4999
                        ctx:text("Release:")
                        ctx:set_next_item_width(control_width - 30)
                        local changed, new_rel = ctx:slider_double("##release", rel_val, 1, 5000, "%.0f ms")
                        if changed then
                            pcall(function() fx:set_param_normalized(MODULATOR_PARAMS.release_ms, (new_rel - 1) / 4999) end)
                        end
                    end
                end

                ctx:unindent(10)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Main Panel Drawing
--------------------------------------------------------------------------------

--- Draw the modulator grid panel
-- @param ctx ImGui context wrapper
-- @param state table State object (needs selected_fx)
-- @param callbacks table Callbacks:
--   - add_modulator_to_device: (device_container, modulator_type) -> modulator_fx
--   - delete_modulator: (modulator_fx) -> nil
--   - refresh_fx_list: () -> nil
-- @return number Width of the panel
function M.draw(ctx, state, callbacks)
    local cfg = M.config

    -- Check if panel is collapsed
    local is_collapsed = state.modulator_panel_collapsed or false

    -- Calculate panel width
    local panel_width
    if is_collapsed then
        panel_width = cfg.collapsed_width
    else
        panel_width = cfg.grid_cols * cfg.slot_width + (cfg.grid_cols + 1) * cfg.slot_padding + cfg.panel_padding * 2
    end

    ctx:push_style_color(imgui.Col.ChildBg(), 0x1A1A1EFF)
    if ctx:begin_child("ModulatorGrid", panel_width, 0, imgui.ChildFlags.Border()) then

        -- Header with collapse button
        if is_collapsed then
            -- Vertical text or icon
            if ctx:button("▶##expand_mod", -1, 30) then
                state.modulator_panel_collapsed = false
            end
            if ctx:is_item_hovered() then
                ctx:set_tooltip("Expand Modulators")
            end
        else
            -- Expanded header
            if ctx:button("◀##collapse_mod", 24, 20) then
                state.modulator_panel_collapsed = true
            end
            if ctx:is_item_hovered() then
                ctx:set_tooltip("Collapse Modulators")
            end

            ctx:same_line()
            ctx:text("Modulators")

            -- Show selected device name
            if state.selected_fx then
                local ok_name, device_name = pcall(function()
                    -- Try to get custom display name first
                    local guid = state.selected_fx:get_guid()
                    if state.display_names[guid] then
                        return state.display_names[guid]
                    end
                    -- Fall back to FX name
                    return state.selected_fx:get_name()
                end)
                if ok_name and device_name then
                    -- Strip container prefix to show clean name
                    device_name = device_name:gsub("^D%d+:%s*", "")
                    ctx:text_colored(0xAAAAFFFF, "→ " .. device_name)
                end
            end

            ctx:separator()

            -- Show content only if expanded
            if not state.selected_fx then
                ctx:text_colored(0x888888FF, "Select a device")
            else
                -- Get the selected device's container
                local selected_device = state.selected_fx
                local device_guid = selected_device:get_guid()

                -- The selected_fx should be the D-container itself
                -- (selected in device_panel.lua as 'container or fx')
                local device_container = selected_device

                if not device_container or not device_container:is_container() then
                    ctx:text_colored(0x888888FF, "Not a container")
                else
                    -- Get modulators in this device
                    local modulators = get_device_modulators(device_container)

                    -- Check if any slot is expanded
                    local expanded_slot = expanded_slots[device_guid]

                    if expanded_slot ~= nil and modulators[expanded_slot + 1] then
                        -- Show expanded modulator controls
                        local modulator = modulators[expanded_slot + 1]
                        local mod_guid = modulator:get_guid()

                        ctx:push_id("expanded_mod_" .. mod_guid)

                        -- Back button
                        if ctx:small_button("← Back") then
                            expanded_slots[device_guid] = nil
                        end

                        ctx:same_line()
                        ctx:text_colored(0xAAAAFFFF, "LFO " .. (expanded_slot + 1))

                        ctx:same_line()
                        -- Delete button
                        ctx:push_style_color(imgui.Col.Button(), 0x663333FF)
                        if ctx:small_button("X##del") then
                            callbacks.delete_modulator(modulator)
                            expanded_slots[device_guid] = nil
                            callbacks.refresh_fx_list()
                        end
                        ctx:pop_style_color()

                        ctx:separator()
                        ctx:spacing()

                        -- Draw modulator controls
                        local control_width = panel_width - cfg.panel_padding * 2 - 20
                        draw_modulator_controls(ctx, modulator, mod_guid, control_width)

                        ctx:pop_id()
                    else
                        -- Show 2×4 grid
                        local total_slots = cfg.grid_rows * cfg.grid_cols

                        for row = 0, cfg.grid_rows - 1 do
                            for col = 0, cfg.grid_cols - 1 do
                                local slot_idx = row * cfg.grid_cols + col

                                if col > 0 then
                                    ctx:same_line()
                                end

                                ctx:push_id("slot_" .. slot_idx)

                                local modulator = modulators[slot_idx + 1]

                                if modulator then
                                    -- Filled slot - show modulator name
                                    ctx:push_style_color(imgui.Col.Button(), 0x334455FF)
                                    ctx:push_style_color(imgui.Col.ButtonHovered(), 0x445566FF)
                                    if ctx:button("LFO " .. (slot_idx + 1), cfg.slot_width, cfg.slot_height) then
                                        -- Expand this modulator
                                        expanded_slots[device_guid] = slot_idx
                                    end
                                    ctx:pop_style_color(2)
                                else
                                    -- Empty slot - show + or dropdown
                                    ctx:push_style_color(imgui.Col.Button(), 0x222222FF)
                                    ctx:push_style_color(imgui.Col.ButtonHovered(), 0x333333FF)
                                    if ctx:button("+##add_" .. slot_idx, cfg.slot_width, cfg.slot_height) then
                                        ctx:open_popup("select_modulator_" .. slot_idx)
                                    end
                                    ctx:pop_style_color(2)

                                    -- Modulator type dropdown
                                    if ctx:begin_popup("select_modulator_" .. slot_idx) then
                                        ctx:text("Add Modulator:")
                                        ctx:separator()
                                        for _, mod_type in ipairs(MODULATOR_TYPES) do
                                            if ctx:selectable(mod_type.name) then
                                                -- Add modulator to device container
                                                callbacks.add_modulator_to_device(device_container, mod_type)
                                                callbacks.refresh_fx_list()
                                            end
                                        end
                                        ctx:end_popup()
                                    end
                                end

                                ctx:pop_id()
                            end
                        end
                    end
                end
            end
        end

        ctx:end_child()
    end
    ctx:pop_style_color()

    return panel_width
end

return M
