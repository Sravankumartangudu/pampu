#!/bin/bash
# Renders the README screenshots of the Mac drop panel (off-screen, no phone needed).
#   scripts/screenshots.sh   → docs/screenshots/mac-near.png, mac-swipe.png, mac-receiving.png, mac-done.png, mac-text.png (+ -dark)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p docs/screenshots
BIN=$(mktemp -d)/render
swiftc -parse-as-library -O -o "$BIN" scripts/render_panel.swift mac/DropPanel.swift mac/Prefs.swift Shared/*.swift
"$BIN"
rm -f "$BIN"
ls docs/screenshots/mac-*.png | sed 's/^/✓ /'
