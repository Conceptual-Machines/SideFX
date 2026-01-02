# SideFX C++ Rewrite Plan

## Overview

Rewrite SideFX as a pure C++ REAPER extension with ImGui UI. This replaces the Lua-based SideFX.lua with a native extension that includes both FX chain management and the modulation engine.

## Current State

### What Exists (extension/ folder)
- **Modulation engine** - Working!
  - `modulator.h/cpp` - Modulator class with Bezier curves, triggers, recording
  - `bezier.h` - Cubic Bezier math and preset shapes
  - `audio_hook.cpp` - Sample-accurate parameter updates
  - `main.cpp` - REAPER plugin entry, action registration
- **Audio hook** - Active and working
- **Test action** - "SideFX: Test Modulation Engine" in Actions list

### What Failed
- Lua API binding via `plugin_register("API_*")` - Functions register but aren't accessible to ReaScript

### Reference
- `magda-reaper/` - Shows how to use ReaImGui from C++
- `SideFX.lua` - Reference for UI/UX to replicate

---

## Architecture

```
reaper_sidefx.dylib
├── Core
│   ├── main.cpp              - Plugin entry, window management
│   ├── sidefx_state.h/cpp    - Global state, selected track, preferences
│   └── reaper_api.h          - REAPER function pointer declarations
│
├── FX Chain
│   ├── fx_chain.h/cpp        - FX/container traversal, manipulation
│   ├── fx_drag_drop.h/cpp    - Drag & drop logic
│   └── plugin_browser.h/cpp  - Plugin list, search, favorites
│
├── Modulation (existing)
│   ├── modulator.h/cpp       - Modulator state management
│   ├── bezier.h              - Curve math
│   └── audio_hook.h/cpp      - Real-time parameter updates
│
└── UI (ImGui via ReaImGui)
    ├── ui_main_window.h/cpp  - Main SideFX window
    ├── ui_fx_column.h/cpp    - FX chain column rendering
    ├── ui_modulator.h/cpp    - Modulator panel
    ├── ui_curve_editor.h/cpp - Bezier curve visual editor
    └── ui_theme.h            - Colors, styling constants
```

---

## Implementation Phases

### Phase 1: UI Foundation
**Goal**: Basic ImGui window that shows selected track info

1. Set up ReaImGui function pointer loading (copy pattern from magda)
2. Create main window with `ImGui_CreateContext`, `ImGui_Begin/End`
3. Show selected track name
4. Register REAPER action to open/close window

**Files to create**:
- `include/ui/sidefx_window.h`
- `src/ui/sidefx_window.cpp`
- `include/reaimgui_api.h` - Function pointer declarations

**Reference**: `magda-reaper/src/ui/magda_imgui_settings.cpp`

---

### Phase 2: FX Chain Display
**Goal**: Display FX chain like SideFX.lua does

1. Get track FX list via REAPER API
2. Detect containers and nested structure
3. Render as columns (one per container depth)
4. Show FX name, enabled state, wet/dry

**REAPER APIs needed**:
- `TrackFX_GetCount`, `TrackFX_GetFXName`
- `TrackFX_GetNamedConfigParm` (for container detection)
- `TrackFX_GetEnabled`, `TrackFX_GetParamNormalized`

**Reference**: `SideFX.lua` lines 200-400 (container logic)

---

### Phase 3: FX Interactions
**Goal**: Full FX manipulation

1. Bypass toggle button
2. Wet/dry slider
3. Right-click context menu (rename, delete, move to container)
4. Double-click to open FX window
5. Drag & drop reordering

**REAPER APIs needed**:
- `TrackFX_SetEnabled`, `TrackFX_SetParamNormalized`
- `TrackFX_Delete`, `TrackFX_CopyToTrack`
- `TrackFX_Show`

---

### Phase 4: Plugin Browser
**Goal**: Add plugins to track

1. Get installed plugins list
2. Search/filter
3. Drag to FX chain or double-click to add
4. Favorites system (saved to config)

**REAPER APIs needed**:
- `EnumInstalledFX`
- `TrackFX_AddByName`

---

### Phase 5: Modulator UI
**Goal**: Visual interface for modulation engine

1. Modulator list panel
2. Create/delete modulators
3. Settings panel (rate, depth, offset, trigger mode)
4. Target FX parameter picker

**Already have**: Modulator core in `modulator.h/cpp`

---

