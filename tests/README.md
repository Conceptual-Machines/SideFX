# SideFX Test Suite

Comprehensive test suite for SideFX with unit tests (using mocks) and integration tests (running in REAPER).

## Test Structure

```
tests/
├── assertions.lua          # Assertion utilities
├── runner.lua              # Unit test runner (standalone)
├── mock/
│   └── reawrap.lua        # Mock ReaWrap classes for unit tests
├── unit/                   # Unit tests (standalone, use mocks)
│   ├── test_naming.lua
│   ├── test_patterns.lua
│   ├── test_rack.lua
│   ├── test_rack_recursive.lua  # Tests recursive container operations
│   └── test_state.lua     # Tests state management
└── integration/            # Integration tests (run in REAPER)
    ├── run_all.lua        # Run all integration tests
    ├── test_containers.lua
    ├── test_racks.lua
    ├── test_edge_cases.lua       # Edge cases and weird scenarios
    ├── test_state_management.lua # UI state management tests
    ├── test_deeply_nested.lua    # Deeply nested rack operations
    └── test_modulators.lua       # Modulator operations
```

## Running Tests

### Unit Tests (Standalone)

Run unit tests outside of REAPER using the test runner:

```bash
cd SideFX
lua tests/runner.lua
```

These tests use mocked ReaWrap classes and don't require REAPER to be running.

**Test Coverage:**
- Naming conventions and parsing
- **Hierarchical naming functions** (general path extraction and name building)
- Pattern matching
- Basic rack operations
- **Recursive container operations** (path building, nested additions)
- **State management** (expanded_path, expanded_racks independence)

### Integration Tests (REAPER)

Integration tests must be run inside REAPER as ReaScript actions. They test actual FX manipulation and container operations.

**To run all integration tests:**
1. Load `tests/integration/run_all.lua` as a ReaScript action in REAPER
2. Or run individual test files:
   - `tests/integration/test_containers.lua` - Basic container operations
   - `tests/integration/test_racks.lua` - Rack and chain operations
   - `tests/integration/test_edge_cases.lua` - Edge cases and weird scenarios
   - `tests/integration/test_state_management.lua` - State management
   - `tests/integration/test_deeply_nested.lua` - Deeply nested rack operations
   - `tests/integration/test_modulators.lua` - Modulator operations

**Test Coverage:**

#### Basic Operations
- Rack creation and management
- Chain creation and management
- Device addition to chains
- Nested rack creation

#### Edge Cases (`test_edge_cases.lua`)
- **Regression: Adding device to empty nested rack** (tests the "pop-out" bug fix)
- Deep nesting (5+ levels: rack → chain → rack → chain → rack)
- Adding multiple devices to deeply nested chains
- Adding racks to chains that already have devices
- Concurrent additions (multiple racks to same chain)
- Operations on empty chains in nested racks
- Rack index generation after nested additions

#### State Management (`test_state_management.lua`)
- Nested rack expansion state independence from parent
- Multiple nested racks with independent expansion state
- Deep nesting state preservation
- State persistence across FX list refresh

#### Modulator Operations (`test_modulators.lua`)
- Adding modulator to device container
- Retrieving modulators from device container
- Verifying modulators appear inside container (not at track level)
- Modulator deletion and cleanup
- Modulator in nested device (Rack → Chain → Device)
- GUID-based refinding after container operations
- Parent-child relationship verification
- Hierarchical naming convention (D1_M1, R1_C1_D1_M1, etc.)

## Test Utilities

### Assertions

The `assertions.lua` module provides:
- `assert.truthy(condition, message)` - Assert condition is true
- `assert.falsy(condition, message)` - Assert condition is false
- `assert.equals(expected, actual, message)` - Assert equality
- `assert.not_equals(expected, actual, message)` - Assert inequality
- `assert.is_nil(value, message)` - Assert value is nil
- `assert.not_nil(value, message)` - Assert value is not nil
- `assert.is_type(type, value, message)` - Assert type
- `assert.contains(str, substring, message)` - Assert string contains substring
- `assert.matches(str, pattern, message)` - Assert string matches pattern
- `assert.length(expected, table, message)` - Assert table length
- `assert.throws(fn, message)` - Assert function throws error
- `assert.no_throw(fn, message)` - Assert function doesn't throw
- `assert.section(name)` - Mark a new test section

### Mock System

The mock ReaWrap system (`mock/reawrap.lua`) provides:
- **TrackFX** class with full container support
- **Track** class with FX chain management
- **Project** class for project-level operations
- Proper parent-child relationship tracking
- Recursive GUID lookup support
- Container move operations (move_out_of_container, add_fx_to_container)

## Writing New Tests

### Unit Test Example

```lua
--- Unit test example
local assert = require("assertions")
local mock_reawrap = require("mock.reawrap")

local M = {}

local function test_something()
    assert.section("Test something")

    -- Setup
    mock_reawrap.reset()
    local track = mock_reawrap.add_track({ name = "Test" })

    -- Test
    -- ... your test code ...

    -- Assert
    assert.truthy(something, "Something should be true")
end

function M.run()
    test_something()
end

return M
```

### Integration Test Example

```lua
--- Integration test example
local assert = require("assertions")
local rack_module = require("lib.rack")

local test_track = nil

local function setup_test_track()
    r.Undo_BeginBlock()
    r.InsertTrackAtIndex(0, false)
    local track_ptr = r.GetTrack(0, 0)
    test_track = Track:new(track_ptr)
    return test_track
end

local function cleanup_test_track()
    if test_track then
        r.DeleteTrack(test_track.pointer)
    end
    r.Undo_EndBlock("Test", -1)
end

local function test_something()
    assert.section("Test something")

    setup_test_track()

    -- Test
    local rack = rack_module.add_rack_to_track()
    assert.not_nil(rack, "Rack should be created")

    cleanup_test_track()
end

-- Run
run_all_tests()
```

## Test Categories

### Unit Tests
- Fast (no REAPER dependency)
- Isolated (use mocks)
- Test specific functions/modules
- Focus on logic and edge cases

### Integration Tests
- Real REAPER operations
- Test complete workflows
- Test complex scenarios
- Verify actual behavior

## Edge Cases Covered

1. **Deep Nesting**: Racks nested 5+ levels deep
2. **Empty Containers**: Operations on empty chains/racks
3. **Concurrent Operations**: Multiple additions in sequence
4. **State Independence**: Nested rack expansion state
5. **Hierarchy Preservation**: Verify parent-child relationships after operations
6. **GUID Persistence**: Verify GUIDs remain valid across operations
7. **Index Generation**: Rack index generation in nested scenarios

## Notes

- Integration tests create test tracks named `_SideFX_*` - these can be safely deleted
- All integration tests use `Undo_BeginBlock` / `Undo_EndBlock` for easy cleanup
- Tests are designed to be idempotent (can be run multiple times)
- Mock system properly tracks parent-child relationships for recursive operations
