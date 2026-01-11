--- Bake Modulation Integration Tests
-- Comprehensive tests for LFO to automation baking
-- @module tests.integration.bake_integration_tests
-- @author SideFX
-- @license MIT
--
-- USAGE:
-- 1. Open bake_test_project.rpp in REAPER
-- 2. Load this script as a ReaScript action
-- 3. Run the action to execute all tests
--
-- See README.md for test project setup instructions

local r = reaper

-- Add project paths
local script_path = ({r.get_action_context()})[2]:match("(.*/)")
local project_root = script_path:match("(.*/SideFX/)") or script_path:match("(.*/)tests/")
if project_root then
    package.path = project_root .. "?.lua;" .. project_root .. "lib/?.lua;" .. package.path
end

local helpers = require('tests.integration.test_helpers')
local modulator_bake = require('lib.modulator.modulator_bake')

local M = {}

--------------------------------------------------------------------------------
-- Test Configuration
--------------------------------------------------------------------------------

-- Track indices in test project (1-based)
local TRACKS = {
    -- Basic continuous mode tests
    UNIPOLAR = 1,           -- Unipolar ramp, Transport trigger
    BIPOLAR = 2,            -- Bipolar sine, Transport trigger

    -- MIDI trigger tests
    MIDI_FAST_RATE = 3,     -- MIDI trigger, fast rate (4 Hz), varied note lengths
    MIDI_SLOW_RATE = 4,     -- MIDI trigger, slow rate (1 Hz), long notes
    MIDI_SYNC_RATE = 5,     -- MIDI trigger, sync rate (1/8), varied notes

    -- Edge case tests
    MIDI_SHORT_NOTES = 6,   -- Very short notes (shorter than one cycle)
    MIDI_LONG_NOTES = 7,    -- Very long notes (many cycles)
    MIDI_WITH_GAPS = 8,     -- Notes with significant gaps between them
}

-- Test parameters
local TEST_PARAMS = {
    -- Rate configurations (in Hz or sync divisions)
    FAST_RATE_HZ = 4,           -- 4 Hz = 0.25s per cycle
    SLOW_RATE_HZ = 1,           -- 1 Hz = 1s per cycle
    SYNC_RATE_BEATS = 0.5,      -- 1/8 note = 0.5 beats per cycle

    -- Expected ranges
    UNIPOLAR_MIN = 0.5,
    UNIPOLAR_MAX = 1.0,
    BIPOLAR_MIN = 0.0,
    BIPOLAR_MAX = 1.0,

    -- Tolerances
    VALUE_TOLERANCE = 0.05,
    TIME_TOLERANCE = 0.05,
    CYCLE_TOLERANCE = 1,
}

--------------------------------------------------------------------------------
-- Formula Verification Tests (No project required)
--------------------------------------------------------------------------------

--- Verify unipolar formula: baseline + lfo * scale
function M.test_formula_unipolar()
    local link_info = { baseline = 0.5, scale = 0.5, offset = 0 }

    local lfo_0 = modulator_bake.calculate_param_value(0, link_info)
    local lfo_1 = modulator_bake.calculate_param_value(1, link_info)

    local pass_0 = helpers.approx_equal(lfo_0, 0.5, 0.001)
    local pass_1 = helpers.approx_equal(lfo_1, 1.0, 0.001)

    if pass_0 and pass_1 then
        return helpers.make_result("Formula Unipolar", true,
            string.format("LFO 0→%.3f, LFO 1→%.3f (correct)", lfo_0, lfo_1))
    else
        return helpers.make_result("Formula Unipolar", false,
            string.format("LFO 0→%.3f (exp 0.5), LFO 1→%.3f (exp 1.0)", lfo_0, lfo_1))
    end
end

