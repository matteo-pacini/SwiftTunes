# Agent instructions

SwiftTunes is a macOS menu bar app: endless generated instrumental music by
genre, composed on the Mac by ACE-Step 1.5 Turbo through an embedded
`ace-server` (acestep.cpp, ggml, Metal). One process: an engine with no UI, and an AppKit shell
over it.

Read, in this order, before any work:

1. `docs/SPEC.md`: what is being built, the decisions already taken, who owns
   which files, and what "done" means.
2. `docs/CONTRACT.md`: the only source for what passes between the engine and
   the app. Only the lead changes it. If it is wrong or incomplete, stop and
   report; do not work around it in code.
3. The working rule notes and wording table the lead hands you (untracked):
   every behaviour rule, numbered, and every sentence shown. The spec and the
   contract cite the numbers.

## Rules

- Swift 6. The shell is AppKit (`NSStatusItem`, `NSPopover`, the status
  item's menu); the popover's content is SwiftUI in an `NSHostingController`.
  No `MenuBarExtra`, no Catalyst, no Electron, no Xcode project file. Apple
  silicon, macOS 14 or later.
- Apple frameworks and tools only: Foundation, AppKit, SwiftUI, AVFoundation,
  Accelerate, MediaPlayer, CryptoKit, Network, ServiceManagement, IOKit;
  SwiftPM, Swift Testing, `codesign`, `plutil`, `taskpolicy`. No third-party
  package, library or runtime, in the app or in the tests (fakes are written
  in Swift). The one exception is building `ace-server`, which needs `cmake`;
  it uses the Makefile generator, so nothing else.
- Mouse first: every action is a visible control. No single-letter shortcuts.
- Say only what is true in the interface: no progress the server does not
  report, no number the system does not give.
- Text from outside (tune and genre names, server errors, file-system errors)
  is drawn as plain text and never interpolated into a command line, a format
  string or attributed-string markup.
- A command aimed at a tune carries the tune's name and does nothing if that
  tune is no longer where the command says it is.
- A player event counts only if it is about the item last asked for.
- Never delete a file the app did not make.
- Never pass `--keep-loaded` to `ace-server`.
- The repository describes SwiftTunes in its own terms. Nothing tracked
  (code, comments, tests, fixtures, documents, commit messages) says where
  its design came from or names another program it resembles.
- Stay inside the files your role owns (`docs/SPEC.md`, "Ownership"). A
  change you need elsewhere is a request to the lead.

## Swift

Load the matching skill before writing or reviewing Swift, and follow it
where this file is silent:

- `swift-concurrency` for anything async, actor-isolated or `Sendable`.
- `swift-testing-expert` for every test.
- `swiftui-expert-skill` for every SwiftUI view.

Concurrency is Swift 6 language mode with complete checking, set per target
in `Package.swift` (swift-tools-version 6.2):

- `TunesEngine` and `SwiftTunes` default to the main actor
  (`.defaultIsolation(MainActor.self)`). The engine is one event loop on the
  main actor; its state is never touched from anywhere else.
- `TunesContract`, `TunesRules`, `TunesPanel` and `TunesFakes` keep the
  default, nonisolated. They are value types and pure functions, `Sendable`,
  callable from any isolation.
- Every target enables `NonisolatedNonsendingByDefault` and
  `InferIsolatedConformances`, so a nonisolated async function runs on its
  caller's actor.
- Work that must leave the main actor is an `async` function marked
  `@concurrent`, taking and returning `Sendable` values: hashing, decoding,
  the loudness scan, the waveform, encoding, large file copies. Nothing else
  hops.
- No `@unchecked Sendable`, `nonisolated(unsafe)` or `@preconcurrency`
  without a comment giving the invariant that makes it safe. No
  `DispatchQueue`, locks or semaphores for state; a C callback hops to the
  main actor before touching anything.
- No `Task.detached`. A `Task` is stored and cancelled by whoever starts it;
  the engine cancels all of its own in `shutdown()`. The one exception is a
  one-shot hop to the main actor from a framework callback that says nothing
  about its thread, with a comment saying so.

SwiftUI views draw the view state `TunesPanel` computes and send commands;
they hold no rules. State reaches them through one `@Observable` main-actor
model the shell owns.

## Checks

```sh
swift build            # everything compiles, warnings are not errors yet
swift test             # all suites; no GPU, no network beyond loopback
swift test --filter <Suite>
Scripts/make-app.sh    # builds ace-server and assembles SwiftTunes.app
```

`cmake` is not installed system-wide. `Scripts/build-ace-server.sh` says how
it finds it; do not install anything globally.

## Working here

- Commit on your own branch in your own worktree. Do not push, tag, or touch
  `main`. Commit messages are imperative, with a scope: `engine: …`,
  `app: …`, `build: …`, `docs: …`.
- The repository will be public one day: no personal names, emails, host
  names or home paths in files, commits, test data or web requests. Fixtures
  are invented data in the real formats.
- Comments say what the code cannot: why, an invariant, a workaround with its
  reference. Never what the line below does, never how the code got here.
- In every report keep three things apart: what was proven on the real Mac,
  what was simulated against fakes, and what is only expected. Show test
  output, not a summary of it.
- Releases, signing identities, pushes and the GitHub repository's settings
  belong to the owner.
