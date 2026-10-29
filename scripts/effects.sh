#!/bin/bash
# Renders frames of every drop effect, iPhone and Mac halves (off-screen, no phone needed).
#   scripts/effects.sh        → docs/screenshots/effects-iphone.png, effects-mac.png (+ frames/ to check by eye)
#   scripts/effects.sh <dir>  → the same, into <dir>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-docs/screenshots}"
mkdir -p "$OUT"
BIN=$(mktemp -d)/render
swiftc -parse-as-library -O -o "$BIN" scripts/render_effects.swift mac/DropPanel.swift mac/Prefs.swift Shared/*.swift
"$BIN" "$OUT"
rm -f "$BIN"
