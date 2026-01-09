# Auto Gain Staging Feature Plan

## Overview
Automatically analyze and adjust gain levels throughout the FX chain to maintain optimal signal levels at each stage. Uses SideFX Utility plugins to both measure output levels and apply corrective gain.

## Core Concept

### The Problem
When building FX chains, each effect can change the output level:
- Compressors often boost output (+3 to +10dB)
- EQs can add/remove energy
- Saturators increase levels
- Result: Cascading gain issues, clipping, or loss of headroom

### The Solution
**Auto Gain Staging** function that:
1. Measures output level at each stage (utility slider5)
2. Calculates required gain adjustment to hit target level
3. Applies adjustment to utility gain parameter (slider1)
4. Runs iteratively until all stages are at target

## SideFX Utility Parameters

### Input Parameters
- **slider1**: Gain (dB) - Range: -24dB to +24dB
- **slider2**: Pan (%)
- **slider3**: Phase Invert L
- **slider4**: Phase Invert R

### Output Measurement
- **slider5**: Output Level - Range: 0-1 (linear amplitude)
  - Calculated: `max(abs(spl0), abs(spl1))`
  - Smoothed: `slider5 = slider5 * 0.95 + level * 0.05`
  - Updates per-sample (real-time)

## Algorithm

### Step 1: Scan Chain for Utilities
```lua
function get_chain_utilities(container)
    local utilities = {}

    for child in container:iter_container_children() do
        local is_util = fx_utils.is_utility_fx(child)
        local is_mod = fx_utils.is_modulator_fx(child)

        if is_util and not is_mod then
            table.insert(utilities, {
                fx = child,
                guid = child:get_guid(),
                current_gain_db = child:get_param_normalized(0) * 48 - 24,  -- slider1 to dB
                output_level = 0,
                target_adjustment_db = 0
            })
        end
    end

    return utilities
end
```

### Step 2: Measure Output Levels
```lua
function measure_utility_levels(utilities)
    for _, util in ipairs(utilities) do
        local ok, level_norm = pcall(function()
            return util.fx:get_param_normalized(4)  -- slider5
        end)

        if ok and level_norm > 0 then
            -- Convert linear amplitude to dB
            util.output_level = 20 * math.log10(level_norm)
        else
            util.output_level = -96  -- Silent
        end
    end
end
```

### Step 3: Calculate Required Adjustments
```lua
function calculate_adjustments(utilities, target_db)
    -- target_db: desired output level (e.g., -12dB for 12dB headroom)

    for _, util in ipairs(utilities) do
        -- How much do we need to adjust to hit target?
        local level_error = util.output_level - target_db

        -- Adjustment needed (invert because we want to compensate)
        util.target_adjustment_db = -level_error

        -- New gain = current gain + adjustment
        local new_gain_db = util.current_gain_db + util.target_adjustment_db

        -- Clamp to slider1 range (-24 to +24 dB)
        new_gain_db = math.max(-24, math.min(24, new_gain_db))

        util.new_gain_db = new_gain_db
    end
end
```

### Step 4: Apply Adjustments
```lua
function apply_gain_adjustments(utilities)
    for _, util in ipairs(utilities) do
        -- Convert dB to normalized parameter value (0-1)
        -- slider1: -24dB to +24dB maps to 0-1
        local gain_norm = (util.new_gain_db + 24) / 48

        local ok = pcall(function()
            util.fx:set_param_normalized(0, gain_norm)
        end)

        if ok then
            print(string.format(
                "Adjusted utility gain: %.1f dB → %.1f dB (output was %.1f dB)",
                util.current_gain_db,
                util.new_gain_db,
                util.output_level
            ))
        end
    end
end
```

### Step 5: Main Function
```lua
function auto_gain_stage(container, opts)
    opts = opts or {}
    local target_db = opts.target_db or -12  -- Default: -12dB (12dB headroom)
    local max_iterations = opts.max_iterations or 3
    local tolerance_db = opts.tolerance_db or 1  -- ±1dB is acceptable

    -- Ensure playback is active for accurate measurement
    if not (reaper.GetPlayState() & 1) then
        reaper.ShowMessageBox(
            "Please start playback before running auto gain staging.\nSignal must be present for accurate measurement.",
            "Auto Gain Staging", 0
        )
        return false
    end

    for iteration = 1, max_iterations do
        -- Wait for measurement to stabilize
        wait_ms(200)  -- Let smoothing settle

        -- Get all utilities in chain
        local utilities = get_chain_utilities(container)

        if #utilities == 0 then
            reaper.ShowMessageBox(
                "No SideFX Utility plugins found in chain.\nAdd utilities between devices to enable gain staging.",
                "Auto Gain Staging", 0
            )
            return false
        end

        -- Measure current levels
        measure_utility_levels(utilities)

        -- Check if we're within tolerance
        local all_within_tolerance = true
        for _, util in ipairs(utilities) do
            local error = math.abs(util.output_level - target_db)
            if error > tolerance_db then
                all_within_tolerance = false
                break
            end
        end

        if all_within_tolerance then
            print(string.format("Auto gain staging complete in %d iteration(s)", iteration))
            return true
        end

        -- Calculate and apply adjustments
        calculate_adjustments(utilities, target_db)
        apply_gain_adjustments(utilities)

        print(string.format("Iteration %d/%d complete", iteration, max_iterations))
    end

    print("Auto gain staging complete (max iterations reached)")
    return true
end
```

