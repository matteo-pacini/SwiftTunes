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
4. `docs/TESTING.md`: the suites, the rules a test follows, the demo and
   its flags, and the rules for anything that shows a window or makes a
   sound.

## Rules

- macOS 26 or later, Apple silicon. Liquid Glass is the base material: adopt
  it everywhere a surface floats, with no fallback path.
- The development environment is Xcode 27.0 (Swift 6.4), on the owner's Mac
  and on the runners alike. Every workflow selects it and stops when
  `xcodebuild -version` reports anything else; nothing is built, tested or
  released with another Xcode.
- Swift 6. The shell is AppKit (`NSStatusItem`, `NSPopover`, the status
  item's menu); the popover's content is SwiftUI in an `NSHostingController`.
  No `MenuBarExtra`, no Catalyst, no Electron, no Xcode project file.
- Apple frameworks and tools only: Foundation, AppKit, SwiftUI, AVFoundation,
  Accelerate, MediaPlayer, CryptoKit, Network, ServiceManagement, IOKit;
  SwiftPM, Swift Testing, `codesign`, `plutil`, `taskpolicy`. No third-party
  package, library or runtime, in the app or in the tests (fakes are written
  in Swift). The one exception is building `ace-server`, which needs `cmake`,
  supplied by the Nix dev shell (`flake.nix`); it uses the Makefile
  generator, so nothing else.
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
- The repository describes SwiftTunes in its own terms. The README credits
  one inspiration, Flowtunes from Omarchy, with a link; that credit is the
  only place another program is named. Nothing else tracked (code, comments,
  tests, fixtures, documents, commit messages) says where the design came
  from or names a program it resembles.
- Stay inside the files your role owns (`docs/SPEC.md`, "Ownership"). A
  change you need elsewhere is a request to the lead.
- Each rule here is the short form. The layout, the wording, the round and
  singing are in `docs/SPEC.md`; types, fields and commands in
  `docs/CONTRACT.md`; testing in `docs/TESTING.md`.

## Swift

Load the matching skill before writing or reviewing Swift. Where a skill and
this file differ, this file wins (the skills prefer `MenuBarExtra`,
`ScrollView` and `List`, for instance; the rules here forbid them):

- `swift-concurrency` for anything async, actor-isolated or `Sendable`.
- `swift-testing-expert` for every test.
- `swiftui-expert-skill` for every SwiftUI view.

The three are in the repository, in `.claude/skills/`, so every checkout
and worktree has them. They are third-party (MIT; sources and notices in
`.claude/skills/NOTICE.md`), installed with the `skills` tool and pinned by
commit in `skills-lock.json`. To restore them: `npx skills
experimental_install`. To move to newer versions: `npx skills update -p`,
then read the diff before committing it. Their helper scripts are theirs
and are no part of the build or the tests.

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

No SwiftUI `ScrollView`, `List`, `Form` or `TextEditor` in the popover: on
macOS 26.7 each was measured stalling the main thread for seconds inside the
renderer, which starves the engine too. Scrolling is an `NSScrollView`
whose document is an `NSHostingView` of the SwiftUI rows, and multi-line
text is an `NSTextView`, each through `NSViewRepresentable`. The demo's
`--demo-probe` measures it; run it on any card that gains a scrolling
region. How to run it: `docs/TESTING.md`, "The demo".

## Checks

```sh
swift build            # everything compiles, warnings are not errors yet
swift test             # all suites; no GPU, no network beyond loopback
swift test --filter <Suite>
Scripts/make-app.sh    # builds ace-server and assembles SwiftTunes.app
```

`cmake` is not installed system-wide: run the scripts inside the dev shell
(`nix develop -c Scripts/make-app.sh`), which supplies it; do not install
anything globally. No script calls `nix` itself.

What each suite covers, the rules a test follows, the real-server tests and
the demo's flags: `docs/TESTING.md`.

## Working here

- Commit on your own branch in your own worktree. Do not push, tag, or touch
  `main`. Commit messages are imperative, with a scope: `engine: …`,
  `app: …`, `build: …`, `docs: …`.
- The repository will be public one day: no personal names, emails, host
  names or home paths in files, commits, test data or web requests. Fixtures
  are invented data in the real formats. The one exception is the bundle
  identifier, `me.matteopacini.SwiftTunes`, which is the app's name to the
  system and stays as it is; a release's signature carries the owner's
  name too, and that is Apple's doing.
- A change a user can notice adds a line under `Unreleased` in
  `CHANGELOG.md`, in plain words for someone who uses the app
  (`docs/SPEC.md`, "Releases").
- No workflow uses `pull_request_target`, and none prints a secret or
  passes one on a command line.
- Comments say what the code cannot: why, an invariant, a workaround with its
  reference. Never what the line below does, never how the code got here.
- In every report keep three things apart: what was proven on the real Mac,
  what was simulated against fakes, and what is only expected. Show test
  output, not a summary of it.
- Before anything shows a window or makes a sound on the owner's machine,
  read `docs/TESTING.md`, "Anything that shows a window or makes a sound":
  ask first, a fixed count, no retries, stop processes by ID.
- Releases, signing identities, pushes and the GitHub repository's settings
  belong to the owner.
