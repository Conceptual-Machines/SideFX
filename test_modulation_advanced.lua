-- SideFX Modulation Engine - Advanced Test Script
-- Tests triggers and automation printing

local function log(msg)
    reaper.ShowConsoleMsg(msg .. "\n")
end

log("=== SideFX Advanced Modulation Test ===\n")

-- Check API
if not reaper.SideFX_Mod_Create then
    log("ERROR: SideFX Modulation Engine not loaded!")
    return
end

-- Get selected track
local track = reaper.GetSelectedTrack(0, 0)
if not track then
    log("Please select a track with FX first!")
    return
end

local fx_count = reaper.TrackFX_GetCount(track)
if fx_count == 0 then
    log("Track needs at least one FX!")
    return
end

local _, track_name = reaper.GetTrackName(track)
local _, fx_name = reaper.TrackFX_GetFXName(track, 0)
local _, param_name = reaper.TrackFX_GetParamName(track, 0, 0)

log("Target: " .. track_name .. " > " .. fx_name .. " > " .. param_name .. "\n")

-- Menu
log("Choose test mode:")
log("  1 = Classic LFO (free running)")
log("  2 = One-shot envelope (manual trigger)")
log("  3 = MIDI-triggered envelope")
log("  4 = Audio-triggered envelope")
log("  5 = Record & Print to automation")
log("")

local mode = 1  -- Default to LFO

-- Create modulator
local mod_id = reaper.SideFX_Mod_Create("Test Modulator")
log("Created modulator ID: " .. mod_id .. "\n")

if mode == 1 then
    -- Classic LFO
    log("=== Mode 1: Classic LFO ===")
    reaper.SideFX_Mod_SetPreset(mod_id, "sine")
    reaper.SideFX_Mod_SetTriggerMode(mod_id, 0)     -- Free
    reaper.SideFX_Mod_SetPlaybackMode(mod_id, 0)    -- Loop
    reaper.SideFX_Mod_SetRateHz(mod_id, 0.5)        -- 0.5 Hz = 2 second cycle
    reaper.SideFX_Mod_SetDepth(mod_id, 0.8)
    reaper.SideFX_Mod_SetOffset(mod_id, 0.5)
    reaper.SideFX_Mod_Link(mod_id, track, 0, 0)
    reaper.SideFX_Mod_SetEnabled(mod_id, true)
    log("LFO running at 0.5 Hz (2 second cycle)")
    
elseif mode == 2 then
    -- One-shot envelope with manual trigger
    log("=== Mode 2: One-shot Envelope ===")
    -- Custom decay envelope
    reaper.SideFX_Mod_SetCurve(mod_id, 0,1, 0.1,0.8, 0.5,0.2, 1,0)
    reaper.SideFX_Mod_SetTriggerMode(mod_id, 4)     -- Manual
    reaper.SideFX_Mod_SetPlaybackMode(mod_id, 1)    -- OneShot
    reaper.SideFX_Mod_SetRateHz(mod_id, 2.0)        -- 500ms envelope
    reaper.SideFX_Mod_SetDepth(mod_id, 1.0)
    reaper.SideFX_Mod_SetOffset(mod_id, 0.0)
    reaper.SideFX_Mod_SetBipolar(mod_id, false)     -- 0 to depth
    reaper.SideFX_Mod_Link(mod_id, track, 0, 0)
    reaper.SideFX_Mod_SetEnabled(mod_id, true)
    
    -- Trigger it
    log("Triggering envelope...")
    reaper.SideFX_Mod_Trigger(mod_id, 1.0)
    log("Envelope triggered! Watch the parameter decay.")
    
