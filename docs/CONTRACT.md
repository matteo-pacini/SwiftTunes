# The contract between the engine and the app

This is the only source for what passes between `TunesEngine` and the app
(`TunesPanel`, `SwiftTunes`). `Sources/TunesContract/` is its transcription
into Swift and must agree with it field for field. Only the lead changes
either. Version: 1.

[R…] cites the numbered rules of the working rule notes (untracked working
material the lead hands to each role).

## Shape

One process. The engine is a main-actor object the app holds through a
protocol. The app never reads the engine's files, never talks to
`ace-server`, and never plays audio itself. The engine never touches AppKit,
the pasteboard, Finder, Now Playing or the status item.

```swift
@MainActor
public protocol EngineAPI: AnyObject {
    /// The latest state. Always complete; never partially updated.
    var snapshot: Snapshot { get }

    /// Calls `handler` once now with the current snapshot, then after every
    /// change, at most once per main run loop pass. Returns a token; the
    /// observation ends when the token is cancelled or released.
    func observe(_ handler: @escaping @MainActor (Snapshot) -> Void) -> SnapshotObservation

    /// Fire and forget. A command that does not apply is ignored silently and
    /// produces no snapshot. Never throws, never blocks.
    func send(_ command: Command)

    func genre(id: String) async -> Result<GenreFields, Refusal>
    func saveGenre(id: String?, fields: GenreFields, base: GenreFields?) async -> Result<GenreSaved, Refusal>
    func deleteGenre(id: String) async -> Result<Void, Refusal>
    func shareInfo(for target: TuneTarget) async -> Result<ShareInfo, Refusal>
    func setPinned(_ on: Bool, for target: TuneTarget) async -> Result<PinResult, Refusal>
    func exportCopy(of target: TuneTarget) async -> Result<URL, Refusal>
    func renameTune(_ target: TuneTarget, to name: String) async -> Result<String, Refusal>
    func composeWithWords(_ words: String, name: String) async -> Result<Void, Refusal>
    /// A two-word name drawn from the selected genre's own lists, as the
    /// composer names its tunes; a fresh pick on each call. Empty when no
    /// genre is selected.
    func suggestTuneName() -> String

    /// Stops the player, cancels the job, stops the server and waits until no
    /// child process remains. Called once, while the app is terminating: the app
    /// answers applicationShouldTerminate with terminateLater and replies when
    /// this returns.
    func shutdown() async
}

public protocol SnapshotObservation: AnyObject { func cancel() }
```

A result that causes a state change is delivered before the snapshot it
causes is observed [notes (b), "Replies"].

The app constructs the live engine with one call owned by the engine module:

```swift
@MainActor public func makeLiveEngine(_ bootstrap: EngineBootstrap) -> EngineAPI

public struct EngineBootstrap: Sendable {
    public var aceServer: URL        // Contents/Helpers/ace-server
    public var lifeline: URL         // Contents/Helpers/tunes-lifeline
    public var defaultGenres: URL    // Contents/Resources/genres.json
    public var pins: URL             // Contents/Resources/pins.json
}
```

`makeLiveEngine` does not start playing or composing. It reads the state
file, the genres file (copying the default one in if none exists) and the
kept tunes, and the first snapshot reflects them.

## Snapshot

`Snapshot` is `Codable`, `Equatable` and `Sendable`. Its JSON form uses the keys below, so the test fixture files decode into
it. Times are Unix
seconds as `Double`. Sizes are bytes as `Int64`. A field marked optional is
`null` in JSON, never absent.

