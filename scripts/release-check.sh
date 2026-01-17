#!/bin/bash
# Release readiness checks for SideFX
# Run this before creating a release to ensure no debug code is present

set -e

ERRORS=0
WARNINGS=0

echo "=== SideFX Release Check ==="
echo ""

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

error() {
    echo -e "${RED}ERROR:${NC} $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "${YELLOW}WARNING:${NC} $1"
    WARNINGS=$((WARNINGS + 1))
}

ok() {
    echo -e "${GREEN}OK:${NC} $1"
}

# 1. Check for ShowConsoleMsg debug statements
echo "Checking for debug console messages..."
DEBUG_MSGS=$(grep -rn "ShowConsoleMsg.*DEBUG" lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$DEBUG_MSGS" ]; then
    error "Found ShowConsoleMsg DEBUG statements:"
    echo "$DEBUG_MSGS" | while read line; do echo "  $line"; done
else
    ok "No ShowConsoleMsg DEBUG statements"
fi

# 2. Check for print() statements (except in comments)
echo ""
echo "Checking for print() statements..."
PRINT_STMTS=$(grep -rn "^[^-]*print(" lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$PRINT_STMTS" ]; then
    error "Found print() statements:"
    echo "$PRINT_STMTS" | while read line; do echo "  $line"; done
else
    ok "No print() statements"
fi

# 3. Check for DEBUG flags set to true
echo ""
echo "Checking for DEBUG flags..."
DEBUG_FLAGS=$(grep -rn "DEBUG.*=.*true" lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$DEBUG_FLAGS" ]; then
    error "Found DEBUG flags set to true:"
    echo "$DEBUG_FLAGS" | while read line; do echo "  $line"; done
else
    ok "No DEBUG flags set to true"
fi

# 4. Check for dev ReaWrap path being prioritized
echo ""
echo "Checking ReaWrap path configuration..."
# The dev path should come AFTER reapack path in package.path
DEV_PATH_LINE=$(grep -n "reawrap_dev" SideFX.lua | grep "package.path" | head -1)
REAPACK_PATH_LINE=$(grep -n "reawrap_reapack" SideFX.lua | grep "package.path" | head -1)
if [ -n "$DEV_PATH_LINE" ] && [ -n "$REAPACK_PATH_LINE" ]; then
    DEV_LINE_NUM=$(echo "$DEV_PATH_LINE" | cut -d: -f1)
    REAPACK_LINE_NUM=$(echo "$REAPACK_PATH_LINE" | cut -d: -f1)
    if [ "$DEV_LINE_NUM" -lt "$REAPACK_LINE_NUM" ]; then
        warn "Dev ReaWrap path is loaded before ReaPack path (dev takes priority)"
    else
        ok "ReaPack ReaWrap path takes priority over dev path"
    fi
else
    ok "ReaWrap path configuration looks standard"
fi

# 5. Check version consistency
echo ""
echo "Checking version consistency..."
VERSION_LUA=$(grep -m1 "@version" SideFX.lua | sed 's/.*@version //')
VERSION_JSON=$(cat docs/version.json 2>/dev/null | grep -o '"version": "[^"]*"' | cut -d'"' -f4)
if [ "$VERSION_LUA" != "$VERSION_JSON" ]; then
    error "Version mismatch: SideFX.lua=$VERSION_LUA, docs/version.json=$VERSION_JSON"
else
    ok "Version consistent: $VERSION_LUA"
fi

# 6. Check for TODO/FIXME comments (warning only)
echo ""
echo "Checking for TODO/FIXME comments..."
TODOS=$(grep -rn "TODO\|FIXME" lib/ --include="*.lua" 2>/dev/null | grep -v "^Binary" || true)
if [ -n "$TODOS" ]; then
    warn "Found TODO/FIXME comments (review before release):"
    echo "$TODOS" | while read line; do echo "  $line"; done
else
    ok "No TODO/FIXME comments"
fi

# 7. Check for ctx:text() debug output (common debug pattern)
echo ""
echo "Checking for debug text output..."
DEBUG_TEXT=$(grep -rn 'ctx:text.*debug\|ctx:text.*DEBUG\|-- DEBUG\|--DEBUG' lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$DEBUG_TEXT" ]; then
    error "Found potential debug text output:"
    echo "$DEBUG_TEXT" | while read line; do echo "  $line"; done
else
    ok "No debug text output found"
fi

# Summary
echo ""
echo "=== Summary ==="
if [ $ERRORS -gt 0 ]; then
    echo -e "${RED}$ERRORS error(s)${NC}, ${YELLOW}$WARNINGS warning(s)${NC}"
    echo "Release check FAILED - fix errors before release"
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${GREEN}0 errors${NC}, ${YELLOW}$WARNINGS warning(s)${NC}"
    echo "Release check PASSED with warnings - review before release"
    exit 0
else
    echo -e "${GREEN}0 errors, 0 warnings${NC}"
    echo "Release check PASSED"
    exit 0
fi
