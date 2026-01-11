--- Modulator Bake
-- Convert LFO modulation to automation envelopes
-- @module modulator.modulator_bake
-- @author SideFX
-- @license MIT

local r = reaper
local PARAM = require('lib.modulator.modulator_constants')
local curve_editor = require('lib.ui.common.curve_editor')

local M = {}

-- Range modes for bake duration
M.RANGE_MODE = {
    PROJECT = 1,        -- Full project length
    TRACK = 2,          -- Track items extent (first item start to last item end)
    TIME_SELECTION = 3, -- Current time selection
    SELECTED_ITEM = 4,  -- Selected MIDI item(s) on track
}

-- Range mode labels for UI
M.RANGE_MODE_LABELS = {
    [1] = "Full Project",
    [2] = "Track Items",
    [3] = "Time Selection",
    [4] = "Selected Item(s)",
}

-- Default bake options
M.DEFAULT_OPTIONS = {
    resolution = 32,        -- Points per cycle
    range_mode = 2,         -- Default to track items (M.RANGE_MODE.TRACK)
    disable_link = false,   -- Set link scale to 0 after bake (keeps link but disables it)
    remove_link = false,    -- Remove parameter link after bake
    remove_modulator = false, -- Remove modulator after bake
}

-- Trigger modes
local TRIGGER_MODE = {
    FREE = 0,
    TRANSPORT = 1,
    MIDI = 2,
    AUDIO = 3,
}

-- Sync rate divisors (beats per cycle)
-- Index matches PARAM_SYNC_RATE normalized value * 17
local SYNC_RATE_BEATS = {
    [0] = 32,    -- 8 bars
    [1] = 16,    -- 4 bars
    [2] = 8,     -- 2 bars
    [3] = 4,     -- 1 bar
    [4] = 2,     -- 1/2
    [5] = 1,     -- 1/4
    [6] = 2/3,   -- 1/4T (triplet)
    [7] = 1.5,   -- 1/4. (dotted)
    [8] = 0.5,   -- 1/8
    [9] = 1/3,   -- 1/8T
    [10] = 0.75, -- 1/8.
    [11] = 0.25, -- 1/16
    [12] = 1/6,  -- 1/16T
    [13] = 0.375,-- 1/16.
    [14] = 0.125,-- 1/32
    [15] = 1/12, -- 1/32T
    [16] = 0.1875,-- 1/32.
    [17] = 0.0625,-- 1/64
}

--------------------------------------------------------------------------------
-- Range Calculation Helpers
--------------------------------------------------------------------------------

--- Get project length in seconds
-- @return number Project length in seconds
function M.get_project_length()
    -- GetProjectLength returns the length of the project (end of last item or marker)
    local length = r.GetProjectLength(0)
    -- Minimum 1 second to avoid zero-length bakes
    return math.max(length, 1)
end

--- Get track items extent (first item start to last item end)
-- @param track Track The track object (ReaWrap)
-- @return number, number start_time, end_time
function M.get_track_items_extent(track)
    local item_count = r.CountTrackMediaItems(track.pointer)
    if item_count == 0 then
        return 0, 1  -- Default to 1 second if no items
    end

    local min_start = math.huge
    local max_end = 0

    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track.pointer, i)
        if item then
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len

            if item_pos < min_start then min_start = item_pos end
            if item_end > max_end then max_end = item_end end
        end
    end

    if min_start == math.huge then
        return 0, 1
    end

    return min_start, max_end
end

--- Get current time selection
-- @return number, number start_time, end_time (or nil if no selection)
function M.get_time_selection()
    local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if start_time == end_time then
        return nil, nil  -- No time selection
    end
    return start_time, end_time
end

