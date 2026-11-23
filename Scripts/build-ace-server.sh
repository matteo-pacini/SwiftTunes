#!/bin/bash
# Builds ace-server (acestep.cpp, Metal) at the revision pinned in
# Config/pins.json and prints the path of the binary on stdout. Progress goes
# to stderr.
#
# The source and build tree live in a cache outside the repository:
# $SWIFTTUNES_BUILD_CACHE, default ~/Library/Caches/SwiftTunes-build.
# Needs git, make and Apple clang (the Xcode command line tools) and cmake,
# all from PATH. Installs nothing.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
pins="$root/Config/pins.json"

pin() { /usr/bin/plutil -extract "$1" raw -o - "$pins"; }
repository="$(pin acestep_cpp.repository)"
revision="$(pin acestep_cpp.revision)"

cache="${SWIFTTUNES_BUILD_CACHE:-$HOME/Library/Caches/SwiftTunes-build}"
src="$cache/acestep.cpp-$revision"
build="$src/build"

if ! command -v cmake >/dev/null 2>&1; then
    echo "build-ace-server: cmake is missing; enter the dev shell (nix develop) or install cmake, and run this again." >&2
    exit 1
fi

for tool in git make /usr/bin/clang /usr/bin/clang++; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "build-ace-server: $tool is missing; install the Xcode command line tools (xcode-select --install) and run this again." >&2
        exit 1
    fi
done

if [ ! -d "$src/.git" ]; then
    echo "build-ace-server: fetching acestep.cpp $revision" >&2
    mkdir -p "$cache"
    tmp="$(mktemp -d "$cache/fetch.XXXXXX")"
    git -C "$tmp" init -q
    git -C "$tmp" remote add origin "$repository"
    git -C "$tmp" fetch -q --depth 1 origin "$revision"
    git -C "$tmp" -c advice.detachedHead=false checkout -q FETCH_HEAD
    git -C "$tmp" submodule update -q --init --recursive --depth 1
    mv "$tmp" "$src"
fi

head="$(git -C "$src" rev-parse HEAD)"
if [ "$head" != "$revision" ]; then
    echo "build-ace-server: $src is at $head, not the pinned $revision; delete that folder and run this again." >&2
    exit 1
fi
# A leading '+', '-' or 'U' means a submodule is not at the commit the pinned
# revision records.
if git -C "$src" submodule status --recursive | grep -q '^[-+U]'; then
    echo "build-ace-server: a submodule in $src is not at its pinned commit; delete that folder and run this again." >&2
    exit 1
fi
if [ -n "$(git -C "$src" status --porcelain --ignore-submodules=none --untracked-files=no)" ]; then
    echo "build-ace-server: $src has local changes; delete that folder and run this again." >&2
    exit 1
fi

echo "build-ace-server: configuring" >&2
cmake -S "$src" -B "$build" -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DGGML_METAL=ON -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=OFF >&2

echo "build-ace-server: building" >&2
cmake --build "$build" --target ace-server -j "$(sysctl -n hw.ncpu)" >&2

binary="$build/ace-server"
if [ ! -x "$binary" ]; then
    echo "build-ace-server: the build finished but $binary is not there." >&2
    exit 1
fi
echo "$binary"
