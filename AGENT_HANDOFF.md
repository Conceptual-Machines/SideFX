# SideFX Agent Handoff - January 2026

## Project Status: Phase 2 UI Rewrite (In Progress)

This is **SideFX v1.0** - a product NOT YET RELEASED. We are building an Ableton Live-style device rack system for REAPER.

---

## What Has Been Completed

### 1. Core UI Framework
- **Horizontal device chain layout** with device panels displaying FX
- **Device panel component** (`lib/ui/device_panel.lua`) with:
  - Header using **4-column table** layout (drag | name | close | collapse)
  - Parameters displayed in columns (auto-calculated based on visible params)
  - **Sidebar** with utility controls, separated by vertical line
  - Collapse/expand button in header (rightmost position)

### 2. Header Layout (Table-Based)
The header uses a proper ImGui table for alignment:

| Column | Content | Width |
|--------|---------|-------|
| 0 | Drag handle (≡) | Fixed 24px |
| 1 | Device name | **Stretch** (fills space) |
| 2 | Close button (×) | Fixed 20px |
| 3 | Collapse button (◀/▶) | Fixed 20px |

- `▶` when collapsed (click to expand)
- `◀` when expanded (click to collapse)

### 3. Sidebar Controls (Right Panel)
The sidebar provides per-FX controls:

| Control | Type | Width | Description |
|---------|------|-------|-------------|
| UI | Button | 70px | Opens native FX UI |
| ON/OFF | Button | 70px | Bypasses FX |
| Wet | Knob (48px) | centered | Wet/dry mix, 0-100% |
| Delta | Button (36px) | centered | REAPER's delta solo (∆/—) |
| Gain | Vertical Fader | 28×70px | Volume from utility JSFX |
| Pan | Slider | 70px | Pan from utility JSFX |
| Phase L/R | Two buttons | 28px each | Phase invert per channel |

- Sidebar separated from params by **vertical line** (`BordersInnerV`)
- All controls are **centered** using `center_item()` helper
- Sidebar width: 120px expanded, 8px collapsed
- Uses `pcall` for robust error handling when FX is deleted

### 4. Parameter Filtering
- **Wet, Delta, Bypass** params are hidden from main display (shown in sidebar)
- Pre-filtered `visible_params` array built at start
- Layout calculated from `visible_count` (no empty gaps)

### 5. SideFX Utility JSFX
Created `jsfx/SideFX_Utility.jsfx`:
- Gain (dB), Pan, Phase L, Phase R controls
- Level metering
- **Auto-inserted** after every non-utility FX added to track

Installation: Symlinked to REAPER's Effects folder:
```bash
ln -sf ".../SideFX/jsfx/SideFX_Utility.jsfx" ".../reaper-portable/Effects/SideFX/"
ln -sf ".../SideFX/jsfx/SideFX_Modulator.jsfx" ".../reaper-portable/Effects/SideFX/"
```

### 6. Parameter Detection
Smart detection for switch vs continuous parameters:
1. Uses `TrackFX_GetParameterStepSizes` API (`istoggle` flag)
2. Checks if `(max - min) / step ≈ 1` (2-state)
3. Fallback: name keywords (`bypass`, `on`, `off`, `mute`, `solo`, `delta`, `mode`)

---

## Current Configuration (`device_panel.lua`)

```lua
M.config = {
    column_width = 180,        -- Width per parameter column
    header_height = 32,
    param_height = 38,         -- Height per param row
    sidebar_width = 120,       -- Width for sidebar (expanded)
    sidebar_padding = 12,      -- Extra padding
    padding = 8,               -- General padding
    border_radius = 6,
    fader_width = 28,          -- Gain fader width
    fader_height = 70,         -- Gain fader height
    knob_size = 48,            -- Wet knob diameter
}

-- Button widths in sidebar
btn_w = 70                     -- UI, ON/OFF, Pan slider width
btn_h = 22                     -- Button height
```

---

## Key Files

| File | Purpose |
|------|---------|
| `SideFX.lua` | Main entry, UI rendering, state management |
| `lib/ui/device_panel.lua` | Device panel + sidebar UI component |
| `lib/ui/rack_panel.lua` | Rack container UI (partial) |
| `jsfx/SideFX_Utility.jsfx` | Gain/Pan/Phase utility |
| `jsfx/SideFX_Modulator.jsfx` | LFO modulator (existing) |