--- Verify bipolar formula: baseline + (lfo - 0.5) * scale
function M.test_formula_bipolar()
    local link_info = { baseline = 0.5, scale = 1.0, offset = -0.5 }

    local lfo_0 = modulator_bake.calculate_param_value(0, link_info)
    local lfo_05 = modulator_bake.calculate_param_value(0.5, link_info)
    local lfo_1 = modulator_bake.calculate_param_value(1, link_info)

    local pass_0 = helpers.approx_equal(lfo_0, 0.0, 0.001)
    local pass_05 = helpers.approx_equal(lfo_05, 0.5, 0.001)
    local pass_1 = helpers.approx_equal(lfo_1, 1.0, 0.001)

    if pass_0 and pass_05 and pass_1 then
        return helpers.make_result("Formula Bipolar", true,
            string.format("LFO 0→%.3f, 0.5→%.3f, 1→%.3f (correct)", lfo_0, lfo_05, lfo_1))
    else
        return helpers.make_result("Formula Bipolar", false,
            string.format("LFO 0→%.3f (exp 0), 0.5→%.3f (exp 0.5), 1→%.3f (exp 1)", lfo_0, lfo_05, lfo_1))
    end
end

--- Test negative scale (inverted modulation)
function M.test_formula_negative_scale()
    local link_info = { baseline = 0.5, scale = -0.5, offset = 0 }

    local lfo_0 = modulator_bake.calculate_param_value(0, link_info)
    local lfo_1 = modulator_bake.calculate_param_value(1, link_info)

    local pass_0 = helpers.approx_equal(lfo_0, 0.5, 0.001)
    local pass_1 = helpers.approx_equal(lfo_1, 0.0, 0.001)

    if pass_0 and pass_1 then
        return helpers.make_result("Formula Negative Scale", true,
            string.format("LFO 0→%.3f, LFO 1→%.3f (correct)", lfo_0, lfo_1))
    else
        return helpers.make_result("Formula Negative Scale", false,
            string.format("LFO 0→%.3f (exp 0.5), LFO 1→%.3f (exp 0.0)", lfo_0, lfo_1))
    end
end

--- Test clamping at boundaries
function M.test_formula_clamping()
    -- Scale that would push value beyond 0-1
    local link_info = { baseline = 0.8, scale = 0.5, offset = 0 }

    local lfo_1 = modulator_bake.calculate_param_value(1, link_info)

    -- 0.8 + 1 * 0.5 = 1.3, should clamp to 1.0
    local passed = helpers.approx_equal(lfo_1, 1.0, 0.001)

    if passed then
        return helpers.make_result("Formula Clamping", true,
            string.format("Value clamped to %.3f (correct)", lfo_1))
    else
        return helpers.make_result("Formula Clamping", false,
            string.format("Value %.3f should be clamped to 1.0", lfo_1))
    end
end

--------------------------------------------------------------------------------
-- Continuous Mode Tests (Free/Transport trigger)
--------------------------------------------------------------------------------

--- Helper to get envelope from track
local function get_test_envelope(track_idx)
    local track = helpers.get_track(track_idx)
    if not track then return nil, nil, "Track not found" end

    local fx_idx = helpers.find_fx_by_name(track, "ReaSynth")
    if not fx_idx then return nil, nil, "ReaSynth not found" end

    local envelope = helpers.get_fx_envelope(track, fx_idx, 0)
    if not envelope then return nil, nil, "No envelope (run bake first)" end

    local points = helpers.read_envelope_points(envelope)
    if #points == 0 then return nil, nil, "Envelope empty (run bake first)" end

    return track, points, nil
end

--- Test unipolar ramp baking
function M.test_continuous_unipolar_range()
    local _, points, err = get_test_envelope(TRACKS.UNIPOLAR)
    if err then
        return helpers.make_result("Continuous Unipolar Range", false, err)
    end

    return helpers.assert_value_range("Continuous Unipolar Range",
        points, TEST_PARAMS.UNIPOLAR_MIN, TEST_PARAMS.UNIPOLAR_MAX, TEST_PARAMS.VALUE_TOLERANCE)
end

