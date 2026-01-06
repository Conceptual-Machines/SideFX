# Modulator Sidebar Refactor Plan

## Overview
Revert from floating modal window back to left sidebar design with:
- Top: 2×4 modulator grid (8 slots)
- Bottom: Modulator controls (when slot selected)

## Why This Design is Better
1. **Single window workflow**: All controls in one place
2. **Easy curve editor access**: Click "UI" button to open JSFX curve editor alongside
3. **No window management**: No floating windows to position
4. **Consistent with DAW conventions**: Modulator controls visible with device

## Current State (What to Change)

### Current Structure
```
Device Panel:
├── Modulator Sidebar (left) - COLLAPSED BY DEFAULT ❌
│   ├── Collapse button
│   ├── Modulator grid (2×4)
│   └── "Click modulator to open controls" message ❌
├── Main Parameters (center)
└── Utility Sidebar (right)

Modulator Controls Window (floating modal) ❌
├── Rate controls (Free/Sync, Hz slider, Sync dropdown)
├── Phase slider
├── Depth slider
├── Trigger mode dropdown
├── LFO mode buttons (Loop/One Shot)
├── Advanced section (MIDI/Audio controls)
└── Parameter Links section
```

### Target Structure
```
Device Panel:
├── Modulator Sidebar (left) - EXPANDED BY DEFAULT ✓
│   ├── Collapse/Expand button
│   ├── Modulator Grid (2×4) - 8 slots
│   │   ├── Each slot: "LFO1", "LFO2", etc. or "+"
│   │   └── Selected slot highlighted
│   └── Modulator Controls (when slot selected) ✓
│       ├── Rate section
│       ├── Phase/Depth sliders
│       ├── Trigger/LFO mode
│       ├── Advanced (collapsible)
│       └── Parameter Links
├── Main Parameters (center)
└── Utility Sidebar (right)
```

## Implementation Steps

### Step 1: Remove Floating Modal Window
**File**: `lib/ui/device_panel.lua`

**Actions**:
- Remove `render_modulator_controls_window()` function (lines ~588-910)
- Remove call to `render_modulator_controls_window()` in device panel (line ~1938)
- Remove `expanded_mod_slot` state tracking for modal (used for window open/close)

**Keep**:
- Grid rendering logic (lines ~1823-1931)
- `get_device_modulators()` helper function
- `add_modulator_to_device()` function

---

### Step 2: Add Inline Controls Below Grid
**File**: `lib/ui/device_panel.lua`

**Location**: After modulator grid rendering (after line ~1931, before `end  -- end expanded sidebar`)

**New Section**: "Modulator Controls" (inline in sidebar)

**Layout**:
```lua
-- After grid rendering, check if a slot is selected
local selected_slot_idx = expanded_mod_slot[state_guid]
if selected_slot_idx and modulators[selected_slot_idx + 1] then
    local selected_modulator = modulators[selected_slot_idx + 1]

    ctx:spacing()
    ctx:separator()
    ctx:spacing()

    -- "Modulator Controls" header
    ctx:push_style_color(imgui.Col.Text(), 0xAAAAAAFF)
    ctx:text("CONTROLS")
    ctx:pop_style_color()
    ctx:separator()

    -- All control sections (Rate, Phase, Depth, etc.)
    -- Use same control rendering code from modal
end
```

---

### Step 3: Update State Management
**File**: `lib/ui/device_panel.lua`

**Changes**:
- Keep `expanded_mod_slot[state_guid]` but use it for highlighting selected grid slot
- Change click behavior: clicking slot toggles selection (highlight), doesn't open modal
- Selected slot shows controls inline below grid

**State Tracking**:
```lua
-- Current: expanded_mod_slot[state_guid] = slot_idx or nil
-- Keep this, but use for inline controls instead of modal
```

---

### Step 4: Adjust Sidebar Width
**File**: `lib/ui/device_panel.lua` - Config section

**Current Width**:
```lua
mod_sidebar_width = 240,  -- Width for modulator 2×4 grid
```

**New Width**: Increase to accommodate controls below grid
```lua
mod_sidebar_width = 280,  -- Width for grid + inline controls
```