### Phase 6: Bezier Curve Editor
**Goal**: Visual curve editing

1. Canvas with curve preview
2. Draggable control points
3. Preset buttons (sine, saw, square, etc.)
4. Real-time preview of modulation

**Implementation**:
- Use `ImGui_DrawList_*` functions for custom rendering
- Hit testing for control point dragging
- Smooth curve rendering with line segments

---

### Phase 7: Automation Recording
**Goal**: Print modulation to track automation

1. Record button starts capturing values
2. Stop/print writes to FX parameter envelope
3. Preview recorded curve before committing

**Already have**: Recording logic in `modulator.h`, just need UI

---

## Technical Notes

### ReaImGui Function Access
```cpp
// In initialization
m_ImGui_CreateContext = (void*(*)(const char*, int*))rec->GetFunc("ImGui_CreateContext");
m_ImGui_Begin = (bool(*)(void*, const char*, bool*, int*))rec->GetFunc("ImGui_Begin");
// ... etc

// Usage
void* ctx = m_ImGui_CreateContext("SideFX", nullptr);
if (m_ImGui_Begin(ctx, "SideFX", &open, nullptr)) {
    m_ImGui_Text(ctx, "Hello World");
}
m_ImGui_End(ctx);
```

### Window Lifecycle
- Create context once on action trigger
- Run UI in deferred callback loop
- Destroy context when window closes

### Container Detection (from SideFX.lua)
```cpp
// Check if FX is a container
char buf[64];
TrackFX_GetNamedConfigParm(track, fx_idx, "container_count", buf, sizeof(buf));
int container_count = atoi(buf);
bool is_container = container_count > 0;
```

### Drag & Drop
Use ImGui's built-in drag/drop:
```cpp
if (ImGui_BeginDragDropSource(ctx, 0)) {
    ImGui_SetDragDropPayload(ctx, "FX_ITEM", &fx_data, sizeof(fx_data));
    ImGui_Text(ctx, fx_name);
    ImGui_EndDragDropSource(ctx);
}
```

---

## File Structure After Rewrite

```
SideFX/
├── extension/
│   ├── CMakeLists.txt
│   ├── Makefile
│   ├── include/
│   │   ├── modulator.h         (existing)
│   │   ├── bezier.h            (existing)
│   │   ├── audio_hook.h        (existing)
│   │   ├── reaimgui_api.h      (new)
│   │   ├── sidefx_state.h      (new)
│   │   └── ui/
│   │       ├── sidefx_window.h
│   │       ├── fx_column.h
│   │       ├── modulator_panel.h
│   │       ├── curve_editor.h
│   │       └── theme.h
│   └── src/
│       ├── main.cpp            (existing, modified)
│       ├── modulator.cpp       (existing)
│       ├── audio_hook.cpp      (existing)
│       ├── sidefx_state.cpp    (new)
│       └── ui/
│           ├── sidefx_window.cpp
│           ├── fx_column.cpp
│           ├── modulator_panel.cpp
│           └── curve_editor.cpp
├── PLAN_CPP_REWRITE.md         (this file)
└── ROADMAP.md                  (update when done)
```

---

## Dependencies

- REAPER SDK (existing symlink)
- WDL (existing symlink)
- ReaImGui extension (must be installed in REAPER)

---

## Testing Strategy

1. **Phase 1**: Window opens/closes, shows track name
2. **Phase 2**: FX list matches REAPER's FX chain
3. **Phase 3**: All interactions work (bypass, wet/dry, etc.)
4. **Phase 4**: Can add plugins from browser
5. **Phase 5**: Modulator controls FX parameters
6. **Phase 6**: Curve editor updates modulator shape
7. **Phase 7**: Automation prints correctly

---

## Estimated Effort

| Phase | Description | Complexity |
|-------|-------------|------------|
| 1 | UI Foundation | Low |
| 2 | FX Chain Display | Medium |
| 3 | FX Interactions | Medium |
| 4 | Plugin Browser | Medium |
| 5 | Modulator UI | Medium |
| 6 | Curve Editor | High |
| 7 | Automation | Low |

---

## Starting Point

Begin with Phase 1. First task:
1. Create `include/reaimgui_api.h` with function pointer declarations
2. Create `src/ui/sidefx_window.cpp` with basic window
3. Modify `main.cpp` to load ReaImGui functions and open window on action

Use `magda-reaper/src/ui/magda_imgui_settings.cpp` as reference for the pattern.