---

## Important Technical Notes

### ImGui/ReaImGui Layout Patterns
- **Right-align elements**: Use a table with stretch column, NOT `same_line()` hacks
- **Vertical separator**: Use `ImGui_TableFlags_BordersInnerV()` on table
- **Centering**: Calculate offset with `(container_w - item_w) / 2`, use `SetCursorPosX`
- `ctx:begin_child(id, w, h, child_flags, window_flags)` - flags must be **numbers**, not booleans
- Wrap FX parameter access in `pcall` - FX can be deleted mid-frame
- Custom widgets: `draw_knob()` and `draw_fader()` in device_panel.lua

### REAPER API
- JSFX path format: `"JS:SideFX/SideFX_Utility"` (not just filename)
- `TrackFX_GetParameterStepSizes(track, fx, param)` returns: `retval, step, smallstep, largestep, istoggle`
- Use `get_param_normalized` / `set_param_normalized` for 0-1 range params

### File Paths (User's Setup)
- Portable REAPER: `/Users/Luca_Romagnoli/Code/personal/ReaScript/reaper-portable/`
- Effects folder: `.../reaper-portable/Effects/SideFX/`

---

## What Still Needs To Be Done

### Phase 2 Remaining (UI)
- [ ] Finalize device panel styling/colors
- [x] Implement proper drag & drop reordering between devices
- [x] Drag & drop plugins from browser to device chain
- [x] Add "+" button to add FX at end of chain
- [x] Arrow connectors between devices (→)

### Phase 3: Rack Management
- [ ] Create `SideFX_Mixer.jsfx` (sums chains to 1-2)
- [ ] `rack_manager.lua` - create/manage racks
- [ ] `routing.lua` - automatic pin mapping for chains
- [ ] Rack UI with vertical chain stacking
- [ ] "+Chain" button to add parallel chains

### Phase 4: Modulator Integration
- [ ] Connect modulators to new UI
- [ ] Link modulators to rack chain parameters

### Phase 5: Presets
- [ ] Device presets
- [ ] Chain presets
- [ ] Rack presets

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| `ImGui_BeginChild: bad argument #5` | Use `0` not `false` for flags |
| `Failed to get param name` | Wrap in `pcall`, FX may be deleted |
| JSFX not loading | Use `JS:Folder/Name` format |
| Wet/Gain stuck at 0 | Use `get_param_normalized` not `get_param` |
| All params detected as switch | Check `istoggle` flag, then step calc |
| Right-align not working | Use table with stretch column, not `same_line()` |
| Empty gaps in param grid | Pre-filter visible_params, use visible_count for layout |

---

## User Preferences (From Conversation)
- Window should be **large and tall**
- Device params expand to **columns** (not vertical list)
- Sidebar controls should be **centered**
- Delta is a **button** not slider
- Phase needs **separate L/R buttons**
- Collapse button in **header, rightmost** position
- **Vertical separator** between params and sidebar
- UI/ON/Pan controls should be **narrower** (70px)
- Gain fader should be **shorter** (70px height)
- No donation/paywall features for now
- This is v1.0, NOT v2.0

---

## How to Test
1. Open REAPER (portable install at `reaper-portable/`)
2. Run SideFX.lua script
3. Add FX to track - utility should auto-insert
4. Sidebar controls should appear for each FX
5. Test collapse/expand button in header
6. Verify Wet/Delta/Bypass NOT shown in param area (only in sidebar)
7. Resize window - no empty gaps should appear

---

## Recent Changes (This Session)
1. Simplified layout from nested child windows to **table-based**
2. Header now uses 4-column table for proper right-alignment
3. Collapse button moved to header (rightmost)
4. Added vertical separator between params and sidebar
5. Narrowed UI/ON buttons and Pan slider (70px)
6. Shortened Gain fader (70px)
7. Pre-filter visible params to eliminate layout gaps

---

## Reference Documentation
- See `IMPLEMENTATION_PLAN.md` for full architecture
- ReaWrap library at `../ReaWrap/lua/`
