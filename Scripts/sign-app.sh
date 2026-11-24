#!/bin/bash
# Signs an assembled SwiftTunes.app: the two helpers, then the bundle. Signs
# ad hoc unless SWIFTTUNES_SIGN_IDENTITY names a signing identity in the
# keychain; with one, it signs with the hardened runtime and a secure
# timestamp. Fails unless plutil and codesign both accept the result. Builds
# nothing, runs nothing but plutil and codesign, and never notarizes.
#
# Usage: Scripts/sign-app.sh <path to SwiftTunes.app>
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1/Contents" ]; then
    echo "usage: Scripts/sign-app.sh <path to SwiftTunes.app>" >&2
    exit 2
fi
app="$1"

identity="${SWIFTTUNES_SIGN_IDENTITY:-}"
if [ -n "$identity" ]; then
    sign=(--force --sign "$identity" --options runtime --timestamp)
else
    sign=(--force --sign -)
fi
# Nested code first: signing the bundle seals the helpers' signatures.
/usr/bin/codesign "${sign[@]}" "$app/Contents/Helpers/ace-server"
/usr/bin/codesign "${sign[@]}" "$app/Contents/Helpers/tunes-lifeline"
/usr/bin/codesign "${sign[@]}" "$app"

/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
