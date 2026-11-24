#!/bin/bash
# Builds SwiftTunes in release, builds ace-server, assembles
# build/SwiftTunes.app and signs it with Scripts/sign-app.sh, which reads
# SWIFTTUNES_SIGN_IDENTITY (ad hoc when unset). Fails unless plutil and
# codesign both accept the result. It never notarizes.
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

Scripts/sign-app.sh "$app"
echo "$app"
