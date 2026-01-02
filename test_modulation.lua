-- SideFX Modulation Engine Test Script
-- Run this to test the modulation API

local function log(msg)
    reaper.ShowConsoleMsg(msg .. "\n")
end

log("=== SideFX Modulation Engine Test ===\n")

-- Check if API is available
if not reaper.SideFX_Mod_Create then
    log("ERROR: SideFX Modulation Engine not loaded!")
    log("Make sure reaper_sidefx_mod.dylib is in UserPlugins and restart REAPER.")
    return
end

log("✓ API available\n")

-- Get selected track
local track = reaper.GetSelectedTrack(0, 0)
if not track then
    log("ERROR: Please select a track with an FX first!")
    return
end

local _, track_name = reaper.GetTrackName(track)
log("Selected track: " .. track_name)

-- Check if track has FX
local fx_count = reaper.TrackFX_GetCount(track)
if fx_count == 0 then
    log("ERROR: Selected track has no FX! Add an FX first.")
    return
end

-- Get first FX name
local _, fx_name = reaper.TrackFX_GetFXName(track, 0)
log("First FX: " .. fx_name)

-- Get first parameter name
local _, param_name = reaper.TrackFX_GetParamName(track, 0, 0)
log("First parameter: " .. param_name .. "\n")

-- Create a modulator
log("Creating modulator...")
local mod_id = reaper.SideFX_Mod_Create("Test LFO")
log("✓ Created modulator ID: " .. mod_id)

-- Set curve to sine
log("Setting sine preset...")
local ok = reaper.SideFX_Mod_SetPreset(mod_id, "sine")
log("✓ Preset set: " .. tostring(ok))

-- Set rate
log("Setting rate to 1 Hz...")
reaper.SideFX_Mod_SetRateHz(mod_id, 1.0)
log("✓ Rate set")

-- Set depth and offset
log("Setting depth=0.5, offset=0.5...")
reaper.SideFX_Mod_SetDepth(mod_id, 0.5)
reaper.SideFX_Mod_SetOffset(mod_id, 0.5)
log("✓ Depth/offset set")

-- Link to first FX, first parameter
log("Linking to " .. fx_name .. " > " .. param_name .. "...")
ok = reaper.SideFX_Mod_Link(mod_id, track, 0, 0)
log("✓ Linked: " .. tostring(ok))

-- Enable modulator
log("Enabling modulator...")
reaper.SideFX_Mod_SetEnabled(mod_id, true)
log("✓ Enabled")

log("\n=== MODULATION ACTIVE ===")
log("The first parameter of " .. fx_name .. " should now be oscillating!")
log("Press play or just watch the FX window.\n")

-- Monitor values for a few seconds
log("Monitoring values for 3 seconds...")
local start_time = reaper.time_precise()
local last_print = 0

local function monitor()
    local elapsed = reaper.time_precise() - start_time
    
    if elapsed < 3.0 then
        -- Print every 0.25 seconds
        if elapsed - last_print > 0.25 then
            local phase = reaper.SideFX_Mod_GetPhase(mod_id)
            local value = reaper.SideFX_Mod_GetValue(mod_id)
            local playing = reaper.SideFX_Mod_IsPlaying(mod_id)
            log(string.format("  t=%.2f: phase=%.3f value=%.3f playing=%s", 
                elapsed, phase, value, tostring(playing)))
            last_print = elapsed
        end
        reaper.defer(monitor)
    else
        -- Done monitoring
        log("\n=== TEST COMPLETE ===")
        log("Modulator is still running. To stop:")
        log("  reaper.SideFX_Mod_SetEnabled(" .. mod_id .. ", false)")
        log("  reaper.SideFX_Mod_Destroy(" .. mod_id .. ")")
        log("\nModulator ID for manual control: " .. mod_id)
    end
end

monitor()

