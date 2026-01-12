# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SideFX is a REAPER 7+ script that provides Ableton/Bitwig-style rack FX management with horizontal device chains, parallel routing, and modulator-based parameter automation. Built using Lua, ReaScript, ImGui, and custom JSFX plugins.

## Development Commands

### Testing
```bash
# Run all unit tests (standalone, no REAPER required)
lua5.4 tests/runner_luaunit.lua
```

### Linting
```bash
# Run Luacheck with project config
luacheck . --config .luacheckrc
```

### CI/CD
- CI runs on push/PR to main/master/develop branches
- Tests: `lua5.4 tests/runner_luaunit.lua`
- Linting: `luacheck . --config .luacheckrc`
- Release workflow auto-tags based on version in `SideFX.lua`

## High-Level Architecture

### Entry Point & Dependencies
- **SideFX.lua**: Main entry point, sets up paths and loads dependencies
- **Dependency Loading Order** (CRITICAL):
  1. EmojImGui loaded FIRST with ReaImGui's builtin path
  2. Clear `package.loaded['imgui']` cache
  3. Load ReaWrap paths (shadows ReaImGui's imgui with ReaWrap's wrapper)
  4. This prevents imgui namespace conflicts between ReaWrap and ReaImGui

### External Dependencies
- **ReaWrap** (`/Users/Luca_Romagnoli/Code/personal/ReaScript/ReaWrap`): OOP wrapper over REAPER API
  - Located at: `../ReaWrap/` (dev) or `Scripts/ReaWrap/Libraries/lua/` (ReaPack)
  - Provides: `Project`, `Track`, `TrackFX`, `imgui.Window`, etc.
  - Use ReaWrap methods (e.g., `fx:get_name()`) instead of raw REAPER API calls
- **ReaImGui**: ImGui bindings for REAPER UI
- **EmojImGui**: Icon/emoji support for UI elements

### Container Hierarchy System
SideFX uses REAPER's Container FX with naming conventions to create nested structures:

1. **D-containers (Devices)**: `D{n}: Plugin Name`
   - Wraps individual plugins (instruments, effects)
   - Contains plugin + optional SideFX_Utility JSFX (for pre/post gain, routing)
   - Created by `device.lua:add_plugin_to_track()`

2. **R-containers (Racks)**: `R{n}`
   - Top-level parallel processing racks
   - Contains: SideFX_Mixer JSFX + multiple C-containers (chains)
   - Mixer has 16 chain slots with individual volume/pan controls
   - Created by `rack.lua:create_rack_from_selection()`

3. **C-containers (Chains)**: `C{n}` (within racks)
   - Parallel chains within a rack
   - Each chain has independent FX chain routed to mixer
   - Created automatically when rack is created

4. **Modulators**: SideFX_Modulator JSFX (unwrapped, no D-container)
   - LFO-based parameter automation using REAPER parameter links (plinks)
   - Must be in same container as target FX for modulation to work
   - Auto-moved into target container when creating parameter links

### Core Modules

**State Management** (`lib/state.lua`):
- Centralized `state` table singleton
- Tracks: selected track, FX list, UI state (expanded paths, selections, rename state)
- Plugin browser state (search, filter, cached plugin list)
- Modulator state (discovered modulators, link selections, parameter link mappings)

**Operations** (`lib/`):
- `rack.lua`: Create R-containers with mixer and parallel chains
- `device.lua`: Add plugins wrapped in D-containers
- `container.lua`: General container operations (navigation, utilities)
- `modulator.lua`: Discover modulators, create/delete parameter links
- `browser.lua`: Scan and filter available plugins
- `fx_utils.lua`: FX type detection (is_mixer, is_utility, is_modulator, etc.)
- `naming.lua`: Generate consistent container names (D{n}, R{n}, C{n} patterns)

**UI Rendering** (`lib/ui/`):
- `rack/rack_ui.lua`: Main UI orchestration, horizontal scrolling device chain
- `device/device_panel.lua`: Collapsible device panels with inline parameter controls
- `device/modulator_panel.lua`: Modulator UI with link management (per-device modulators)
- `main/browser_panel.lua`: Plugin search/filter browser
- `main/toolbar.lua`: Top action bar (add device, add modulator, create rack)
- `common/widgets.lua`: Reusable UI components

**JSFX Plugins** (`jsfx/`):
- `SideFX_Mixer.jsfx`: 16-chain mixer for rack parallel routing
- `SideFX_Utility.jsfx`: Pre/post gain, routing controls (in device containers)
- `SideFX_Modulator.jsfx`: Bezier curve LFO with parameter link output

### Critical Concepts

#### FX Index Instability
- Moving FX between containers invalidates indices
- **Always**: Store GUID before move → perform move → re-find by GUID
- Use `track:find_fx_by_guid(guid)` to locate FX after structural changes
- See `modulator.lua:174-191` for reference implementation

