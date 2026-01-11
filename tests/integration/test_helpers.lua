--- Integration Test Helpers
-- Utilities for bake modulation integration tests
-- @module tests.integration.test_helpers
-- @author SideFX
-- @license MIT

local r = reaper

local M = {}

--------------------------------------------------------------------------------
-- Envelope Reading
--------------------------------------------------------------------------------

--- Read all points from an automation envelope
-- @param envelope userdata REAPER envelope pointer
-- @return table Array of {time, value, shape, tension, selected}
function M.read_envelope_points(envelope)
    if not envelope then return {} end

    local count = r.CountEnvelopePoints(envelope)
    local points = {}

    for i = 0, count - 1 do
        local retval, time, value, shape, tension, selected = r.GetEnvelopePoint(envelope, i)
        if retval then
            points[#points + 1] = {
                time = time,
                value = value,
                shape = shape,
                tension = tension,
                selected = selected
            }
        end
    end

    return points
end

--- Get envelope for an FX parameter
-- @param track userdata Track pointer
-- @param fx_idx number FX index
-- @param param_idx number Parameter index
-- @return userdata|nil Envelope pointer or nil
function M.get_fx_envelope(track, fx_idx, param_idx)
    return r.GetFXEnvelope(track, fx_idx, param_idx, false)
end

--- Clear all points from an envelope
-- @param envelope userdata REAPER envelope pointer
function M.clear_envelope(envelope)
    if not envelope then return end
    local count = r.CountEnvelopePoints(envelope)
    for i = count - 1, 0, -1 do
        r.DeleteEnvelopePointEx(envelope, -1, i)
    end
    r.Envelope_SortPoints(envelope)
end

--------------------------------------------------------------------------------
-- Value Comparison
--------------------------------------------------------------------------------

--- Check if two values are approximately equal
-- @param a number First value
-- @param b number Second value
-- @param tolerance number Maximum allowed difference (default 0.01)
-- @return boolean True if values are within tolerance
function M.approx_equal(a, b, tolerance)
    tolerance = tolerance or 0.01
    return math.abs(a - b) <= tolerance
end

--- Find min and max values in envelope points
-- @param points table Array of envelope points
-- @return number, number min_value, max_value
function M.get_value_range(points)
    if #points == 0 then return 0, 0 end

    local min_val = points[1].value
    local max_val = points[1].value

    for _, p in ipairs(points) do
        if p.value < min_val then min_val = p.value end
        if p.value > max_val then max_val = p.value end
    end

    return min_val, max_val
end

