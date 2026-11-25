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
| 2 | Language and UI | Swift 6, complete concurrency checking. macOS 26 is the oldest system it runs on; Liquid Glass is the base material. The shell is AppKit; the popover's content is SwiftUI in an `NSHostingController`. The lifeline shim is C. |
| 2a | Dependencies | Apple frameworks and tools only, in the app and in the tests. The exceptions are `ace-server` itself, the model, and `cmake` to build the server. |
| 3 | Who owns `ace-server` | The app, through the lifeline shim: the shim holds the read end of a pipe whose write end only the app holds, and kills the server's process group when the pipe closes. |
| 4 | Where `ace-server` comes from | Built from the pinned acestep.cpp revision, without its web page (see "Releases"), and embedded in `SwiftTunes.app/Contents/Helpers`. |
| 5 | Signing, releases | Local builds are ad-hoc signed. A `v*` tag makes a release: signed with the owner's Developer ID, notarized, a zip on a draft GitHub release (see "Releases"). |
| 6 | Repository | Public on GitHub; nothing is pushed without the owner's word. |
| 7 | Kept format | AAC, 256 kbit/s, `.m4a`, encoded by the system. |
| 8 | Holds | Memory pressure (warn or critical), Low Power Mode, thermal state serious or critical. All three are checked before each job and every 30 s while held. While a job runs only power and heat are checked, every 10 s: the server's own load raises memory pressure, so that check would hold every tune. |
| 9 | Global shortcut | None. No notifications either. |
| 10 | Keys in the popover | Only the standard ones: Esc closes or cancels, Return presses the default button, Tab moves between fields, fields edit as fields do. |
| 11 | Starting genres | Nine starting genres, bundled, copied to Application Support at first launch. Each has a palette of four colours; a genre without one gets one from its name. |
| 12 | Start at login | A "Start at Login" item in the status item's menu through `SMAppService`, off by default. If registration fails the item shows the failure as plain text and stays off. |
| 13 | Updates | None. The menu shows the running version. |
| 14 | Memory figure | "about 8 GiB of memory". |
| 15 | Server lifetime | The server runs only while a job needs it: stopped whenever the composer rests (queue full), is held, fails, or is off. A stop while a job runs first asks the server to cancel the job and waits up to 1 s, so quitting does not wait out the 5 s kill grace. The server runs at lower priority (nice 10). |
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

380 pt wide, macOS 26, Liquid Glass throughout. The owner's approved picture
is working material the lead hands to the app role; in words:

- **Backdrop.** Every card sits on a colour field made from the selected
  genre's palette: a `MeshGradient` whose points drift slowly in a
  `TimelineView`. It animates only while the popover is open. Text is white
  on it in dark appearance and near-black on a paler field in light.
- **Glass.** Controls, shelf cards, the composer bar, the footer toast and
  grouped rows use `glassEffect` inside a `GlassEffectContainer`; nothing
  draws its own blur. Play and pause morph in place.
- **Player card**, three parts kept apart:
  - NOW PLAYING: the label (with `· KEPT TUNES` or `· REPEATING`) and the
    genre button, then the tune's name large and rounded, `N BPM · <key>`,
    and the tune's shape: 78 mirrored columns of dots that fill as it plays;
    a click seeks, a drag scrubs. Position and length under it. One row of
    six round controls: shuffle, repeat, play/pause (large, solid), next,
    share, scrap. A click on the playing tune's name turns it into a
    text field holding the name, selected, with a tick and a cross beside
    it: Return or the tick saves (`renameTune`), Esc or the cross puts the
    old name back. The rule it breaks, or the engine's refusal, shows under
    it and the field stays open. The name's tooltip is `Rename`. With nothing to play the hero shows the empty-state
    sentences and, while a tune is being made, the forming wave.
  - UP NEXT and BEING MADE: see "The queue". Rows are glass: a small square
    of artwork, the name with a NEW badge, `N BPM · <key>`, the length at
    the right; hover shows play it now, share and scrap in place of the
    length (job row: scrap).
  - COMPOSER: one glass bar: the label, the state as a pill, the switch;
    the `Makes <g>, keeps N ahead` line; the hold or failure sentence and
    the model line when they apply; `Try now` when failed or no device.
  - The undo line and notices are a glass toast above the bottom edge.
