# SideFX v1.0 Release Plan

## Overview
Final tasks before v1.0 release. No gain staging in this release.

## Tasks

### 1. Settings Dialog Updates
- [ ] Remove gain staging section from settings
- [ ] Add Bake Settings section:
  - Disable link after bake (checkbox, default: true)
  - Default range mode (dropdown: Project/Track/Time Selection/Selected Items)
  - Show range picker modal (checkbox, default: true)

### 2. UI Improvements
- [ ] Shift-key fine tuning for all slider controls
  - Hold Shift for finer adjustment (0.1x or 0.01x multiplier)
- [ ] Display parameter values on controls
  - Show current value tooltip or inline text

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

## Out of Scope for v1.0
- Gain staging feature (deferred to future release)

## Timeline
Testing scheduled for next week.
