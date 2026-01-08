# MCP SERVER CONFIGURATION - READ THIS FIRST

## CRITICAL: If you don't see MCP tools available, the user will be VERY frustrated

This has been fixed **10+ times** across sessions. Do NOT suggest editing config files again.

## Current Status (as of 2026-01-07)

**BOTH config files are now CORRECTLY configured with stdio transport:**

1. `/Users/Luca_Romagnoli/.claude/.mcp.json` ✅ CORRECT
2. `/Users/Luca_Romagnoli/.config/claude-code/mcp.json` ✅ CORRECT (just fixed)

Both files contain:
```json
{
  "mcpServers": {
    "reaper-dev": {
      "command": "npx",
      "args": ["-y", "reaper-dev-mcp"]
    }
  }
}
```

## What the MCP Server Provides

The `reaper-dev-mcp` server (at `/Users/Luca_Romagnoli/Code/personal/ReaScript/reaper-dev-mcp`) provides:

### Tools:
- `get_function_info` - Look up ReaScript, JSFX, or ReaWrap function details
- `search_functions` - Search across APIs

### Resources:
- `reascript://jsfx-fundamentals` - Core JSFX concepts
- `reascript://parameter-system` - REAPER parameter system
- `reascript://parameter-modulation` - Parameter linking (plink API)
- `reascript://fx-containers` - FX container system
- `reascript://reawrap-api` - ReaWrap API reference

## If MCP Tools Still Don't Work

1. **DO NOT** suggest editing config files again
2. **DO NOT** say "let me fix this for you"
3. Instead, check if:
   - The package exists: `npm list -g reaper-dev-mcp` or check if npx can find it
   - The server builds: Check `/Users/Luca_Romagnoli/Code/personal/ReaScript/reaper-dev-mcp/dist/index.js` exists
   - There are startup errors visible to you

## User's Expectation

The user has published this as an npm package specifically to use with `npx`. They spent significant time on this. If it's not working after session restart, there's a deeper issue (not config file syntax).

---

## Testing Session - 2026-01-07 15:30

### What Was Tested

Attempted to use `get_function_info` and `search_functions` tools in active session.

**Result:** Both tools returned "No such tool available" errors.

### Investigation Findings

✅ **Server package:** Exists, npx can find it
✅ **Server build:** `/Users/Luca_Romagnoli/Code/personal/ReaScript/reaper-dev-mcp/dist/index.js` exists and is current
✅ **Server transport logic:** Correctly auto-detects stdio mode (checks `process.stdin.isTTY === false`)
✅ **Config syntax:** Verified correct in `/Users/Luca_Romagnoli/.config/claude-code/mcp.json`

### Root Cause

**MCP servers are loaded at Claude Code startup, not dynamically during sessions.**

The config is correct. The server code is correct. The tools simply weren't loaded because this session started before the config was updated, or Claude Code hasn't been restarted since the last config change.

### For Future Claude Instances

**When MCP tools aren't available:**

1. ✅ **First:** Try to use the tools - they might work now after restart
2. ❌ **Don't:** Immediately suggest editing config files
3. ✅ **Do:** Verify the server package/build exists (quick sanity check)
4. ✅ **Do:** Ask the user: "Have you restarted Claude Code since the last config change?"
5. ⚠️ **Only if:** Tools still don't work after confirmed restart, then investigate deeper

**Why this matters:** The config has been "fixed" 10+ times. The issue is session state, not file syntax. Don't waste time re-fixing what's already correct.