## UI Integration

### ✅ SELECTED: Option A - Toolbar Button
Add to main toolbar (global, works on entire visible chain):
```
[Refresh] [+ Rack] | Track Name > ... | [💾] [⚙️] [⚡]
                                                   └─ Gain Stage button
```

**Rationale:**
- Most visible and discoverable location
- Works on entire track/chain (most common use case)
- Consistent with other global actions (Refresh, Add Rack)
- Easy to access during mixing workflow

**Behavior:**
1. Click "⚡" button in toolbar
2. Opens "Auto Gain Stage" modal dialog
3. Shows target level, tolerance, current utility levels
4. User confirms → applies adjustments
5. Creates undo point

---

### Future: Additional Entry Points

#### Chain Context Menu (v1.1)
Add to chain header right-click menu for per-chain staging:
```
┌─────────────────────────────┐
│ Chain 1                     │
│ ┌─────────────────────────┐ │
│ │ Rename Chain            │ │
│ │ Delete Chain            │ │
│ │ ─────────────────       │ │
│ │ Auto Gain Stage...   ⚡ │ │ ← Per-chain option
│ └─────────────────────────┘ │
└─────────────────────────────┘
```

#### Device Panel Action (v1.2)
Add button to device panel when utility is present:
```
┌─────────────────────────┐
│  SideFX Utility     [⚡] │ ← Gain stage button
│  ┌─────────┐            │
│  │ Gain    │ +3dB       │
│  └─────────┘            │
└─────────────────────────┘
```

## Auto Gain Stage Dialog

When user triggers function, show modal:

```
╔═══════════════════════════════════════════╗
║  Auto Gain Stage                          ║
╠═══════════════════════════════════════════╣
║                                           ║
║  Target Level:  [-12] dB                  ║
║                 ▲ Recommended for headroom║
║                                           ║
║  Tolerance:     [±1] dB                   ║
║                                           ║
║  Max Iterations: [3]                      ║
║                                           ║
║  ⚠ Playback must be active               ║
║     Signal present for measurement        ║
║                                           ║
║  Found 4 utilities in chain:              ║
║  • Device 1 Output: -6.2 dB               ║
║  • Device 2 Output: +2.4 dB ⚠             ║
║  • Device 3 Output: -11.8 dB              ║
║  • Device 4 Output: -9.1 dB               ║
║                                           ║
║           [Cancel]  [Apply]               ║
╚═══════════════════════════════════════════╝
```

## Advanced Options

### Per-Stage Target Levels
Allow different targets for different stages:
```lua
local stage_targets = {
    [1] = -12,  -- First stage: -12dB
    [2] = -12,  -- Second stage: -12dB
    [3] = -6,   -- Pre-master: -6dB (hotter)
}
```

### Preserve Relative Levels
Option to maintain relative level differences between stages:
```lua
function preserve_relative_levels(utilities, target_db)
    -- Calculate average current level
    local avg_level = 0
    for _, util in ipairs(utilities) do
        avg_level = avg_level + util.output_level
    end
    avg_level = avg_level / #utilities

    -- Apply same offset to all utilities
    local offset = target_db - avg_level

    for _, util in ipairs(utilities) do
        util.target_adjustment_db = offset
    end
end
```

### Safe Mode (Attenuate Only)
Only reduce gain, never boost:
```lua
function safe_gain_stage(utilities, target_db)
    for _, util in ipairs(utilities) do
        if util.output_level > target_db then
            -- Reduce gain to hit target
            util.target_adjustment_db = -(util.output_level - target_db)
        else
            -- Leave quiet stages alone (no boost)
            util.target_adjustment_db = 0
        end
    end
end
```

## Iterative Approach

Why multiple iterations?
1. **Downstream effects**: Adjusting gain at stage 1 affects measurements at stage 2+
2. **Smoothing lag**: slider5 has 0.95 smoothing coefficient
3. **Signal variation**: Dynamic content (music) varies over time

Each iteration:
1. Measure → Adjust → Wait
2. Levels converge toward target
3. Typically converges in 2-3 iterations

## Workflow Example

### Before Auto Gain Staging
```
Input      → EQ        → Compressor → Saturator → Output
-18dB      → -18dB     → -8dB ⚠      → +2dB ⚠⚠   → +2dB ⚠⚠
           Util +0dB   Util +0dB     Util +0dB
```

### After Auto Gain Staging (Target: -12dB)
```
Input      → EQ        → Compressor → Saturator → Output
-18dB      → -18dB     → -8dB        → +2dB      → -12dB ✓
           Util +0dB   Util -4dB ✓   Util -14dB ✓
```

