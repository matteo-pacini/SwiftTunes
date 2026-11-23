# SwiftTunes

A macOS menu bar app that plays endless instrumental music by genre. Pick a
genre and it plays the tunes kept for it; turn the composer on and it writes
new ones on your Mac with ACE-Step 1.5 Turbo, run locally on the GPU through
an embedded `ace-server`.

Work in progress: the build and the bundle are in place; the engine and the
interface are still being written, so the app built today is a placeholder.

## Requirements

- A Mac with Apple silicon, macOS 14 or later.
- About 8 GiB of memory free while a tune is being composed.
- 7.57 GiB of disk for the model, downloaded from Hugging Face on first use.

To build: Xcode 26 or later (Swift 6.2), and `cmake`. `cmake` is the one tool
beyond Xcode, needed only to build `ace-server`; the build uses the Makefile
generator, so nothing else. `Scripts/build-ace-server.sh` takes `cmake` from
`PATH`, or runs it through `nix shell nixpkgs#cmake` when Nix is installed,
and otherwise stops and says so. It installs nothing.

## Build and run

```sh
swift build
swift test
Scripts/make-app.sh
open build/SwiftTunes.app
```

`Scripts/make-app.sh` builds the app in release, fetches acestep.cpp at the
revision pinned in `Config/pins.json` and builds `ace-server` with Metal,
assembles `build/SwiftTunes.app`, signs it ad hoc, and checks it with
`plutil -lint` and `codesign --verify --deep --strict`.

The workflow in `.github/workflows/ci.yml` runs `swift build` and
`swift test` on a macOS runner. It has not run yet: it starts once the
repository is pushed to GitHub.

## Where files live

| What | Where |
|---|---|
| Model weights, `genres.json`, `state.json` | `~/Library/Application Support/me.matteopacini.SwiftTunes/` (the models folder is excluded from backup) |
| Wave cache, scrapped tunes, work files | `~/Library/Caches/me.matteopacini.SwiftTunes/` |
| Kept tunes | `~/Music/Tunes/<genre>/` |
| Exports | `~/Music/Tunes/Exports/` |
| acestep.cpp source and build tree (building only) | `~/Library/Caches/SwiftTunes-build/`, or `$SWIFTTUNES_BUILD_CACHE` |

## Licence

SwiftTunes is licensed under the GNU General Public License, version 3 or
later; see `LICENSE`.

It bundles and downloads work by others under their own licences:

- `ace-server` is built from [acestep.cpp](https://github.com/ServeurpersoCom/acestep.cpp)
  (MIT).
- The model is [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5) (MIT),
  in the GGUF conversion at
  [Serveurperso/ACE-Step-1.5-GGUF](https://huggingface.co/Serveurperso/ACE-Step-1.5-GGUF).
