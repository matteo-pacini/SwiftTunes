# SwiftTunes: specification

Status: approved for build. Numbers in brackets such as [R37] cite the working rule notes (untracked
working material the lead hands to each role; R = its numbered rules 1 to
113). Where this document and those notes differ, this document wins; where the
contract and anything else differ, `docs/CONTRACT.md` wins.

## What it is

A menu bar app (`LSUIElement`, no Dock icon, no main window): an
`NSStatusItem` that opens an `NSPopover`. It plays the tunes kept for a genre
and, while the composer switch is on, composes new ones with `ace-server`
running as a child on Metal. One process owns everything; there is no
separate service and so no link cards.

Bundle identifier `me.matteopacini.SwiftTunes`. App name SwiftTunes. Licence
GPL-3.0-or-later.

## Decisions taken

| # | Decision | Taken |
|---|---|---|
| 1 | Build system | A Swift package, plus `Scripts/make-app.sh` to build `ace-server` and assemble the bundle. No Xcode project. |
| 2 | Language and UI | Swift 6, complete concurrency checking. The shell is AppKit; the popover's content is SwiftUI in an `NSHostingController`. The lifeline shim is C. |
| 2a | Dependencies | Apple frameworks and tools only, in the app and in the tests. The exceptions are `ace-server` itself, the model, and `cmake` to build the server. |
| 3 | Who owns `ace-server` | The app, through the lifeline shim: the shim holds the read end of a pipe whose write end only the app holds, and kills the server's process group when the pipe closes. |
| 4 | Where `ace-server` comes from | Built from the pinned acestep.cpp revision and embedded in `SwiftTunes.app/Contents/Helpers`. |
| 5 | Signing, releases | Local builds only, ad-hoc signed. No release workflow yet. |
| 6 | Repository | Private on GitHub; nothing is pushed without the owner's word. |
| 7 | Kept format | AAC, 256 kbit/s, `.m4a`, encoded by the system. |
| 8 | Holds | Memory pressure (warn or critical), Low Power Mode, thermal state serious or critical. Checked before each job, every 10 s while one runs, every 30 s while held. |
| 9 | Global shortcut | None. No notifications either. |
| 10 | Keys in the popover | Only the standard ones: Esc closes or cancels, Return presses the default button, Tab moves between fields, fields edit as fields do. |
| 11 | Starting genres | Nine starting genres, bundled, copied to Application Support at first launch. |
| 12 | Start at login | A "Start at Login" item in the status item's menu through `SMAppService`, off by default. If registration fails the item shows the failure as plain text and stays off. |
| 13 | Updates | None. The menu shows the running version. |
| 14 | Memory figure | "about 8 GiB of memory". |
| 15 | Server lifetime | The server runs only while a job needs it: stopped whenever the composer rests (queue full), is held, fails, or is off. |
| 16 | Wording | The sentences of the rule notes, with the substitutions of the working wording table. |
| 17 | Validation mismatches | Where the rule notes give two readings of a validation rule (their "Read first", 1 to 3), the first, panel-side reading. |

## Measured on an M4 Pro, 24 GiB (the only Mac measured)

A 180 s tune takes about 65 s (32 to 36 s writing, 31 to 34 s rendering).
Peak server footprint while writing 6.9 to 8.0 GiB, while rendering 2.0 to
2.8 GiB. The idle server keeps about 0.1 GiB more after each tune, hence
decision 15. Cancel ends a job in under 1 s. The server starts in 0.2 s.
Output is 48 kHz stereo 16-bit WAV. Device name `MTL0`.

## Behaviour (not open)

Rules [R1] to [R59] for the engine and [R63] to [R113] for the panel, read
with these points, which win over the notes:

- **Player.** `AVQueuePlayer` holds the playing item and the next one
  [R18]. End and failure notifications count only when their
  object is the item last asked for [R19]. There is no player process to
  restart, so [R22] does not apply.
