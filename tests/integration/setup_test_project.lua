--- Setup Test Project for Bake Integration Tests
-- Creates 8 tracks with ReaSynth, SideFX_Modulator, and MIDI items
-- @module tests.integration.setup_test_project
-- @author SideFX
-- @license MIT
--
-- USAGE:
-- 1. Open a new REAPER project
-- 2. Set tempo to 120 BPM
-- 3. Run this script as a ReaScript action
-- 4. Manually configure modulator settings and create parameter links
--
-- After running:
-- - Create parameter links on each track (Modulator → ReaSynth param 0)
-- - Set modulator trigger mode and rate per README instructions
-- - Bake automation on each track
-- - Run bake_integration_tests.lua

local r = reaper

--------------------------------------------------------------------------------
-- Configuration
--------------------------------------------------------------------------------

-- Track configurations
local TRACKS = {
    {
        name = "1-Continuous Unipolar",
        description = "Transport trigger, Sync 1 bar, Unipolar 50%",
        midi = nil,  -- No MIDI needed
    },
    {
        name = "2-Continuous Bipolar",
        description = "Transport trigger, Sync 1 bar, Bipolar 100%",
        midi = nil,
    },
    {
        name = "3-MIDI Fast Rate",
        description = "MIDI trigger, Free 4 Hz, mixed note lengths",
        midi = {
            length = 16,  -- 16 beats = 4 bars
            notes = {
                -- {start_beat, length_beats, pitch}
                -- Quarter notes (0.5s at 120 BPM = 1 beat)
                {0, 1, 60},
                {2, 1, 62},
                -- Half notes (1s = 2 beats)
                {4, 2, 64},
                {7, 2, 65},
                -- Whole notes (2s = 4 beats)
                {10, 4, 67},
            }
        },
    },
    {
        name = "4-MIDI Slow Rate",
        description = "MIDI trigger, Free 1 Hz, long notes",
        midi = {
            length = 32,  -- 8 bars
            notes = {
                -- Whole notes (4 beats)
                {0, 4, 60},
                {6, 4, 62},
                -- 2-bar notes (8 beats)
                {12, 8, 64},
                {22, 8, 65},
            }
        },
    },
    {
        name = "5-MIDI Sync Rate",
        description = "MIDI trigger, Sync 1/8, mixed notes",
        midi = {
            length = 16,
            notes = {
                {0, 2, 60},
                {3, 1, 62},
                {5, 2, 64},
                {8, 4, 65},
                {13, 2, 67},
            }
        },
    },
    {
        name = "6-MIDI Short Notes",
        description = "MIDI trigger, Free 1 Hz, very short notes",
        midi = {
            length = 8,
            notes = {
                -- 16th notes (0.25 beats)
                {0, 0.25, 60},
                {1, 0.25, 62},
                {2, 0.25, 64},
                {3, 0.25, 65},
                -- 32nd notes (0.125 beats)
                {4, 0.125, 67},
                {4.5, 0.125, 69},
                {5, 0.125, 71},
                {5.5, 0.125, 72},
                -- Some slightly longer for comparison
                {6, 0.5, 60},
                {7, 0.5, 62},
            }
        },
    },
    {
        name = "7-MIDI Long Notes",
        description = "MIDI trigger, Free 1 Hz, very long notes",
        midi = {
            length = 64,  -- 16 bars
            notes = {
                -- 4-bar note (16 beats = 8 seconds at 120 BPM)
                {0, 16, 60},
                -- 8-bar note (32 beats = 16 seconds)
                {20, 32, 64},
            }
        },
    },
    {
        name = "8-MIDI With Gaps",
        description = "MIDI trigger, Free 4 Hz, notes with gaps",
        midi = {
            length = 16,
            notes = {
                -- Note, then gap, then note...
                {0, 1, 60},      -- beat 0-1
                -- gap: beat 1-3 (1 second gap)
                {3, 2, 62},      -- beat 3-5
                -- gap: beat 5-8 (1.5 second gap)
                {8, 1, 64},      -- beat 8-9
                -- gap: beat 9-11 (1 second gap)
                {11, 2, 65},     -- beat 11-13
                -- gap: beat 13-15
                {15, 1, 67},     -- beat 15-16
            }
        },
    },
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Convert beats to project time (seconds)
local function beats_to_time(beats)
    return r.TimeMap2_beatsToTime(0, beats)
end

--- Convert beats to PPQ for MIDI
local function beats_to_ppq(take, beats)
    local time = beats_to_time(beats)
    return r.MIDI_GetPPQPosFromProjTime(take, time)
end

--- Create a MIDI item on a track
local function create_midi_item(track, start_beat, length_beats)
    local start_time = beats_to_time(start_beat)
    local end_time = beats_to_time(start_beat + length_beats)
    local item = r.CreateNewMIDIItemInProj(track, start_time, end_time)
    return item
end

--- Add a note to a MIDI take
local function add_note(take, start_beat, length_beats, pitch, velocity)
    velocity = velocity or 100
    local start_ppq = beats_to_ppq(take, start_beat)
    local end_ppq = beats_to_ppq(take, start_beat + length_beats)

    r.MIDI_InsertNote(take, false, false, start_ppq, end_ppq, 0, pitch, velocity, false)
end

--- Create track with FX
local function create_track(index, name)
    r.InsertTrackAtIndex(index, true)
    local track = r.GetTrack(0, index)

    -- Set track name
    r.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

    -- Add ReaSynth
    local reasynth_idx = r.TrackFX_AddByName(track, "ReaSynth", false, -1)
    if reasynth_idx < 0 then
        r.ShowConsoleMsg("Warning: Could not add ReaSynth to track " .. name .. "\n")
    end

    -- Add SideFX_Modulator
    local mod_idx = r.TrackFX_AddByName(track, "SideFX_Modulator", false, -1)
    if mod_idx < 0 then
        r.ShowConsoleMsg("Warning: Could not add SideFX_Modulator to track " .. name .. "\n")
        r.ShowConsoleMsg("  Make sure SideFX_Modulator.jsfx is installed\n")
    end

    return track
end

--------------------------------------------------------------------------------
-- Main Setup Function
--------------------------------------------------------------------------------

local function setup_test_project()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)

    -- Check tempo
    local tempo = r.Master_GetTempo()
    if math.abs(tempo - 120) > 0.1 then
        r.ShowConsoleMsg(string.format(
            "Warning: Project tempo is %.1f BPM. Tests expect 120 BPM.\n" ..
            "Set tempo to 120 BPM for accurate test results.\n\n", tempo))
    end

    r.ShowConsoleMsg("\n")
    r.ShowConsoleMsg("╔══════════════════════════════════════════════════════════════╗\n")
    r.ShowConsoleMsg("║         SETTING UP BAKE TEST PROJECT                         ║\n")
    r.ShowConsoleMsg("╚══════════════════════════════════════════════════════════════╝\n\n")

    -- Create tracks
    for i, config in ipairs(TRACKS) do
        r.ShowConsoleMsg(string.format("Creating track %d: %s\n", i, config.name))
        r.ShowConsoleMsg(string.format("  → %s\n", config.description))

        local track = create_track(i - 1, config.name)

        -- Create MIDI item if needed
        if config.midi then
            local item = create_midi_item(track, 0, config.midi.length)
            local take = r.GetActiveTake(item)

            if take then
                for _, note in ipairs(config.midi.notes) do
                    add_note(take, note[1], note[2], note[3])
                end
                r.MIDI_Sort(take)
                r.ShowConsoleMsg(string.format("  → Created MIDI item with %d notes\n",
                    #config.midi.notes))
            end
        else
            r.ShowConsoleMsg("  → No MIDI item (continuous mode)\n")
        end

        r.ShowConsoleMsg("\n")
    end

    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Setup Bake Test Project", -1)

    -- Print next steps
    r.ShowConsoleMsg("══════════════════════════════════════════════════════════════\n")
    r.ShowConsoleMsg("SETUP COMPLETE! Next steps:\n")
    r.ShowConsoleMsg("══════════════════════════════════════════════════════════════\n\n")

    r.ShowConsoleMsg("For each track, configure the modulator:\n\n")

    r.ShowConsoleMsg("Track 1 (Continuous Unipolar):\n")
    r.ShowConsoleMsg("  • Trigger: Transport\n")
    r.ShowConsoleMsg("  • Rate: Sync 1 bar\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 2 (Continuous Bipolar):\n")
    r.ShowConsoleMsg("  • Trigger: Transport\n")
    r.ShowConsoleMsg("  • Rate: Sync 1 bar\n")
    r.ShowConsoleMsg("  • Mode: Bipolar, Depth 100%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 3 (MIDI Fast Rate):\n")
    r.ShowConsoleMsg("  • Trigger: MIDI\n")
    r.ShowConsoleMsg("  • Rate: Free 4 Hz\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 4 (MIDI Slow Rate):\n")
    r.ShowConsoleMsg("  • Trigger: MIDI\n")
    r.ShowConsoleMsg("  • Rate: Free 1 Hz\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 5 (MIDI Sync Rate):\n")
    r.ShowConsoleMsg("  • Trigger: MIDI\n")
    r.ShowConsoleMsg("  • Rate: Sync 1/8\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 6 (MIDI Short Notes):\n")
    r.ShowConsoleMsg("  • Trigger: MIDI\n")
    r.ShowConsoleMsg("  • Rate: Free 1 Hz\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 7 (MIDI Long Notes):\n")
    r.ShowConsoleMsg("  • Trigger: MIDI\n")
    r.ShowConsoleMsg("  • Rate: Free 1 Hz\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("Track 8 (MIDI With Gaps):\n")
    r.ShowConsoleMsg("  • Trigger: MIDI\n")
    r.ShowConsoleMsg("  • Rate: Free 4 Hz\n")
    r.ShowConsoleMsg("  • Mode: Unipolar, Depth 50%, Baseline 50%\n")
    r.ShowConsoleMsg("  • Link to ReaSynth param 0\n\n")

    r.ShowConsoleMsg("══════════════════════════════════════════════════════════════\n")
    r.ShowConsoleMsg("After configuring all modulators:\n")
    r.ShowConsoleMsg("1. Bake automation on each track\n")
    r.ShowConsoleMsg("2. Run bake_integration_tests.lua\n")
    r.ShowConsoleMsg("══════════════════════════════════════════════════════════════\n")

    r.UpdateArrange()
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------

setup_test_project()
