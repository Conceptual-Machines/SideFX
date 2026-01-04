# SideFX Agent Handoff - January 2026

## Project Status: Phase 3 Rack System (Near Complete)

This is **SideFX v1.0** - a product NOT YET RELEASED. We are building an Ableton Live-style device rack system for REAPER.

---

## What Has Been Completed

### 1. Core UI Framework ✅
- **Horizontal device chain layout** with device panels displaying FX
- **Device panel component** (`lib/ui/device_panel.lua`) with:
  - Header using **4-column table** layout (drag | name | close | collapse)
  - Parameters displayed in columns (auto-calculated based on visible params)
  - **Sidebar** with utility controls, separated by vertical line
  - Collapse/expand toggle via burger menu (≡)
  - Collapsed panels: full height, narrow width, wrapped name, UI/ON buttons visible

### 2. D-Container Architecture ✅
FX are wrapped in "Device Containers" (D-prefix):

```
Track Chain:
├── D1: ReaEQ              ← D-Container
│   ├── _FX: ReaEQ         ← Main FX (prefixed)
│   └── _Util              ← Utility JSFX (prefixed)
├── D2: ReaComp
│   ├── _FX: ReaComp
│   └── _Util
```

**Benefits:**
- Move FX + utility as a single unit
- Cleaner chain organization  
- Self-documenting names in REAPER's native FX window
- Auto-renumbering when chain order changes

### 3. R-Container (Rack) Architecture ✅
Parallel processing racks with chains:

```
Track Chain:
├── D1: ReaEQ              ← Regular device
├── R1: Parallel FX        ← R-Container (Rack)
│   ├── R1_C1              ← Chain container
│   │   └── R1_C1_D1: Dist ← Device inside chain
│   │       ├── _FX: Dist
│   │       └── _Util
│   ├── R1_C2              ← Another chain
│   │   └── R1_C2_D1: Reverb
│   │       ├── _FX: Reverb
│   │       └── _Util
│   └── _R1_M              ← Internal mixer (hidden)
├── D2: Limiter
```

**Rack Features:**
- 64 internal channels for parallel routing
- Each chain routes to sideband channels (3/4, 5/6, etc.)
- Mixer JSFX sums all chains back to 1/2
- Hierarchical naming: `R{rack}_C{chain}_D{device}`
- Click chain → expands to show devices in new column

### 4. SideFX JSFX Plugins ✅

| JSFX | Purpose | UI Visibility |
|------|---------|---------------|
| `SideFX_Utility.jsfx` | Gain/Pan/Phase per device | Hidden (controlled via SideFX UI) |
| `SideFX_Mixer.jsfx` | Sums parallel chains with per-chain vol/pan + master | Sliders hidden (- prefix) |
| `SideFX_Modulator.jsfx` | LFO modulation | Visible (has @gfx UI) |

**SideFX_Mixer.jsfx Parameters:**
- slider1: Master Gain (-24 to +12 dB)
- slider2: Master Pan (-100 to +100)
- slider10-25: Chain 1-16 Volume (-60 to +12 dB)
- slider30-45: Chain 1-16 Pan (-100 to +100)
- All sliders use `-` prefix to hide from native JSFX UI
- Explicit in_pin/out_pin declarations for 16 stereo inputs → 1 stereo output

Installation: Symlinked to REAPER's Effects folder:
```bash
ln -sf ".../SideFX/jsfx/SideFX_Utility.jsfx" ".../reaper-portable/Effects/SideFX/"
ln -sf ".../SideFX/jsfx/SideFX_Mixer.jsfx" ".../reaper-portable/Effects/SideFX/"
ln -sf ".../SideFX/jsfx/SideFX_Modulator.jsfx" ".../reaper-portable/Effects/SideFX/"
```

### 5. Drag & Drop ✅
- Drag plugins from browser → drop on chain to add
- Drag FX between positions to reorder
- Drop on device → insert before
- "+" button at end of chain for adding

### 6. Sidebar Controls ✅

| Control | Source | Description |
|---------|--------|-------------|
| UI | - | Opens native FX UI |
| ON/OFF | - | Bypasses device (container) |
| Mix | Container wet/dry | Parallel blend 0-100% |
| Gain | Utility JSFX | Volume adjustment |
| Pan | Utility JSFX | Stereo position |
| Phase L/R | Utility JSFX | Phase invert per channel |

### 7. Parameter Detection ✅
Smart detection for switch vs continuous parameters:
1. Uses `TrackFX_GetParameterStepSizes` API (`istoggle` flag)
2. Checks if `(max - min) / step ≈ 1` (2-state)
3. Fallback: name keywords (`bypass`, `on`, `off`, `mute`, `solo`, `delta`, `mode`)

---

## Current UI Layout

