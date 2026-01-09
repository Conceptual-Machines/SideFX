--- Modulator Panel UI Component
-- Shows modulator FX and their parameter links
-- @module ui.modulator_panel
-- @author Nomad Monad
-- @license MIT

local imgui = require('imgui')
local r = reaper

local M = {}

--------------------------------------------------------------------------------
-- Parameter Mapping
--------------------------------------------------------------------------------

-- Parameters are indexed by declaration order in JSFX, not slider number!
local PARAM_MAP = {
    tempo_mode = 0,    -- slider1 (param 0)
    rate_hz = 1,       -- slider2 (param 1)
    sync_rate = 2,     -- slider3 (param 2)
    phase = 4,         -- slider5 (param 4)
    depth = 5,         -- slider6 (param 5)
    trigger_mode = 6,  -- slider20 (param 6 - 7th declared param)
    midi_source = 7,   -- slider21 (param 7)
    midi_note = 8,     -- slider22 (param 8)
    audio_thresh = 9,  -- slider23 (param 9)
    attack_ms = 10,    -- slider24 (param 10)
    release_ms = 11,   -- slider25 (param 11)
    lfo_mode = 12,     -- slider28 (param 12 - 13th declared param)
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
-- UI Drawing Functions
--------------------------------------------------------------------------------

--- Draw a UI button icon (window/screen icon)
-- @param ctx ImGui context
-- @param label string Label for the button
-- @param width number Button width
-- @param height number Button height
-- @return boolean True if clicked
local function draw_ui_icon(ctx, label, width, height)
    -- Invisible button for interaction
    r.ImGui_InvisibleButton(ctx.ctx, label, width, height)
    local clicked = r.ImGui_IsItemClicked(ctx.ctx, 0)

    -- Get button bounds for drawing
    local item_min_x, item_min_y = r.ImGui_GetItemRectMin(ctx.ctx)
    local item_max_x, item_max_y = r.ImGui_GetItemRectMax(ctx.ctx)

    -- Draw window/screen icon using DrawList
    local draw_list = r.ImGui_GetWindowDrawList(ctx.ctx)
    local center_x = (item_min_x + item_max_x) / 2
    local center_y = (item_min_y + item_max_y) / 2
    local icon_size = 12
    local half_size = icon_size / 2

    -- Draw a simple window icon: rectangle with a line in the middle (like a window)
    local x1 = center_x - half_size
    local y1 = center_y - half_size
    local x2 = center_x + half_size
    local y2 = center_y + half_size

    -- Greyish color for the icon
    local icon_color = 0xAAAAAAFF
    -- Border color
    local border_color = 0x666666FF

    -- Draw border around the button
    r.ImGui_DrawList_AddRect(draw_list, item_min_x, item_min_y, item_max_x, item_max_y, border_color, 0, 0, 1.0)

    -- Outer rectangle (window frame) - signature: (draw_list, x1, y1, x2, y2, color, rounding, flags, thickness)
    r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, icon_color, 0, 0, 2)
    -- Inner line (window pane divider)
    r.ImGui_DrawList_AddLine(draw_list, center_x, y1, center_x, y2, icon_color, 1.5)

    return clicked