#### Parameter Link Index Semantics (REAPER plinks)
- **Top-level FX**: Use direct track FX index (0, 1, 2, etc.)
- **Nested FX in same container**: Use LOCAL container-relative index (0, 1, 2, etc.)
- **Nested FX in different containers**: Use encoded global index
- When creating plink: `TrackFX_SetNamedConfigParm(track, target_fx_idx, "plink.X:Y", "B:A")`
  - Where X = modulator's container-local index, Y = modulator param, A = target param
- Bug fix context: See AGENT_HANDOFF.md lines 28-58 for detailed explanation

#### ReaWrap Container Methods
```lua
fx:get_parent_container()           -- Get container FX is nested in
container:get_container_children()  -- Get array of child FX (1-indexed Lua array)
container:add_fx_to_container(fx, pos)  -- Move FX into container
track:find_fx_by_guid(guid)         -- Find FX by GUID (stable across moves)
fx:is_container()                   -- Check if FX is a container
```

#### UI State Persistence
- State saved via `ExtState` API (not in project file)
- Keyed by track GUID for per-track state
- Saved on: FX changes, expand/collapse, rename operations
- Debounced to avoid excessive saves (frame-based throttling)

## Testing Strategy

### Unit Tests (`tests/unit/`)
- Use mocked ReaWrap classes (`tests/mock/reawrap.lua`)
- Test modules in isolation (naming, patterns, rack logic, state management)
- Run standalone without REAPER: `lua5.4 tests/runner.lua`

### Integration Tests (`tests/integration/`)
- Require REAPER environment (not run in CI)
- Test actual FX operations, container creation, deeply nested structures

## Important Files Reference

**When modifying parameter controls:**
- `lib/ui/device/device_panel.lua` - Pattern reference for control rendering (sliders, toggles, dropdowns)
- `lib/ui/device/modulator_panel.lua` - Modulator parameter controls (device-specific modulators)
- JSFX files in `jsfx/` - Add "-" prefix to hide parameters from JSFX UI

**When modifying container/FX operations:**
- `lib/modulator/modulator.lua` - Parameter link creation (lines 140-200 especially)
- `lib/rack/rack.lua` - Rack creation logic
- `lib/device/device.lua` - Device container wrapping

**When debugging:**
- `debug_check_plinks.lua` - Inspect actual parameter link values in REAPER

## Code Patterns

### API Usage: Prefer ReaWrap Over Raw REAPER API

**General Rule**: Use ReaWrap's OOP wrappers instead of raw REAPER API calls wherever possible.

**Why ReaWrap:**
- Cleaner, more maintainable code (object-oriented vs procedural)
- Type safety and better error handling
- Consistent API across the codebase
- Easier to test (mock objects vs raw functions)

**Examples:**
```lua
-- ❌ Raw API (avoid)
local fx_name = reaper.TrackFX_GetFXName(track_pointer, fx_idx, "")
local param_count = reaper.TrackFX_GetNumParams(track_pointer, fx_idx)

-- ✅ ReaWrap (preferred)
local fx_name = fx:get_name()
local param_count = fx:get_num_params()
```

**When Raw API is Acceptable:**
- Quick prototyping/debugging during development
- ReaWrap doesn't have a wrapper for the specific API call yet
- Performance-critical hot paths (see below)

**Performance Considerations:**

ReaWrap adds minimal overhead (~1-2 extra Lua function calls per operation). This is negligible for:
- UI interactions (button clicks, user actions) - humans operate at ~100ms scale
- One-off operations (scanning plugins, creating containers)
- Typical UI rendering at 30-60 FPS

However, ReaWrap overhead *might* be measurable in hot paths:
- **Per-frame FX iteration**: Looping through all FX every frame (10-100+ FX × 60 FPS = thousands of calls/sec)
- **Tight loops with many API calls**: Processing large datasets in Lua (rare in this codebase)

**Profile before optimizing:**
1. Use ReaWrap by default (maintainability > premature optimization)
2. If performance issues arise, profile to identify actual bottlenecks
3. Only switch to raw API if profiling shows ReaWrap calls dominating execution time
4. Document the reason with a comment explaining the performance requirement

**Refactoring Guidelines:**
- When touching existing code with raw API calls, refactor to ReaWrap if feasible
- New code should always use ReaWrap unless there's a specific reason not to
- If using raw API for performance, add a comment: `-- Raw API for performance (profiled)`
- Consider batching operations or caching instead of raw API as first optimization

### Safe FX Operations
```lua
-- Wrap in pcall to handle deleted FX gracefully
local ok, name = pcall(function() return fx:get_name() end)
if ok and name then
    -- use name
end
```

### Undo Blocks
```lua
r.Undo_BeginBlock()
r.PreventUIRefresh(1)
-- operations here
r.PreventUIRefresh(-1)
r.Undo_EndBlock("Action Name", -1)
```

### UI Refresh After State Changes
```lua
state_module.invalidate_fx_list()  -- Mark for refresh
state_module.save_state_if_needed()  -- Persist to ExtState
```

## Git Workflow

- Feature branches off `main`
- Pre-commit hooks: trailing whitespace, EOF fixer, no direct commits to main
- Commit messages: Conventional format with emoji footer + Co-Authored-By
- CI runs on push to main/master/develop