--- Get selected items extent on a track
-- @param track Track The track object (ReaWrap)
-- @return number, number start_time, end_time (or nil if no selected items)
function M.get_selected_items_extent(track)
    local selected_count = r.CountSelectedMediaItems(0)
    if selected_count == 0 then
        return nil, nil
    end

    local min_start = math.huge
    local max_end = 0
    local found_on_track = false

    for i = 0, selected_count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item then
            local item_track = r.GetMediaItemTrack(item)
            if item_track == track.pointer then
                found_on_track = true
                local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                local item_end = item_pos + item_len

                if item_pos < min_start then min_start = item_pos end
                if item_end > max_end then max_end = item_end end
            end
        end
    end

    if not found_on_track or min_start == math.huge then
        return nil, nil
    end

    return min_start, max_end
end

--- Get time range based on range mode
-- @param track Track The track object
-- @param range_mode number One of M.RANGE_MODE values
-- @return number, number, string start_time, end_time, error_message
function M.get_time_range(track, range_mode)
    range_mode = range_mode or M.DEFAULT_OPTIONS.range_mode

    if range_mode == M.RANGE_MODE.PROJECT then
        return 0, M.get_project_length(), nil

    elseif range_mode == M.RANGE_MODE.TRACK then
        local start_time, end_time = M.get_track_items_extent(track)
        return start_time, end_time, nil

    elseif range_mode == M.RANGE_MODE.TIME_SELECTION then
        local start_time, end_time = M.get_time_selection()
        if not start_time then
            return nil, nil, "No time selection. Create a time selection first."
        end
        return start_time, end_time, nil

    elseif range_mode == M.RANGE_MODE.SELECTED_ITEM then
        local start_time, end_time = M.get_selected_items_extent(track)
        if not start_time then
            return nil, nil, "No items selected on this track. Select MIDI item(s) first."
        end
        return start_time, end_time, nil

    else
        -- Fallback to track items
        local start_time, end_time = M.get_track_items_extent(track)
        return start_time, end_time, nil
    end
end

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Get the trigger mode of a modulator
-- @param modulator TrackFX The modulator FX object
-- @return number Trigger mode (0=Free, 1=Transport, 2=MIDI, 3=Audio)
function M.get_trigger_mode(modulator)
    local ok, trigger_mode = pcall(function()
        return modulator:get_param(PARAM.PARAM_TRIGGER_MODE)
    end)
    return ok and math.floor(trigger_mode + 0.5) or TRIGGER_MODE.FREE
end

