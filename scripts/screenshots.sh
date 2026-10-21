#!/bin/bash
# Regenerates docs/screenshots from the real views, using sample data instead of your config.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build
BROWSWITCH_CONFIG="$(mktemp -d)/config.json"
cp scripts/screenshot-config.json "$BROWSWITCH_CONFIG"
BROWSWITCH_CONFIG="$BROWSWITCH_CONFIG" "$(swift build --show-bin-path)/Browswitch" --screenshots docs/screenshots
sips -s format png Resources/AppIcon.icns --out docs/icon.png -Z 256 >/dev/null
echo "Updated docs/screenshots"
