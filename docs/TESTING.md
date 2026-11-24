# Testing

How SwiftTunes is tested, and the rules a test or a measurement follows.
`AGENTS.md` has the commands; this says what each layer is for.

## The suites

| Suite | What it covers | Against |
|---|---|---|
| `TunesRulesTests` | The pure rules: silences, rounds and modes over seeded rounds, the keep rule, file and export names, genre and tune and words validation, timings, download arithmetic | Nothing: values in, values out |
| `TunesPanelTests` | The panel's decisions: which card shows, every heading, row, label and sentence, what each control sends | Snapshot fixtures in `Tests/TunesPanelTests/Fixtures` (invented data in the real format) |
| `TunesEngineTests` | The live engine: composing, the round, Previous, scrap and undo, renaming, singing, own words, downloads, removal, holds, failures, stopping | Fakes: a model server and a model host on loopback, a player, a process launcher, hold signals and a manual clock (`Tests/TunesFakes`, `Rig.swift`) |
| `SessionTests` (in the engine suite) | The engine and the panel run together: the engine's own snapshots go through the panel at each step of a session | The same fakes |
| `SwiftTunesTests` | The AppKit pieces behind the SwiftUI views: the scroll box, the plain text editor, the main menu | Views in a hosting view, no window shown |

`swift test` runs all of them with no GPU, no model and no network beyond
loopback.

## Rules for tests

- **A test fails first.** A fix or a rule comes with a test that was seen
  failing before the change. A report says which tests failed first and
  which pass trivially.
- **No waiting on the wall clock.** Time is the injected clock; the rig
  moves it. A test that must wait on a real process, player or server
  waits on its event under a time limit, stops when the process exits, and
  fails with what it saw.
- **The engine suite runs twice:** plainly, and under a CPU limit with
  `taskpolicy -b swift test --filter TunesEngineTests`, because timing
  faults show on a slow machine first.
- **Both layers together.** A change to what the panel shows or the engine
  reports updates `SessionTests`, with each expected value taken from the
  engine's real snapshot, not from a note.
- **Every field counts.** View-state types use synthesised equality.
  `EqualityTests` changes each stored field of each such type and expects
  the values to differ, so a view cannot miss a change.
- **A command carries the tune's name as drawn.** Tests cover a click made
  from a row drawn before the list changed.
- **Fakes are written in Swift**, in the package. Nothing else is needed to
  run the tests.

## The real model server

Tests that start the real `ace-server` are off unless asked for:

- `TUNES_REAL_ACE_SERVER`, `TUNES_REAL_MODELS` and `TUNES_REAL_OUT` enable
  `RealServerTests` (one tune composed end to end; no audio is played).
- `TUNES_REAL_PLANS` also enables the plans-only checks (writing only,
  nothing rendered).

They are never run while another `ace-server` is running: two at once need
about 15 GiB.

## The demo

The app runs without the engine on recorded snapshots:

```sh
SwiftTunes --demo <fixture.jsonl> [--demo-line N] [--demo-open <card>]
```

- `--demo-step <seconds>` walks the fixture's snapshots one after another
  with the popover open.
- `--demo-appearance light` forces the light look.
- `--demo-still` holds the clock, the meter and the backdrop still, for
  screenshots.
- `--demo-probe <log file>` measures main-thread stalls: a 100 ms
  main-actor loop that logs how late each tick is. Run it on any card that gains a scrolling
  region (see `AGENTS.md` on scrolling).

The README's images are demo screenshots: the popover window alone, taken
with `--demo-still`, checked by eye for a half-drawn control and for an
inactive look before they are used.

## Anything that shows a window or makes a sound

A probe, a screenshot run or a listening test happens on the owner's
screen and speakers, so:

- Ask first, and say how many windows and for how long.
- The script has a fixed count it cannot exceed, ends itself after a stated
  time whatever happens, and never retries. A bad result is reported, not
  rerun.
- Stop processes by their process ID, never by name: the owner may be
  running the real app.
- No sound unless the owner asked for it.

## What tests do not show

Reports keep three things apart: what was proven on the real Mac, what was
simulated against fakes, and what is only expected. These need a person:
audible playback, pointer hover and drag, scrolling by hand, key
equivalents in the real popover, the media keys and Now Playing, Start at
Login, a real download, and ending the app with `kill -9`.