- **Forming wave.** The same dots moving like a level meter: low and loose
  while writing, taller while rendering, settling into the tune's shape when
  it is done. It shows the stage and nothing else: no growth over time.
- **Artwork.** Each tune has a picture drawn from its name, tempo and key
  inside its genre's palette: a pure recipe in `TunesPanel`, drawn in
  SwiftUI, never stored. It is on the shelf, in the share sheet, and in the
  Now Playing widget (rendered once per tune with `ImageRenderer`).
- **Chooser.** Title `Genre`, the chip, a grid three across of tiles in each
  genre's palette with its name and kept count, `+ New genre` last. A click
  plays what is kept and the tile grows into the player's backdrop. Hover
  shows the pencil.
- **Editor.** A grouped form: Name, Prompt, Variations, Tempo (slowest and
  fastest), Colours (four swatches, each a colour well). The error sits
  under its row. Then the hint, `Delete genre…` on the left, `Cancel` and
  `Save` on the right.
- **Share sheet.** The artwork, large, draggable: dropping it anywhere
  gives the tune's file. Under the name and meta line the hint `Drag the
  picture to drop the tune anywhere`. Rows: `Share…` (the system share
  sheet; sub line `Mail, Messages, AirDrop and the rest`), `Copy its path`,
  `Show it in Finder`, `Export a copy`, `Keep it for good` (a switch).
  There is no `Copy the file` row.
- **Setup cards**: as before, on glass over a neutral field.
- **Status item**: a waveform symbol that animates while playing and holds
  still when paused, the genre's name while playing, the composer's dot.
- **Motion and power.** Everything animated stops when the popover closes.
  Reduce Motion: still fields, no forming motion, no morphs. Low Power
  Mode: still backdrop. Reduce Transparency is left to the system's glass.

## The queue

- **Order.** `queue` is everything that will play, in order, for the rest of
  the round: the finished new tunes first (a new tune always plays next),
  then the kept tunes in the round's order. The round's order is drawn once:
  with shuffle on, a shuffled order of the kept tunes not yet played, drawn
  when the round starts and redrawn for what is left when shuffle is turned
  on; with shuffle off, the order made. Every kept tune plays once a round,
  and the first tune of a new round is never the last of the one before. A
  tune that becomes kept joins the end of the order. `roundLeft` is the
  number of kept tunes in `queue`.
- **UP NEXT** lists finished tunes only, numbered from 1, three rows in the
  player. Under them: `then N more this round · Show all` when there are
  more, which opens the queue card. Its right-hand text: `N new, then kept`
  when new tunes wait, else `from N kept, shuffled` or `N kept, in the order
  made`.
- **BEING MADE**, a separate block under UP NEXT with the right-hand text
  `plays next when ready`: the job row and the `Not started` placeholders.
  It is absent when the composer is off and no own-words tune is waiting.
- **The queue card.** Back link to the player, `QUEUE · N THIS ROUND`, the
  title `Up next`, the same right-hand text, then every row numbered in play
  order in a scrolling list; BEING MADE stays under the list. Last line:
  `after these, the round starts over`, or with repeat off `The round ends
  after <t>.` Rows offer play it now, share and scrap on hover, as in the
  player.

## Singing

- **Per genre.** A genre has a Singing switch (the genres file's optional
  `sung` key). A sung genre's prompt describes the voice. Flipping the
  switch changes only tunes made from then on; kept tunes stay and keep
  playing. The editor's hint says `Tunes already kept stay as they are; new
  ones will be sung.` or `…new ones will be instrumental.` when the switch
  differs from the saved value. Editor row: `Singing`, sub line `The model
  writes the words, in English. Say what the voice is like in the prompt.`
- **The request.** For a sung genre the caption is the prompt and two
  variations with no `instrumental` appended, `lyrics` is empty, and
  `vocal_language` is `en`. The model writes the words; the plan goes to the
  renderer unchanged.
- **Thin words.** A plan with fewer than 6 sung lines, or fewer than 4
  different sung lines compared without case, is written again; the third
  such plan for one tune is the failure `3 plans in a row had too few sung
  lines`. While writing again the composer shows `Writing again: the last
  plan had too few sung lines.` A sung line is a non-empty line that does
  not start with `[`. The silence rule applies as for any tune and has its
  own count.
- **The words are kept** in the file's lyrics tag. A tune is `sung` when its
  file has words. `sung` joins the tempo and key wherever they show: `110
  BPM · A minor · sung`.
- **Showing them.** A sung playing tune has a `Lyrics` button under its meta
  line. Open, the wave becomes a thin strip that still seeks, and the words
  show under the heading `LYRICS AS WRITTEN`, scrolling, as plain text.
- **Names** stay the two-word kind. Nothing filters the words.
- **Your own words.** A sung genre's composer bar has `Sing my words…`. It
  opens a sheet: back link, `SING MY WORDS`, the title `A tune in <g>`, four
  buttons (`+ Verse`, `+ Chorus`, `+ Bridge`, `+ Instrumental break`) that
  insert `[Verse]` and so on as a line of its own at the caret, a plain text
  editor, the line `N sung lines · N of 2,000 characters` with `English
  sings best` at the right, a Name field offering a two-word name, the note
  `It is made once, with the genre's sound, and plays next when ready. The
  model may not sing every word as written.`, then `Cancel` and `Compose`.
  Refusals: `A tune needs at least one sung line.`, `The words are at most
  2,000 characters; these have N.`, the tune-name rules, and `A tune with
  your words is already being made.`
- An own-words tune is made once, before the genre's own, whether or not the
  composer switch is on (setup must be ready and the holds apply). Its words
  are sent as given, with no thin-words check. Its row in BEING MADE shows
  its name and `with your words · being written` (or `being rendered`) and
  the time line. Scrapping the row cancels it.

## Ownership

One worktree and one branch per role. The package manifest, the bundle
layout and `docs/CONTRACT.md` each have a single owner.

| Role | Owns |
|---|---|
| lead | `docs/SPEC.md`, `docs/CONTRACT.md`, `AGENTS.md`, merges |
| repo | `Package.swift`, `Sources/TunesContract/` (a transcription of the contract; changed only on the lead's instruction), `Scripts/`, `Config/`, `Resources/`, `Support/` (Info.plist, entitlements), `README.md`, `LICENSE`, `CHANGELOG.md`, `.gitignore`, `.github/` |
| engine | `Sources/TunesContract/GenreRules.swift` (the one file of that target with logic; the repo role leaves a stub), `Sources/TunesRules/`, `Sources/TunesEngine/`, `Sources/tunes-lifeline/`, `Tests/TunesRulesTests/`, `Tests/TunesEngineTests/`, `Tests/TunesFakes/` |
| app | `Sources/TunesPanel/`, `Sources/SwiftTunes/`, `Tests/TunesPanelTests/`, `Tests/SwiftTunesTests/` |

Targets:

- `TunesContract`: types and the engine protocol. No logic beyond coding.
- `TunesRules`: the pure rules of the engine [R1 to R59 where pure]. No I/O.
  Depends on `TunesContract`.
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

An updater, a
global shortcut, a Nix package, measurements on any other Mac.

## Removing the music model

- The status item's menu has `Remove Music Model…`, enabled when any model
  file or part file is on disk. It asks first, in an alert: title `Remove
  the music model?`, text `It frees X.XX GiB. Composing stops until it is
  downloaded again; your tunes stay.`, buttons `Remove` and `Cancel`.
- Removing turns the composer off, cancels any job and any download, stops
  the server, and deletes the model files and their part files from the
  app's models folder: only the names the pins list, nothing else there.
  `setup` becomes `missing`. Playback is not interrupted.
- Without the model the player stays usable: kept tunes play as before. The
  setup cards show only when no genre has a kept tune. Otherwise the
  composer bar stands in for them: `The music model is not on this Mac.`
  with a `Download` button and the size; while downloading, the progress
  line, speed and `Cancel`; after a failure, the error and `Resume`. The
  switch is absent until the model is ready.
- A failure to delete shows `could not remove the music model: <error>` in
  the strip; whatever was deleted stays deleted.

## The round and Previous

This section wins over "The queue" where they differ.

- **The round is one list** in a fixed order: the tunes already played this
  round (`played`, oldest first), the playing tune, then `queue`. A tune's
  number is its place in that list and does not change as the round goes
  on. Played tunes are not removed when they end.
- **What moves.** A newly made tune is inserted right after the playing
  tune (it plays next), so the tunes after it move down by one. A scrapped
  tune leaves the list; undo puts it back where it was. Turning shuffle on
  or off redraws only `queue`.
- **Previous.** More than 3 seconds into a tune it restarts it. Within the
  first 3 seconds it goes back one: the last of `played` becomes the
  playing tune and the tune that was playing becomes the first of `queue`,
  ahead of any new tune. With nothing in `played` it restarts. It never
  reaches a scrapped tune or an earlier round. The Previous media key and
  the Now Playing control do the same.
- **Play it again.** Playing a tune of `played` jumps back to it: it becomes
  the playing tune, and every tune after it in the list, the one that was
  playing included, returns to `queue` in list order.
- **The end.** With repeat all, when the last tune ends a new round is drawn
  and `played` empties. With repeat off the round ends: nothing plays,
  `ended` is true and `played` holds the whole round. Starting over draws a
  new round. Repeat one is unchanged and adds nothing to `played`.
- `played` is not saved; after a restart the round starts afresh.
- **In the player.** The controls gain Previous, left of play (tooltip
  `Previous`), dimmed when nothing plays. The list's heading is `THIS ROUND`
  with `N of M` at the right (the playing tune's number, the round's
  length). Three rows of the round, always consecutive: the playing tune,
  highlighted, with a small level meter in place of its number (still when
  paused), then the next two with their numbers. When fewer than two tunes
  follow, the window keeps its three rows by reaching back: played rows,
  dimmed, sit above the playing one (a round of two with the second playing
  shows 1 and 2; the last of twelve shows 10, 11 and 12). With nothing playing: the next three, and the right-hand
  text is `M tunes`. Under them `then N more this round · Show all` when
  more follow. BEING MADE is unchanged.
- **The queue card** becomes the round: label `THIS ROUND · M TUNES`, title
  `This round`, at the right the modes (`shuffled` or `in the order made`,
  then `repeat all`, `repeat one` or `repeat off`, joined by ` · `). Every
  row in list order: played rows dimmed, the playing row highlighted, the
  rest plain. Opening it, and each change of tune while it is open, brings
  the playing row into view. Hover on a played row offers `Play it again`,
  share and scrap; on a waiting row, play it now, share and scrap. Last
  line: `after these, a new round is drawn`, or with repeat off `The round
  ends after <t>.`

## The list is a playlist

This section wins over "The round and Previous" and "The queue" where they
differ. Everything about order, Previous, Play it again and what moves
stays as written there.

- **Nothing is hidden.** The player shows the whole round as one scrolling
  list under `THIS ROUND`: every played tune (dimmed), the playing tune
  (highlighted, with the level meter in place of its number), and every
  waiting tune, each at its fixed number. There is no three-row window, no
  `then N more` line and no separate round card; `Show all` is gone.
- **The list area** is four rows tall and scrolls (the AppKit scroll box),
  with the soft fade at an edge that has more beyond it. A round of four or
  fewer shows whole, with no scrolling and no empty space kept for missing
  rows.
- **It follows the music, gently.** When the playing tune changes, the list
  scrolls just enough to bring the playing row into view, placing it second
  from the top when the round is long enough, so the one before it and the
  two after it show. It does not scroll while the pointer is over the list
  or within three seconds of the user scrolling it. Opening the popover
  places it the same way.
- **Rows never jump on their own.** A tune ending changes only which row is
  highlighted. The only insertions and removals are the three causes
  already listed (a new tune after the playing one, a scrap or its undo, a
  redraw of what is waiting when shuffle changes), and each is animated in
  place.
- The right-hand text of the heading stays `N of M`, or `M tunes` with
  nothing playing, or `nothing`. BEING MADE sits under the list, unchanged.

## Volume

This section adds to "Layout of the popover" and wins where they differ.

- **What it is.** One level for this app's sound, from 0 (silent) to 1
  (full), applied to the engine's player. It is not the Mac's output
  volume and never changes it. A new installation starts at 1.
- **Where.** A row of its own in NOW PLAYING, under the round controls,
  as wide as the card: a small speaker, the slider, a speaker with waves.
  The two speakers are marks, not buttons. The slider is the system's
  control, so its glass is the system's. No number is shown. The tooltip
  and the accessibility label are `Volume`. The row is there whenever the
  round controls are.
- **Dragging.** The sound follows the pointer. While the pointer holds the
  slider the app sends `setVolume(to:dragging: true)` for each new place,
  in steps of 0.01, and draws its own place, not the snapshot's; on release
  it sends the last place with `dragging: false`. A click on the track is
  a drag that ends at once.
- **The engine** clamps the level to 0…1, ignores one that is not finite,
  applies it to the player at once and reports it as `volume`. A level
  equal to the current one produces no snapshot. The command writes `state.json`
  only with `dragging: false`, and the engine writes it at shutdown; a drag
  writes the file once. A save made for another reason during a drag holds
  the level of that moment. At launch the saved level is applied before anything
  plays; a state file with no level, or one out of range, reads as 1.
- The level holds across tunes, stop and play, genres and rounds. Muting
  in tests is separate from it. Now Playing and the media keys have no
  part in it.

## Releases

This section wins over decision 5 as first written and over "Not in this
round".

- **What a release is.** `SwiftTunes-<version>.zip` holding only
  `SwiftTunes.app` (arm64, macOS 26 or later), and
  `SwiftTunes-<version>.zip.sha256`, on a GitHub release of the tag
  `v<version>`. The app and both helpers are signed with the owner's
  Developer ID with the hardened runtime and a secure timestamp, with no
  entitlements; the app is notarized and the ticket stapled before it is
  zipped. The model files are not in it.
- **The version** lives in `Support/Info.plist`
  (`CFBundleShortVersionString`, and `CFBundleVersion` equal to it). The tag
  is `v` followed by it, or by it and a hyphen and a suffix for a
  pre-release (`v0.2.0-rc.1` with `0.2.0` in the plist).
- **The changelog.** `CHANGELOG.md` is written for the people who use the
  app, newest first: `## Unreleased`, then one `## <version>` section per
  release. A change a user can notice adds a line under `Unreleased` as part
  of its own work. Releasing is one commit on `main` that renames
  `Unreleased` to the version, sets the version in the plist and opens a new
  empty `Unreleased`. `Scripts/release-notes.sh <version>` prints that
  version's section and fails when there is none; the release's text is its
  output.
- **Signing in the scripts.** `Scripts/sign-app.sh <app>` signs an assembled
  bundle, the two helpers and then the bundle: ad hoc unless
  `SWIFTTUNES_SIGN_IDENTITY` names an identity, and with one,
  `--options runtime --timestamp`. It builds nothing and runs nothing but
  `codesign`. `Scripts/make-app.sh` builds, assembles and ends by calling
  it, so a local build is one command as before. Neither notarizes: that is
  the workflow's.
- **Notices.** The bundle carries `LICENSE` and `ThirdPartyNotices.txt` in
  `Contents/Resources`: the notice and permission text of each project
  compiled into `ace-server` (acestep.cpp; ggml, with the copyright line of
  the code it carries from others; cpp-httplib; yyjson), copied from the
  pinned sources. `make-app.sh` fails without either file. A new pin is not
  done until the notices were checked against it.
- **No web page in the server.** `ace-server` is built with an empty
  `tools/public/index.html.gz`, so it serves nothing at `/`. `Scripts/build-ace-server.sh` makes exactly two changes in
  its cached checkout: it empties that file, and it quotes the one variable
  in `tools/xxd.cmake` that makes the embedding step fail on an empty file.
  It checks that the file is empty and that `xxd.cmake` differs from the
  pinned revision by that line alone; any other change to a tracked file still stops
  it.
- **The workflow** (`.github/workflows/release.yml`) runs on a pushed `v*`
  tag, in two jobs. The first runs in the `release` environment, which
  holds the secrets and accepts only `v*` tags, with a token that can only
  read the repository. In order: the tag's commit is on `main`, the tag
  matches the plist and the changelog has the section, all before any
  secret is used; `swift test`; `make-app.sh` with no identity, so every
  build step and all code from elsewhere has run before the key exists;
  then the identity is imported into a temporary keychain whose password is
  made for the run, and `sign-app.sh` signs; notarize, staple, zip,
  checksum; the zip is expanded again and that copy passes
  `codesign --verify --deep --strict`, `stapler validate` and `spctl
  --assess`. Its build cache is the run's own folder. The keychain and the
  key files are removed whatever happened. The second job has no secrets
  and uses no action from outside GitHub: it takes the zip, the checksum
  and the notes from the first and makes a **draft** release, with the one
  token that can write. A tag with a hyphen makes a pre-release: the plist
  and the changelog section carry the part before the hyphen, the zip is
  named after the whole tag. A run publishes nothing; one that fails while
  uploading may leave a draft, which the owner deletes.
- **The same tools everywhere.** Xcode 27.2 builds, tests and
  releases, on the owner's Mac and on the runners: each workflow's first
  step selects it and fails when `xcodebuild -version` does not say
  `Xcode 27.2`. The workflows that build the app install
  Nix and run `nix develop -c Scripts/make-app.sh`, so `cmake` is the one
  `flake.lock` pins. `ci.yml` builds the ad-hoc app on every push, and
  checks that the changelog has a section for the plist's version.
- **Secrets.** No workflow uses `pull_request_target`. A secret reaches a
  step only through `env:` and is used as a quoted shell variable; none is
  written into a workflow's script text, echoed, or put in an uploaded
  file. Every action a
  job with secrets uses is pinned to a full commit hash.
- **Tags.** The owner pushes the tag and publishes the draft. A tag whose
  run failed, or whose draft was thrown away, may be deleted and pushed
  again; a tag with a published release never moves.
- **Done** for a release: the run is green, and the owner has opened the
  downloaded zip on a Mac with no Gatekeeper warning, composed a tune and
  heard it.

## The icon

- **The picture.** A white swift in a wide glide under a pair of lavender
  beamed notes, on near-black. Its source is `Resources/AppIcon.png`:
  1024 px square, the art filling the whole square, no rounded corners of
  its own.
- **The icon file.** `Resources/AppIcon.icns` is made from the source by
  `Scripts/make-icon.sh`, with Apple's tools only: the art is clipped to the
  macOS icon shape, a rounded square inset in the canvas, and written at
  every size from 16 to 1024 points, at 1x and 2x. It also writes `docs/screenshots/icon.png`, the
  256-pixel member, for the README. All three files are committed;
  a build does not make the icon again. A new picture means running the
  script and committing all three.
- **In the bundle.** `Support/Info.plist` names it (`CFBundleIconFile`),
  `Scripts/make-app.sh` copies it into `Contents/Resources` and fails
  without it.
- The status item keeps its own symbol; the icon is what Finder, Login
  Items and the release page show.

## New tunes join the end

This section wins over "The queue", "The round and Previous", "The list is a
playlist" and "Singing" where they say a new tune plays next.

- **Where a new tune goes.** A tune the composer finishes joins the end of
  the round: it becomes the last of `queue`, after every tune already
  waiting, and plays when the round reaches it. Nothing already listed
  moves or changes its number; only the round's length grows by one. An
  own-words tune is the same.
- **With nothing waiting** the new tune is the whole of `queue`, so it is
  what plays next: the first tune of a genre still starts by itself, and a
  tune finished after a round ended with repeat off still plays.
- **Shuffle and new rounds.** Changing shuffle redraws the kept tunes that
  wait and leaves the waiting new tunes after them, in the order they were
  made. A new round drawn while new tunes wait puts them last too.
- **Previous** puts the playing tune back first in `queue`, as before; a new
  tune no longer goes behind it, it goes last.
- **The composer** is unchanged: it keeps `ahead` (2) finished new tunes
  waiting and rests until one of them starts. With a long round that means
  it rests for most of the round; that is accepted.
- **The list's changes** are now: a new tune added at the end, a scrap or
  its undo, a redraw of what is waiting when shuffle changes.
- **Wording.** BEING MADE's right-hand text is `joins the round when ready`.
  The own-words sheet says `It is made once, with the genre's sound, and
  joins the end of the round when ready.` Repeat one's line about new tunes
  waiting is unchanged.
- **Done:** the tests of the engine and the panel that put a new tune first
  expect it last; the panel fixtures whose `queue` shows new tunes first
  show them last; the README's screenshots made from those fixtures are
  taken again; `SessionTests` follows the engine's real snapshots.

## Rows that join and leave

This section wins over "The list is a playlist" where it says an insertion
or a removal is animated in place.

- A row that joins THIS ROUND or leaves it does so at once, with no fade
  and no scaling: inside a glass container a fade reaches a row's content
  but not its glass, so the glass would stand empty while the content
  fades. The rows around it still slide to their places.
- A change that only reorders the rows (shuffle changed, a new round drawn)
  is not animated: the list is simply drawn in its new order.
- **Version.** These two rules and "New tunes join the end" are release
  0.1.1. The 0.1.0 section of the changelog describes 0.1.0 as it was
  built; what changed since is listed under `Unreleased` until the release
  commit names it 0.1.1.

## Music models

This section wins over decision 14, "Removing the music model" and every
earlier sentence that assumes one model. It is release 0.2.0.

- **The models.** Two, of one family, sharing three files (the diffusion
  model, the text encoder, the VAE: 3.42 GiB) and differing in the
  language model: `small`, shown as `Small`, variant `0.6B Q8`, its file
  `acestep-5Hz-lm-0.6B-Q8_0.gguf` (709,846,656 bytes); `large`, shown as
  `Large`, variant `4B Q8`, today's file. `Config/pins.json` lists them,
  each with its file, hash, memory figure and the installed memory from
  which it is suggested. The list is open: a third model is a new entry,
  not new code. The 1.7B model is not offered: at Q8 it computes garbage
  on Metal, and at full precision it is nearly as heavy as Large.
- **Measured** (M1 Max, 64 GiB, one instrumental and one sung tune each):
  Small peaks at 3.1 GiB and takes about 40 s a tune; Large peaks at
  7.2 GiB and takes about 50 s. The figures quoted are `about 4 GiB of
  memory` for Small and `about 8 GiB of memory` for Large.
- **The suggestion.** The engine reads the Mac's installed memory once.
  Under 24 GiB the suggested model is Small; from 24 GiB, Large. It only
  pre-selects; any model may be chosen on any Mac.
- **The chosen model** is the one new tunes are made with. While no model
  is on disk it is the one `download` fetches, and starts as the suggested
  one. Once a model is on disk only a model on disk can be chosen. It is
  saved in `state.json`; a state file without it means the model on disk
  (Large when both are), so an existing installation carries on as it was.
  A change applies from the next tune: a tune being made is finished with
  the model it started with.
- **The server.** Every `/lm` request names its model's file in
  `lm_model`. Without it the server takes the first language model by file
  name, which would be the smallest on disk whatever was chosen.
- **First run.** The setup card lists the models as rows under its
  sentence: a round mark (filled for the chosen one), the name with the
  variant small beside it, `Suggested` on the suggested one, and under the
  name `X.XX GiB download · about N GiB of memory`. A click on a row
  chooses it. Under the rows: `This Mac has N GiB of memory. Large follows
  the prompt and the words more closely; Small is quicker and lighter. You
  can add the other later.` The `download` and `free on disk` rows and the
  button stay; the `memory while composing` row goes, its figure now being
  in each model's row. The composer bar's stand-in (kept tunes, no model)
  is unchanged and fetches the chosen model.
- **The composer bar.** Its model line reads `ACE-Step 1.5 Turbo ·
  <device>` and ends in a capsule with the chosen model's name and a
  chevron, in the genre button's style, tooltip `Music models`. It opens
  the models card. The capsule shows whenever the model line does, and
  also when the composer is off or resting, on a line of its own, so the
  card is always one click from the player.
- **The models card** (`MUSIC MODELS`, with `Back`): title `Music models`,
  then `New tunes are made with the ticked one. A change applies from the
  next tune.` One row per model: a tick on the chosen one; the name and
  variant; under them `X.XX GiB on this Mac · about N GiB of memory` or
  `X.XX GiB to download · about N GiB of memory`; at the right `Use` (on
  disk, not chosen), `Remove` (on disk; absent on the chosen one while
  another is on disk), or `Download` (not on disk). While a model
  downloads its row shows the bar, `X of Y GiB · <speed>` and `Cancel`,
  and no other row offers `Download`. A failed download shows its error
  and `Resume` in that row. Under the rows: `Both share 3.42 GiB of other
  files, kept while a model remains. This card is also under Music
  Models… in the menu bar icon's menu.`
- **Downloading another model** is allowed while music plays and while
  the composer works; composing carries on with the chosen model. One
  download at a time. It fetches the model's own file, and any shared file
  that is missing.
- **Removing.** `Remove` asks first: title `Remove <name>?`, text `It frees
  X.XX GiB. Your tunes stay.`, buttons `Remove` and `Cancel`. It deletes
  that model's file and its part file, nothing else. The chosen model
  cannot be removed while another is on disk: choose the other first. The
  only model on disk is removed as "Removing the music model" says (the
  shared files go too, composing stops), with that section's alert.
- **The menu.** `Remove Music Model…` becomes `Music Models…`, always
  enabled. It opens the popover on the models card.
- **Sing my words.** With more than one model on disk the sheet has a row
  `Model` under `Name`: one capsule per model on disk, the one in use lit,
  starting on the chosen model. That tune alone is made with it.
- **What is kept per model:** the stage timings behind the estimates, in
  `state.json` (the timings already saved are Large's). A tune's file
  records the model that made it, in its tags; it is shown nowhere.
- **Holds, failures, the keep rule, the round** are unchanged.
- **Only what the pins name.** Deleting touches only files the pins list;
  a language-model file the pins do not name is neither used nor deleted.
- **Done:** rules tests for the pins with two models, each choice's
  download size and the suggestion at 8, 16, 24, 32 and 64 GiB; engine
  tests against the fake server: `lm_model` on every `/lm`, a change
  applying from the next tune, the words tune using its own model, the
  choice surviving a restart, an old state file, first download of each
  choice, a second model fetching one file, one download at a time,
  removing one, removing the last, refusing the chosen one, timings per
  model, the tag; panel tests for every row, sentence and button state
  above and equality for each new field; `SessionTests` through a first
  run choosing Small; one real-server tune with each model on the real
  Mac; the README, the changelog and the screenshots that change.

## Music models: what a review settled

This section adds to "Music models" and wins where they differ.

- **The choice never moves by itself.** The first model to be complete on
  disk becomes the chosen one and is saved then, whichever command fetched
  it. A model downloaded later is never chosen until `Use` is pressed.
  When the chosen model's file is no longer on disk (deleted outside the
  app) and another model is, the other becomes the chosen one and is
  saved: downloading the first again does not switch back.
- **Checked before each tune.** Before a tune is started the engine looks
  at the files. With the chosen model gone and another on disk, the choice
  moves as above. With no model on disk, `setup` becomes `missing` and the
  composer stops, as after a removal. `setup` and `models` never disagree
  in one snapshot.
- **Resume follows the download.** Wherever a failed or cancelled download
  is offered again (the setup card, the composer bar's stand-in, a row of
  the models card), it carries on with the model that download was for:
  `download` when that is the chosen model, `downloadModel` otherwise.
- **Removing is decided when it happens.** A row's `Remove` always sends
  `removeOneModel` with that model's id; the engine decides then whether
  it is the only model on disk. The alert shown is chosen from what was on
  screen: `Remove <name>?` with another model on disk, the one of
  "Removing the music model" without.
- **A model with only a part on disk** (a download cancelled or failed)
  shows in its row `X.XX of Y.YY GiB downloaded`, with `Resume` and
  `Remove`. `Remove` deletes the part; with no complete model on disk it
  removes everything, shared files and their parts included.
- **Removing a model a tune is being made with** (a words tune made with
  the other model): the tune starts over with the chosen model.
- **The footnote** is computed: `The models share X.XX GiB of other files,
  kept while a model remains. This card is also under Music Models… in the
  menu bar icon's menu.` The figure is the snapshot's `sharedBytes`.
- **With no memory figure** (`memoryBytes` 0) the sentence under the setup
  card's rows starts at `Large follows…`.
- **The pins are checked:** choices must run by rising
  `suggested_from_bytes`, and no file name may appear twice; otherwise the
  pins are in error, as for any other fault in that file.
- **Tests added for:** every one of the above; `lm_model` on a rewrite
  after thin words and on the request after a failure; the first download
  made through `downloadModel`; the suggestion with 0 bytes and at exactly
  24 GiB with the real thresholds; the contract's new fields encoding, and
  decoding when absent.

## Shuffle starts off

A new installation starts with shuffle off: a round plays the kept tunes in
the order they were made, newest last. A state file that says nothing
about shuffle reads as off. A saved choice is kept as it is. Repeat still
starts as all. This is part of release 0.2.0.
