# Integration Tests for Bake Modulation

Comprehensive integration tests for the "Bake LFO to Automation" feature.

## Test Files

| File | Description |
|------|-------------|
| `bake_integration_tests.lua` | Main test runner with all test cases |
| `test_helpers.lua` | Utility functions for envelope reading and assertions |
| `bake_test_project.rpp` | Pre-configured REAPER test project (you create this) |

## Quick Start

### 1. Create the Test Project

Open REAPER and create a new project with the following setup:

**Project Settings:**
- Tempo: **120 BPM**
- Time signature: **4/4**

---

### Track 1: Continuous Unipolar

**Purpose:** Test basic unipolar modulation with Transport trigger

**Setup:**
1. Add **ReaSynth** (built-in REAPER synth)
2. Add **SideFX_Modulator** after ReaSynth
3. Create parameter link: Modulator → ReaSynth param 0 (Volume)

**Modulator Settings:**
- Waveform: Ramp Up (or any)
- Mode: **Unipolar** (offset = 0)
- Depth: **50%**
- Baseline: **50%**
- Rate: **Sync 1 bar**
- Trigger: **Transport**

**Expected after bake:**
- Value range: 0.5 to 1.0
- Duration: 8 seconds (4 bars at 120 BPM)

---

### Track 2: Continuous Bipolar

**Purpose:** Test bipolar modulation (full range centered on baseline)

**Setup:**
1. Add **ReaSynth**
2. Add **SideFX_Modulator**
3. Create parameter link to param 0

**Modulator Settings:**
- Waveform: Sine
- Mode: **Bipolar** (offset = -0.5)
- Depth: **100%**
- Baseline: **50%**
- Rate: **Sync 1 bar**
- Trigger: **Transport**

**Expected after bake:**
- Value range: 0.0 to 1.0

---

### Track 3: MIDI Trigger - Fast Rate

**Purpose:** Test MIDI trigger with fast rate (multiple cycles per note)

**Setup:**
1. Create a **MIDI item** (4-8 bars) with varied note lengths:
   - Some quarter notes (0.5s at 120 BPM)
   - Some half notes (1s)
   - Some whole notes (2s)
   - Include gaps between some notes
2. Add **ReaSynth**
3. Add **SideFX_Modulator**
4. Create parameter link to param 0

**Modulator Settings:**
- Waveform: Sine or Ramp
- Mode: **Unipolar**
- Depth: **50%**
- Baseline: **50%**
- Rate: **Free 4 Hz** (0.25s per cycle)
- Trigger: **MIDI**

**Expected after bake:**
- Phase resets at each note
- Quarter note (0.5s) → 2 cycles
- Half note (1s) → 4 cycles
- Whole note (2s) → 8 cycles
- No automation in gaps between notes

---

### Track 4: MIDI Trigger - Slow Rate

**Purpose:** Test MIDI trigger with slow rate (fewer cycles per note)

**Setup:**
1. Create a **MIDI item** with long notes:
   - Whole notes (2s at 120 BPM)
   - 2-bar notes (4s)
2. Add **ReaSynth**
3. Add **SideFX_Modulator**
4. Create parameter link to param 0

**Modulator Settings:**
- Waveform: Sine
- Mode: **Unipolar**
- Depth: **50%**
- Baseline: **50%**
- Rate: **Free 1 Hz** (1s per cycle)
- Trigger: **MIDI**

**Expected after bake:**
- Whole note (2s) → 2 cycles
- 2-bar note (4s) → 4 cycles

---

### Track 5: MIDI Trigger - Sync Rate

**Purpose:** Test MIDI trigger with tempo-synced rate

**Setup:**
1. Create a **MIDI item** with varied notes
2. Add **ReaSynth**
3. Add **SideFX_Modulator**
4. Create parameter link to param 0

**Modulator Settings:**
- Waveform: Ramp
- Mode: **Unipolar**
- Depth: **50%**
- Baseline: **50%**
- Rate: **Sync 1/8** (0.25s per cycle at 120 BPM)
- Trigger: **MIDI**

**Expected after bake:**
- Same as Track 3 (1/8 at 120 BPM = 0.25s = 4 Hz)

---

### Track 6: MIDI Trigger - Short Notes

**Purpose:** Test partial cycles (notes shorter than one LFO cycle)

**Setup:**
1. Create a **MIDI item** with very short notes:
   - 16th notes (0.125s at 120 BPM)
   - 32nd notes (0.0625s)
2. Add **ReaSynth**
3. Add **SideFX_Modulator**
4. Create parameter link to param 0

**Modulator Settings:**
- Rate: **Free 1 Hz** (1s per cycle - much longer than notes)
- Trigger: **MIDI**

**Expected after bake:**
- Each short note produces partial automation
- Phase resets at each note
- Value doesn't complete full range (partial cycle)

---

### Track 7: MIDI Trigger - Long Notes

**Purpose:** Test many cycles within single notes

