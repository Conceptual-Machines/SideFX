# SideFX v2.0 - Ableton-Style Rack System

## Overview

Transform SideFX into an Ableton Live-style device rack for REAPER with automatic parallel chain routing.

---

## Architecture

```
Input (channels 1-2)
    │
    ▼ (all chains read from 1-2)
┌──────────────────────────────────────────────────────────────┐
│ RACK                                                         │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Chain 1 │ [Synth] → [EQ] → [Comp]        → out 3-4      │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │ Chain 2 │ [Synth] → [Dist] → [Filter]    → out 5-6      │ │
│  ├─────────────────────────────────────────────────────────┤ │
│  │ Chain 3 │ [Synth] → [Chorus]             → out 7-8      │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
    │
    ▼
[SideFX_Mixer] (sums 3-4, 5-6, 7-8... → 1-2)
    │
    ▼
[Master FX] → [Limiter] (on 1-2)
```

### Key Concepts

- **Channels 1-2**: Reserved for final output / main bus
- **Channels 3-4, 5-6, 7-8...**: Individual chain outputs
- **Each chain**: Container with input pins reading 1-2, output pins to unique pair
- **Mixer**: Sums all chain outputs back to 1-2
- **Max chains**: 31 (using channels 3-64)

---

## Phase 1: Channel Mixer JSFX

### File: `jsfx/SideFX_Mixer.jsfx`

### Features
- 8 stereo input pairs (channels 3-4 through 17-18)
- Volume slider per chain
- Mute/Solo per chain
- Pan per chain (optional)
- Master volume
- Sum all active chains to output 1-2

### Interface
```
slider1:0<-60,12,0.1>Chain 1 Vol (dB)
slider2:0<-60,12,0.1>Chain 2 Vol (dB)
slider3:0<-60,12,0.1>Chain 3 Vol (dB)
slider4:0<-60,12,0.1>Chain 4 Vol (dB)
slider5:0<-60,12,0.1>Chain 5 Vol (dB)
slider6:0<-60,12,0.1>Chain 6 Vol (dB)
slider7:0<-60,12,0.1>Chain 7 Vol (dB)
slider8:0<-60,12,0.1>Chain 8 Vol (dB)

slider10:0<0,1,1>Chain 1 Mute
slider11:0<0,1,1>Chain 2 Mute
...

slider20:0<-12,12,0.1>Master Vol (dB)
```

### Visual (optional @gfx)
- Level meters per chain
- Visual mixer layout

---

## Phase 2: UI Rewrite - Horizontal Device Chain

### 2.1 Main Layout

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Toolbar: [Refresh] [Add Rack] [+ FX] | Track Name > Breadcrumb          │
├─────────┬───────────────────────────────────────────────────┬───────────┤
│         │                                                   │           │
│ Plugin  │  Device Chain (horizontal scroll)                 │ Modulator │
│ Browser │  [Dev1] → [Rack...] → [Dev2] → [Mixer]            │ Column    │
│         │                                                   │           │
│ - VST   │  Racks show chains stacked vertically:            │ [+ Add]   │
│ - JSFX  │  ┌─────────────────────────────────┐              │           │
│ - AU    │  │ Chain 1 │ [FX] → [FX] → [FX]   │              │ LFO 1     │
│         │  │ Chain 2 │ [FX] → [FX]          │              │  → Synth  │
│         │  └─────────────────────────────────┘              │           │
│         │                                                   │           │
└─────────┴───────────────────────────────────────────────────┴───────────┘
```

**Toolbar buttons:**
- `[Refresh]` - Reload FX list
- `[Add Rack]` - Create new parallel rack
- `[+ FX]` - Quick-add FX at end of chain

### 2.2 Device Panel Component

Each FX displayed as a "device" panel:

**Collapsed (default):**
```
┌─────────────────┐
│ ≡ Device Name ✕ │  ← Drag handle, name, close
├─────────────────┤
│ Param1   ████░░ │  ← First few parameters
│ Param2   ██░░░░ │
│ Param3   █████░ │
│ [Show more ▼]   │  ← Expand to show all
├─────────────────┤
│ [UI] [Bypass]   │  ← Open native UI, bypass toggle
└─────────────────┘
```

**Expanded:**
```
┌─────────────────┐
│ ≡ Device Name ✕ │
├─────────────────┤
│ Param1   ████░░ │  ← ALL parameters shown
│ Param2   ██░░░░ │
│ Param3   █████░ │
│ Param4   ███░░░ │
│ Param5   ██████ │
│ Param6   █░░░░░ │
│ ...             │  (scrollable if many)
│ [Show less ▲]   │  ← Collapse back
├─────────────────┤
│ [UI] [Bypass]   │
└─────────────────┘
```

- Fixed width per device (~150-200px)
- **Show all parameters** with expand/collapse
- Scrollable if too many params when expanded
- Drag to reorder
- Right-click for context menu

### 2.3 Rack Display (Container)

**Collapsed:**
```
┌─────────────────┐
│ ▶ Rack Name   ✕ │
│   3 chains      │
└─────────────────┘
```

**Expanded:**
```
┌────────────────────────────────────────────────────────────────┐
│ ▼ Rack Name                                        [+Chain] ✕  │
├────────────────────────────────────────────────────────────────┤
│ Chain 1: Sub  │ [SubSynth] → [EQ] → [Comp]           │ Vol ██░ │
├───────────────┼──────────────────────────────────────┼─────────┤
│ Chain 2: Bass │ [BassSynth] → [Dist] → [Filter]      │ Vol ███ │
├───────────────┼──────────────────────────────────────┼─────────┤
│ Chain 3: Top  │ [Synth] → [Chorus] → [EQ]            │ Vol █░░ │
└───────────────┴──────────────────────────────────────┴─────────┘
```

- Chains stack vertically within the rack
- Each chain shows its devices horizontally
- Per-chain volume (controls mixer)
- "+Chain" adds new parallel chain

---

## Phase 3: Rack Management (Lua Backend)

### 3.0 User Workflow: Creating Parallel Chains

**Step 1: Add a Rack**
```
User clicks [Add Rack] in toolbar
         │
         ▼