| Swift | JSON key | Type | Meaning |
|---|---|---|---|
| `version` | `v` | `Int` | Always 1. |
| `setup` | `setup` | `Setup`: `missing`, `downloading`, `ready`, `failed` | Whether the four model files are in place [R48]. |
| `download` | `download` | `Download?` | Present while downloading, and kept with its `error` after a failure; nil after a cancel or once done. |
| `need` | `need` | `Need` | What setup needs. |
| `genres` | `genres` | `[GenreSummary]` | In file order. |
| `genre` | `genre` | `String?` | The selected genre's id. |
| `keptTotal` | `kept_total` | `Int` | Kept tunes of the selected genre (pinned included). |
| `composing` | `composing` | `Bool` | The composer switch. |
| `ahead` | `ahead` | `Int` | How many finished new tunes the composer keeps ahead (2). |
| `player` | `player` | `PlayerState`: `none`, `playing`, `paused` | |
| `stopped` | `stopped` | `Bool` | A genre is picked and the player is not meant to play [R20]. |
| `tune` | `tune` | `PlayingTune?` | The playing (or paused) tune. |
| `pos` | `pos` | `Double` | Position in seconds, true at `posAt`. |
| `posAt` | `pos_at` | `Double` | When `pos` was sampled. |
| `queue` | `queue` | `[QueuedTune]` | What plays next, in order [R1]. Command indexes refer to this array. |
| `played` | `played` | `[QueuedTune]` | The tunes already played this round, oldest first; the playing tune is not in it (spec, "The round and Previous"). Decodes as empty when absent. |
| `shuffle` | `shuffle` | `Bool` | |
| `repeat` | `repeat` | `RepeatMode`: `all`, `one`, `off` | |
| `ended` | `ended` | `Bool` | Repeat is off and every kept tune was played this round [R9]. |
| `roundLeft` | `round_left` | `Int` | Kept tunes not yet played this round. |
| `keep` | `keep` | `Int` | The newest-N rule's N (50). |
| `ready` | `ready` | `Int` | Finished new tunes waiting in the queue. |
| `keptPlaying` | `kept_playing` | `Bool` | The playing tune is a kept one and `ready` is 0. |
| `canNext` | `can_next` | `Bool` | Next would do something [R16]. |
| `job` | `job` | `Job?` | The tune being made, if any. |
| `expect` | `expect` | `Expect?` | Median stage times of the last five tunes; nil until both stages have been timed once [R41]. |
| `undo` | `undo` | `Undo?` | An offered undo. |
| `model` | `model` | `Model` | The composer's model and its state. |
| `error` | `error` | `String?` | One line for the strip over the player: the first present of the pins file's error, the genres file's error, the play error, the file error. Plain text. |

`Download`: `file` (`Int`, 1-based), `files` (`Int`), `name` (`String`: one of
`language model`, `diffusion model`, `text encoder`, `VAE`), `done`
(`Int64`, over all files), `total` (`Int64`), `rate` (`Double`, bytes per
second), `error` (`String?`).

`Need`: `downloadBytes` / `download_bytes` (`Int64`, still to fetch [R49]),
`onDiskBytes` / `on_disk_bytes` (`Int64`: what the model files and parts take
now, the figure removal would free),
`diskFreeBytes` / `disk_free_bytes` (`Int64`), `ramBytes` / `ram_bytes`
(`Int64`, 8 GiB: the figure the wording quotes).

`GenreSummary`: `id`, `name`, `kept` (`Int`), `sung` (`Bool`), `palette` (`[String]?`: four
colours as `#RRGGBB`, nil when the genres file gives none; the panel then
makes one from the name).

`PlayingTune`: `name` (`String`: the title once read, the file stem until
then), `file` (`String`: the file stem, no extension), `bpm` (`Int?`), `key`
(`String?`), `length` (`Double?`, nil until read), `kept` (`Bool`), `new`
(`Bool`, always `!kept`), `pinned` (`Bool`), `pos` (`Int?`: 1-based place in
the order made, only when kept and shuffle is off), `wave` (`[Double]`, 78
values in 0…1, empty until read).

`PlayingTune` and `QueuedTune` also carry `sung` (`Bool`: the file has
words). `PlayingTune` alone carries `lyrics` (`String?`: the words as
written, nil when not sung).

`QueuedTune`: as `PlayingTune` without `wave` and `lyrics`. `queue` holds
the whole rest of the round in play order (spec, "The queue"), not only the
next few.

`Job`: `stage` (`JobStage`: `writing`, `rendering`), `sung` (`Bool`), `ownWords`
(`Bool`), `name` (`String?`: the name given to an own-words tune, else nil), `started` (`Double`), `expectS` /
`expect_s` (`Double?`: the median for this stage), `writtenS` / `written_s`
(`Double?`: how long writing took, set while rendering).

`Expect`: `writingS` / `writing_s`, `renderingS` / `rendering_s` (`Double`).

`Undo`: `name` (`String`), `until` (`Double`), `genre` (`String?`: the id of
the genre whose folder the tune returns to, nil if that genre is gone).

