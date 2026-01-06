# Gain Staging Feature Plan

## Overview
Add visual gain staging to SideFX by reading output levels from SideFX Utility plugins in the chain and displaying them as compact meters.

## Current Capabilities

### SideFX Utility JSFX
The utility plugin already has level metering built-in:
- **slider5**: Output Level (0-1 range, hidden parameter)
- Calculated as: `max(abs(spl0), abs(spl1))`
- Smoothed with: `slider5 = slider5 * 0.95 + level * 0.05`
- Updates every sample

This means we can already read signal levels from any utility in the chain!

## Proposed Feature

### Visual Design
Add compact level meters to each device in the chain that has a utility plugin:

```
┌─────────────────────────┐
│  Device Name        [●] │  ← Header with gain indicator
│  ┌─────────┐            │
│  │ Param 1 │            │
│  └─────────┘            │
│                         │
│  Output: ████▌░░ -6dB   │  ← Level meter (optional expanded view)
└─────────────────────────┘
```

### Compact Mode (Default)
- **Gain dot indicator** in device header
  - 🟢 Green: -12dB to -6dB (optimal range)
  - 🟡 Yellow: -6dB to -3dB (getting hot)
  - 🔴 Red: -3dB to 0dB (clipping risk)
  - ⚫ Gray: Below -24dB (too quiet)

### Expanded Mode (Optional)
- Small horizontal meter bar below device header
- dB readout next to meter
- Peak hold indicator
- Color-coded segments:
  - Green: -∞ to -12dB
  - Yellow: -12dB to -6dB
  - Orange: -6dB to -3dB
  - Red: -3dB to 0dB

## Implementation Steps

### Phase 1: Data Collection
**File**: `lib/ui/device_panel.lua`

1. **Detect utility plugins** in device container
   ```lua
   function get_device_utility(container)
       for child in container:iter_container_children() do
           if fx_utils.is_utility_fx(child) then
               return child
           end
       end
       return nil
   end
   ```

2. **Read output level** from slider5
   ```lua
   local ok, level_norm = pcall(function()
       return utility_fx:get_param_normalized(4)  -- slider5 (0-indexed)
   end)
   if ok then
       -- level_norm is 0-1, representing linear amplitude
       local level_db = 20 * math.log10(level_norm + 0.00001)  -- Avoid log(0)
       return level_db
   end
   ```

3. **Cache levels** in state
   ```lua
   state.device_levels = state.device_levels or {}
   state.device_levels[device_guid] = {
       level_db = level_db,
       peak_db = math.max(peak_db, level_db),
       timestamp = os.clock()
   }
   ```

### Phase 2: Visual Indicators

#### Option A: Header Dot (Minimal)
**Location**: Device panel header (next to device name)

```lua
-- In device header rendering
local level_db = state.device_levels[guid] and state.device_levels[guid].level_db or -96

-- Color coding
local dot_color
if level_db > -3 then
    dot_color = 0xFF3333FF  -- Red
elseif level_db > -6 then
    dot_color = 0xFFAA33FF  -- Orange
elseif level_db > -12 then
    dot_color = 0xFFFF33FF  -- Yellow
elseif level_db > -24 then
    dot_color = 0x33FF33FF  -- Green
else
    dot_color = 0x666666FF  -- Gray (too quiet)
end

-- Draw indicator dot
ctx:push_style_color(imgui.Col.Text(), dot_color)
ctx:text("●")
ctx:pop_style_color()

-- Tooltip with exact level
if ctx:is_item_hovered() then
    ctx:set_tooltip(string.format("Output: %.1f dB", level_db))
end
```

#### Option B: Compact Meter Bar
**Location**: Below device header, above parameters

```lua
-- Draw meter bar (100px wide, 4px tall)
local meter_width = 100
local meter_height = 4
local fill_width = math.min(meter_width, (level_db + 60) / 60 * meter_width)  -- -60dB to 0dB range

-- Background
ctx:push_style_color(imgui.Col.FrameBg(), 0x333333FF)
ctx:dummy(meter_width, meter_height)
ctx:pop_style_color()

-- Fill with gradient (green -> yellow -> red)
local fill_color
if level_db > -6 then
    fill_color = 0xFF3333FF  -- Red
elseif level_db > -12 then
    fill_color = 0xFFAA33FF  -- Orange
else
    fill_color = 0x33FF33FF  -- Green
end

-- Draw fill
ctx:push_style_color(imgui.Col.PlotHistogram(), fill_color)
ctx:progress_bar(fill_width / meter_width, meter_width, meter_height, "")
ctx:pop_style_color()

-- dB readout
ctx:same_line()
ctx:text(string.format("%.1f dB", level_db))
```

### Phase 3: Chain Overview
**File**: `SideFX.lua` (main chain view)

Add a "Gain Staging" mode toggle in toolbar:
- When enabled, show compact meters above each device in chain
- Highlight devices with problematic levels (too hot or too quiet)
- Show suggested adjustments