**Setup:**
1. Create a **MIDI item** with very long notes:
   - 4-bar notes (8s at 120 BPM)
   - 8-bar notes (16s)
2. Add **ReaSynth**
3. Add **SideFX_Modulator**
4. Create parameter link to param 0

**Modulator Settings:**
- Rate: **Free 1 Hz**
- Trigger: **MIDI**

**Expected after bake:**
- 4-bar note → 8 cycles
- 8-bar note → 16 cycles

---

### Track 8: MIDI Trigger - Notes with Gaps

**Purpose:** Verify no automation in gaps between notes

**Setup:**
1. Create a **MIDI item** with notes and significant gaps:
   - Note → 1 beat gap → Note → 2 beat gap → Note
   - Gaps should be at least 0.5s
2. Add **ReaSynth**
3. Add **SideFX_Modulator**
4. Create parameter link to param 0

**Modulator Settings:**
- Rate: **Free 4 Hz**
- Trigger: **MIDI**

**Expected after bake:**
- Automation only during notes
- No automation points in gap regions
- Phase resets at each note start

---

## 2. Bake the Automation

For each track:
1. Select the track
2. Open SideFX UI
3. Click "Bake All" in the modulator panel
4. Verify automation envelope appears

---

## 3. Run the Tests

1. Open `bake_test_project.rpp` in REAPER
2. Load `bake_integration_tests.lua` as a ReaScript action:
   - Actions → Show action list
   - New action → Load ReaScript
   - Select `bake_integration_tests.lua`
3. Run the action
4. Check REAPER console (View → Show Console) for results

---

## Test Categories

### Formula Tests (No Project Required)
These tests verify the math works correctly:
- **Formula Unipolar**: `baseline + lfo * scale`
- **Formula Bipolar**: `baseline + (lfo - 0.5) * scale`
- **Formula Negative Scale**: Inverted modulation
- **Formula Clamping**: Values stay within 0-1

### Continuous Mode Tests
- **Continuous Unipolar Range**: Value range 0.5 to 1.0
- **Continuous Bipolar Range**: Value range 0.0 to 1.0
- **Continuous Timing**: Duration matches 4 bars

### MIDI Trigger Tests - Core
- **MIDI Automation During Notes**: Automation only during notes
- **MIDI Phase Reset**: Phase resets at each note start
- **MIDI Fast Rate Cycles**: Correct cycle count at 4 Hz
- **MIDI Slow Rate Cycles**: Correct cycle count at 1 Hz
- **MIDI Sync Rate**: Tempo-synced rate works

### MIDI Trigger Tests - Edge Cases
- **MIDI Short Notes**: Partial cycles for short notes
- **MIDI Long Notes**: Many cycles for long notes
- **MIDI Gaps Between Notes**: Segments align with notes
- **MIDI No Points In Gaps**: No stray points in gaps

### MIDI Trigger Tests - Value Ranges
- **MIDI Unipolar Range**: Correct value range per note

---

## Running Specific Test Groups

You can run specific test groups by modifying the script or calling:

```lua
-- In REAPER console:
local tests = require('tests.integration.bake_integration_tests')

-- Run only formula tests (no project needed)
tests.run_formula_tests()

-- Run only continuous mode tests
tests.run_continuous_tests()

-- Run only MIDI trigger tests
tests.run_midi_tests()

-- Run all tests
tests.run_all_tests()
```

---

## Expected Results Summary

At 120 BPM with default settings:

| Test | Expected |
|------|----------|
| Unipolar Range | 0.5 - 1.0 |
| Bipolar Range | 0.0 - 1.0 |
| 4 Bar Duration | 8.0 seconds |
| Fast Rate (4 Hz) | 4 cycles/second |
| Slow Rate (1 Hz) | 1 cycle/second |
| Sync 1/8 Rate | 4 cycles/second (at 120 BPM) |

---

## Troubleshooting

### "Track not found"
- Ensure test project has all 8 tracks
- Track order must match configuration

### "ReaSynth not found"
- Add ReaSynth to the specified track
- Any synth with automatable parameters works

### "No envelope (run bake first)"
- Use SideFX to bake the modulation before running tests
- Check that parameter link exists

### "No MIDI notes found"
- Create MIDI items on the track
- Notes must be within the first 20 seconds

### Phase reset test fails
- Ensure modulator is set to MIDI trigger mode
- Check that notes have gaps between them (not legato)

---

## Adding New Tests

1. Add test function to `bake_integration_tests.lua`:
```lua
function M.test_my_new_test()
    local track, points, err = get_test_envelope(TRACKS.MY_TRACK)
    if err then
        return helpers.make_result("My Test", false, err)
    end

    -- Your test logic here...

    return helpers.make_result("My Test", true, "Description of what passed")
end
```

2. Add track constant if needed:
```lua
local TRACKS = {
    -- ... existing tracks ...
    MY_TRACK = 9,
}
```

3. Register in the appropriate test group in `run_all_tests()`

4. Update this README with track setup instructions
