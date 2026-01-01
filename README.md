# SideFX

Smart FX container management for REAPER 7+.

## Features

- **Visual rack-style FX chain view** - See your entire FX chain with container hierarchy
- **One-click parallel chain creation** - Select FX and create parallel routing instantly
- **Instrument layer routing** - Fix multi-instrument container issues with proper routing
- **Container routing diagnostics** - Detect and auto-fix common routing problems

## Requirements

- REAPER 7.0+
- [ReaImGui](https://forum.cockos.com/showthread.php?t=250419) extension
- [ReaWrap](https://github.com/Conceptual-Machines/ReaWrap) library

## Installation

### Via ReaPack (Recommended)

1. Install [ReaPack](https://reapack.com/) if you haven't already
2. Add this repository: `https://raw.githubusercontent.com/Conceptual-Machines/SideFX/main/index.xml`
3. Install "SideFX" from the ReaPack browser

### Manual Installation

1. Download `SideFX.lua` and the `lib/` folder
2. Place them in your REAPER Scripts folder
3. Load as a new action in REAPER

## Usage

1. Select a track with FX
2. Run the SideFX action
3. Use the visual interface to:
   - View FX chain structure
   - Select multiple FX (Shift+click)
   - Create parallel racks from selection
   - Create instrument layers
   - Diagnose and fix routing issues

## Screenshots

*Coming soon*

## License

MIT License - see [LICENSE](LICENSE)

## Author

Nomad Monad