--- Get all MIDI notes (start and end times) from a track within a time range
-- @param track Track The track object (ReaWrap)
-- @param start_time number Start time in seconds
-- @param end_time number End time in seconds
-- @return table Array of {start, duration} sorted by start time
function M.get_midi_notes(track, start_time, end_time)
    local notes = {}

    -- Iterate through all media items on the track
    local item_count = r.CountTrackMediaItems(track.pointer)
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track.pointer, i)
        if item then
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len

            -- Check for looped items
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                local source = r.GetMediaItemTake_Source(take)
                local source_len = r.GetMediaSourceLength(source)

                -- Skip items completely outside our time range
                if item_end >= start_time and item_pos <= end_time then
                    -- Get all MIDI notes in this take
                    local _, note_count = r.MIDI_CountEvts(take)

                    -- Calculate how many loops fit in the item
                    local num_loops = math.ceil(item_len / source_len)

                    for loop = 0, num_loops - 1 do
                        local loop_offset = loop * source_len

                        for n = 0, note_count - 1 do
                            local _, _, _, note_start_ppq, note_end_ppq = r.MIDI_GetNote(take, n)
                            -- Convert PPQ to project time (relative to item start)
                            local note_start_rel = r.MIDI_GetProjTimeFromPPQPos(take, note_start_ppq) - item_pos
                            local note_end_rel = r.MIDI_GetProjTimeFromPPQPos(take, note_end_ppq) - item_pos

                            -- Apply loop offset
                            local note_start = item_pos + note_start_rel + loop_offset
                            local note_end = item_pos + note_end_rel + loop_offset

                            -- Clamp to item bounds
                            if note_start >= item_end then break end
                            if note_end > item_end then note_end = item_end end

                            -- Only include notes within our time range
                            if note_start >= start_time and note_start < end_time then
                                local duration = note_end - note_start
                                if duration > 0 then
                                    notes[#notes + 1] = { start = note_start, duration = duration }
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sort by start time
    table.sort(notes, function(a, b) return a.start < b.start end)

    -- Filter to monophonic: skip notes that start while previous note is still sounding
    local mono_notes = {}
    local last_end = -1
    for _, note in ipairs(notes) do
        if note.start >= last_end then
            mono_notes[#mono_notes + 1] = note
            last_end = note.start + note.duration
        end
    end

    return mono_notes
end

--- Get the cycle duration of a modulator in seconds
-- @param modulator TrackFX The modulator FX object
-- @return number Duration in seconds
function M.get_cycle_duration(modulator)
    -- Check tempo mode (0=Free, 1=Sync)
    local ok_mode, tempo_mode = pcall(function()
        return modulator:get_param(PARAM.PARAM_TEMPO_MODE)
    end)
    local is_sync = ok_mode and tempo_mode >= 0.5

    if is_sync then
        -- Sync mode: calculate from sync rate and project tempo
        local ok_rate, sync_rate_norm = pcall(function()
            return modulator:get_param_normalized(PARAM.PARAM_SYNC_RATE)
        end)
        local sync_idx = ok_rate and math.floor(sync_rate_norm * 17 + 0.5) or 5
        local beats_per_cycle = SYNC_RATE_BEATS[sync_idx] or 1

        -- Get project tempo
        local bpm = r.Master_GetTempo()
        local seconds_per_beat = 60 / bpm

        return beats_per_cycle * seconds_per_beat
    else
        -- Free mode: 1 / rate_hz
        local ok_rate, rate_hz = pcall(function()
            return modulator:get_param(PARAM.PARAM_RATE_HZ)
        end)
        rate_hz = ok_rate and rate_hz or 1
        if rate_hz < 0.01 then rate_hz = 0.01 end

        return 1 / rate_hz
    end
end

--- Sample the LFO curve at specified resolution
-- @param modulator TrackFX The modulator FX object
-- @param resolution number Number of sample points
-- @return table Array of {t, value} where t is 0-1 and value is 0-1
function M.sample_lfo_curve(modulator, resolution, phase_offset)
    phase_offset = phase_offset or 0

    -- Read curve data from modulator
    local points = curve_editor.read_points_from_fx(modulator)
    local num_points = #points
    local segment_curves = curve_editor.read_segment_curves_from_fx(modulator, num_points)
    local global_curve = curve_editor.read_global_curve_from_fx(modulator)

    local samples = {}
    for i = 0, resolution do
        local t = i / resolution
        -- Apply phase offset, wrap values > 1.0 but keep 1.0 as 1.0 (don't wrap to 0)
        local phase_t = t + phase_offset
        if phase_t > 1.0 then
            phase_t = phase_t - 1.0
        end
        local value = curve_editor.eval_curve(points, phase_t, segment_curves, global_curve)
        samples[i + 1] = { t = t, value = value }
    end

    return samples
end

--- Calculate the final parameter value from LFO output
-- @param lfo_output number LFO output value (0-1)
-- @param link_info table Link information {baseline, scale, offset}
-- @return number Final parameter value (0-1 normalized)
function M.calculate_param_value(lfo_output, link_info)
    local baseline = link_info.baseline or 0.5
    local scale = link_info.scale or 1.0
    local offset = link_info.offset or 0

    -- REAPER plink formula: baseline + (lfo + offset) * scale
    -- For unipolar (offset=0): baseline + lfo * scale → baseline to baseline+scale
    -- For bipolar (offset=-0.5): baseline + (lfo - 0.5) * scale → baseline ± scale/2
    local final = baseline + (lfo_output + offset) * scale

    -- Clamp to 0-1
    return math.max(0, math.min(1, final))
end

--- Get link information for a parameter
-- @param target_fx TrackFX The target FX
-- @param param_idx number The parameter index
-- @return table|nil Link info or nil if not linked
function M.get_link_info(target_fx, param_idx)
    -- ReaWrap get_param_link_info returns nil if no active link,
    -- or a table with: active (bool), effect, param, scale, offset, baseline
    local link_info = target_fx:get_param_link_info(param_idx)
    if not link_info then
        return nil
    end

    -- Use values from ReaWrap, with fallback defaults
    -- If baseline is 0, try to get from current param value
    local baseline = link_info.baseline
    if baseline == 0 then
        local ok, current = pcall(function()
            return target_fx:get_param_normalized(param_idx)
        end)
        if ok and current then
            baseline = current
        end
    end

    return {
        baseline = baseline or 0.5,
        scale = link_info.scale or 1.0,
        offset = link_info.offset or 0,
        effect = link_info.effect,
        param = link_info.param,
    }
end

--------------------------------------------------------------------------------
-- Main Bake Function
--------------------------------------------------------------------------------

--- Bake modulation to automation envelope
-- @param track Track The track object (ReaWrap)
-- @param modulator TrackFX The modulator FX
-- @param target_fx TrackFX The target FX being modulated
-- @param param_idx number The parameter index on target_fx
-- @param options table|nil Bake options (uses defaults if nil)
-- @return boolean, string Success and message
function M.bake_to_automation(track, modulator, target_fx, param_idx, options)
    options = options or {}
    local resolution = options.resolution or M.DEFAULT_OPTIONS.resolution
    local range_mode = options.range_mode or M.DEFAULT_OPTIONS.range_mode

    -- Get link information
    local link_info = M.get_link_info(target_fx, param_idx)
    if not link_info then
        return false, "Parameter is not linked to a modulator"
    end

    -- Get cycle duration and trigger mode
    local cycle_duration = M.get_cycle_duration(modulator)
    local trigger_mode = M.get_trigger_mode(modulator)

    -- Determine time range based on range mode
    local start_time, end_time, range_error = M.get_time_range(track, range_mode)
    if range_error then
        return false, range_error
    end

    local total_duration = end_time - start_time
    if total_duration <= 0 then
        return false, "Invalid time range (duration <= 0)"
    end

    -- Get phase offset from modulator
    local ok_phase, phase = pcall(function()
        return modulator:get_param_normalized(PARAM.PARAM_PHASE)
    end)
    local phase_offset = (ok_phase and phase) or 0

    -- Sample the LFO curve (with phase offset applied)
    local samples = M.sample_lfo_curve(modulator, resolution, phase_offset)

    -- Get or create automation envelope
    -- GetFXEnvelope needs track-level FX index
    local fx_idx = target_fx.pointer
    local envelope = r.GetFXEnvelope(track.pointer, fx_idx, param_idx, true)
    if not envelope then
        return false, "Could not create automation envelope"
    end

    -- Begin undo block
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Clear existing points in range
    r.DeleteEnvelopePointRange(envelope, start_time - 0.001, end_time + 0.001)

    local total_points = 0
    local num_cycles = 0

    if trigger_mode == TRIGGER_MODE.MIDI then
        -- MIDI trigger mode: phase resets at each note, rate determines cycle frequency
        local midi_notes = M.get_midi_notes(track, start_time, end_time)

        if #midi_notes == 0 then
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("Bake LFO to Automation", -1)
            return false, "No MIDI notes found in time range"
        end

        r.ShowConsoleMsg(string.format("Bake: Found %d MIDI notes for trigger (cycle_duration=%.3fs)\n",
            #midi_notes, cycle_duration))

        for _, note in ipairs(midi_notes) do
            local note_duration = note.duration
            local note_end = note.start + note_duration

            -- Calculate how many cycles fit in this note based on rate
            local cycles_in_note = note_duration / cycle_duration
            local full_cycles = math.floor(cycles_in_note)
            local partial_cycle_fraction = cycles_in_note - full_cycles

            -- Bake full cycles
            for cycle = 0, full_cycles - 1 do
                local cycle_start = note.start + cycle * cycle_duration
                for _, sample in ipairs(samples) do
                    local time = cycle_start + sample.t * cycle_duration
                    if time <= note_end then
                        local value = M.calculate_param_value(sample.value, link_info)
                        r.InsertEnvelopePointEx(envelope, -1, time, value, 0, 0, false, true)
                        total_points = total_points + 1
                    end
                end
                num_cycles = num_cycles + 1
            end

            -- Bake partial cycle at end of note (if any significant portion remains)
            if partial_cycle_fraction > 0.01 then
                local partial_start = note.start + full_cycles * cycle_duration
                for _, sample in ipairs(samples) do
                    if sample.t <= partial_cycle_fraction then
                        local time = partial_start + sample.t * cycle_duration
                        if time <= note_end then
                            local value = M.calculate_param_value(sample.value, link_info)
                            r.InsertEnvelopePointEx(envelope, -1, time, value, 0, 0, false, true)
                            total_points = total_points + 1
                        end
                    end
                end
            end
        end
    else
        -- Free/Transport mode: bake continuous cycles
        num_cycles = math.ceil(total_duration / cycle_duration)

        for cycle = 0, num_cycles - 1 do
            local cycle_start = start_time + cycle * cycle_duration
            for _, sample in ipairs(samples) do
                local time = cycle_start + sample.t * cycle_duration
                -- Don't exceed end_time
                if time <= end_time then
                    local value = M.calculate_param_value(sample.value, link_info)
                    r.InsertEnvelopePointEx(envelope, -1, time, value, 0, 0, false, true)
                    total_points = total_points + 1
                end
            end
        end
    end

    -- Sort points after batch insert
    r.Envelope_SortPoints(envelope)

    -- Optionally disable parameter link (set scale to 0)
    if options.disable_link then
        local plink_prefix = string.format("param.%d.plink.", param_idx)
        target_fx:set_named_config_param(plink_prefix .. "scale", "0")
    end

    -- Optionally remove parameter link entirely
    if options.remove_link then
        target_fx:remove_param_link(param_idx)
        -- Restore baseline value
        target_fx:set_param_normalized(param_idx, link_info.baseline)
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Bake LFO to Automation", -1)

    local mode_str = trigger_mode == TRIGGER_MODE.MIDI and "MIDI triggered" or "continuous"
    return true, string.format("Baked %d points (%d cycles, %s, %.1f-%.1fs)",
        total_points, num_cycles, mode_str, start_time, end_time)
end

--- Bake all provided links to automation
-- @param track Track The track object
-- @param modulator TrackFX The modulator FX
-- @param target_fx TrackFX The target FX (device being modulated)
-- @param links table Array of link info from get_existing_param_links
-- @param options table|nil Bake options
-- @return boolean, string Success and message
function M.bake_all_links(track, modulator, target_fx, links, options)
    if not track or not modulator or not target_fx then
        return false, "Invalid track, modulator, or target"
    end

    if not links or #links == 0 then
        return false, "No links provided"
    end

    local baked_count = 0
    local errors = {}

    for _, link in ipairs(links) do
        local success, msg = M.bake_to_automation(track, modulator, target_fx, link.param_idx, options)
        if success then
            baked_count = baked_count + 1
        else
            table.insert(errors, msg)
        end
    end

    if baked_count == 0 then
        return false, "Failed to bake: " .. (errors[1] or "unknown error")
    end

    local msg = string.format("Baked %d parameter(s)", baked_count)
    if #errors > 0 then
        msg = msg .. string.format(" (%d errors)", #errors)
    end

    return true, msg
end

return M
