#!/bin/bash
# Makes Resources/AppIcon.icns from Resources/AppIcon.png (1024 px square,
# full bleed): Scripts/make-icon.swift clips the art to the macOS icon shape
# and draws every iconset member, then iconutil packs them. Apple's tools
# only. The build does not run this; commit both files after running it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/AppIcon.iconset"

swift Scripts/make-icon.swift Resources/AppIcon.png "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o Resources/AppIcon.icns
echo "$root/Resources/AppIcon.icns"