elseif mode == 3 then
    -- MIDI-triggered
    log("=== Mode 3: MIDI-triggered Envelope ===")
    reaper.SideFX_Mod_SetPreset(mod_id, "ease")     -- Smooth attack/decay
    reaper.SideFX_Mod_SetTriggerMode(mod_id, 3)     -- MidiNote
    reaper.SideFX_Mod_SetPlaybackMode(mod_id, 1)    -- OneShot
    reaper.SideFX_Mod_SetRateHz(mod_id, 2.0)
    reaper.SideFX_Mod_SetMidiChannel(mod_id, -1)    -- Omni
    reaper.SideFX_Mod_SetMidiNote(mod_id, -1)       -- Any note
    reaper.SideFX_Mod_SetVelocityToDepth(mod_id, true)
    reaper.SideFX_Mod_SetDepth(mod_id, 1.0)
    reaper.SideFX_Mod_SetOffset(mod_id, 0.0)
    reaper.SideFX_Mod_Link(mod_id, track, 0, 0)
    reaper.SideFX_Mod_SetEnabled(mod_id, true)
    log("Play MIDI notes to trigger the envelope!")
    log("Velocity will control depth.")
    
elseif mode == 4 then
    -- Audio-triggered
    log("=== Mode 4: Audio-triggered Envelope ===")
    reaper.SideFX_Mod_SetPreset(mod_id, "ease")
    reaper.SideFX_Mod_SetTriggerMode(mod_id, 1)     -- AudioLevel
    reaper.SideFX_Mod_SetPlaybackMode(mod_id, 1)    -- OneShot
    reaper.SideFX_Mod_SetTriggerTrack(mod_id, track) -- Same track as source
    reaper.SideFX_Mod_SetAudioThreshold(mod_id, 0.3)
    reaper.SideFX_Mod_SetRetriggerDelay(mod_id, 100)
    reaper.SideFX_Mod_SetRateHz(mod_id, 4.0)        -- 250ms envelope
    reaper.SideFX_Mod_SetDepth(mod_id, 0.8)
    reaper.SideFX_Mod_SetOffset(mod_id, 0.1)
    reaper.SideFX_Mod_Link(mod_id, track, 0, 0)
    reaper.SideFX_Mod_SetEnabled(mod_id, true)
    log("Play audio on this track to trigger!")
    
elseif mode == 5 then
    -- Record and print to automation
    log("=== Mode 5: Record & Print ===")
    reaper.SideFX_Mod_SetPreset(mod_id, "sine")
    reaper.SideFX_Mod_SetTriggerMode(mod_id, 0)     -- Free
    reaper.SideFX_Mod_SetPlaybackMode(mod_id, 0)    -- Loop
    reaper.SideFX_Mod_SetRateHz(mod_id, 1.0)
    reaper.SideFX_Mod_SetDepth(mod_id, 0.8)
    reaper.SideFX_Mod_SetOffset(mod_id, 0.5)
    reaper.SideFX_Mod_Link(mod_id, track, 0, 0)
    reaper.SideFX_Mod_SetEnabled(mod_id, true)
    
    -- Start recording for 4 seconds
    local cursor = reaper.GetCursorPosition()
    log("Recording from " .. cursor .. " to " .. (cursor + 4) .. "...")
    reaper.SideFX_Mod_StartRecording(mod_id, cursor, cursor + 4, 0.02)
    
    -- Wait and print
    local function wait_and_print()
        if reaper.SideFX_Mod_IsRecording(mod_id) then
            reaper.defer(wait_and_print)
        else
            local count = reaper.SideFX_Mod_GetRecordedPointCount(mod_id)
            log("Recording complete! " .. count .. " points captured.")
            
            log("Printing to automation...")
            local result = reaper.SideFX_Mod_PrintToAutomation(mod_id, 0)  -- Linear shape
            log("Printed " .. result .. " points to automation!")
            log("Check the FX parameter envelope in the track!")
            
            reaper.SideFX_Mod_SetEnabled(mod_id, false)
        end
    end
    
    wait_and_print()
end

log("\n=== Modulator ID: " .. mod_id .. " ===")
log("To clean up: reaper.SideFX_Mod_Destroy(" .. mod_id .. ")")