- **Media keys.** `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`
  carry [R11]: play, pause, toggle, next, seek, and stop. Previous is
  disabled. `playbackState` is set on every start, pause and stop.
- **Files.** `<YYYYMMDD-HHMMSS>-<bpm>bpm-<key>.m4a` [R29]. Tags: title,
  genre, tempo, and the key in the comment as `key: <key>`. Export is a file
  copy under the readable name `<genre> - <title>.m4a` [R34], since the tags
  are already in the file.
- **Audio work.** Decode, the loudness backstop [R38], the tail trim with its
  1.5 s fade [R39], the 78-bar waveform and the encode run in-process with
  AVFoundation and Accelerate. No external encoder.
- **Holds.** [R43] with the three holds of decision 8 and no others.
- **Device.** [R44] is replaced: the server is started with `--device MTL0`;
  if its log shows no Metal device the state is `no_device`.
- **Server lifetime.** Decision 15 replaces "up while the switch is on"
  [R14]. While the composer rests the model state is `idle` and no server
  process exists.
- **Paths.** Weights, `genres.json` and `state.json` in
  `~/Library/Application Support/me.matteopacini.SwiftTunes/`; wave cache,
  scrapped tunes and work files in `~/Library/Caches/me.matteopacini.SwiftTunes/`;
  tunes in `~/Music/Tunes/<genre name>/`, exports in `~/Music/Tunes/Exports/`.
  The models folder is excluded from backup.
- **No global scrap** [R110 does not apply], **no bar flash**, **no
  notifications**. The status item follows [R111] to [R113] without the
  flash.
- **No key table** [R83 to R87, R90 do not apply]. Selection of a queue row
  is replaced by the pointer: the row under the pointer offers play it now,
  share and scrap; the job row offers scrap.
- **Share sheet** [R101 to R109]: copy the file (`NSPasteboard`, the file
  URL), copy its path, show it in Finder (`NSWorkspace`), export a copy, keep
  it for good. No watchdog is needed; these calls do not block.

## Wording

The sentences are those of the rule notes, section (c), with the
substitutions of the working wording table (untracked, with the notes).
No sentence names a key.

Buttons: `Download`, `Cancel`, `Resume`, `Try now`, `Save`, `Cancel`,
`Delete genre…`, `Delete <g>`, `Keep it`, `Undo · N s`. Menu: `SwiftTunes
<version>` (disabled), `Start at Login`, `Quit SwiftTunes`.

## Layout of the popover

