# Fix for Brittle Nested Rack State Management

## Problem

When clicking to expand a chain in the **last nested rack** (deepest level), the parent rack would collapse. This was because all nested racks shared a single global state variable `expanded_nested_chain`.

### Root Cause

**Before:** Single global state variable
```lua
expanded_nested_chain = nil  -- Only ONE chain could be expanded globally
```

This meant:
- If Rack1 → Chain1 → Rack2 (nested) → Chain2
- Clicking Chain2 in Rack2 would set `expanded_nested_chain = chain2_guid`
- But Rack1 (parent) would check this same variable and see it doesn't match any of its chains
- Result: Parent rack would appear collapsed

### Example Scenario

```
R1 (top-level)
  └─ C1
      └─ R2 (nested rack)
          ├─ C2
          └─ C3
```

**Before:**
- Click C2 in R2 → `expanded_nested_chain = C2_guid`
- R1 checks `expanded_nested_chain` → doesn't match C1 → R1 collapses ❌

**After:**
- Click C2 in R2 → `expanded_nested_chains[R2_guid] = C2_guid`
- R1 checks `expanded_path[2]` → separate state → R1 stays expanded ✅

## Solution

Changed from single global variable to **per-rack dictionary**:

**After:** Keyed by rack GUID
```lua
expanded_nested_chains = {}  -- {[rack_guid] = chain_guid}
```

This allows:
- Each nested rack to track its own expanded chain independently
- Multiple nested racks at different levels to coexist
- Parent racks to maintain their own state separately

### Changes Made

1. **State variable** (`lib/state.lua`):
   ```lua
   -- Before
   expanded_nested_chain = nil
   
   -- After
   expanded_nested_chains = {}  -- {[rack_guid] = chain_guid}
   ```

2. **Chain click handler** (`SideFX.lua` - `draw_chain_row()`):
   ```lua
   -- Before
   state.expanded_nested_chain = chain_guid
   
   -- After
   local rack_guid = rack:get_guid()
   state.expanded_nested_chains[rack_guid] = chain_guid
   ```

3. **Chain selection check** (`SideFX.lua` - `draw_rack_panel()`):
   ```lua
   -- Before
   is_selected = (state.expanded_nested_chain == chain_guid)
   
   -- After
   local rack_guid = rack:get_guid()
   is_selected = (state.expanded_nested_chains[rack_guid] == chain_guid)
   ```

4. **Chain column display** (`SideFX.lua` - `draw_chain_column()`):
   ```lua
   -- Before
   if rack_data.is_expanded and state.expanded_nested_chain then
   
   -- After
   local rack_guid = dev:get_guid()
   local nested_chain_guid = state.expanded_nested_chains[rack_guid]
   if rack_data.is_expanded and nested_chain_guid then
   ```

5. **Chain deletion** (`SideFX.lua` - `draw_chain_row()`):
   ```lua
   -- Before
   state.expanded_nested_chain = nil
   
   -- After
   local rack_guid = rack:get_guid()
   state.expanded_nested_chains[rack_guid] = nil
   ```

## Testing

### Test Scenario

1. Create Rack1 (top-level)
2. Add Chain1 to Rack1
3. Add Rack2 inside Chain1 (nested rack)
4. Expand Rack2 to see its chains
5. Click a chain in Rack2 (deepest level)

### Expected Behavior

✅ Rack1 stays expanded (doesn't collapse)
✅ Rack2 stays expanded
✅ Chain in Rack2 expands to show devices
✅ All levels can coexist independently

### Previous Behavior

✗ Rack1 would collapse when clicking chain in Rack2
✗ Only one nested rack chain could be expanded at a time
✗ Deep nesting would break parent rack state

## Files Modified

1. `lib/state.lua`: Changed state variable from single value to dictionary
2. `SideFX.lua`: Updated all references to use per-rack state lookup

## Benefits

- ✅ **Robust**: Each rack maintains independent state
- ✅ **Scalable**: Supports arbitrary nesting depth
- ✅ **Isolated**: Parent racks unaffected by nested rack changes
- ✅ **Correct**: Matches the mental model of nested containers

## Related

This fix works together with:
- ReaWrap stale pointer fix (backend)
- Original nested rack UI fix (frontend)

All three fixes are required for full nested rack functionality.