### Device Chain View
```
┌─────────────────────────────────────────────────────────────────────────┐
│ [Browser]  │  D1: ReaEQ → D2: ReaComp → R1: Rack → D3: Limiter → [+]   │
│            │     ▼                          ▼                           │
│ Plugins    │  [Device Panel]            [Rack Panel] [Chain Column]     │
│ ├─ VST     │  ┌──────────┐              ┌────────┐   ┌──────────────┐   │
│ ├─ JS      │  │ ≡ ReaEQ ×│              │▼ Rack  │   │Chain: C1     │   │
│ └─ ...     │  │ params   │              │ C1 [ON]│   │ [Device]     │   │
│            │  │ Gain Pan │              │ C2 [ON]│   │              │   │
│            │  └──────────┘              └────────┘   └──────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

### Rack Panel (350px wide expanded, 150px collapsed)
**Expanded View:**
- Master output section at top (Gain slider + Pan control)
- List of chains with: Name | ON/OFF | Delete | Volume | Pan (all on same line)
- Click chain → expands column showing devices
- "+Chain" button to add new chains

**Collapsed View:**
- Chain count display
- Custom pan slider with center indicator
- Vertical gain fader with dB scale (-24 to +12)
- Stereo level meters (L/R)
- dB value label with background

**Mixer Controls:**
- Per-chain volume (-60 to +12 dB)
- Per-chain pan (balance, -100L to +100R)
- Master gain (-24 to +12 dB)
- Master pan (balance)
- All controls: double-click slider to reset, double-click label to edit value

### Chain Column (500px wide)
- Shows devices inside selected chain
- Full device panels with controls
- Same layout as top-level devices

---

## Key Files

| File | Purpose |
|------|---------|
| `SideFX.lua` | Main entry, UI rendering, state management, rack/chain logic |
| `lib/ui/device_panel.lua` | Device panel + sidebar UI component |
| `jsfx/SideFX_Utility.jsfx` | Gain/Pan/Phase utility (hidden sliders) |
| `jsfx/SideFX_Mixer.jsfx` | Chain mixer (completely hidden) |
| `jsfx/SideFX_Modulator.jsfx` | LFO modulator |

---

## Naming Convention

### Internal Names (REAPER FX Chain)
```
D{n}: {name}           ← Top-level device container
  _FX: {name}          ← Main FX inside container
  _Util                ← Utility JSFX inside container

R{n}: {name}           ← Rack container
  R{n}_C{m}            ← Chain container (no display name)
    R{n}_C{m}_D{p}: {name}  ← Device inside chain
      _FX: {name}
      _Util
  _R{n}_M              ← Internal mixer (hidden)
```

### Display Names (SideFX UI)
- Internal prefixes (`_FX:`, `_Util`, `_R{n}_M`, `R{n}_C{m}_D{p}_`) are stripped
- Users see clean names: "ReaEQ", "Compressor", "Reverb"
- Users can rename devices (stored in `renamed_name` config)

---

## Channel Routing (Racks)

```
Rack R1 (64 internal channels):
├── Input: 1/2 (main signal)
├── Chain C1: Output → 3/4
├── Chain C2: Output → 5/6
├── Chain C3: Output → 7/8
├── ...up to 32 stereo chains
└── Mixer: Sums 3/4 + 5/6 + ... → 1/2
```

**Pin Mapping:**
- Chains use `container_pins_str` to route output
- Format: `0:0 1:1 0:2 1:3` (L→ch3, R→ch4)
- Mixer sums all even channels (stereo pairs) to 1/2

---

## What Still Needs To Be Done

### Phase 3 Remaining (Racks)
- [ ] Add FX to existing chain (currently only creates new chain)
- [ ] Reorder chains within rack
- [x] "+Chain" button inside rack panel ✅
- [x] Per-chain volume/pan controls ✅
- [x] Master output (gain/pan) for rack ✅
- [ ] Visual feedback during drag over chains

### Phase 4: Recursive Containers
- [ ] Allow racks inside chains (nested racks)
- [ ] Update naming for deep nesting: `R1_C1_R2_C1_D1`
- [ ] Breadcrumb navigation for deep hierarchies

### Phase 5: Modulator Integration
- [ ] Connect modulators to new UI
- [ ] Link modulators to rack chain parameters
- [ ] Modulation depth indicators on knobs

### Phase 6: Presets
- [ ] Device presets (single FX + utility settings)
- [ ] Chain presets (sequence of devices)
- [ ] Rack presets (parallel structure)

### Phase 7: Polish
- [ ] Finalize color scheme
- [ ] Keyboard shortcuts
- [ ] Undo/redo support
- [ ] Performance optimization

---

## Important Technical Notes

### Container Addressing (ReaWrap)
**ALWAYS use ReaWrap methods for container operations:**
```lua
-- Adding FX to container
container:add_fx_to_container("JS:SideFX/SideFX_Utility")

-- Iterating container children
for child in container:iter_container_children() do
    -- process child
