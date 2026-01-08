# ReaScript/ReaWrap MCP Server - Documentation Plan

## Purpose
Create an MCP (Model Context Protocol) server that provides **reference documentation** about REAPER development, ReaScript API, JSFX programming, and ReaWrap API. This serves as a lookup reference for factual information.

**Separate from this**: Agent skill for active debugging, pattern detection, and context-aware assistance.

## Division of Responsibilities

### MCP Server (This Plan)
**Static reference documentation**
- JSFX syntax and fundamentals
- ReaScript API function signatures and behavior
- ReaWrap API reference
- Core concepts (what is plink, containers, etc.)

### Agent Skill (Separate)
**Active, context-aware assistance**
- Debugging user's code issues
- Detecting common pitfalls in current codebase
- Suggesting patterns for current task
- Analyzing parameter mappings
- Container operation guidance
- "Why isn't X working" troubleshooting

## Repository Name
`reascript-reawrap-mcp` or `reaper-dev-mcp`

---

## MCP Documentation Categories

### 1. JSFX Fundamentals (`jsfx-fundamentals.md`)

**Purpose**: Core JSFX concepts that are non-obvious or commonly misunderstood

**Topics**:
- **Parameter Indexing** (CRITICAL)
  - Parameters are indexed by SLIDER NUMBER ORDER, not declaration order
  - Example: slider1, slider2, slider3, slider20, slider21, slider26, slider28, slider30
  - → param[0], param[1], param[2], param[3], param[4], param[5], param[6], param[7]
  - slider26 comes BEFORE slider28 in parameter index (12 vs 14)
  - Real example from SideFX_Modulator showing the bug and fix

- **Slider Visibility**
  - `-` prefix hides from JSFX UI but keeps functional
  - Example: `slider4:0<0,1,0.001>-Output` (hidden output param)

- **@sections**
  - @init: Run once on load
  - @slider: Run when slider changes
  - @block: Run once per audio block
  - @sample: Run for each sample
  - @gfx: Graphics/UI (optional)

- **Memory Management**
  - Local variables vs memory arrays
  - When to use which

**Code Examples**: Include real JSFX snippets showing correct parameter access

---

### 2. REAPER Parameter System (`parameter-system.md`)

**Purpose**: How REAPER's parameter system actually works

**Topics**:
- **Parameter Types**
  - Continuous (normalized 0.0-1.0)
  - Discrete/Switch (0, 1 for toggles; integer steps for enums)
  - When to use `TrackFX_SetParam` vs `set_param_normalized`

- **Reading Parameters**
  - `TrackFX_GetParam(track, fx, param_idx)` - returns raw value
  - `TrackFX_GetParamNormalized()` - returns 0.0-1.0
  - Discrete params: use raw value for switches/enums

- **Setting Parameters**
  - Discrete params: use `TrackFX_SetParam` with raw values (0, 1, 2, etc.)
  - Continuous params: can use normalized or raw
  - Common mistake: using normalized on discrete params causes wrong param to change

- **Named Config Parameters**
  - `TrackFX_GetNamedConfigParm` returns SINGLE value (buf or nil), not (retval, buf)
  - Used for: plink API, container info, FX-specific config
  - Common mistake: destructuring as two values

**Code Examples**: Correct vs incorrect parameter access patterns

---

### 3. Parameter Modulation (plink API) (`parameter-modulation.md`)

**Purpose**: REAPER's parameter linking system

**Topics**:
- **What is plink?**
  - REAPER's internal parameter modulation system
  - Format: `param.X.plink.active/effect/param/scale`
  - Used by: LFO plugins, modulators, parameter automation

- **Local vs Global FX Indices** (CRITICAL)
  - When both source and target are in SAME container: use LOCAL index (0, 1, 2...)
  - When in different containers or track: use GLOBAL index (0x2000000 + offset)
  - How to detect: compare parent container GUIDs
  - How to get local index: iterate container children, find by GUID, use position

- **Creating Links**
  - Set `param.X.plink.active` to "1"
  - Set `param.X.plink.effect` to source FX index (local or global)
  - Set `param.X.plink.param` to source parameter index
  - Set `param.X.plink.scale` to modulation amount

- **Reading Links**
  - Read `param.X.plink.active` - if not "1", no link
  - Read effect/param/scale values
  - Convert to numbers (returned as strings)

- **Real Bug Story**: Include the exact bug we hit and how we debugged it

**Code Examples**:
- Correct local index detection
- Creating/removing plink
- ReaWrap's high-level API vs raw

---

### 4. FX Container System (`fx-containers.md`)

**Purpose**: Working with container FX (racks, parallel chains)

**Topics**:
- **Container Pointers**
  - Track-level: 0, 1, 2...
  - Container children: 0x2000000 + local_index
  - Nested containers: 0x2000000 + (0x2000000 + ...)

- **Pointer Refresh**
  - When FX move, pointers change
  - Must refresh pointer after operations
  - Use GUID for stable identification

- **Adding FX to Containers**
  - Create at track level first
  - Store GUID
  - Move into container
  - Re-find by GUID (pointer changed)

- **Parent/Child Navigation**
  - `get_parent_container()`
  - `get_container_children()`
  - `is_container()`

**Code Examples**: Safe container manipulation patterns

---

### 5. ReaWrap API Reference (`reawrap-api.md`)

**Purpose**: Reference documentation for ReaWrap's API

**Topics**:
- **Object Model Overview**
  - Track, TrackFX, Item, Take classes
  - How objects wrap REAPER pointers
  - GUID-based identification

- **TrackFX Methods**
  - Standard wrapped methods (get_param, set_param, etc.)
  - Custom high-level methods (create_param_link, etc.)
  - Container-specific methods
  - Return value patterns

- **Track Methods**
  - FX enumeration and finding
  - Adding/removing FX
  - Container operations

- **Important Notes**
  - Return value conventions (single vs tuple)
  - Pointer refresh requirements
  - When objects become stale

**Code Examples**: Method signatures with actual return values

---

## MCP Server Structure

### Resources
Provide read-only documentation via `resources/list` and `resources/read`

```
resources://reascript/jsfx-fundamentals
resources://reascript/parameter-system
resources://reascript/parameter-modulation
resources://reascript/fx-containers
resources://reascript/reawrap-api
```

### Tools (Optional)
Could provide tools for:
- Looking up specific ReaScript function signatures
- Searching ReaWrap methods by name
- Quick parameter type reference

---

## Implementation Plan

### Phase 1: Core Documentation
1. Create repo structure
2. Write jsfx-fundamentals.md
3. Write parameter-system.md
4. Write parameter-modulation.md
5. Write fx-containers.md
6. Write reawrap-api.md

### Phase 2: MCP Server
7. Set up TypeScript/JavaScript MCP server
8. Implement resources endpoint
9. Test with Claude Desktop
10. Add to mcp.json configuration

### Phase 3: Agent Skill (Separate Implementation)
11. Create agent skill for REAPER development assistance
12. Implement debugging strategies
13. Implement common pitfall detection
14. Implement pattern suggestions
15. Test integration with MCP server

---

## Success Criteria

1. **No More Token Burn**: Stop rediscovering JSFX parameter indexing every session
2. **Fast Problem Solving**: Quick lookup for plink API, container indices
3. **Prevent Regressions**: Document all bugs so they're never repeated
4. **Reusable Knowledge**: Can be used across all REAPER projects
5. **Community Value**: Could be shared with REAPER dev community

---

## Next Steps

1. Review this plan - any missing knowledge areas?
2. Create repository
3. Start with Phase 1 (most critical docs first)
4. Test MCP server with Claude Desktop
5. Iterate based on actual usage