--- Test bipolar sine baking
function M.test_continuous_bipolar_range()
    local _, points, err = get_test_envelope(TRACKS.BIPOLAR)
    if err then
        return helpers.make_result("Continuous Bipolar Range", false, err)
    end

    return helpers.assert_value_range("Continuous Bipolar Range",
        points, TEST_PARAMS.BIPOLAR_MIN, TEST_PARAMS.BIPOLAR_MAX, TEST_PARAMS.VALUE_TOLERANCE)
end

--- Test that continuous mode covers expected duration
function M.test_continuous_timing()
    local _, points, err = get_test_envelope(TRACKS.UNIPOLAR)
    if err then
        return helpers.make_result("Continuous Timing", false, err)
    end

    -- Default bake is 4 bars
    local bar_duration = helpers.get_bar_duration()
    local expected_end = 4 * bar_duration

    return helpers.assert_time_range("Continuous Timing",
        points, 0, expected_end, 0.1)
end

--------------------------------------------------------------------------------
-- MIDI Trigger Tests - Core Functionality
--------------------------------------------------------------------------------

--- Test: MIDI trigger produces automation only during notes
function M.test_midi_automation_during_notes_only()
    local track, points, err = get_test_envelope(TRACKS.MIDI_FAST_RATE)
    if err then
        return helpers.make_result("MIDI Automation During Notes", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes == 0 then
        return helpers.make_result("MIDI Automation During Notes", false,
            "No MIDI notes found on track")
    end

    return helpers.assert_automation_follows_notes("MIDI Automation During Notes",
        points, notes, TEST_PARAMS.TIME_TOLERANCE)
end

--- Test: Phase resets at each note start
function M.test_midi_phase_reset()
    local track, points, err = get_test_envelope(TRACKS.MIDI_FAST_RATE)
    if err then
        return helpers.make_result("MIDI Phase Reset", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes < 2 then
        return helpers.make_result("MIDI Phase Reset", false,
            "Need at least 2 notes to test phase reset")
    end

    -- Get the expected start value (first point of first segment)
    local segments = helpers.find_note_segments(points, notes)
    if #segments == 0 then
        return helpers.make_result("MIDI Phase Reset", false, "No segments found")
    end

    local expected_start = segments[1].points[1].value
    local reset_count = 0
    local messages = {}

    for i = 2, #segments do
        local seg = segments[i]
        local first_point = seg.points[1]
        if helpers.approx_equal(first_point.value, expected_start, TEST_PARAMS.VALUE_TOLERANCE) then
            reset_count = reset_count + 1
        else
            messages[#messages + 1] = string.format(
                "Note %d: start value %.3f != expected %.3f",
                i, first_point.value, expected_start)
        end
    end

    local expected_resets = #segments - 1
    if reset_count == expected_resets then
        return helpers.make_result("MIDI Phase Reset", true,
            string.format("All %d notes show phase reset to %.3f", #segments, expected_start))
    else
        return helpers.make_result("MIDI Phase Reset", false,
            string.format("%d/%d phase resets detected. %s",
                reset_count, expected_resets, table.concat(messages, "; ")))
    end
end

--- Test: Fast rate produces multiple cycles per note
function M.test_midi_fast_rate_cycles()
    local track, points, err = get_test_envelope(TRACKS.MIDI_FAST_RATE)
    if err then
        return helpers.make_result("MIDI Fast Rate Cycles", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes == 0 then
        return helpers.make_result("MIDI Fast Rate Cycles", false, "No MIDI notes")
    end

    local segments = helpers.find_note_segments(points, notes)
    local cycle_duration = 1 / TEST_PARAMS.FAST_RATE_HZ  -- 0.25s at 4 Hz

    return helpers.assert_cycles_per_note("MIDI Fast Rate Cycles",
        segments, cycle_duration, TEST_PARAMS.CYCLE_TOLERANCE)
end

--- Test: Slow rate produces fewer cycles per note
function M.test_midi_slow_rate_cycles()
    local track, points, err = get_test_envelope(TRACKS.MIDI_SLOW_RATE)
    if err then
        return helpers.make_result("MIDI Slow Rate Cycles", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes == 0 then
        return helpers.make_result("MIDI Slow Rate Cycles", false, "No MIDI notes")
    end

    local segments = helpers.find_note_segments(points, notes)
    local cycle_duration = 1 / TEST_PARAMS.SLOW_RATE_HZ  -- 1s at 1 Hz

    return helpers.assert_cycles_per_note("MIDI Slow Rate Cycles",
        segments, cycle_duration, TEST_PARAMS.CYCLE_TOLERANCE)
end

--- Test: Sync rate works correctly with MIDI trigger
function M.test_midi_sync_rate()
    local track, points, err = get_test_envelope(TRACKS.MIDI_SYNC_RATE)
    if err then
        return helpers.make_result("MIDI Sync Rate", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes == 0 then
        return helpers.make_result("MIDI Sync Rate", false, "No MIDI notes")
    end

    local segments = helpers.find_note_segments(points, notes)
    local beat_duration = helpers.get_beat_duration()
    local cycle_duration = beat_duration * TEST_PARAMS.SYNC_RATE_BEATS  -- 1/8 note

    return helpers.assert_cycles_per_note("MIDI Sync Rate",
        segments, cycle_duration, TEST_PARAMS.CYCLE_TOLERANCE)
end

--------------------------------------------------------------------------------
-- MIDI Trigger Tests - Edge Cases
--------------------------------------------------------------------------------

--- Test: Very short notes (shorter than one LFO cycle)
function M.test_midi_short_notes()
    local track, points, err = get_test_envelope(TRACKS.MIDI_SHORT_NOTES)
    if err then
        return helpers.make_result("MIDI Short Notes", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes == 0 then
        return helpers.make_result("MIDI Short Notes", false, "No MIDI notes")
    end

    local segments = helpers.find_note_segments(points, notes)

    -- Short notes should still produce automation (partial cycle)
    if #segments == 0 then
        return helpers.make_result("MIDI Short Notes", false,
            "No automation segments found for short notes")
    end

    -- Each segment should have points even if note is shorter than cycle
    local all_have_points = true
    for i, seg in ipairs(segments) do
        if #seg.points < 2 then
            all_have_points = false
            break
        end
    end

    if all_have_points then
        return helpers.make_result("MIDI Short Notes", true,
            string.format("All %d short notes produced partial automation", #segments))
    else
        return helpers.make_result("MIDI Short Notes", false,
            "Some short notes missing automation points")
    end
end

--- Test: Very long notes (many LFO cycles)
function M.test_midi_long_notes()
    local track, points, err = get_test_envelope(TRACKS.MIDI_LONG_NOTES)
    if err then
        return helpers.make_result("MIDI Long Notes", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 30)
    if #notes == 0 then
        return helpers.make_result("MIDI Long Notes", false, "No MIDI notes")
    end

    local segments = helpers.find_note_segments(points, notes)

    -- Long notes should produce many cycles
    -- Using slow rate (1 Hz), a 4-second note should have ~4 cycles
    local cycle_duration = 1 / TEST_PARAMS.SLOW_RATE_HZ
    local messages = {}
    local all_ok = true

    for i, seg in ipairs(segments) do
        local expected_cycles = seg.note.duration / cycle_duration
        local actual_cycles = helpers.estimate_cycle_count(seg.points)

        if expected_cycles >= 3 and actual_cycles < 2 then
            all_ok = false
            messages[#messages + 1] = string.format(
                "Note %d (%.1fs): expected ~%.0f cycles, got %d",
                i, seg.note.duration, expected_cycles, actual_cycles)
        else
            messages[#messages + 1] = string.format(
                "Note %d: %d cycles (OK)", i, actual_cycles)
        end
    end

    return helpers.make_result("MIDI Long Notes", all_ok, table.concat(messages, "; "))
end

--- Test: Notes with gaps between them
function M.test_midi_gaps_between_notes()
    local track, points, err = get_test_envelope(TRACKS.MIDI_WITH_GAPS)
    if err then
        return helpers.make_result("MIDI Gaps Between Notes", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes < 2 then
        return helpers.make_result("MIDI Gaps Between Notes", false,
            "Need at least 2 notes with gaps")
    end

    -- Check that there are actual gaps between notes
    local has_gaps = false
    for i = 2, #notes do
        local prev_end = notes[i-1].start + notes[i-1].duration
        local gap = notes[i].start - prev_end
        if gap > 0.1 then
            has_gaps = true
            break
        end
    end

    if not has_gaps then
        return helpers.make_result("MIDI Gaps Between Notes", false,
            "No significant gaps found between notes (need gaps > 0.1s)")
    end

    -- Verify automation follows notes (not continuous through gaps)
    return helpers.assert_automation_follows_notes("MIDI Gaps Between Notes",
        points, notes, TEST_PARAMS.TIME_TOLERANCE)
end

--- Test: Verify no automation points exist in gaps between notes
function M.test_midi_no_points_in_gaps()
    local track, points, err = get_test_envelope(TRACKS.MIDI_WITH_GAPS)
    if err then
        return helpers.make_result("MIDI No Points In Gaps", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    if #notes < 2 then
        return helpers.make_result("MIDI No Points In Gaps", false, "Need at least 2 notes")
    end

    -- Find points that fall in gaps
    local gap_tolerance = 0.01
    local points_in_gaps = 0

    for _, p in ipairs(points) do
        local in_any_note = false
        for _, note in ipairs(notes) do
            local note_end = note.start + note.duration
            if p.time >= note.start - gap_tolerance and p.time <= note_end + gap_tolerance then
                in_any_note = true
                break
            end
        end
        if not in_any_note then
            points_in_gaps = points_in_gaps + 1
        end
    end

    if points_in_gaps == 0 then
        return helpers.make_result("MIDI No Points In Gaps", true,
            string.format("All %d points fall within notes", #points))
    else
        return helpers.make_result("MIDI No Points In Gaps", false,
            string.format("%d points found in gaps between notes", points_in_gaps))
    end
end

--------------------------------------------------------------------------------
-- MIDI Trigger Tests - Value Ranges
--------------------------------------------------------------------------------

--- Test: MIDI trigger respects unipolar range per note
function M.test_midi_unipolar_value_range()
    local track, points, err = get_test_envelope(TRACKS.MIDI_FAST_RATE)
    if err then
        return helpers.make_result("MIDI Unipolar Range", false, err)
    end

    local notes = helpers.get_midi_notes_in_range(track, 0, 20)
    local segments = helpers.find_note_segments(points, notes)

    if #segments == 0 then
        return helpers.make_result("MIDI Unipolar Range", false, "No segments")
    end

    -- Check value range across all segments
    local all_min, all_max = 1, 0
    for _, seg in ipairs(segments) do
        local seg_min, seg_max = helpers.get_value_range(seg.points)
        if seg_min < all_min then all_min = seg_min end
        if seg_max > all_max then all_max = seg_max end
    end

    return helpers.assert_value_range("MIDI Unipolar Range",
        {{ value = all_min }, { value = all_max }},
        TEST_PARAMS.UNIPOLAR_MIN, TEST_PARAMS.UNIPOLAR_MAX, TEST_PARAMS.VALUE_TOLERANCE)
end

--------------------------------------------------------------------------------
-- Test Runner
--------------------------------------------------------------------------------

--- Run all formula tests (no project required)
function M.run_formula_tests()
    local tests = {
        { name = "Formula Unipolar", func = M.test_formula_unipolar },
        { name = "Formula Bipolar", func = M.test_formula_bipolar },
        { name = "Formula Negative Scale", func = M.test_formula_negative_scale },
        { name = "Formula Clamping", func = M.test_formula_clamping },
    }

    local results = helpers.run_tests(tests)
    helpers.print_results(results)
    return results
end

--- Run continuous mode tests
function M.run_continuous_tests()
    local tests = {
        { name = "Continuous Unipolar Range", func = M.test_continuous_unipolar_range },
        { name = "Continuous Bipolar Range", func = M.test_continuous_bipolar_range },
        { name = "Continuous Timing", func = M.test_continuous_timing },
    }

    local results = helpers.run_tests(tests)
    helpers.print_results(results)
    return results
end

--- Run MIDI trigger tests
function M.run_midi_tests()
    local tests = {
        -- Core MIDI functionality
        { name = "MIDI Automation During Notes", func = M.test_midi_automation_during_notes_only },
        { name = "MIDI Phase Reset", func = M.test_midi_phase_reset },
        { name = "MIDI Fast Rate Cycles", func = M.test_midi_fast_rate_cycles },
        { name = "MIDI Slow Rate Cycles", func = M.test_midi_slow_rate_cycles },
        { name = "MIDI Sync Rate", func = M.test_midi_sync_rate },

        -- Edge cases
        { name = "MIDI Short Notes", func = M.test_midi_short_notes },
        { name = "MIDI Long Notes", func = M.test_midi_long_notes },
        { name = "MIDI Gaps Between Notes", func = M.test_midi_gaps_between_notes },
        { name = "MIDI No Points In Gaps", func = M.test_midi_no_points_in_gaps },

        -- Value ranges
        { name = "MIDI Unipolar Range", func = M.test_midi_unipolar_value_range },
    }

    local results = helpers.run_tests(tests)
    helpers.print_results(results)
    return results
end

--- Run all tests
function M.run_all_tests()
    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("╔══════════════════════════════════════════════════════════════╗\n")
    r.ShowConsoleMsg("║         BAKE MODULATION INTEGRATION TESTS                    ║\n")
    r.ShowConsoleMsg("╚══════════════════════════════════════════════════════════════╝\n")

    local all_tests = {
        -- Formula tests
        { name = "Formula Unipolar", func = M.test_formula_unipolar },
        { name = "Formula Bipolar", func = M.test_formula_bipolar },
        { name = "Formula Negative Scale", func = M.test_formula_negative_scale },
        { name = "Formula Clamping", func = M.test_formula_clamping },

        -- Continuous mode tests
        { name = "Continuous Unipolar Range", func = M.test_continuous_unipolar_range },
        { name = "Continuous Bipolar Range", func = M.test_continuous_bipolar_range },
        { name = "Continuous Timing", func = M.test_continuous_timing },

        -- MIDI trigger tests
        { name = "MIDI Automation During Notes", func = M.test_midi_automation_during_notes_only },
        { name = "MIDI Phase Reset", func = M.test_midi_phase_reset },
        { name = "MIDI Fast Rate Cycles", func = M.test_midi_fast_rate_cycles },
        { name = "MIDI Slow Rate Cycles", func = M.test_midi_slow_rate_cycles },
        { name = "MIDI Sync Rate", func = M.test_midi_sync_rate },
        { name = "MIDI Short Notes", func = M.test_midi_short_notes },
        { name = "MIDI Long Notes", func = M.test_midi_long_notes },
        { name = "MIDI Gaps Between Notes", func = M.test_midi_gaps_between_notes },
        { name = "MIDI No Points In Gaps", func = M.test_midi_no_points_in_gaps },
        { name = "MIDI Unipolar Range", func = M.test_midi_unipolar_value_range },
    }

    local results = helpers.run_tests(all_tests)
    helpers.print_results(results)

    return results
end

--------------------------------------------------------------------------------
-- Main entry point when run as ReaScript action
--------------------------------------------------------------------------------

if ({r.get_action_context()})[2] then
    M.run_all_tests()
end

return M
