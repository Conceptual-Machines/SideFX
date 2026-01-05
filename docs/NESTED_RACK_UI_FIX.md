# Nested Rack UI Fix - Chain Expansion

## Problem

When clicking a chain inside a nested rack (e.g., R2 inside R1), the UI would collapse the parent rack (R1) instead of expanding to show the chain's devices.

### Root Cause

The chain click handler used `expanded_path[2]` for all chains, but this state variable is designed for top-level racks only. Nested racks need separate state management to avoid conflicts.

## Solution

### 1. Added New State Variable

**File: `lib/state.lua`**

Added `expanded_nested_chain` to track which chain is selected in nested racks:

```lua
-- Expanded chain in nested rack (separate from expanded_path to avoid conflicts)
expanded_nested_chain = nil,  -- chain GUID
```

### 2. Updated Chain Row Handler

**File: `SideFX.lua` - `draw_chain_row()`**

- Added `is_nested_rack` parameter to know if the chain belongs to a nested rack
- Use `expanded_nested_chain` for nested rack chains
- Use `expanded_path[2]` for top-level rack chains (existing behavior)

```lua
if is_nested_rack then
    -- Nested rack chain: use expanded_nested_chain
    state.expanded_nested_chain = chain_guid
else
    -- Top-level rack chain: use expanded_path[2]
    state.expanded_path[2] = chain_guid
end
```

### 3. Updated Chain Column Display

**File: `SideFX.lua` - `draw_chain_column()`**

When drawing nested racks in chain columns, check if a chain is selected and display its devices:

```lua
if rack_data.is_expanded and state.expanded_nested_chain then
    local nested_chain = find_chain_by_guid(state.expanded_nested_chain)
    if nested_chain then
        ctx:same_line()
        draw_chain_column(ctx, nested_chain, rack_data.rack_h)
    end
end
```

### 4. Updated Chain Deletion

When deleting a chain, clear the appropriate state variable based on whether it's nested or not.

## Testing

### Test Scenario

1. Create a rack (R1) in SideFX
2. Add a chain (R1_C1) to R1
3. Add a nested rack (R2) inside R1_C1
4. Expand R2 to show its chains
5. Click on a chain in R2 (e.g., R2_C1)

### Expected Behavior

✅ R2 should stay expanded
✅ R2_C1's devices should appear in a new column to the right
✅ You can add plugins to R2_C1
✅ Clicking R2_C1 again should collapse it

### Previous Behavior

✗ R1 would collapse
✗ R2 would disappear from view
✗ No way to access nested chain devices

## Files Modified

1. `SideFX.lua`:
   - `draw_chain_row()` - Added `is_nested_rack` parameter
   - Chain click handling - Use `expanded_nested_chain` for nested racks
   - `draw_chain_column()` - Display nested chain column when selected
   - Chain deletion - Clear appropriate state variable

2. `lib/state.lua`:
   - Added `expanded_nested_chain` state variable

## Backward Compatibility

✅ Top-level rack behavior unchanged
✅ Existing state management preserved
✅ No breaking changes

## Related Fix

This UI fix works together with the ReaWrap fix for stale pointers:
- ReaWrap handles the backend (adding FX to nested containers)
- This fix handles the frontend (displaying nested chain devices)

Both fixes are required for full nested rack functionality.

