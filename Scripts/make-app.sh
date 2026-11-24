#!/bin/bash
# Builds SwiftTunes in release, builds ace-server, and assembles an ad-hoc
# signed build/SwiftTunes.app. Fails unless plutil and codesign both accept
# the result.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

for notice in LICENSE Resources/ThirdPartyNotices.txt; do
    if [ ! -s "$notice" ]; then
        echo "make-app: $notice is missing or empty; the app does not ship without it." >&2
        exit 1
    fi
done

swift build -c release --product SwiftTunes
swift build -c release --product tunes-lifeline
bin="$(swift build -c release --show-bin-path)"

ace_server="$(Scripts/build-ace-server.sh)"

app="$root/build/SwiftTunes.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Helpers" "$app/Contents/Resources"
cp Support/Info.plist "$app/Contents/Info.plist"
cp "$bin/SwiftTunes" "$app/Contents/MacOS/SwiftTunes"
cp "$bin/tunes-lifeline" "$app/Contents/Helpers/tunes-lifeline"
cp "$ace_server" "$app/Contents/Helpers/ace-server"
cp Resources/genres.json "$app/Contents/Resources/genres.json"
cp Config/pins.json "$app/Contents/Resources/pins.json"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp Resources/ThirdPartyNotices.txt "$app/Contents/Resources/ThirdPartyNotices.txt"

# Nested code first: signing the bundle seals the helpers' signatures.
/usr/bin/codesign --force --sign - "$app/Contents/Helpers/ace-server"
/usr/bin/codesign --force --sign - "$app/Contents/Helpers/tunes-lifeline"
/usr/bin/codesign --force --sign - "$app"

/usr/bin/plutil -lint "$app/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
echo "$app"