end

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Draw a dropdown combo control for selecting from options
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param label string Label to display
-- @param param_idx number Parameter index in PARAM_MAP
-- @param options table Array of option labels
-- @param current_idx number Current selected index (0-based)
-- @param id_suffix string Unique ID suffix
-- @param width number Control width
-- @param normalize_fn function Optional: convert index to normalized value (default: index / #options-1)
-- @param denormalize_fn function Optional: convert normalized value to index
local function draw_combo_control(ctx, fx, label, param_idx, options, current_idx, id_suffix, width, normalize_fn, denormalize_fn)
    ctx:text(label .. ":")
    ctx:same_line()
    ctx:set_next_item_width(width)
    if ctx:begin_combo("##" .. label .. "_" .. id_suffix, options[current_idx + 1]) then
        for i, option_label in ipairs(options) do
            if ctx:selectable(option_label, i - 1 == current_idx) then
                local norm_val = normalize_fn and normalize_fn(i - 1) or ((i - 1) / (#options - 1))
                pcall(function() fx:set_param_normalized(param_idx, norm_val) end)
            end
        end
        ctx:end_combo()
    end
end

--- Draw a slider control with value conversion
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param label string Label to display
-- @param param_idx number Parameter index in PARAM_MAP
-- @param display_val number Current display value
-- @param min_val number Minimum display value
-- @param max_val number Maximum display value
-- @param format string Format string for display (e.g., "%.0f")
-- @param id_suffix string Unique ID suffix
-- @param width number Control width
-- @param convert_to_norm function Convert display value to normalized (0-1)
local function draw_slider_control(ctx, fx, label, param_idx, display_val, min_val, max_val, format, id_suffix, width, convert_to_norm)
    ctx:text(label .. ":")
    ctx:same_line()
    ctx:set_next_item_width(width)
    local changed, new_val = ctx:slider_double("##" .. label .. "_" .. id_suffix, display_val, min_val, max_val, format)
    if changed then
        pcall(function() fx:set_param_normalized(param_idx, convert_to_norm(new_val)) end)
    end
end

--- Draw MIDI trigger controls (source + note)
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param mod_fx_idx number Modulator FX index
-- @param width number Control width
local function draw_midi_controls(ctx, fx, mod_fx_idx, width)
    -- MIDI Source
    local ok_src, midi_src = pcall(function() return fx:get_param_normalized(PARAM_MAP.midi_source) end)
    if ok_src then
        local src_idx = midi_src > 0.5 and 1 or 0
        draw_combo_control(ctx, fx, "MIDI Source", PARAM_MAP.midi_source, MIDI_SOURCES, src_idx, "midi_src_" .. mod_fx_idx, width - 130,
            function(idx) return idx > 0.5 and 1 or 0 end,
            function(norm) return norm > 0.5 and 1 or 0 end)
    end

    -- MIDI Note
    local ok_note, midi_note = pcall(function() return fx:get_param_normalized(PARAM_MAP.midi_note) end)
    if ok_note then
        local note_val = math.floor(midi_note * 127 + 0.5)
        draw_slider_control(ctx, fx, "MIDI Note", PARAM_MAP.midi_note, note_val, 0, 127, "%.0f", "midi_note_" .. mod_fx_idx, width - 130,
            function(display_val) return display_val / 127 end)
    end
end

--- Draw audio trigger controls (threshold)
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param mod_fx_idx number Modulator FX index
-- @param width number Control width
local function draw_audio_controls(ctx, fx, mod_fx_idx, width)
    local ok_thresh, audio_thresh = pcall(function() return fx:get_param_normalized(PARAM_MAP.audio_thresh) end)
    if ok_thresh then
        local thresh_pct = audio_thresh * 100
        draw_slider_control(ctx, fx, "Audio Threshold", PARAM_MAP.audio_thresh, thresh_pct, 0, 100, "%.0f%%", "audio_thresh_" .. mod_fx_idx, width - 150,
            function(display_val) return display_val / 100 end)
    end
end

--- Draw attack/release controls
-- @param ctx ImGui context
-- @param fx ReaWrap FX object
-- @param mod_fx_idx number Modulator FX index
-- @param width number Control width
local function draw_attack_release_controls(ctx, fx, mod_fx_idx, width)
    local ok_atk, attack_ms = pcall(function() return fx:get_param_normalized(PARAM_MAP.attack_ms) end)
    if ok_atk then
        local atk_val = 1 + attack_ms * 1999
        draw_slider_control(ctx, fx, "Attack", PARAM_MAP.attack_ms, atk_val, 1, 2000, "%.0f ms", "attack_" .. mod_fx_idx, width - 130,
            function(display_val) return (display_val - 1) / 1999 end)
    end

    local ok_rel, release_ms = pcall(function() return fx:get_param_normalized(PARAM_MAP.release_ms) end)
    if ok_rel then
        local rel_val = 1 + release_ms * 4999
        draw_slider_control(ctx, fx, "Release", PARAM_MAP.release_ms, rel_val, 1, 5000, "%.0f ms", "release_" .. mod_fx_idx, width - 130,
            function(display_val) return (display_val - 1) / 4999 end)
    end
end

--- Draw modulator parameter controls
-- @param ctx ImGui context wrapper
-- @param mod table Modulator data {fx, fx_idx, name}
-- @param state table State object
-- @param width number Available width
local function draw_modulator_params(ctx, mod, state, width)
    local fx = mod.fx

    -- Safely get parameters (FX might be deleted)
    local ok, tempo_mode = pcall(function() return fx:get_param_normalized(PARAM_MAP.tempo_mode) end)
    if not ok then return end

    local is_sync = tempo_mode > 0.5

    -- Rate Controls
    ctx:text("Rate:")
    ctx:same_line()

    -- Free/Sync toggle buttons
    local button_width = 45
    if not is_sync then
        ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
    end
    if ctx:button("Free##mode_" .. mod.fx_idx, button_width, 0) then
        pcall(function() fx:set_param_normalized(PARAM_MAP.tempo_mode, 0) end)
    end
    if not is_sync then
        ctx:pop_style_color()
    end

    ctx:same_line()
    if is_sync then
        ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
    end
    if ctx:button("Sync##mode_" .. mod.fx_idx, button_width, 0) then
        pcall(function() fx:set_param_normalized(PARAM_MAP.tempo_mode, 1) end)
    end
    if is_sync then
        ctx:pop_style_color()
    end

    -- LFO Mode toggle buttons (underneath Rate mode buttons)
    local ok_lfo, lfo_mode = pcall(function() return fx:get_param_normalized(PARAM_MAP.lfo_mode) end)
    if ok_lfo then
        local is_oneshot = lfo_mode > 0.5

        ctx:text("Mode:")
        ctx:same_line()

        if not is_oneshot then
            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
        end
        if ctx:button("Loop##lfo_" .. mod.fx_idx, button_width, 0) then
            pcall(function() fx:set_param_normalized(PARAM_MAP.lfo_mode, 0) end)
        end
        if not is_oneshot then
            ctx:pop_style_color()
        end

        ctx:same_line()
        if is_oneshot then
            ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
        end
        if ctx:button("One Shot##lfo_" .. mod.fx_idx, button_width + 25, 0) then
            pcall(function() fx:set_param_normalized(PARAM_MAP.lfo_mode, 1) end)
        end
        if is_oneshot then
            ctx:pop_style_color()
        end
    end

    -- Rate control (Hz slider or Sync dropdown) - on next line for full width
    ctx:set_next_item_width(width - 20)
    if not is_sync then
        -- Free mode: Hz slider
        -- get_param returns normalized 0-1, set_param expects normalized 0-1
        local ok_rate, rate_norm, min_val, max_val = pcall(function() return fx:get_param(PARAM_MAP.rate_hz) end)
        if ok_rate and rate_norm then
            -- Convert normalized to Hz (0.01 - 20)
            local hz_val = 0.01 + rate_norm * 19.99
            local changed, new_hz = ctx:slider_double("##rate_hz_" .. mod.fx_idx, hz_val, 0.01, 20, "%.2f Hz")
            if changed then
                -- Convert Hz back to normalized
                local norm_val = (new_hz - 0.01) / 19.99
                pcall(function() fx:set_param(PARAM_MAP.rate_hz, norm_val) end)
            end
        end
    else
        -- Sync mode: dropdown
        local ok_sync, sync_rate = pcall(function() return fx:get_param_normalized(PARAM_MAP.sync_rate) end)
        if ok_sync then
            local sync_idx = math.floor(sync_rate * 17 + 0.5)
            sync_idx = math.max(0, math.min(17, sync_idx))
            if ctx:begin_combo("##sync_rate_" .. mod.fx_idx, SYNC_RATES[sync_idx + 1]) then
                for i, label in ipairs(SYNC_RATES) do
                    if ctx:selectable(label, i - 1 == sync_idx) then
                        local norm_val = (i - 1) / 17
                        pcall(function() fx:set_param_normalized(PARAM_MAP.sync_rate, norm_val) end)
                    end
                end
                ctx:end_combo()
            end
        end
    end

    -- Phase slider
    local ok_phase, phase = pcall(function() return fx:get_param_normalized(PARAM_MAP.phase) end)
    if ok_phase then
        ctx:text("Phase:")
        ctx:same_line()
        ctx:set_next_item_width(width - 100)
        local phase_deg = phase * 360
        local changed, new_deg = ctx:slider_double("##phase_" .. mod.fx_idx, phase_deg, 0, 360, "%.0f°")
        if changed then
            pcall(function() fx:set_param_normalized(PARAM_MAP.phase, new_deg / 360) end)
        end
    end

    -- Depth slider
    local ok_depth, depth = pcall(function() return fx:get_param_normalized(PARAM_MAP.depth) end)
    if ok_depth then
        ctx:text("Depth:")
        ctx:same_line()
        ctx:set_next_item_width(width - 100)
        local depth_pct = depth * 100
        local changed, new_pct = ctx:slider_double("##depth_" .. mod.fx_idx, depth_pct, 0, 100, "%.0f%%")
        if changed then
            pcall(function() fx:set_param_normalized(PARAM_MAP.depth, new_pct / 100) end)
        end
    end

    -- Trigger Mode dropdown
    local ok_trig, trigger_mode = pcall(function() return fx:get_param_normalized(PARAM_MAP.trigger_mode) end)
    if ok_trig then
        local trigger_idx = math.floor(trigger_mode * 3 + 0.5)
        trigger_idx = math.max(0, math.min(3, trigger_idx))

        draw_combo_control(ctx, fx, "Trigger", PARAM_MAP.trigger_mode, TRIGGER_MODES, trigger_idx, "trigger_" .. mod.fx_idx, width - 100,
            function(idx) return idx / 3 end)

        -- Advanced section (collapsible) - only show if trigger mode needs it
        if trigger_idx == 2 or trigger_idx == 3 then
            local is_advanced = state.modulator_advanced[mod.fx_idx] or false
            if ctx:small_button(is_advanced and "▼ Advanced##adv_" .. mod.fx_idx or "▶ Advanced##adv_" .. mod.fx_idx) then
                state.modulator_advanced[mod.fx_idx] = not is_advanced
            end

            if is_advanced then
                ctx:indent(10)

                -- MIDI controls (show only if Trigger=MIDI)
                if trigger_idx == 2 then
                    draw_midi_controls(ctx, fx, mod.fx_idx, width)
                end

                -- Audio Threshold (show only if Trigger=Audio)
                if trigger_idx == 3 then
                    draw_audio_controls(ctx, fx, mod.fx_idx, width)
                end

                -- Attack/Release (show if Trigger=MIDI or Audio)
                if trigger_idx == 2 or trigger_idx == 3 then
                    draw_attack_release_controls(ctx, fx, mod.fx_idx, width)
                end

                ctx:unindent(10)
            end
        end
    end

    ctx:spacing()
    ctx:separator()
end

--------------------------------------------------------------------------------
-- Modulator Panel
--------------------------------------------------------------------------------

--- Draw modulator panel
-- @param ctx ImGui context wrapper
-- @param width number Width of the panel
-- @param state table State object
-- @param callbacks table Callbacks:
--   - find_modulators_on_track: () -> table Array of modulator data
--   - get_linkable_fx: () -> table Array of linkable FX
--   - get_modulator_links: (fx_idx) -> table Array of links
--   - create_param_link: (mod_fx_idx, target_fx_idx, target_param_idx) -> nil
--   - remove_param_link: (target_fx_idx, target_param_idx) -> nil
--   - add_modulator: () -> nil
--   - delete_modulator: (fx_idx) -> nil
function M.draw(ctx, width, state, callbacks)
    if ctx:begin_child("Modulators", width, 0, imgui.ChildFlags.Border()) then
        ctx:text("Modulators")
        ctx:same_line()
        if ctx:small_button("+ Add") then
            callbacks.add_modulator()
        end
        ctx:separator()

        if not state.track then
            ctx:text_colored(0x888888FF, "Select a track")
            ctx:end_child()
            return
        end

        local modulators = callbacks.find_modulators_on_track()

        if #modulators == 0 then
            ctx:text_colored(0x888888FF, "No modulators")
            ctx:text_colored(0x666666FF, "Click '+ Add'")
        else
            local linkable_fx = callbacks.get_linkable_fx()

            for i, mod in ipairs(modulators) do
                ctx:push_id("mod_" .. mod.fx_idx)

                -- Header row: buttons first, then name
                -- Show UI button
                if draw_ui_icon(ctx, "##ui_" .. mod.fx_idx, 24, 20) then
                    mod.fx:show(3)
                end
                ctx:same_line()

                -- Delete button
                ctx:push_style_color(imgui.Col.Button(), 0x663333FF)
                ctx:push_style_color(imgui.Col.ButtonHovered(), 0x444444FF)
                if ctx:small_button("X##del_" .. mod.fx_idx) then
                    ctx:pop_style_color(2)
                    ctx:pop_id()
                    callbacks.delete_modulator(mod.fx_idx)
                    ctx:end_child()
                    return
                end
                ctx:pop_style_color(2)
                ctx:same_line()

                -- Modulator name as collapsing header
                ctx:push_style_color(imgui.Col.Header(), 0x445566FF)
                ctx:push_style_color(imgui.Col.HeaderHovered(), 0x556677FF)
                local header_open = ctx:collapsing_header(mod.name, imgui.TreeNodeFlags.DefaultOpen())
                ctx:pop_style_color(2)

                if header_open then
                    -- Draw parameter controls
                    draw_modulator_params(ctx, mod, state, width)
                    -- Show existing links
                    local links = callbacks.get_modulator_links(mod.fx_idx)
                    if #links > 0 then
                        ctx:text_colored(0xAAAAAAFF, "Links:")
                        for _, link in ipairs(links) do
                            ctx:push_id("link_" .. link.target_fx_idx .. "_" .. link.target_param_idx)

                            -- Truncate names to fit
                            local fx_short = link.target_fx_name:sub(1, 15)
                            local param_short = link.target_param_name:sub(1, 12)

                            ctx:text_colored(0x88CC88FF, "→")
                            ctx:same_line()
                            ctx:text_wrapped(fx_short .. " : " .. param_short)
                            ctx:same_line(width - 30)

                            -- Remove link button
                            ctx:push_style_color(imgui.Col.Button(), 0x664444FF)
                            if ctx:small_button("×") then
                                callbacks.remove_param_link(link.target_fx_idx, link.target_param_idx)
                            end
                            ctx:pop_style_color()

                            ctx:pop_id()
                        end
                        ctx:spacing()
                    end

                    -- Two dropdowns to add new link
                    ctx:text_colored(0xAAAAAAFF, "+ Add link:")

                    -- Get current selection for this modulator
                    local selected_target = state.mod_selected_target[mod.fx_idx]
                    local fx_preview = selected_target and selected_target.name or "Select FX..."

                    -- Dropdown 1: Select target FX
                    ctx:set_next_item_width(width - 20)
                    if ctx:begin_combo("##targetfx_" .. i, fx_preview) then
                        for _, fx in ipairs(linkable_fx) do
                            if ctx:selectable(fx.name .. "##fx_" .. fx.fx_idx) then
                                state.mod_selected_target[mod.fx_idx] = {
                                    fx_idx = fx.fx_idx,
                                    name = fx.name,
                                    params = fx.params
                                }
                            end
                        end
                        ctx:end_combo()
                    end

                    -- Dropdown 2: Select parameter (only if FX is selected)
                    if selected_target then
                        ctx:set_next_item_width(width - 20)
                        if ctx:begin_combo("##targetparam_" .. i, "Select param...") then
                            for _, param in ipairs(selected_target.params) do
                                if ctx:selectable(param.name .. "##p_" .. param.idx) then
                                    callbacks.create_param_link(mod.fx_idx, selected_target.fx_idx, param.idx)
                                    -- Clear selection after linking
                                    state.mod_selected_target[mod.fx_idx] = nil
                                end
                            end
                            ctx:end_combo()
                        end
                    end
                end

                ctx:spacing()
                ctx:separator()
                ctx:pop_id()
            end
        end

        ctx:end_child()
    end
end

return M
