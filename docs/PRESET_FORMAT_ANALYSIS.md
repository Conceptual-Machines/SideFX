# SideFX Modulator Preset Format Analysis

This document describes the correct JSFX preset format discovered through empirical testing and analysis of REAPER-saved presets.

## Key Discovery: Name Position at 64

**CRITICAL**: The preset name must be inserted at **position 64** (after slider64/P13X, before slider65/P13Y), NOT at the end of the data.

This was discovered by:
1. Saving a preset from REAPER's native UI
2. Analyzing the hex-encoded data in the .ini file
3. Observing that the quoted preset name appears at position 64

Without this, presets with more than 12 points will have points 13-16 shifted by one position.

## Format Overview

The preset uses **slider NUMBER positions** (not definition order) with dashes (`-`) for unused slider positions.

```
position 1-6:   slider1-6 values (Rate section)
position 7-19:  dashes (sliders don't exist)
position 20-25: slider20-25 values (Trigger section)
position 26-29: slider26-29 values (Grid, Snap, LFO Mode, Curve Shape)
position 30:    slider30 value (Num Points)
position 31-39: dashes (sliders don't exist)
position 40-63: slider40-63 values (P1X through P12Y, then P13X)
position 64:    "PresetName" (QUOTED, inserted here!)
position 65-71: slider65-71 values (P13Y through P16Y)
position 72-86: slider72-86 values or dashes (Segment curves)
```

## Why Position 64?

REAPER embeds the preset name at position 64, which falls between:
- Position 63 = slider64 = P13X (last value before name)
- Position 65 = slider65 = P13Y (first value after name)

This is NOT at the end of the data stream. The name interrupts the slider values.

## Correct Python Implementation

```python
def create_preset(name, num_points, points):
    values = ["-"] * 86

    # Position 1-6: slider1-6
    values[0:6] = ["0", "1", "5", "0", "0", "1"]

    # Position 20-25: slider20-25
    values[19:25] = ["0", "0", "0", "0.5", "100", "500"]

    # Position 26-29: slider26-29
    values[25:29] = ["2", "1", "0", "0"]

    # Position 30: slider30 (num points)
    values[29] = str(num_points)

    # Position 40-71: slider40-71 (point data)
    for i in range(16):
        values[39 + i*2] = str(points[i][0])      # X
        values[39 + i*2 + 1] = str(points[i][1])  # Y

    # INSERT NAME AT POSITION 64 (critical!)
    values.insert(64, f'"{name}"')

    # Encode
    full = " ".join(values)
    return base64.b64encode(full.encode()).decode()
```

## Common Mistakes (That Break Presets)

### 1. Putting name at end
```python
# WRONG - breaks presets with >12 points
full = " ".join(values) + " " + name
```

### 2. Using definition order without dashes
```python
# WRONG - produces single point, straight line
values = [v1, v2, v3, ..., v67, name]  # No dashes, 67 values
```

### 3. Forgetting the quotes around name
```python
# WRONG - name must be quoted
values.insert(64, name)  # Should be f'"{name}"'
```

## REAPER's Two Preset Formats

REAPER uses different formats for different storage:

### .rpl files (preset libraries)
- Base64-encoded
- Used by `<REAPER_PRESET_LIBRARY>` tags
- What we generate with the Python script

### .ini files (user presets)
- Hex-encoded
- Stored in `presets/js-*.ini` files
- Created when user saves via REAPER UI

Both formats use the same underlying structure with name at position 64.

## Slider Layout Reference

| Position | Slider | Description |
|----------|--------|-------------|
| 1-6 | slider1-6 | Tempo, Rate, Sync, Output, Phase, Depth |
| 7-19 | - | (unused) |
| 20-25 | slider20-25 | Trigger Mode, MIDI Source/Note, Threshold, Attack, Release |
| 26-27 | slider26-27 | Grid, Snap |
| 28-29 | slider28-29 | LFO Mode, Curve Shape |
| 30 | slider30 | Num Points |
| 31-39 | - | (unused) |
| 40-71 | slider40-71 | Point data (16 × X,Y pairs) |
| **64** | - | **PRESET NAME INSERTED HERE** |
| 72-86 | slider72-86 | Segment curves (15 values) |

## Value Encoding

- Most values stored as raw values (not normalized)
- Segment curves use raw -1 to +1 range
- Point coordinates use 0 to 1 range
- Dashes (`-`) mean "use default value"

## Segment Curve Behavior

**Important**: Curve values are relative to the segment direction, not absolute.

A positive curve value (~0.8) bulges "outward" from the straight line, but the visual
result depends on whether the segment goes UP or DOWN:

- **Upward segment** (y increases): positive curve appears as "inward" bulge visually
- **Downward segment** (y decreases): positive curve appears as "outward" bulge visually

Example - Shark_Fin preset:
- Segment 1: (0,0) → (0.2,1) going UP, curve=0.82 → appears inward
- Segment 2: (0.2,1) → (1,0) going DOWN, curve=0.80 → appears outward

When designing presets, test empirically and use the actual values from REAPER's UI
rather than trying to calculate them mathematically.
