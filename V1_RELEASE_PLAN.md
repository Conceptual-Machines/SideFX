# SideFX v1.0 Release Plan

## Overview
This document outlines the remaining features needed before SideFX v1.0 release. Features are prioritized as Essential (must have), Important (should have), or Nice-to-Have (can defer to v1.1).

---

## Essential Features (Must Complete)

### 1. Parameter Visibility System ⭐ HIGH PRIORITY
**Problem**: Plugins like Serum expose 400+ parameters, cluttering the UI.

**Solution A: Smart Parameter Selection (Default Hidden)**
- All parameters hidden by default
- "+ Add Parameter" button on each device
- Click → Shows modal with searchable parameter list
- Select parameters to show in device panel
- Store selection in `state.visible_params[fx_guid] = {1, 3, 5, ...}`

**Solution D: Plugin Editor (Advanced)**
- Right-click device → "Edit Parameters..."
- Opens dedicated editor window
- Full parameter list with checkboxes
- Drag to reorder visible parameters
- Save/load parameter layouts as presets

**Default Behavior**: First 8 parameters visible on new devices

**Implementation:**
- Files: `lib/core/state.lua`, `lib/ui/device/device_panel.lua`, `lib/ui/device/param_selector.lua`
- Estimated time: 6-8 hours
- Priority: **Essential** (biggest UX issue currently)

---

### 2. Auto Gain Staging ⚡
**Problem**: Cascading gain issues as effects change levels throughout chain.

**Solution**: Automated gain staging using utility output measurement
- Toolbar button: "⚡ Gain Stage"
- Measures output level at each utility (slider5)
- Calculates and applies compensating gain (slider1)
- Iterative: runs 2-3 times for convergence
- Default target: -12 dBFS (configurable)

**Workflow:**
1. User starts playback (signal required)
2. Clicks "⚡ Gain Stage" in toolbar
3. Dialog shows current levels and target
4. System measures → calculates → shows preview
5. User confirms → applies adjustments
6. Creates undo point

**Algorithm:**
```
For each utility:
  measured_db = 20 * log10(slider5)
  error_db = measured_db - target_db
  new_gain = current_gain - error_db
  Apply to slider1
Wait 200ms, repeat 2-3 times
```

**Implementation:**
- Files: `lib/utils/gain_staging.lua`, `lib/ui/main/toolbar.lua`
- Estimated time: 8-10 hours
- Priority: **Essential** (unique feature, core mixing workflow)
- See: `GAIN_STAGING_PLAN.md` for detailed design

---

### 3. Import Existing FX Chain
**Problem**: Users can't easily migrate existing REAPER chains into SideFX.

**Solution**: "Import Chain" button
- Scans track FX chain for non-container FX
- For each FX:
  - Creates D-container (Device wrapper)
  - Moves FX into container
  - Adds SideFX_Utility plugin
  - Sets utility to 0dB (neutral)
- Preserves FX order and settings
- Creates undo point

**UI Location**: Toolbar or context menu

**Implementation:**
- Files: `lib/import/chain_converter.lua`, `lib/ui/main/toolbar.lua`
- Estimated time: 4-5 hours
- Priority: **Essential** (onboarding, adoption barrier)

---

### 4. REAPER FX Chain Protection 🔒
**Problem**: User can inadvertently break SideFX structure by modifying chain in REAPER.

**Solution**: Warning system when SideFX window is open
- Store FX chain snapshot on window open
- Check every 500ms for changes:
  - FX count changed
  - Container names changed
  - FX order changed
- If detected:
  - Show warning banner at top of window
  - Options: "Revert Changes" or "Refresh SideFX"