```
[Device1] [Device2] [Device3] [Device4]
   -6dB     +2dB⚠     -12dB     -18dB
   🟢       🔴        🟢        ⚫
```

## Advanced Features (Future)

### 1. Auto Gain Staging
```lua
function auto_gain_stage(chain)
    -- Analyze all utility levels in chain
    -- Suggest gain adjustments to keep each stage at -12dB (headroom)
    -- User can accept/reject suggestions
end
```

### 2. Gain History Graph
- Show gain over time for selected device
- Identify transient peaks vs sustained levels
- Help diagnose problematic gain spikes

### 3. Target Level Setting
- User configurable target level (default: -12dB)
- Color coding adjusts based on target
- Per-device or global setting

### 4. Peak Hold with Reset
- Hold peak level for X seconds
- Visual peak indicator (thin line)
- Right-click to reset peak

## Configuration

Add to `lib/ui/device_panel.lua` config:

```lua
-- Gain staging
gain_staging_enabled = true,        -- Show gain indicators
gain_meter_mode = "dot",            -- "dot", "bar", or "none"
gain_target_db = -12,               -- Target level for optimal gain
gain_warning_threshold_db = -3,    -- Show warning above this
gain_quiet_threshold_db = -24,     -- Show warning below this
gain_update_rate_ms = 50,          -- Update frequency (20Hz)
```

## Technical Considerations

### Performance
- Reading parameters is fast (pcall overhead minimal)
- Only read utility level, not all parameters
- Cache levels, update at 20Hz max (every 3 frames at 60fps)
- Skip hidden/collapsed devices

### Accuracy
- `slider5` uses peak detection: `max(abs(spl0), abs(spl1))`
- Smoothed with 0.95 coefficient (fast response, minimal lag)
- True peak, not RMS (more conservative for clipping detection)
- Updates per-sample (accurate for transients)

### Compatibility
- Only works with SideFX Utility plugins
- Devices without utility show no indicator (or gray)
- Non-utility devices can't be monitored (limitation)
- Could add utility auto-insertion: "Add Utility for Gain Staging"

## Benefits

1. **Visual feedback**: Instantly see if any stage is clipping or too quiet
2. **Mix confidence**: Know your levels are optimal throughout the chain
3. **Problem diagnosis**: Quickly identify which device is causing clipping
4. **Workflow**: No need to open each device to check levels
5. **Education**: Users learn proper gain staging by seeing levels

## Limitations

1. **Utility required**: Devices must have SideFX Utility to be monitored
2. **No input metering**: Only monitors output of utility (not device itself)
3. **Stereo only**: Shows max(L, R), not separate channels
4. **No frequency analysis**: Just overall level, not per-band

## Future Enhancements

- **Spectrum analyzer**: Mini FFT view for frequency balance
- **Stereo correlation**: Show L/R balance and phase issues
- **LUFS metering**: Integrate loudness measurement (more complex)
- **Compare mode**: Show before/after levels when adjusting
- **Automation recording**: Record gain adjustments as automation

## Files to Modify

1. **lib/ui/device_panel.lua**
   - Add `get_device_utility()` function
   - Add `read_output_level()` function
   - Add gain indicator rendering in header
   - Add optional meter bar below header

2. **lib/fx_utils.lua**
   - Add `is_utility_fx()` helper (if not exists)
   - Add `get_utility_level()` wrapper

3. **lib/state.lua**
   - Add `device_levels` table to state
   - Add peak hold tracking
   - Add level history (optional)

4. **SideFX.lua**
   - Add "Gain Staging" toolbar toggle
   - Add chain overview meters (when enabled)
   - Add auto-gain-staging modal (future)

## Testing Checklist

- [ ] Correctly detects SideFX Utility in device container
- [ ] Reads slider5 (output level) without errors
- [ ] Converts linear amplitude to dB correctly
- [ ] Color coding matches dB thresholds
- [ ] Tooltip shows exact dB value
- [ ] Updates smoothly (no flickering)
- [ ] Performance: No lag with 10+ devices
- [ ] Works with nested racks
- [ ] Handles missing utility gracefully (no errors)
- [ ] Peak hold resets correctly
- [ ] State persists across window close/open

## Priority
**Medium-High** - Very useful for mixing workflow, requires minimal changes to existing code

## Estimated Effort
- Phase 1 (Data Collection): ~2 hours
- Phase 2 (Visual Indicators): ~3 hours
- Phase 3 (Chain Overview): ~2 hours
- Testing & Polish: ~2 hours
- **Total: ~9 hours**

---

## Example Usage Flow

1. User builds FX chain with utilities between devices
2. SideFX automatically shows gain dots in device headers
3. User notices red dot on "Compressor" device
4. Clicks to expand, sees +2dB output
5. Adjusts utility gain to -10dB post-compression
6. Dot turns green, indicates healthy level
7. Next device receives optimal input level

This creates a visual gain staging workflow without leaving SideFX!
