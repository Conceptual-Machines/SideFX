# SideFX v1.0 Release Plan

## Overview
Final tasks before v1.0 release. No gain staging in this release.

## Tasks

### 1. Settings Dialog Updates
- [x] Remove gain staging section from settings
- [x] Add Bake Settings section:
  - Disable link after bake (checkbox, default: true)
  - Default range mode (dropdown: Project/Track/Time Selection/Selected Items)
  - Show range picker modal (checkbox, default: true)

### 2. UI Improvements
- [x] Shift-key fine tuning for all slider controls
  - Hold Shift for finer adjustment (0.1x or 0.01x multiplier)
- [x] Display parameter values on controls
  - Show current value tooltip or inline text
- [x] Smart unit detection for parameters (auto-detect dB, Hz, ms, etc.)
- [x] User-configurable unit overrides in parameter selector

### 3. Testing
- [ ] Manual testing of all core features:
  - Device creation and management
  - Rack creation with parallel chains
  - Modulator parameter linking
  - Bake to automation (all range modes)
  - Preset save/load
  - Settings persistence
- [ ] Test edge cases:
  - Deeply nested containers
  - Multiple modulators per device
  - MIDI trigger mode with various note patterns

### 4. Documentation
- [ ] HTML manual covering:
  - Installation
  - Quick start guide
  - Device management
  - Rack creation
  - Modulator usage and parameter linking
  - Baking automation
  - Settings reference

## Known Bugs (Fix Before Release)
- [ ] Track name in toolbar header doesn't update when track is renamed in REAPER

## Out of Scope for v1.0
- Gain staging feature (deferred to future release)

## Timeline
Testing scheduled for next week.