┌──────────────────────────────────────────────────┐
│ ▼ New Rack                           [+Chain] ✕  │
├──────────────────────────────────────────────────┤
│ Chain 1 │ (empty - drag FX here)       │ Vol ███ │
└──────────────────────────────────────────────────┘
         │
         ▼
[SideFX_Mixer] (auto-inserted after rack)
```

**Step 2: Add Parallel Chains**
```
User clicks [+Chain] inside rack
         │
         ▼
┌──────────────────────────────────────────────────┐
│ ▼ New Rack                           [+Chain] ✕  │
├──────────────────────────────────────────────────┤
│ Chain 1 │ [Synth] → [EQ]               │ Vol ███ │
├──────────────────────────────────────────────────┤
│ Chain 2 │ (empty - drag FX here)       │ Vol ███ │  ← NEW
└──────────────────────────────────────────────────┘
```

**Step 3: Populate Chains**
- Drag FX from browser into each chain
- Each chain processes in parallel
- Mixer sums outputs to 1-2

**Alternative Workflows (v2.0+):**
- Drag FX below another → auto-create rack
- Select multiple FX → right-click → "Make Parallel"
- Drag existing FX into rack to add as new chain

### 3.0.1 Expand Rack to Separate Tracks

Right-click rack → "Expand to Tracks"

**Before:**
```
Track: Bass Layer
  └─ Rack
       ├─ Chain 1: Sub   │ [SubSynth] → [EQ]
       ├─ Chain 2: Mid   │ [BassSynth] → [Dist]
       └─ Chain 3: Top   │ [Synth] → [Chorus]
```

**After:**
```
Folder: Bass Layer
  ├─ Track: Sub   │ [SubSynth] → [EQ]
  ├─ Track: Mid   │ [BassSynth] → [Dist]
  └─ Track: Top   │ [Synth] → [Chorus]
```

**What happens:**
1. Create folder track with rack name
2. For each chain:
   - Create child track with chain name
   - Move FX from chain to new track
   - Route to parent folder
3. Delete original rack + mixer
4. Folder sums all children automatically

**Benefits:**
- Individual track controls (volume, pan, sends)
- Separate automation lanes per chain
- Better visual overview in mixer
- Can still collapse folder to save space

**Reverse: "Collapse Tracks to Rack"**
- Select folder with child tracks
- Right-click → "Collapse to Rack"
- Creates rack with chains from each child track

### 3.1 Creating a Rack

When user clicks "Add Rack":
1. Create container "SideFX Rack"
2. Create first chain container inside (output → 3-4)
3. Insert SideFX_Mixer after rack
4. Store rack metadata in track extended state

### 3.2 Adding a Chain

When user clicks "+Chain":
1. Determine next available channel pair (5-6, 7-8...)
2. Create container with:
   - Input pins: 1-2
   - Output pins: next available pair
3. Update SideFX_Mixer slider visibility

### 3.3 Pin Routing

Set container pins via:
```lua
-- Set input pins (read from 1-2)
reaper.TrackFX_SetPinMappings(track, fx_idx, 0, 0, 1, 0)  -- input L from ch1
reaper.TrackFX_SetPinMappings(track, fx_idx, 0, 1, 2, 0)  -- input R from ch2