### Result
- EQ utility: No change needed (level already good)
- Compressor utility: Reduced -4dB (compensate for compression gain)
- Saturator utility: Reduced -14dB (compensate for saturation boost)
- Final output: -12dB (optimal for further processing)

## Implementation Files

### 1. Create New Module
**File**: `lib/gain_staging.lua`

```lua
local M = {}

-- Main function (as described above)
function M.auto_gain_stage(container, opts)
    -- Implementation here
end

-- Helper functions
function M.get_chain_utilities(container)
    -- Implementation here
end

function M.measure_utility_levels(utilities)
    -- Implementation here
end

-- ... etc

return M
```

### 2. Add UI in Device Panel
**File**: `lib/ui/device_panel.lua`

Add "⚡ Gain Stage" button to utility device header

### 3. Add Toolbar Action
**File**: `lib/ui/toolbar.lua`

Add "Auto Gain Stage" button to main toolbar

### 4. Add Chain Menu Item
**File**: `lib/ui/rack_ui.lua` or `SideFX.lua`

Add context menu item for chains

## Safety Considerations

### 1. Playback Required
- Must have signal flowing for accurate measurement
- Check `reaper.GetPlayState()` before running
- Show clear warning if stopped

### 2. Undo Point
```lua
reaper.Undo_BeginBlock()
-- Apply all gain adjustments
reaper.Undo_EndBlock("Auto Gain Stage", -1)
```

### 3. Gain Limits
- Clamp to slider1 range (-24dB to +24dB)
- Warn if adjustment exceeds range
- Suggest manual adjustment if needed

### 4. Zero-Signal Detection
```lua
if util.output_level < -90 then
    print("Warning: No signal detected at utility " .. util.guid)
    -- Skip or use nominal adjustment
end
```

### 5. User Confirmation
Show preview of adjustments before applying:
```
Proposed Adjustments:
  • Utility 1: +0.0 dB (no change)
  • Utility 2: -4.2 dB
  • Utility 3: -14.8 dB

Apply these adjustments? [Yes] [No]
```

## Configuration

Add to settings:
```lua
gain_staging = {
    default_target_db = -12,
    default_tolerance_db = 1,
    default_max_iterations = 3,
    require_playback = true,
    safe_mode = false,  -- Only attenuate, never boost
    preserve_relative = false,  -- Maintain level relationships
}
```

## Testing Checklist

- [ ] Correctly identifies all utilities in chain
- [ ] Measures output levels accurately (compare to REAPER meter)
- [ ] Calculates correct gain adjustments
- [ ] Applies adjustments to slider1
- [ ] Converges to target within tolerance
- [ ] Handles zero-signal gracefully
- [ ] Respects gain limits (-24 to +24 dB)
- [ ] Creates undo point
- [ ] Shows clear warnings/errors
- [ ] Works with nested racks
- [ ] Handles missing utilities
- [ ] Preserves other utility settings (pan, phase)

## Future Enhancements

### 1. RMS vs Peak
Add option to use RMS instead of peak for target matching

### 2. Frequency-Weighted Staging
Use different targets for different frequency ranges

### 3. Headroom Reservation
Target different levels for different device types:
- Compressors: -12dB (need headroom)
- Limiters: -3dB (expect hot signal)
- Effects: -18dB (prefer conservative)

### 4. Visual Preview
Show before/after gain structure with animated graph

### 5. Batch Staging
Apply to all chains in track at once

### 6. Learn Mode
Remember typical adjustments needed for specific effect combos

## Limitations

1. **Requires utilities**: Can only measure/adjust stages with SideFX Utility
2. **Dynamic content**: Measurements vary with signal content
3. **Latency**: Some plugins have latency that affects measurement
4. **Sidechain**: Doesn't account for sidechain inputs
5. **Stereo only**: No M/S or multi-channel support

## Benefits

1. **One-click optimization**: No manual gain adjustment needed
2. **Consistent workflow**: Same target level throughout chain
3. **Prevent clipping**: Automatically create headroom
4. **Save time**: No trial-and-error gain tweaking
5. **Learn proper levels**: See what adjustments are needed
6. **Iterative improvement**: Converges to optimal levels

## Priority
**High** - Core mixing feature, unique value proposition for SideFX

## Estimated Effort
- Core algorithm: ~4 hours
- UI integration (dialog): ~3 hours
- Toolbar/menu integration: ~2 hours
- Testing & polish: ~3 hours
- Documentation: ~1 hour
- **Total: ~13 hours**

---

## Key Innovation

This is an **active gain staging system** that doesn't just show levels—it fixes them automatically. Similar to auto-gain in modern DAWs, but applied per-stage in the FX chain rather than just at the track level.

The utility plugins act as both **sensors** (slider5 measures output) and **actuators** (slider1 adjusts gain), creating a closed-loop control system for optimal gain structure.
