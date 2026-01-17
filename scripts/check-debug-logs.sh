#!/bin/bash
# Check for debug logs that shouldn't be in release builds
# Run this before tagging a release

set -e

echo "========================================"
echo "SideFX Debug Log Checker"
echo "========================================"
echo ""

# Change to project root
cd "$(dirname "$0")/.."

FOUND_ISSUES=0

# Check for DEBUG prefixed logs (should be removed)
echo "Checking for DEBUG logs..."
DEBUG_LOGS=$(grep -rn "ShowConsoleMsg.*DEBUG" lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$DEBUG_LOGS" ]; then
    echo "❌ Found DEBUG logs that should be removed:"
    echo "$DEBUG_LOGS"
    echo ""
    FOUND_ISSUES=1
else
    echo "✓ No DEBUG logs found"
fi

# Check for [module] prefixed debug logs (should be removed)
echo ""
echo "Checking for [module] debug prefixes..."
MODULE_LOGS=$(grep -rn 'ShowConsoleMsg.*\[.*\]' lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$MODULE_LOGS" ]; then
    echo "❌ Found [module] prefixed logs that may need review:"
    echo "$MODULE_LOGS"
    echo ""
    FOUND_ISSUES=1
else
    echo "✓ No [module] prefixed logs found"
fi

# Check for hardcoded dev paths
echo ""
echo "Checking for hardcoded dev paths..."
DEV_PATHS=$(grep -rn "/Users/" lib/ --include="*.lua" 2>/dev/null || true)
if [ -n "$DEV_PATHS" ]; then
    echo "❌ Found hardcoded user paths:"
    echo "$DEV_PATHS"
    echo ""
    FOUND_ISSUES=1
else
    echo "✓ No hardcoded dev paths found"
fi

# Summary of user-facing logs (for reference, not an error)
echo ""
echo "========================================"
echo "User-facing logs (OK for release):"
echo "========================================"
grep -rn "ShowConsoleMsg.*SideFX:" lib/ --include="*.lua" 2>/dev/null | head -20 || true
echo ""
echo "(Showing first 20 matches)"

echo ""
echo "========================================"
if [ $FOUND_ISSUES -eq 0 ]; then
    echo "✓ All checks passed - ready for release!"
    exit 0
else
    echo "❌ Issues found - please fix before release"
    exit 1
fi