end
```

**DO NOT use raw REAPER API** - the `0x2000000` addressing is complex and error-prone.

### Building Nested Containers
When creating deeply nested structures (rack → chain → device):
1. Build innermost container (device) at track level first
2. Add FX and utility inside device
3. Create parent container (chain) at track level
4. Move device INTO chain
5. Move chain INTO rack

This avoids pointer invalidation issues.

### ImGui Layout Patterns
- **Right-align**: Use table with stretch column
- **Centering**: `(container_w - item_w) / 2` with `SetCursorPosX`
- **Child flags**: Must be numbers, not booleans
- **Wrap FX access in `pcall`**: FX can be deleted mid-frame

### Custom UI Components (SideFX.lua)
**`draw_pan_slider(ctx, label, pan_val, width)`**
- Custom pan control with center line indicator
- Visual: slider bar (12px) + text label below (16px)
- Separate interaction zones: slider for dragging, label for editing
- Double-click slider → reset to center
- Double-click label → popup to type value
- Returns: `changed, new_val`

**Collapsed Rack Fader**
- Vertical fader with dB scale markings (-24 to +12)
- Stereo level meters (green/yellow/red coloring)
- dB label with background, double-click to edit

### State Management
```lua
state = {
    expanded_path = {
        [1] = rack_guid,      -- Expanded rack
        [2] = chain_guid,     -- Selected chain within rack
    },
    collapsed_panels = {},    -- Device panel collapse state
}
```

---

## Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| FX added to wrong container | Build containers at track level first, then move |
| `Failed to get FX name` | Wrap in `pcall`, FX may be deleted or stale |
| Utility not showing controls | Check `is_utility_fx()` pattern matching |
| Mixer visible in rack | Ensure name starts with `_` (underscore prefix) |
| Channel routing wrong | Check `container_pins_str` format |
| Nested addressing fails | Use ReaWrap's `add_fx_to_container`, not raw API |

---

## User Preferences (From Conversation)
- Window should be **large and tall**
- Device params expand to **columns** (not vertical list)
- Sidebar controls should be **centered**
- Phase needs **separate L/R buttons**
- Collapse button is **burger menu** (≡)
- Collapsed panels: **full height, narrow, show UI button and wrapped name**
- **Vertical separator** between params and sidebar
- Utility/Mixer JSFX **completely hidden** in native UI
- Container Mix and Utility Gain shown; internal FX Wet hidden
- Rack panel: **narrow (200px)**, chain column: **wide (500px)**
- Clean display names (no internal prefixes)
- This is v1.0, NOT v2.0

---

## How to Test

### Basic Device Chain
1. Open REAPER (portable install at `reaper-portable/`)
2. Run SideFX.lua script
3. Add FX to track → creates D-container with utility
4. Sidebar controls should appear for each device
5. Click burger menu (≡) to collapse/expand panel

### Rack System
1. Click "+ Rack" button
2. Drag plugin onto rack drop zone → creates chain with device
3. Click chain name → expands to show devices in column
4. Add multiple chains, verify routing (3/4, 5/6, etc.)
5. Check mixer sums all chains to 1/2

### Naming
1. Check REAPER's native FX chain view
2. Verify hierarchical names: `D1:`, `R1:`, `R1_C1_D1:`, etc.
3. In SideFX UI, verify clean names (no prefixes)

---

## Recent Session Summary (January 4, 2026)

### Completed This Session:
1. ✅ Implemented FX drag & drop from browser
2. ✅ Created D-Container architecture (FX + Utility in container)
3. ✅ Implemented R-Container (Rack) system
4. ✅ Created SideFX_Mixer.jsfx for chain summing
5. ✅ Implemented 64-channel routing for racks
6. ✅ Chain click → expands devices in new column
7. ✅ Hierarchical naming convention
8. ✅ Device panel collapse (full height, narrow)
9. ✅ Hidden utility/mixer sliders from native JSFX UI (- prefix)
10. ✅ Per-chain volume and pan controls in rack UI
11. ✅ Master output section (gain/pan) for racks
12. ✅ Collapsed rack view with vertical fader + stereo meters
13. ✅ Custom pan slider component with center line indicator
14. ✅ Double-click to reset controls to default
15. ✅ Double-click on labels to edit values via popup
16. ✅ Chain containers set to 64 channels for sideband routing

### Current State:
- Basic device chain works (add, remove, reorder)
- Racks fully functional with parallel chains
- Per-chain mixing (volume/pan) exposed in UI
- Master output controls for rack summing
- Collapsed view shows fader + stereo meters
- All mixer controls hidden from native REAPER UI
- All naming is consistent and auto-numbered

### Next Priority:
- Add FX to existing chain (vs always creating new)
- Recursive racks (racks inside chains)
- Modulator integration

---

## Reference Documentation
- See `IMPLEMENTATION_PLAN.md` for full architecture
- ReaWrap library at `../ReaWrap/lua/`
- Memory note: Use ReaWrap's `container:add_fx_to_container()` for container child operations