380 pt wide. The published draft (owner's private page) is the picture; in
words:

- The cards are SwiftUI views; a switch is a `Toggle` with the switch style.
- **Player card**, three sections separated by hairlines:
  - NOW PLAYING: right of the heading, the suffix (`repeating`, `kept tunes`)
    and a genre button (`<g> ⌄`) that opens the chooser. Then the tune's
    name, `N BPM · <key>`, the waveform (click seeks), position and length,
    and one row of controls: play/pause, next, then shuffle, repeat (with its
    mode as text), share, scrap.
  - UP NEXT: heading with its right-hand text [R78], the rows [R77], the job
    row, `Not started` placeholders.
  - COMPOSER: heading with the state label and a switch; the lines of
    [R80]; `Try now` when failed or no device.
  - A footer line only when there is something to say: the undo line with its
    button, or a notice for 6 s [R91, R92].
- **Chooser**: back link to the player, title `Genre`, the chip, a grid three
  across, `+ New genre` last. A pencil on the hovered cell opens the editor.
- **Editor**: back link, title, chip, the four fields, error under its field,
  the hint, then `Delete genre…` on the left (absent for a new genre and for
  the last genre) and `Cancel`, `Save` on the right. Delete asks in place
  with `Keep it` and `Delete <g>`.
- **Share sheet**: back link, the tune, five rows; keep for good is a switch.
- **Setup cards**: the three of [notes (c), "Setup"] with one button each.
- **Status item**: a note glyph (template image), the genre's name while
  playing, the composer's dot. Left click opens the popover; right click
  opens the menu.

## Ownership

One worktree and one branch per role. The package manifest, the bundle
layout and `docs/CONTRACT.md` each have a single owner.

| Role | Owns |
|---|---|
| lead | `docs/SPEC.md`, `docs/CONTRACT.md`, `AGENTS.md`, merges |
| repo | `Package.swift`, `Sources/TunesContract/` (a transcription of the contract; changed only on the lead's instruction), `Scripts/`, `Config/`, `Resources/`, `Support/` (Info.plist, entitlements), `README.md`, `LICENSE`, `.gitignore`, `.github/` |
| engine | `Sources/TunesContract/GenreRules.swift` (the one file of that target with logic; the repo role leaves a stub), `Sources/TunesRules/`, `Sources/TunesEngine/`, `Sources/tunes-lifeline/`, `Tests/TunesRulesTests/`, `Tests/TunesEngineTests/`, `Tests/TunesFakes/` |
| app | `Sources/TunesPanel/`, `Sources/SwiftTunes/`, `Tests/TunesPanelTests/` |

Targets:

- `TunesContract`: types and the engine protocol. No logic beyond coding.
- `TunesRules`: the pure rules of the service [R1 to R59 where pure]. No I/O.
- `TunesEngine`: the live engine. Depends on `TunesContract`, `TunesRules`.
- `tunes-lifeline`: the C shim, an executable.
- `TunesPanel`: the pure panel decisions: from a
  snapshot and the panel's own state to what each card shows, every heading,
  row, label and sentence. Depends on `TunesContract` only.
- `SwiftTunes`: the executable: the AppKit shell and the SwiftUI views. Depends on `TunesContract`,
  `TunesPanel`, `TunesEngine` (to construct it; it talks to it only through
  the contract's protocol).
- Tests use Swift Testing.

## Done

1. `swift test` passes, with:
   - `TunesRulesTests`: every value table of the rule notes, (f) part 1: silences, rounds and modes over seeded rounds, the
     keep rule, file and export names, genre parsing, formatting and
     validation at each boundary, medians and timings, download arithmetic,
     multipart parsing, levels and waveform.
   - `TunesEngineTests`: the engine against a fake `ace-server` and a fake
     Hugging Face on loopback and a fake player (rule notes, (f) part 2, the
     scenarios that apply): first snapshot; download, resume and the
     cancel race; the two-request job and the queue; keep; state file; next
     and idle; silence rewrite and the third-plan failure; the loudness
     backstop; holds; the genres file; scrap, undo and play carrying names;
     failed moves; an unplayable tune; a late player event after a genre
     pick; genre editing; shuffle, repeat, pins and share; the server stopped
     whenever the composer rests; shutdown leaves no child; restart reads
     state back and plays nothing by itself.
   - `TunesPanelTests`: the panel cases of the rule notes, (f), that are not about
     keys, against the fixture files adapted to this contract.
   - The engine suite passes again under a CPU limit (`taskpolicy -b`).
2. `Scripts/make-app.sh` produces `SwiftTunes.app` with `ace-server` and
   `tunes-lifeline` in `Contents/Helpers`; `plutil -lint` passes on its
   Info.plist, which has `LSUIElement`; `codesign --verify --deep --strict`
   passes.
3. On the real Mac, by hand, from the assembled app: one tune composed and
   played end to end; ten tunes with the composer on, two kept ahead, memory
   back at baseline when it rests; `kill -9` of the app leaves no
   `ace-server`; every action reachable by pointer; media keys and Now
   Playing; copy and Finder.
4. A reviewer who wrote none of it has checked the diff against this
   document and built a field-by-field agreement table between the contract,
   the engine and the app.

## Not in this round

A release workflow, Developer ID signing and notarization, an updater, a
global shortcut, a Nix package, measurements on any other Mac.
