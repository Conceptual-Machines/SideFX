-- SideFX_Modulator.jsfx Parameter Indices
-- Parameters are indexed BY SLIDER NUMBER ORDER in declaration sequence,
-- NOT by declaration order in the file!

local M = {}

-- Rate section (sliders 1-6)
M.PARAM_TEMPO_MODE = 0    -- slider1: Free/Sync
M.PARAM_RATE_HZ = 1        -- slider2: Rate (Hz)
M.PARAM_SYNC_RATE = 2      -- slider3: Sync Rate
M.PARAM_OUTPUT = 3         -- slider4: Output
M.PARAM_PHASE = 4          -- slider5: Phase
M.PARAM_DEPTH = 5          -- slider6: Depth

-- Trigger section (sliders 20-25)
M.PARAM_TRIGGER_MODE = 6   -- slider20: Trigger Mode (Free/Transport/MIDI/Audio)
M.PARAM_MIDI_SOURCE = 7    -- slider21: MIDI Source
M.PARAM_MIDI_NOTE = 8      -- slider22: MIDI Note
M.PARAM_AUDIO_THRESHOLD = 9 -- slider23: Audio Threshold
M.PARAM_ATTACK = 10        -- slider24: Attack
M.PARAM_RELEASE = 11       -- slider25: Release

-- Editor section (sliders 26-27) - come BEFORE slider28 by number!
M.PARAM_GRID = 12          -- slider26: Grid
M.PARAM_SNAP = 13          -- slider27: Snap

-- LFO Mode section (slider 28) - comes AFTER sliders 26-27 by number!
M.PARAM_LFO_MODE = 14      -- slider28: Loop/One Shot

-- Curve section
M.PARAM_NUM_POINTS = 15    -- slider30: Number of points
M.PARAM_POINT_START = 16   -- slider40+: First curve point (X1)

return M
