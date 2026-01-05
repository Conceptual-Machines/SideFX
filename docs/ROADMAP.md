# SideFX Roadmap

## Current Status

SideFX is a visual FX chain manager for REAPER with:
- Column-based UI (Miller columns style) for FX chain navigation
- Plugin browser with VST/AU/JS tabs
- Container support (create, add to, remove from)
- Drag-and-drop FX management
- Per-FX bypass and wet/dry controls
- Multi-select with shift-click
- Dockable window

---

## Planned Features

### High Priority

#### 1. Style Background and Borders Based on REAPER Theme
- Read REAPER theme colors via API
- Apply theme colors to window background, borders, and UI elements
- Ensure visual consistency with user's REAPER setup

#### 2. Rename Option for Chains, Instruments, and FX
- Right-click menu option to rename
- Inline text editing in the FX list
- Persist custom names (via FX named config params or project data)

#### 3. Dissolve Container (Remove Container)
- Move all children one level up (to parent container or main chain)
- Delete the empty container
- Wrap entire operation in single undo block
- **Status**: Partially implemented, needs debugging for nested containers

### Medium Priority

#### 4. Smart Container / Parallel Routing
- For plugins like Serum2 that block the audio signal
- Route channels to separate outputs and mix them back
- Visual distinction (different icon or color)
- Menu option to enable/disable parallel mode
- Consider automatic detection if possible

#### 5. Multiband Splitter Routing Option
- Add multiband splitter as a routing option for containers
- Split signal into frequency bands
- Route each band through container's FX chain
- Mix bands back together at output

#### 6. Save/Load Chain Presets
- Save entire FX chains (including containers) as presets
- Load presets to recreate chain structure
- Store in REAPER resource path or custom location
- Import/export as files

### Low Priority

#### 7. Parameter Modulation System
- Design phase: define how modulation will work
- Consider LFO, envelope, MIDI CC sources
- Visual parameter linking interface
- Real-time modulation display

#### 8. Group Plugins by Manufacturer or Style
- Alternative grouping options in plugin browser
- Filter by manufacturer, category, or custom tags
- Remember user preferences

---

## Known Issues

### Container Operations
- Nested container addressing needs refinement (ReaWrap dependency)
- TrackFX objects become stale after move operations - must re-lookup by GUID
- Dissolve container may not work correctly for deeply nested structures

### UI/UX
- Horizontal scrollbar visibility could be improved
- Column widths are currently fixed

---

## Dependencies

- **ReaWrap**: OOP wrapper for ReaScript (v0.6.2+)
  - Container operations (`add_fx_to_container`, `move_out_of_container`)
  - FX iteration and GUID-based lookup
- **ReaImGui**: ImGui bindings for REAPER
- **EmojImGui**: Emoji/icon support for ReaImGui

---

## Contributing

When implementing new features:
1. Always use ReaWrap abstractions, not raw REAPER API
2. Store FX GUIDs before operations, re-lookup after
3. Wrap destructive operations in undo blocks (`with_undo()`)
4. Test with nested containers
5. Ensure UI refreshes correctly after external changes

