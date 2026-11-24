#!/bin/bash
# Prints the section of CHANGELOG.md for one version: the lines under
# "## <version>" up to the next "## " heading, without the heading and
# without blank lines at either end. Fails when the changelog has no such
# heading, or when the section under it is empty.
#
# Usage: Scripts/release-notes.sh <version>
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    echo "usage: Scripts/release-notes.sh <version>" >&2
    exit 2
fi
version="$1"
changelog="$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md"

# The heading is compared as a whole line, never as a pattern, so a version
# such as 0.1.0 does not match 0x1y0.
awk -v heading="## $version" '
    $0 == heading { found = 1; inside = 1; next }
    inside && /^## / { inside = 0 }
    inside { lines[++n] = $0 }
    END {
        if (!found) exit 1
        first = 1
        while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
        last = n
        while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
        if (first > last) exit 1
        for (i = first; i <= last; i++) print lines[i]
    }
' "$changelog" || {
    echo "release-notes: CHANGELOG.md has no section for $version, or it is empty." >&2
    exit 1
}
