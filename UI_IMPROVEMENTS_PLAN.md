# UI Improvements Plan

## Overview
A series of UI refinements to improve visual consistency, reduce clutter, and optimize layout density in SideFX.

---

## 1. Plugin List Icons

**Current state**: No emojis/icons in plugin list
**Goal**: Restore visual indicators for plugin types

**Implementation**:
- Add 🎛️ (4 knobs emoji) for FX plugins
- Add 🎹 (piano emoji) for instrument plugins
- Location: `lib/ui/main/browser_panel.lua` - plugin list rendering
- Detection: Use existing `is_instrument` logic from plugin scanning

---

## 2. UI Panel Icon

**Current state**: Using some icon for UI button
**Goal**: Replace with spanner emoji for consistency

**Implementation**:
- Replace current icon with 🔧 (spanner emoji)
- Location: `lib/ui/device/device_panel/sidebar.lua` or `header.lua` - UI button rendering
- Should match pattern used for other icon buttons

---

## 3. Refresh FX List Icon

**Current state**: Loop icon missing/broken
**Goal**: Restore loop icon to refresh button

**Implementation**:
- Add 🔄 (loop emoji) to refresh button
- Location: `lib/ui/main/toolbar.lua` - refresh button
- Verify icon font is loaded and available

---

## 4. Delta Button Size

**Current state**: Delta button appears too large
**Goal**: Reduce button size for better visual balance

**Implementation**:
- Location: `lib/ui/device/device_panel/header.lua` - delta button rendering
- Reduce button width (currently fixed at 32px?)
- Possibly reduce height to match other header buttons
- Ensure text/icon still readable

---

## 5. Gain Fader Height

**Current state**: Fader too high, triggers auto-scroll to phase buttons
**Goal**: Reduce fader height to prevent unwanted scrolling

**Implementation**:
- Location: `lib/ui/device/device_panel/sidebar.lua` - gain fader rendering
- Calculate fader height more conservatively
- Leave more space at bottom for phase buttons
- Test with various window heights

---

## 6. Modulator Section Layout

**Current state**: Text labels, wide sliders, controls spread vertically
**Goal**: Compact layout, remove labels, combine controls horizontally

### 6a. Remove All Text Labels
- Remove "Rate", "Phase", "Depth", "Trigger", "Mode" text labels
- Controls should be self-explanatory with tooltips

### 6b. Rate Slider Width
- Make rate slider narrower
- Currently takes full width, reduce by ~30%?

### 6c. Phase and Depth on Same Line
- **Current**: Phase on one row, depth on another
- **New**: Phase | Depth (horizontal layout)
- Use table with 2 columns

### 6d. Trigger and Mode on Same Line
- **Current**: Trigger menu separate from mode buttons
- **New**: [Trigger ▼] [Loop] [One Shot] (all horizontal)
- Trigger menu should be narrower
- Mode buttons (loop/one shot) should be toggle buttons

**Implementation**:
- Location: `lib/ui/device/modulator_sidebar.lua` - modulator controls rendering
- Restructure layout tables
- Adjust column widths
- Add tooltips to replace text labels

---

## 7. Path Display Simplification

**Current state**: Full hierarchical paths shown (R1_C1_D1, R1_C1, etc.)
**Goal**: Show only the local name without parent prefix

**Examples**:
- `R1_C1` → `C1`
- `R1_C1_D1` → `D1`
- `R2` → `R2` (already short)

**Implementation**:
- Create display helper function: `get_short_path(full_name)` or similar
- Strip parent prefix pattern matching `R\d+_C\d+_` or `R\d+_`
- Location: Apply in:
  - Device panel headers (`lib/ui/device/device_panel/header.lua`)
  - Rack headers (`lib/ui/rack/rack_ui.lua`)
  - Chain names (`lib/ui/rack/rack_ui.lua`)
- **IMPORTANT**: Backend naming stays unchanged, this is UI display only
- Possibly add to `lib/fx/fx_naming.lua` as utility function

---

## Implementation Order

### Phase 1: Quick Wins (Icons & Paths)
1. Restore plugin list icons (emojis)
2. Fix UI panel icon (spanner)
3. Fix refresh icon (loop)
4. Simplify path display

### Phase 2: Layout Adjustments
5. Resize delta button
6. Adjust gain fader height

### Phase 3: Modulator Refactor
7. Remove modulator labels
8. Narrow rate slider
9. Combine phase + depth horizontally
10. Combine trigger + mode buttons horizontally

---

## Critical Files

### Icons & Display
- `lib/ui/main/browser_panel.lua` - plugin list icons
- `lib/ui/device/device_panel/sidebar.lua` - UI button icon
- `lib/ui/main/toolbar.lua` - refresh icon
- `lib/fx/fx_naming.lua` - path display utility (new function)

### Layout Adjustments
- `lib/ui/device/device_panel/header.lua` - delta button size
- `lib/ui/device/device_panel/sidebar.lua` - gain fader height

### Modulator Layout
- `lib/ui/device/modulator_sidebar.lua` - all modulator controls

### Path Display Updates
- `lib/ui/device/device_panel/header.lua` - device name display
- `lib/ui/rack/rack_ui.lua` - rack and chain name display

---

## Testing Checklist

- [ ] Plugin list shows correct icons for FX vs instruments
- [ ] UI button shows spanner emoji
- [ ] Refresh button shows loop emoji
- [ ] Delta button is smaller and readable
- [ ] Gain fader doesn't trigger auto-scroll
- [ ] Modulator controls are compact and usable
- [ ] Tooltips work on label-less modulator controls
- [ ] Paths display short names (C1, D1) instead of full paths (R1_C1, R1_C1_D1)
- [ ] Backend operations still work with full path names
- [ ] All controls remain functional after layout changes

---

## Notes

- Icon font (EmojImGui) must be loaded for emojis to display
- Path simplification is UI-only, backend naming unchanged
- Test modulator layout with various window sizes
- Consider adding tooltips to replaced text labels
- Verify gain fader height calculation with min/max window sizes