**Consider**: May need to be wider (~300-320px) to fit all controls comfortably

---

### Step 5: Default Sidebar to Expanded
**File**: `lib/ui/device_panel.lua`

**Current**: Sidebar collapsed by default
**New**: Sidebar expanded by default so grid is visible

**Change**: Update initialization of sidebar expansion state
```lua
-- Default to expanded instead of collapsed
if sidebar_expanded[state_guid] == nil then
    sidebar_expanded[state_guid] = true  -- Was: false
end
```

---

### Step 6: Vertical Scrolling for Controls
**File**: `lib/ui/device_panel.lua`

**Issue**: Modulator controls may be tall (Rate, Phase, Depth, Trigger, LFO Mode, Advanced, Links)

**Solution**: Wrap controls in scrollable child region if needed
```lua
-- After "CONTROLS" header
local controls_height = available_height - grid_height - 100  -- Reserve space
if ctx:begin_child("modulator_controls_" .. guid, 0, controls_height, false) then
    -- All control rendering here
    ctx:end_child()
end
```

---

### Step 7: Control Section Organization
**Structure in sidebar** (top to bottom):

1. **Grid Section** (fixed height)
   - 2×4 grid of modulator slots
   - ~200px height

2. **Controls Section** (scrollable if needed)
   - Rate (Free/Sync buttons + Hz slider or Sync dropdown)
   - Phase slider (0-360°)
   - Depth slider (0-100%)
   - Trigger mode dropdown
   - LFO mode buttons (Loop/One Shot)
   - Advanced section (collapsible with `>` arrow)
     - MIDI Note, MIDI Channel, Audio Threshold
   - Parameter Links section
     - "Active Links" list
     - "Add Link" controls

**Compact Layout**:
- Use smaller spacing between sections
- Reduce padding
- Use `ctx:spacing()` sparingly
- Consider 2-column layout for some controls (e.g., Phase/Depth side-by-side)

---

### Step 8: Update Selection Highlighting
**File**: `lib/ui/device_panel.lua`

**Grid Slot Highlighting**:
```lua
-- In grid rendering loop
local is_selected = (expanded_mod_slot[state_guid] == slot_idx)
if is_selected then
    -- Highlight selected slot
    ctx:push_style_color(imgui.Col.Button(), 0x5588AAFF)
end
```

**Visual Feedback**:
- Selected slot: Bright highlight (0x5588AAFF)
- Unselected slots: Default color
- Clicking selected slot again: Deselect (hide controls)

---

### Step 9: Control Panel Responsiveness
**Considerations**:

1. **No modulator selected**: Show grid only
2. **Modulator selected**: Show grid + controls below
3. **Sidebar collapsed**: Show only collapse button and thin bar
4. **Curve editor**: User clicks "UI" button on grid slot or in controls to open JSFX window

**UI Button Placement**:
- Option A: Add "UI" button next to each grid slot (small button overlay)
- Option B: Add "UI" button at top of controls section when modulator selected
- **Recommendation**: Option B - cleaner, one button, clear context

---

### Step 10: Testing Checklist
After refactoring:

- [ ] Grid displays modulators correctly (LFO1, LFO2, etc.)
- [ ] Clicking slot selects it and shows controls below
- [ ] Clicking selected slot deselects it and hides controls
- [ ] All control widgets work (sliders, buttons, dropdowns)
- [ ] Parameter changes affect JSFX modulator
- [ ] Parameter links work correctly
- [ ] Sidebar collapse/expand works
- [ ] Scrolling works if controls overflow
- [ ] "UI" button opens JSFX curve editor window
- [ ] Adding/deleting modulators updates grid
- [ ] Multiple devices can have independent modulator selections

---

## UI/UX Improvements to Consider

### Grid Slot Context Menu
Right-click on modulator slot:
- "Open Curve Editor" (opens JSFX window)
- "Rename Modulator" (custom user-friendly name)
- "Delete Modulator"
- "Duplicate Modulator" (future enhancement)