-- Set output pins (write to 3-4, 5-6, etc.)
reaper.TrackFX_SetPinMappings(track, fx_idx, 1, 0, ch_out_L, 0)
reaper.TrackFX_SetPinMappings(track, fx_idx, 1, 1, ch_out_R, 0)
```

### 3.4 Rack State

Store in track extended state:
```lua
{
  racks = {
    {
      container_guid = "...",
      mixer_guid = "...",
      chains = {
        { guid = "...", name = "Sub", output_channels = {3, 4} },
        { guid = "...", name = "Bass", output_channels = {5, 6} },
      }
    }
  }
}
```

---

## Phase 4: Modulator Integration

### 4.1 Keep Modulator Column
- Stays on right side
- Can link to any device parameter in any chain

### 4.2 Link to Chain Parameters
- Dropdown shows: Rack > Chain > Device > Param
- Works with container-encoded FX indices

### 4.3 Modulator Routing
- Modulators stay at top level (before rack)
- Use plink to modulate params inside chains

---

## Phase 5: Presets

### 5.1 Preset Types

| Type | Contents | File Extension |
|------|----------|----------------|
| Device | Single FX + params | `.rfxpreset` |
| Chain | Container + FX inside | `.rfxchain` |
| Rack | All chains + mixer + routing | `.sidefx_rack` |
| Full | Entire track FX chain | `.sidefx_full` |

### 5.2 Rack Preset Format

```json
{
  "version": "2.0",
  "type": "rack",
  "name": "Bass Layer",
  "chains": [
    {
      "name": "Sub",
      "output_channels": [3, 4],
      "fx_chain": "<base64 encoded RfxChain>"
    },
    {
      "name": "Mid Bass",
      "output_channels": [5, 6],
      "fx_chain": "<base64 encoded RfxChain>"
    }
  ],
  "mixer_state": {
    "chain_volumes": [0, -3, -6],
    "chain_pans": [0, 0, 0],
    "master_volume": 0
  }
}
```

---

## File Structure

```
SideFX/
├── SideFX.lua                    # Main entry point
├── IMPLEMENTATION_PLAN.md        # This file
│
├── lib/
│   ├── ui/
│   │   ├── device_panel.lua      # Device panel component
│   │   ├── rack_panel.lua        # Rack container UI
│   │   ├── chain_row.lua         # Chain row within rack
│   │   └── mixer_strip.lua       # Mixer channel strip
│   │
│   ├── core/
│   │   ├── rack_manager.lua      # Create/manage racks
│   │   ├── chain_manager.lua     # Create/manage chains
│   │   ├── routing.lua           # Pin routing helpers
│   │   └── state.lua             # Track extended state
│   │
│   └── presets/
│       ├── device_presets.lua
│       ├── rack_presets.lua
│       └── chain_presets.lua
│
├── jsfx/
│   ├── SideFX_Modulator.jsfx     # Existing modulator
│   └── SideFX_Mixer.jsfx         # NEW: Channel mixer
│
└── presets/
    ├── devices/
    ├── racks/
    └── chains/
```

---

## Implementation Order

### Sprint 1: Foundation
1. [ ] Create `SideFX_Mixer.jsfx`
2. [ ] Test channel routing manually
3. [ ] Basic horizontal UI layout

### Sprint 2: Rack System
4. [ ] `rack_manager.lua` - create rack + chains
5. [ ] `routing.lua` - auto pin setup
6. [ ] Rack UI component

### Sprint 3: Device Panels
7. [ ] `device_panel.lua` - individual FX display
8. [ ] Drag & drop reordering
9. [ ] Horizontal scrolling chain view

### Sprint 4: Integration
10. [ ] Connect modulator to new UI
11. [ ] Rack/chain presets
12. [ ] Polish & UX

---

## Open Questions

1. ~~**Parameter display**: Show all params or let user select "macros"?~~ → **Show all with expand/collapse**
2. **Chain naming**: Auto-name or prompt user?
3. **Visual feedback**: Level meters? Waveforms?
4. **Keyboard shortcuts**: What actions need shortcuts?

---

## References

- [REAPER Container Documentation](https://www.reaper.fm/sdk/reascript/reascript.php)
- [Ableton Live Rack Design](https://www.ableton.com/en/manual/instrument-drum-and-effect-racks/)
- [ReaWrap API](../ReaWrap/lua/)

