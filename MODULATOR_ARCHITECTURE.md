# Modulator Architecture

## Current System (Device Modulators)

**Location**: `lib/ui/device_panel.lua` - Modulator sidebar (left side)

**Concept**: Each device has its own modulators inside its container
- Modulators live inside the device container (Container > Modulator + Device + Utility)
- 8 modulator slots per device (4×2 grid)
- Modulators can only modulate their parent device
- UI shows in left sidebar of device panel
- Parameter linking done through REAPER's plink API

**Files**:
- `lib/ui/device_panel.lua` - Device panel with modulator sidebar (ACTIVE)
- `jsfx/SideFX_Modulator.jsfx` - Bezier LFO modulator JSFX

## Old System (Global Modulators)

**Location**: `lib/ui/modulator_panel.lua` - Separate panel

**Status**: DEPRECATED / NOT USED

This was the old global modulator system before we moved to device-specific modulators.

**Files**:
- `lib/ui/modulator_panel.lua` - Old global modulator panel (NOT USED)
- `lib/modulator.lua` - Modulator utilities (may have old plink code)

## Key Distinction

- **Device modulators** = Current system, per-device, in device_panel.lua
- **Global modulators** = Old system, deprecated, in modulator_panel.lua

**All current work should focus on device_panel.lua's modulator sidebar!**