`Model`: `name` (`String`, `ACE-Step 1.5 Turbo`), `variant` (`String`,
`4B Q8`), `device` (`String`: the Metal device's name from the server's log,
or `Metal` before one was seen), `state` (`ModelState`), `since` (`Double`),
`silenceS` / `silence_s` (`Int?`: seconds of silence in the plan being
rewritten), `thinWords` / `thin_words` (`Bool`: the plan being
rewritten had too few sung lines), `detail` (`String?`: the failure's text, plain), `failures`
(`Int`), `retryAt` / `retry_at` (`Double?`), `ramUsedBytes` /
`ram_used_bytes` (`Int64?`: the server's footprint while it runs),
`ramFreeBytes` / `ram_free_bytes` (`Int64?`: always nil on the Mac).

`ModelState`: `unloaded` (composer off), `starting`, `idle` (composer on and
resting, no server process), `writing`, `rendering`, `held_memory`,
`held_power`, `held_heat`, `failed`, `no_device`.

### Notes on values

- `model.ram_free_bytes` is always null: the system gives a pressure level,
  not a trustworthy free figure.
- `need.ram_bytes` is 8 GiB.
- Unknown enum values do not decode; there is no older or newer peer.

## Commands

```swift
public enum Command: Sendable, Equatable {
    case selectGenre(id: String)       // unknown or already selected: ignored [R13]
    case toggle                        // [R15]
    case play                          // as toggle when paused, stopped or ended; nothing when playing
    case pause                         // nothing unless playing
    case stop                          // halts; `stopped` becomes true [R20]
    case next                          // only when canNext [R16]
    case previous                      // spec, "The round and Previous"; nothing when no tune plays
    case playPlayed(index: Int, name: String)   // index into `played`; ignored unless that tune is there
    case scrapPlayed(index: Int, name: String)  // index into `played`; the tune leaves the round, with the usual undo
    case seek(to: Double)              // seconds, clamped to 0…length
    case setComposer(on: Bool)         // [R14]
    case setShuffle(on: Bool)          // [R8]
    case setRepeat(RepeatMode)         // [R8]
    case scrapPlaying(name: String)    // [R25]
    case scrapQueued(index: Int, name: String)
    case scrapJob                      // cancels the tune being made; no undo
    case undo                          // [R26]
    case playQueued(index: Int, name: String)   // [R17]
    case retry                         // only in failed or no_device [R42]
    case download
    case cancelDownload
    case removeModel                   // spec, "Removing the music model"; ignored when nothing is on disk
    case refresh                       // re-reads the genres file and memory, then notifies
}

public struct TuneTarget: Sendable, Equatable {
    public var name: String            // the tune's name or its file stem
    public var index: Int?             // nil: the playing tune, else a queue index
    public var inPlayed: Bool          // false by default; true: `index` is an index into `played`
}
```

Every command aimed at a tune carries its name. The engine acts only if the
tune at that place (the playing tune, or `queue[index]`) has that name or
that file stem [R28]; otherwise `send` does nothing and the async calls
return the refusal `That tune is no longer there.` For a `TuneTarget` with
no index and no match, the engine looks the name up as a file in the
selected genre's folder [R33].

`play`, `pause` and `stop` exist for the media keys; the popover's button
sends `toggle`.

## Results

`GenreFields`: `name` (`String`), `caption` (`String`), `turns`
(`[String]`), `bpm` (`[Int]`, exactly two: slowest, fastest), `sung` (`Bool`,
the genres file's optional `sung` key, written only when true), `palette`
(`[String]?`, four `#RRGGBB` colours or nil; saved as the genre's optional
`palette` key, removed from the file when nil; anything else is refused
with `A palette is four colours.` and no field). Sent to
`saveGenre` untrimmed; the engine trims and drops blank and repeated
variations [R52]. `base` is the value `genre(id:)` returned, unchanged, and
is nil for a new genre [R55].

`GenreSaved`: `id` (`String`), `renamed` (`Renamed?`: `from`, `to`, the
genre names, when the folder moved).

`Refusal` (an `Error`, `Sendable`, `Equatable`): `field` (`GenreField?`: `name`, `caption`, `turns`, `bpm`; nil
when the refusal names no field) and `text` (`String`, a full sentence,
plain). The texts are those of the notes' section (c), "Genre editor" and
"Share sheet", with the changes in `docs/SPEC.md`, "Wording".

`ShareInfo`: `name`, `genre` (the folder's name), `bpm` (`Int?`), `key`
(`String?`), `length` (`Double?`), `bytes` (`Int64`), `path` (`URL`, the
file), `exportPath` (`URL`, where an export would go), `pinned` (`Bool`).

`PinResult`: `on` (`Bool`), `name` (`String`).

`exportCopy` returns the URL written.

`renameTune` gives a tune a new name and returns the name as saved. The
engine trims it, checks it with `TuneRules.nameError`, and rewrites the
title tag of the file in place (a tagged copy beside it, then an atomic
replace; the file's own name, which holds when it was made, its tempo and
its key, does not change). The wave cache and the next snapshot carry the
new name. A name equal to the current one succeeds and writes nothing.
Refusals: `That tune is no longer there.`, a `TuneRules` sentence, or
`could not rename <t>: <error>`; `field` is always nil.

```swift
public enum TuneRules {
    public static let nameMax = 60
    /// The first rule a tune's name breaks, or nil. Checked on the trimmed
    /// name, in this order, with these sentences:
    ///   `A tune needs a name.`
    ///   `A name cannot hold control characters or line breaks.`
    ///   `A name is at most 60 characters; this one has N.`
    public static func nameError(_ name: String) -> String?
}
```

Like `GenreRules`, this is shared so the field and the engine cannot
disagree; the engine role owns the file and its tests.

`composeWithWords` asks for one tune sung with the given words in the
selected genre (spec, "Singing"). It returns once the request is accepted;
the tune then shows as the job. Refusals (no field): a `WordsRules` or
`TuneRules` sentence, `A tune with your words is already being made.`, and
`That genre is not sung.` when the selected genre has the switch off.

```swift
public enum WordsRules {
    public static let max = 2000
    /// Non-empty lines that do not start with "[".
    public static func sungLines(_ words: String) -> [String]
    /// For words the user wrote: `A tune needs at least one sung line.` or
    /// `The words are at most 2,000 characters; these have N.`, else nil.
    public static func wordsError(_ words: String) -> String?
    /// For words the model wrote: fewer than 6 sung lines, or fewer than 4
    /// different ones compared without case.
    public static func tooThin(_ words: String) -> Bool
}
```

Result types are `Sendable` and `Equatable`; they are not coded. Enum cases
are camel case in Swift with the snake-case raw values given here.
`TunesRules` may use the contract's types; `TunesFakes` uses none.

## Who decides what

| Thing | Engine | App |
|---|---|---|
| Which tune plays next, rounds, shuffle, repeat | decides [R1 to R12] | shows |
| The player and its events | owns | sends commands |
| Now Playing info and remote commands | no | owns; maps remote commands to `play`, `pause`, `toggle`, `next`, `seek`, `stop`, and fills the info from the snapshot |
| Composing, the server, holds, retries, timings | owns | shows |
| Files: tunes, keep rule, pins, scrap and undo, export | owns | never touches |
| Genres file, validation on save | owns; its refusal is final | validates as the user types with the same rules and sentences, so a save that passes locally is only refused for what the file knows [R97] |
| Copy the file, copy its path, show it in Finder | no | does, with `ShareInfo.path` |
| Every sentence the user reads | supplies `error`, `model.detail`, `download.error`, `Refusal.text` | everything else, in `TunesPanel` |
| Position between snapshots | samples `pos` at `posAt` | extrapolates while playing, capped at the length [R66] |
| The 1 s tick for countdowns and the job's clock | no | owns [R65] |
| Start at login, Quit, the version | no | owns |

Validation is the one rule set that exists twice. Both sides implement the
notes' [R53] and [R97] with decision 17: "Line N" counts the lines as typed,
the length is checked before the Exports name, and trimming removes Unicode
whitespace as Swift's `trimmingCharacters(in: .whitespacesAndNewlines)`
does. `TunesRules` exports the function; `TunesPanel` must not reimplement
it differently. To keep one implementation, the shared function lives in
`TunesContract` as `GenreRules.fieldError(...)`, pure, and both call it.

```swift
public enum GenreRules {
    /// The first rule the fields break, in the panel's order, or nil.
    /// `others` are the names of the other genres, for the duplicate rule.
    public static func fieldError(_ fields: GenreFieldsText, others: [String]) -> Refusal?
}

/// The fields as typed: tempos are text until they parse.
public struct GenreFieldsText: Sendable, Equatable {
    public var name: String
    public var caption: String
    public var turns: String        // one per line
    public var slowest: String
    public var fastest: String
}
```

The editor shows one error under each field at once, and marks which tempo
box an error is about, so the same file also gives every field's first
problem:

```swift
public enum GenreBox: Sendable, Hashable { case name, caption, turns, slowest, fastest }

public struct GenreProblem: Sendable, Equatable {
    public var field: GenreField      // slowest and fastest share `bpm`
    public var boxes: Set<GenreBox>   // the boxes to mark; both tempo boxes when slowest is above fastest
    public var text: String
}

extension GenreRules {
    /// At most one problem per field, in the order `fieldError` checks them.
    /// `fieldError` is the first of these as a `Refusal`.
    public static func problems(_ fields: GenreFieldsText, others: [String]) -> [GenreProblem]
}
```

The helpers `trim`, `parseTurns`, `wholeNumber` and the limits are public so
the panel parses and counts exactly as the rules do.

This is the only logic in `TunesContract`. The engine owns its tests.
