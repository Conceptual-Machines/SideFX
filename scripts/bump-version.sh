#!/bin/bash
# Bump version in all places
# Usage: ./scripts/bump-version.sh 0.3.0

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.3.0"
    exit 1
fi

VERSION=$1

# Validate version format
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: Invalid version format. Must be X.Y.Z (e.g., 0.3.0)"
    exit 1
fi

echo "Bumping version to $VERSION..."

# Update SideFX.lua
sed -i.bak "s/@version [0-9]*\.[0-9]*\.[0-9]*/@version $VERSION/" SideFX.lua
rm -f SideFX.lua.bak

# Update docs/version.json
echo "{\"version\": \"$VERSION\"}" > docs/version.json

# Update README badge
sed -i.bak "s/version-[0-9]*\.[0-9]*\.[0-9]*/version-$VERSION/" README.md
rm -f README.md.bak

echo "Updated:"
echo "  - SideFX.lua (@version $VERSION)"
echo "  - docs/version.json"
echo "  - README.md badge"
echo ""
echo "Don't forget to commit and push!"
