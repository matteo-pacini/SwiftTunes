# SwiftTunes

A macOS menu bar app that plays endless music by genre, composed on your Mac
by ACE-Step 1.5 Turbo through an embedded `ace-server` running on the GPU.
Nothing is sent anywhere once the model is downloaded.

<p align="center">
  <img src="docs/screenshots/playing.png" width="380" alt="The SwiftTunes popover playing a Jazz tune: its name, tempo and key, the tune's shape as columns of dots filled up to the position, and seven round controls with Previous left of the play button. Below, This round reads 5 of 12: the playing tune is highlighted with a small level meter in place of its number, followed by tunes 6 and 7 and five more this round; then the tune being made, and the composer bar.">
</p>

SwiftTunes is inspired by [Flowtunes](https://github.com/omacom/flowtunes)
from Omarchy.

## What it does

- **Genres you edit.** Nine genres to start with, each with its own colours.
  Add, rename or delete genres; each has a prompt, variations, a tempo range,
  four colours and a Singing switch.
- **Tunes kept, tunes made.** A genre plays the tunes kept for it. Turn the
  composer on and it writes new ones and keeps two ready ahead; a new tune
  plays next. The newest 50 of a genre are kept.
- **The round, held in order.** This round lists every tune of the round in
  one order: the ones already played, the playing one, then what waits. A
  tune keeps its number as the round goes on; only a newly made tune, which
  plays next, moves the ones after it down by one. Played tunes stay in the
  list, dimmed, and any of them can be played again. Every kept tune plays
  once a round, shuffled or in the order made; repeat all, one or off. What
  is being made shows apart, under it.
- **Previous.** Within the first three seconds of a tune, Previous goes back
  to the one before it in the round; later, it starts the tune again.
- **Sung genres and your own words.** A sung genre's tunes have words,
  written by the model in English; the words of the playing tune open under
  it. From a sung genre you can also ask for one tune sung with words you
  write.
- **Scrap and undo.** Scrap any tune in the round and it can be brought back
  for ten seconds; scrapping the one being made stops it.
- **Keep for good.** A tune kept for good is never removed by the newest-50
  rule.
- **Share and drag out.** Drag a tune's picture out of the popover to drop
  the file anywhere, or use the system share sheet; copy its path, show it in
  Finder, or export a copy.
- **Rename.** Click the playing tune's name to give it another.
- **Removing the model.** The menu removes the 7.57 GiB model when you want
  the space back; your tunes stay and keep playing.
- Every tune gets a picture drawn from its name, tempo and key.

## A look

<table>
  <tr>
    <td><img src="docs/screenshots/composing.png" width="250" alt="Nothing playing yet in Synthwave: the hero shows a wave of dots that moves while the first tune is written, This round has nothing in it yet, and a separate Being made list shows the tune being written and one not started."></td>
    <td><img src="docs/screenshots/lyrics.png" width="250" alt="A sung tune playing, with tempo, key and the word sung under its name; the wave has shrunk to a thin strip and the words show in a scrolling box headed Lyrics as written. Below the controls, This round reads 1 of 5 with the playing tune highlighted."></td>
    <td><img src="docs/screenshots/genres.png" width="250" alt="The genre chooser: nine genres as tiles in their own colours, each with its kept count or what is playing, and a dashed tile to add a new genre."></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/own-words.png" width="250" alt="The sheet for a tune with your own words: buttons that insert verse, chorus, bridge and instrumental break marks, a text box with the words, a count of sung lines and characters, a suggested name, and Compose."></td>
    <td><img src="docs/screenshots/editor.png" width="250" alt="Editing a sung genre in grouped rows, its name selected for typing: prompt, variations, tempo range, the Singing switch with its explanation, four colour wells, and the buttons to delete, cancel or save."></td>
    <td><img src="docs/screenshots/playing-light.png" width="250" alt="The playing state in light appearance: the same layout on a pale wash of the genre's colours with dark text."></td>
  </tr>
</table>

## Requirements

- A Mac with Apple silicon, macOS 26 or later.
- About 8 GiB of memory free while a tune is being composed.
- 7.57 GiB of disk for the model, downloaded from Hugging Face on first use.

To build: Xcode 27 (Swift 6.4) and `cmake`. `cmake` is
the one tool beyond Xcode, needed only to build `ace-server`; the build uses
the Makefile generator, so nothing else. The scripts take `cmake` from
`PATH` and stop with a sentence saying so when it is missing. They install
nothing.

## Building

With Nix, enter the dev shell from `flake.nix`, which adds `cmake` and
leaves Swift, clang, the SDK and `codesign` to Xcode:

```sh
nix develop
swift build
swift test
Scripts/make-app.sh
open build/SwiftTunes.app
```

Without Nix, install `cmake` (from [cmake.org](https://cmake.org/download/)
or a package manager) so that it is on `PATH`, then run the same commands
without `nix develop`. `swift build` and `swift test` need no `cmake`.

`Scripts/make-app.sh` builds the app in release, fetches acestep.cpp at the
revision pinned in `Config/pins.json` and builds `ace-server` with Metal,
assembles `build/SwiftTunes.app`, signs it ad hoc, and checks it with
`plutil -lint` and `codesign --verify --deep --strict`.

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

Credits, and the work by others it bundles and downloads under their own
licences:

- Inspired by [Flowtunes](https://github.com/omacom/flowtunes) from Omarchy.
- `ace-server` is built from [acestep.cpp](https://github.com/ServeurpersoCom/acestep.cpp)
  (MIT).
- The model is [ACE-Step 1.5](https://github.com/ace-step/ACE-Step-1.5) (MIT),
  in the GGUF conversion at
  [Serveurperso/ACE-Step-1.5-GGUF](https://huggingface.co/Serveurperso/ACE-Step-1.5-GGUF).