### Grid Slot Visual States
- **Empty**: "+" button
- **Has modulator**: "LFO1", "LFO2", etc.
- **Selected**: Highlighted background
- **Active (modulating)**: Subtle indicator (dot, color change)

### Control Section Header
When modulator selected, show:
```
┌─────────────────────────┐
│ LFO1: SideFX Modulator  │ <- Name with [UI] button
│ ▼ CONTROLS              │ <- Collapsible section
└─────────────────────────┘
```

### Compact Control Layout Ideas
Since sidebar is narrow (~280-300px):

**Rate Section**:
```
[Free][Sync]  <- Full width buttons
[====== Hz slider ======]  OR  [Sync Rate Dropdown▼]
```

**Phase/Depth** (side by side):
```
Phase: [====] 180°
Depth: [====] 50%
```

**Trigger/LFO Mode**:
```
Trigger: [Free    ▼]
Mode: [Loop][One Shot]
```

---

## Code Sections to Reuse

### From Current Modal (to move inline)
**File**: `lib/ui/device_panel.lua` lines ~598-908

**Reusable sections**:
1. Parameter reading (tempo_mode, rate_hz, sync_rate, etc.) - lines 598-605
2. Rate controls (Free/Sync buttons + conditional Hz/Sync controls) - lines 607-667
3. Phase slider - lines 670-687
4. Depth slider - lines 690-706
5. Trigger mode dropdown - lines 709-729
6. LFO Mode buttons - lines 732-770
7. Advanced section (collapsible) - lines 773-818
8. Parameter Links section - lines 821-908

**Adaptation needed**:
- Remove `begin_window()` / `end_window()` wrapper
- Adjust widths to fit sidebar (~260px usable width)
- Keep all parameter logic unchanged

---

## Potential Issues & Solutions

### Issue 1: Sidebar Too Narrow
**Problem**: Controls cramped at 280px width

**Solutions**:
- Increase to 300-320px
- Use even more compact layouts (icons instead of text labels)
- Make some sections collapsible by default

### Issue 2: Controls Too Tall
**Problem**: Controls extend beyond visible area

**Solutions**:
- Add scrolling to controls section (already in plan)
- Make Advanced section collapsed by default
- Reduce spacing between controls
- Consider tabbed interface (Basic/Advanced tabs)

### Issue 3: Grid Slot Selection State
**Problem**: State persists across device switches

**Solutions**:
- Use per-device state key: `expanded_mod_slot[device_guid]`
- Clear selection when switching devices
- Already implemented correctly with `state_guid`

---

## Files to Modify

### Primary Changes
1. **lib/ui/device_panel.lua**
   - Remove modal window function
   - Add inline controls after grid
   - Adjust sidebar width
   - Update selection logic

### Configuration Changes
2. **lib/ui/device_panel.lua** (config section)
   - Update `mod_sidebar_width`
   - Default sidebar expanded

### Testing
3. **tests/integration/test_modulators.lua**
   - Update tests if needed (modal removed)
   - Verify grid + inline controls work

---

## Timeline Estimate

### Phase 1: Remove Modal (~30 min)
- Delete `render_modulator_controls_window()` function
- Remove modal call
- Test that grid still renders

### Phase 2: Add Inline Controls (~1-2 hours)
- Copy control rendering code from modal
- Place below grid
- Adjust layout for sidebar width
- Wire up parameter reading/writing

### Phase 3: Polish & Test (~30-60 min)
- Adjust spacing and sizing
- Add scrolling if needed
- Test all controls
- Default sidebar expanded
- Add "UI" button for curve editor

### Total: ~2-3 hours

---

## Success Criteria

✅ **Done when**:
1. Floating modal window removed
2. Modulator controls render inline below grid
3. All controls work (sliders, buttons, dropdowns, links)
4. Sidebar defaults to expanded
5. Selection state managed correctly
6. Curve editor accessible via "UI" button
7. No regressions in existing functionality

---

## Notes
- Keep hierarchical naming (just completed)
- Keep all parameter logic unchanged
- Focus on moving UI location, not changing functionality
- Test with multiple modulators to verify selection works
- Consider adding "UI" button prominently for curve editor access
