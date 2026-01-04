# SideFX Agent Handoff - January 2026

## Project Status: Phase 2 UI Rewrite (In Progress)

This is **SideFX v1.0** - a product NOT YET RELEASED. We are building an Ableton Live-style device rack system for REAPER.

---

## What Has Been Completed

### 1. Core UI Framework
- **Horizontal device chain layout** with device panels displaying FX
- **Device panel component** (`lib/ui/device_panel.lua`) with:
  - Header with drag handle, name, close button
  - Parameters displayed in columns (configurable)
  - Expand/collapse functionality for parameters
  - **Sidebar** with utility controls

### 2. Sidebar Controls (Right Panel)
The sidebar provides per-FX controls:

| Control | Type | Description |
|---------|------|-------------|
| UI | Button | Opens native FX UI |
| ON/OFF | Button | Bypasses FX |
| Wet | Knob (0-100%) | Wet/dry mix, default 100% |
| Delta | Button (∆/—) | REAPER's delta solo |
| Gain | Vertical Fader (-24 to +24 dB) | Volume from utility JSFX |
| Pan | Slider (-1 to +1) | Pan from utility JSFX |
| Phase L/R | Two buttons (ØL, ØR) | Phase invert per channel |

- Sidebar is **collapsible** (◀/▶ button in fixed header)
- All controls are **centered** in the sidebar
- Uses `pcall` for robust error handling when FX is deleted

### 3. SideFX Utility JSFX
Created `jsfx/SideFX_Utility.jsfx`:
- Gain (dB), Pan, Phase L, Phase R controls
- Level metering
- **Auto-inserted** after every non-utility FX added to track

Installation: Symlinked to REAPER's Effects folder:
```bash
ln -sf ".../SideFX/jsfx/SideFX_Utility.jsfx" ".../reaper-portable/Effects/SideFX/"
ln -sf ".../SideFX/jsfx/SideFX_Modulator.jsfx" ".../reaper-portable/Effects/SideFX/"
```

### 4. Parameter Detection
Smart detection for switch vs continuous parameters:
1. Uses `TrackFX_GetParameterStepSizes` API (`istoggle` flag)
2. Checks if `(max - min) / step ≈ 1` (2-state)
3. Fallback: name keywords (`bypass`, `on`, `off`, `mute`, `solo`, `delta`, `mode`)

---

## Current Configuration (`device_panel.lua`)

```lua
M.config = {
    column_width = 180,
    header_height = 32,
    param_height = 38,
    sidebar_width = 120,
    sidebar_padding = 12,
    fader_width = 28,
    fader_height = 100,
    knob_size = 48,
    btn_h = 22,
    delta_btn_w = 36,
    phase_btn_w = 24,
    collapse_btn_w = 14,
    collapse_btn_h = 14,
    padding = 8,
    border_radius = 6,
}
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

### ImGui/ReaImGui Specifics
- `ctx:begin_child(id, w, h, child_flags, window_flags)` - flags must be **numbers**, not booleans!
  - Use `0` for no flags, `imgui.ChildFlags.Border()` for border
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
- [ ] Implement proper drag & drop reordering between devices
- [ ] Add "+" button to add FX at end of chain
- [ ] Arrow connectors between devices (→)

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

---

## User Preferences (From Conversation)
- Window should be **large and tall**
- Device params expand to **columns** (not vertical list)
- Sidebar controls should be **centered**
- Delta is a **button** not slider
- Phase needs **separate L/R buttons**
- No donation/paywall features for now
- This is v1.0, NOT v2.0

---

## How to Test
1. Open REAPER (portable install at `reaper-portable/`)
2. Run SideFX.lua script
3. Add FX to track - utility should auto-insert
4. Sidebar controls should appear for each FX
5. Test collapse/expand, knob/fader interactions

---

## Reference Documentation
- See `IMPLEMENTATION_PLAN.md` for full architecture
- ReaWrap library at `../ReaWrap/lua/`