--- Sample envelope value at a specific time
-- @param points table Array of envelope points
-- @param time number Time to sample at
-- @return number Interpolated value at time
function M.sample_at_time(points, time)
    if #points == 0 then return 0 end
    if #points == 1 then return points[1].value end

    -- Find surrounding points
    local prev, next_pt
    for i, p in ipairs(points) do
        if p.time <= time then
            prev = p
        end
        if p.time >= time and not next_pt then
            next_pt = p
        end
    end

    if not prev then return points[1].value end
    if not next_pt then return points[#points].value end
    if prev.time == next_pt.time then return prev.value end

    -- Linear interpolation (ignoring shape for simplicity)
    local t = (time - prev.time) / (next_pt.time - prev.time)
    return prev.value + t * (next_pt.value - prev.value)
end

--------------------------------------------------------------------------------
-- Test Assertions
--------------------------------------------------------------------------------

--- Test result structure
-- @param name string Test name
-- @param passed boolean Whether test passed
-- @param message string Description or error message
-- @param details table Optional detailed data
-- @return table Test result
function M.make_result(name, passed, message, details)
    return {
        name = name,
        passed = passed,
        message = message,
        details = details or {}
    }
end

--- Assert envelope value range matches expected
-- @param name string Test name
-- @param points table Envelope points
-- @param expected_min number Expected minimum value
-- @param expected_max number Expected maximum value
-- @param tolerance number Value tolerance (default 0.02)
-- @return table Test result
function M.assert_value_range(name, points, expected_min, expected_max, tolerance)
    tolerance = tolerance or 0.02
    local actual_min, actual_max = M.get_value_range(points)

    local min_ok = M.approx_equal(actual_min, expected_min, tolerance)
    local max_ok = M.approx_equal(actual_max, expected_max, tolerance)

    if min_ok and max_ok then
        return M.make_result(name, true,
            string.format("Range [%.3f, %.3f] matches expected [%.3f, %.3f]",
                actual_min, actual_max, expected_min, expected_max))
    else
        return M.make_result(name, false,
            string.format("Range mismatch: actual [%.3f, %.3f], expected [%.3f, %.3f]",
                actual_min, actual_max, expected_min, expected_max),
            { actual_min = actual_min, actual_max = actual_max,
              expected_min = expected_min, expected_max = expected_max })
    end
end

--- Assert envelope has expected number of points
-- @param name string Test name
-- @param points table Envelope points
-- @param expected_count number Expected point count
-- @return table Test result
function M.assert_point_count(name, points, expected_count)
    local actual = #points
    if actual == expected_count then
        return M.make_result(name, true,
            string.format("Point count %d matches expected", actual))
    else
        return M.make_result(name, false,
            string.format("Point count mismatch: actual %d, expected %d", actual, expected_count),
            { actual = actual, expected = expected_count })
    end
end

--- Assert envelope timing covers expected duration
-- @param name string Test name
-- @param points table Envelope points
-- @param expected_start number Expected start time
-- @param expected_end number Expected end time
-- @param tolerance number Time tolerance in seconds (default 0.01)
-- @return table Test result
function M.assert_time_range(name, points, expected_start, expected_end, tolerance)
    tolerance = tolerance or 0.01
    if #points == 0 then
        return M.make_result(name, false, "No points in envelope")
    end

    local actual_start = points[1].time
    local actual_end = points[#points].time

    local start_ok = M.approx_equal(actual_start, expected_start, tolerance)
    local end_ok = M.approx_equal(actual_end, expected_end, tolerance)

    if start_ok and end_ok then
        return M.make_result(name, true,
            string.format("Time range [%.3f, %.3f] matches expected", actual_start, actual_end))
    else
        return M.make_result(name, false,
            string.format("Time range mismatch: actual [%.3f, %.3f], expected [%.3f, %.3f]",
                actual_start, actual_end, expected_start, expected_end),
            { actual_start = actual_start, actual_end = actual_end })
    end
end

--------------------------------------------------------------------------------
-- Test Runner
--------------------------------------------------------------------------------

--- Run a list of test functions and collect results
-- @param tests table Array of {name, func} test definitions
-- @return table Results summary
function M.run_tests(tests)
    local results = {
        total = #tests,
        passed = 0,
        failed = 0,
        tests = {}
    }

    for _, test in ipairs(tests) do
        local ok, result = pcall(test.func)
        if ok and result then
            results.tests[#results.tests + 1] = result
            if result.passed then
                results.passed = results.passed + 1
            else
                results.failed = results.failed + 1
            end
        else
            results.tests[#results.tests + 1] = M.make_result(
                test.name, false, "Test threw error: " .. tostring(result))
            results.failed = results.failed + 1
        end
    end

    return results
end

--- Print test results to console
-- @param results table Results from run_tests
function M.print_results(results)
    r.ShowConsoleMsg("\n========== Test Results ==========\n")
    r.ShowConsoleMsg(string.format("Total: %d | Passed: %d | Failed: %d\n\n",
        results.total, results.passed, results.failed))

    for _, test in ipairs(results.tests) do
        local status = test.passed and "PASS" or "FAIL"
        r.ShowConsoleMsg(string.format("[%s] %s\n", status, test.name))
        r.ShowConsoleMsg(string.format("       %s\n", test.message))
    end

    r.ShowConsoleMsg("\n==================================\n")
end

--------------------------------------------------------------------------------
-- Project/Track Helpers
--------------------------------------------------------------------------------

--- Get track by index (1-based)
-- @param idx number Track index (1-based)
-- @return userdata|nil Track pointer
function M.get_track(idx)
    return r.GetTrack(0, idx - 1)
end

--- Get FX by name on a track
-- @param track userdata Track pointer
-- @param name_pattern string FX name pattern to search for
-- @return number|nil FX index or nil if not found
function M.find_fx_by_name(track, name_pattern)
    local count = r.TrackFX_GetCount(track)
    for i = 0, count - 1 do
        local _, name = r.TrackFX_GetFXName(track, i, "")
        if name:find(name_pattern) then
            return i
        end
    end
    return nil
end

--- Get project tempo
-- @return number BPM
function M.get_tempo()
    return r.Master_GetTempo()
end

--- Calculate bar duration at current tempo
-- @return number Duration in seconds
function M.get_bar_duration()
    local bpm = r.Master_GetTempo()
    local _, beats_per_bar = r.GetProjectTimeSignature2(0)
    beats_per_bar = beats_per_bar or 4
    return (60 / bpm) * beats_per_bar
end

--- Calculate beat duration at current tempo
-- @return number Duration in seconds
function M.get_beat_duration()
    local bpm = r.Master_GetTempo()
    return 60 / bpm
end

--------------------------------------------------------------------------------
-- MIDI Helpers
--------------------------------------------------------------------------------

--- Get MIDI notes from a track within a time range
-- @param track userdata Track pointer
-- @param start_time number Start time in seconds
-- @param end_time number End time in seconds
-- @return table Array of {start, duration} notes
function M.get_midi_notes_in_range(track, start_time, end_time)
    local notes = {}

    local item_count = r.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        if item then
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len

            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                if item_end >= start_time and item_pos <= end_time then
                    local _, note_count = r.MIDI_CountEvts(take)

                    for n = 0, note_count - 1 do
                        local _, _, _, note_start_ppq, note_end_ppq = r.MIDI_GetNote(take, n)
                        local note_start = r.MIDI_GetProjTimeFromPPQPos(take, note_start_ppq)
                        local note_end = r.MIDI_GetProjTimeFromPPQPos(take, note_end_ppq)

                        if note_start >= start_time and note_start < end_time then
                            notes[#notes + 1] = {
                                start = note_start,
                                duration = note_end - note_start
                            }
                        end
                    end
                end
            end
        end
    end

    table.sort(notes, function(a, b) return a.start < b.start end)
    return notes
end

--- Find envelope segments that correspond to MIDI notes
-- Groups consecutive envelope points that fall within note boundaries
-- @param points table Envelope points
-- @param notes table MIDI notes {start, duration}
-- @param gap_threshold number Max gap between points to consider same segment (default 0.1s)
-- @return table Array of segments {start_time, end_time, points, note_idx}
function M.find_note_segments(points, notes, gap_threshold)
    gap_threshold = gap_threshold or 0.1
    local segments = {}

    for note_idx, note in ipairs(notes) do
        local note_end = note.start + note.duration
        local segment_points = {}

        for _, p in ipairs(points) do
            -- Point is within note boundaries (with small tolerance)
            if p.time >= note.start - 0.001 and p.time <= note_end + 0.001 then
                segment_points[#segment_points + 1] = p
            end
        end

        if #segment_points > 0 then
            segments[#segments + 1] = {
                start_time = segment_points[1].time,
                end_time = segment_points[#segment_points].time,
                points = segment_points,
                note_idx = note_idx,
                note = note
            }
        end
    end

    return segments
end

--- Count complete LFO cycles in a segment by finding peaks/troughs
-- @param points table Envelope points in the segment
-- @param tolerance number Tolerance for peak detection (default 0.05)
-- @return number Estimated cycle count
function M.estimate_cycle_count(points, tolerance)
    tolerance = tolerance or 0.05
    if #points < 3 then return 0 end

    local peaks = 0
    local troughs = 0

    for i = 2, #points - 1 do
        local prev = points[i - 1].value
        local curr = points[i].value
        local next_v = points[i + 1].value

        -- Local maximum (peak)
        if curr > prev + tolerance and curr > next_v + tolerance then
            peaks = peaks + 1
        end
        -- Local minimum (trough)
        if curr < prev - tolerance and curr < next_v - tolerance then
            troughs = troughs + 1
        end
    end

    -- A complete cycle has one peak and one trough
    return math.max(peaks, troughs)
end

--- Check if envelope shows phase reset at a specific time
-- Phase reset means value returns to start of waveform
-- @param points table Envelope points
-- @param reset_time number Time where reset should occur
-- @param expected_start_value number Expected value at phase 0 (default: first point value)
-- @param tolerance number Time and value tolerance
-- @return boolean, string Whether reset detected and description
function M.check_phase_reset(points, reset_time, expected_start_value, tolerance)
    tolerance = tolerance or 0.05

    -- Find point closest to reset_time
    local closest_point = nil
    local min_dist = math.huge

    for _, p in ipairs(points) do
        local dist = math.abs(p.time - reset_time)
        if dist < min_dist then
            min_dist = dist
            closest_point = p
        end
    end

    if not closest_point or min_dist > tolerance then
        return false, string.format("No point near reset time %.3f", reset_time)
    end

    expected_start_value = expected_start_value or points[1].value

    if M.approx_equal(closest_point.value, expected_start_value, tolerance) then
        return true, string.format("Phase reset at %.3f (value=%.3f)", reset_time, closest_point.value)
    else
        return false, string.format("Value at %.3f is %.3f, expected %.3f",
            reset_time, closest_point.value, expected_start_value)
    end
end

--- Assert that automation exists only during MIDI notes (with gaps between)
-- @param name string Test name
-- @param points table Envelope points
-- @param notes table MIDI notes
-- @param tolerance number Time tolerance
-- @return table Test result
function M.assert_automation_follows_notes(name, points, notes, tolerance)
    tolerance = tolerance or 0.05

    if #points == 0 then
        return M.make_result(name, false, "No envelope points")
    end

    if #notes == 0 then
        return M.make_result(name, false, "No MIDI notes")
    end

    local segments = M.find_note_segments(points, notes, tolerance)

    if #segments ~= #notes then
        return M.make_result(name, false,
            string.format("Found %d segments but expected %d (one per note)", #segments, #notes),
            { segments = #segments, notes = #notes })
    end

    -- Check each segment starts near note start
    for i, seg in ipairs(segments) do
        local note = notes[i]
        if not M.approx_equal(seg.start_time, note.start, tolerance) then
            return M.make_result(name, false,
                string.format("Segment %d starts at %.3f but note starts at %.3f",
                    i, seg.start_time, note.start))
        end
    end

    return M.make_result(name, true,
        string.format("All %d segments align with notes", #segments))
end

--- Assert expected number of cycles per note based on rate
-- @param name string Test name
-- @param segments table Segments from find_note_segments
-- @param cycle_duration number Expected duration of one LFO cycle
-- @param tolerance number Tolerance for cycle count (default 0.5)
-- @return table Test result
function M.assert_cycles_per_note(name, segments, cycle_duration, tolerance)
    tolerance = tolerance or 0.5

    local all_ok = true
    local messages = {}

    for i, seg in ipairs(segments) do
        local note_duration = seg.note.duration
        local expected_cycles = note_duration / cycle_duration
        local actual_cycles = M.estimate_cycle_count(seg.points)

        -- For very short notes, we might have 0 complete cycles but still have points
        local min_expected = math.max(0, math.floor(expected_cycles) - 1)
        local max_expected = math.ceil(expected_cycles) + 1

        if actual_cycles < min_expected or actual_cycles > max_expected then
            all_ok = false
            messages[#messages + 1] = string.format(
                "Note %d: expected ~%.1f cycles, got %d", i, expected_cycles, actual_cycles)
        else
            messages[#messages + 1] = string.format(
                "Note %d: %.1f expected, %d actual (OK)", i, expected_cycles, actual_cycles)
        end
    end

    return M.make_result(name, all_ok, table.concat(messages, "; "))
end

return M