- Optional: Soft lock (warn but don't block)

**Implementation:**
- Files: `lib/core/state.lua`, `lib/ui/main/main_window.lua`
- Estimated time: 3-4 hours
- Priority: **Essential** (data integrity, prevent corruption)

---

### 5. Keyboard Control Refinements ⌨️
**Problem**: Mouse-only parameter control is slow and imprecise.

**Solution**: Basic keyboard enhancements
- **Double-click slider**: Opens text input box
  - Type value → Enter to apply, Esc to cancel
- **Shift+drag**: Fine tuning (10x slower sensitivity)
- **Ctrl+click**: Reset to default value

**Implementation:**
- Files: `lib/ui/device/device_panel/params.lua`
- Estimated time: 2-3 hours
- Priority: **Essential** (basic workflow efficiency)

---

## Important Features (Should Complete)

### 6. Config Panel - Basic Settings
**Problem**: No way to customize SideFX behavior or appearance.

**Solution**: Settings dialog (gear icon in toolbar)
- **Display:**
  - Show/Hide Track Name (checkbox)
  - Show/Hide Breadcrumbs (checkbox)
  - Icon Font Size (slider: Small/Medium/Large)
- **Behavior:**
  - Auto-refresh on track change (checkbox)
  - Remember window position (checkbox)
- **Gain Staging:**
  - Default target level (slider: -24 to 0 dB)
  - Tolerance (slider: 0.5 to 3 dB)

**Storage**: ReaScript ExtState per project

**Implementation:**
- Files: `lib/ui/settings/settings_dialog.lua`, `lib/core/config.lua`
- Estimated time: 4-5 hours
- Priority: **Important** (user preferences)

---

### 7. Parameter Selector - Search & Filter
**Enhancement to Feature #1**

**Features:**
- Search box: Filter parameters by name
- Category filter: All / Control / Modulation / Mix / Output
- Sort options: Alphabetical / By Index / By Type
- "Show modified" toggle: Only show params that differ from default

**Implementation:**
- Part of `lib/ui/device/param_selector.lua`
- Estimated time: 2-3 hours (included in #1)
- Priority: **Important** (makes large param lists manageable)

---

### 8. Preset System - Chain Presets
**Problem**: Users can't save/recall entire device chain configurations.

**Solution**: Chain preset system
- Save button (💾) in toolbar
- Format: `.RfxChain` (REAPER) + `.sidefx.json` (metadata)
- Metadata stores:
  - Custom device names
  - Visible parameter selections
  - Modulator configurations
- Preset browser dropdown
- Load preset → Clears chain, loads new

**Implementation:**
- Files: `lib/presets/chain_presets.lua`, `lib/ui/main/toolbar.lua`
- Estimated time: 6-8 hours
- Priority: **Important** (shareability, workflow efficiency)

---

## Nice-to-Have Features (Can Defer)

### 9. Container Navigation & Breadcrumbs
**Status**: Plan written (see implementation plan from earlier conversation)
- Click rack/chain headers to navigate into them
- Breadcrumb trail updates automatically
- Filter view to show only current container
- Priority: **Nice-to-Have** (can be v1.1 feature)

### 10. Advanced Keyboard Shortcuts
- Tab/Shift+Tab: Navigate between parameters
- Arrow keys: Adjust value
- Home/End: Min/Max value
- Priority: **Nice-to-Have** (power user feature)

### 11. Compact Mode
- Smaller UI elements
- Reduced padding
- Compact device panels
- Priority: **Nice-to-Have** (screen real estate optimization)

---

## Development Roadmap

### Sprint 1: Core Functionality (Priority: Essential)
**Week 1-2:**
1. Parameter Visibility System (A + D) - 8 hours
2. Keyboard Control Refinements - 3 hours
3. Import Existing Chain - 5 hours

**Deliverable**: Users can manage parameter visibility and import chains

---

### Sprint 2: Gain Staging & Protection (Priority: Essential)
**Week 3:**
4. Auto Gain Staging - 10 hours
5. REAPER FX Chain Protection - 4 hours

**Deliverable**: Core mixing features complete, data integrity protected

---

### Sprint 3: Configuration & Polish (Priority: Important)
**Week 4:**
6. Config Panel - Basic Settings - 5 hours
7. Chain Presets System - 8 hours

**Deliverable**: User preferences, preset sharing

---

### Sprint 4: Testing & Documentation
**Week 5:**
- Comprehensive testing of all features
- User documentation
- Demo videos
- Bug fixes
- Performance optimization

---

## Release Criteria

### Must Have:
- ✅ All Essential features (#1-5) complete
- ✅ No critical bugs
- ✅ Basic documentation (README)
- ✅ Works on macOS (primary target)

### Should Have:
- Config panel
- Chain presets
- Windows compatibility testing

### Can Defer:
- Container navigation
- Advanced shortcuts
- Compact mode

---

## Feature Comparison: Current vs. v1.0

| Feature | Current | v1.0 |
|---------|---------|------|
| Device management | ✅ | ✅ |
| Rack/chain system | ✅ | ✅ |
| Modulator routing | ✅ | ✅ |
| Parameter visibility | ❌ Shows all | ✅ User selectable |
| Gain staging | ❌ Manual | ✅ Automated |
| Import existing chain | ❌ Manual rebuild | ✅ One-click import |
| FX chain protection | ❌ None | ✅ Warning system |
| Keyboard controls | ❌ Mouse only | ✅ Double-click, Shift |
| Config panel | ❌ None | ✅ Basic settings |
| Chain presets | ❌ None | ✅ Save/load |
| Container navigation | ❌ None | 🔄 Deferred to v1.1 |

---

## Testing Plan

### Feature Testing Matrix

| Feature | Unit Tests | Integration Tests | Manual QA |
|---------|-----------|-------------------|-----------|
| Parameter visibility | Mock param lists | Add/remove params | Serum, Vital |
| Gain staging | Calculation logic | Live measurement | Real chains |
| Import chain | FX detection | Container creation | Various plugins |
| Chain protection | Change detection | Warning display | User scenarios |
| Keyboard controls | Input handling | Param editing | All control types |

### Performance Benchmarks
- Large chains (50+ devices): < 60ms frame time
- Parameter visibility toggle: < 100ms
- Gain staging (3 iterations): < 1s
- Import chain: < 2s for 10 devices

---

## Risk Assessment

### High Risk:
1. **Gain staging accuracy**: Real-world measurement variability
   - Mitigation: Extensive testing with various signals
   - Fallback: Manual adjustment mode

2. **Parameter visibility storage**: State corruption
   - Mitigation: Validate stored param indices
   - Fallback: Reset to default (first 8 params)

### Medium Risk:
3. **FX chain protection**: False positives on valid operations
   - Mitigation: Smart detection (ignore benign changes)
   - Fallback: User can disable protection

4. **Import existing chain**: Complex chains with routing
   - Mitigation: Warn about unsupported features
   - Fallback: Manual conversion guide

### Low Risk:
5. **Keyboard controls**: ImGui compatibility
   - Mitigation: Test all control types
   - Fallback: Mouse-only for unsupported controls

---

## Post-Release (v1.1 Roadmap)

### User-Requested Features:
- Container navigation (if demand is high)
- Chain preset sharing (online library)
- Multi-track operations
- Template system
- Macro controls (map multiple params)

### Technical Debt:
- Performance optimization (virtual scrolling)
- Code cleanup (reduce duplication)
- Test coverage (increase to 80%)
- Documentation (API reference)

---

## Success Metrics

### v1.0 Release Goals:
- **Adoption**: 100 active users in first month
- **Stability**: < 1 crash per 100 hours of use
- **Workflow improvement**: 50% faster than manual chain building
- **User satisfaction**: 4+ stars average rating

---

## Timeline Summary

| Phase | Duration | Deliverable |
|-------|----------|-------------|
| Sprint 1 | 2 weeks | Core functionality |
| Sprint 2 | 1 week | Gain staging |
| Sprint 3 | 1 week | Config & presets |
| Sprint 4 | 1 week | Testing & docs |
| **Total** | **5 weeks** | **v1.0 Release** |

---

## Next Steps

1. ✅ Write implementation plan (this document)
2. ⏭️ Implement Parameter Visibility System (Feature #1)
3. ⏭️ Implement remaining Essential features (#2-5)
4. ⏭️ Testing & bug fixes
5. ⏭️ Documentation & release

---

**Last Updated**: 2026-01-09
**Status**: Planning Complete, Ready for Implementation
