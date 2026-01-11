# Bake LFO to Automation - Status

## What's Working

### Core Bake Functionality (`lib/modulator/modulator_bake.lua`)
- Unipolar mode (offset=0): `baseline + lfo * scale`
- Bipolar mode (offset=-0.5): `baseline + (lfo - 0.5) * scale`
- Free/Transport trigger modes: continuous cycles based on modulator rate
- Sync and Free rate modes
- Phase offset support
- "Disable link after bake" option
- Default: bake 4 bars from project start

### MIDI Trigger Mode
- Detects MIDI trigger mode from modulator (`PARAM_TRIGGER_MODE = 6`)
- Reads MIDI notes from track including looped items
- Phase resets at each note trigger
- Automation length = note duration
- Cycle frequency determined by modulator rate (not stretched to note)
- Partial cycles at note end are included (if > 1% of cycle)
- Monophonic filter: skips overlapping notes (polyphony not supported)

### UI (`lib/ui/device/modulator_sidebar.lua`)
- "Disable link after bake" checkbox
- "Bake All" button in linked parameters section

### Integration Test Framework (`tests/integration/`)
- `test_helpers.lua` - envelope reading, value comparison, assertions
- `bake_integration_tests.lua` - test runner with formula tests
- `README.md` - test project setup instructions

## Still TODO

1. **Audio trigger mode** - not implemented yet (trigger on audio transients)
2. **Different track MIDI/Audio source** - currently only reads MIDI from same track, need to support sidechain sources
3. **Create test REAPER project** (`tests/integration/bake_test_project.rpp`)

## Key Constants

```lua
-- Trigger modes (PARAM_TRIGGER_MODE = 6)
TRIGGER_MODE.FREE = 0      -- continuous
TRIGGER_MODE.TRANSPORT = 1 -- restart on play
TRIGGER_MODE.MIDI = 2      -- restart on MIDI note
TRIGGER_MODE.AUDIO = 3     -- restart on audio transient (TODO)
```

## Formula Reference

```lua
-- REAPER plink formula
target = baseline + (lfo + offset) * scale

-- Unipolar (offset=0): baseline to baseline+scale
-- Bipolar (offset=-0.5): baseline ± scale/2
```

## Files Modified

- `lib/modulator/modulator_bake.lua` - main bake logic, MIDI trigger support
- `lib/ui/device/modulator_sidebar.lua` - bake UI
- `tests/integration/test_helpers.lua` - new file
- `tests/integration/bake_integration_tests.lua` - new file
- `tests/integration/README.md` - new file
