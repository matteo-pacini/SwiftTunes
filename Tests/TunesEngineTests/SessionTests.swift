import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesPanel
import TunesRules

/// What the user would see for one snapshot of the real engine, through the
/// panel's own decisions.
struct Seen {
    let card: Card
    let footer: Footer?
    let status: StatusItem

    var player: PlayerCard? {
        if case .player(let p) = card { return p }
        return nil
    }

    var setup: SetupCard? {
        if case .setup(let c) = card { return c }
        return nil
    }

    var share: ShareCard? {
        if case .share(let c) = card { return c }
        return nil
    }

    var chooser: ChooserCard? {
        if case .chooser(let c) = card { return c }
        return nil
    }

    var composerText: [String] { player?.composer.lines.map(\.text) ?? [] }

    /// Every sentence on the card, for a dump.
    var dump: String {
        var out: [String] = []
        switch card {
        case .setup(let c):
            out += ["setup \(c.kind)", c.title, c.detail]
            out += c.models.map { "(\($0.chosen ? "x" : " ")) \($0.name) \($0.variant) \($0.tag) | \($0.sub)" } + (c.modelsNote.isEmpty ? [] : [c.modelsNote])
            out += c.rows.map { "\($0.label): \($0.value)" } + ["[\(c.button.text) \(c.button.enabled)]"]
        case .models(let c):
            out += ["models", c.label, c.title, c.detail]
            out += c.rows.map { r in
                "\(r.ticked ? "✓" : "-") \(r.name) \(r.variant) | \(r.sub)\(r.error.isEmpty ? "" : " | \(r.error)") [\(r.buttons.map(\.control.text).joined(separator: ", "))]"
            }
            out.append(c.footnote)
        case .chooser(let c): out += ["chooser", c.title, c.chip, c.strip ?? "-"] + c.cells.map { "\($0.name) · \($0.sub)" }
        case .editor(let e): out += ["editor", e.title]
        case .share(let c): out += ["share", c.head, c.name, c.meta] + c.rows.map { "\($0.title) / \($0.sub) \($0.on.map { "\($0)" } ?? "")" }
        case .words(let c): out += ["words", c.title, c.counter]
        case .player(let p):
            out += ["player", "strip: \(p.strip ?? "-")", "now: \(p.now.genre.text) \(p.now.suffix) | \(p.now.title) | \(p.now.meta) | \(p.now.badge)"]
            out += ["controls: play \(p.now.playPause.enabled)/\(p.now.showsPause) next \(p.now.next.enabled) shuffle \(p.now.shuffle.lit) repeat \(p.now.repeat.lit) '\(p.now.repeat.text)' share \(p.now.share.enabled) scrap \(p.now.scrap.enabled) '\(p.now.scrap.help)'"]
            out += ["next: \(p.next.head)"] + p.next.rows.map { "  \($0.kind) \($0.number) \($0.name) [\($0.tag)] \($0.sub) | \($0.right)" }
            out += ["composer: \(p.composer.on) \(p.composer.label) retry \(p.composer.retry?.text ?? "-")"] + p.composer.lines.map { "  \($0.text) | \($0.right)" }
        }
        switch footer {
        case .notice(let t)?: out.append("footer: \(t)")
        case .undo(let t, let b)?: out.append("footer: \(t) [\(b.text)]")
        case nil: break
        }
        out.append("status: dim \(status.dim) '\(status.text)' dot \(status.dot.map { "\($0)" } ?? "-")")
        return out.joined(separator: "\n")
    }
}

/// The engine and the panel run together: each step drives the real engine
/// on the rig and reads its own snapshot back through the panel.
@Suite(.serialized, .timeLimit(.minutes(1))) struct SessionTests {
    static let home = "/home-for-tests"

    /// The round's names in list order, from the engine's snapshot.
    static func round(_ s: Snapshot) -> [String] {
        s.played.map(\.name) + (s.tune.map { [$0.name] } ?? []) + s.queue.map(\.name)
    }

    /// `N of M`: the playing tune's place in the round, the round's length.
    static func place(_ s: Snapshot) -> String {
        "\(s.played.count + 1) of \(round(s).count)"
    }

    func see(_ rig: Rig, _ panel: Panel = Panel()) -> Seen {
        let s = rig.snap
        let now = rig.clock.now
        return Seen(card: Decide.card(s, panel, now: now, home: Self.home),
                    footer: Decide.footer(s, panel, now: now), status: Decide.statusItem(s))
    }

    @Test func aSession() async throws {
        let rig = try await Rig(ready: false)
        var log: [String] = []
        func step(_ name: String) -> Seen {
            let seen = see(rig)
            log.append("== \(name)\n\(seen.dump)")
            return seen
        }

        // First launch, no weights.
        var seen = step("first launch")
        #expect(seen.setup?.kind == .missing)
        #expect(seen.setup?.detail == "ACE-Step 1.5 Turbo composes on this computer. Nothing is sent anywhere after the download.")
        // Each model's row quotes its memory: the rig's Mac has 64 GiB, so
        // Large is suggested and chosen.
        #expect(seen.setup?.rows.map(\.label) == ["download", "free on disk"])
        #expect(seen.setup?.models.map { "\($0.name) \($0.chosen) \($0.tag)" } == ["Small false ", "Large true Suggested"])
        #expect(seen.setup?.models.last?.sub == "\(Format.gib(rig.snap.need.downloadBytes, decimals: 2)) download · about 8 GiB of memory")
        #expect(seen.setup?.button.text == "Download" && seen.setup?.command == .download)
        #expect(seen.status.dim && seen.status.dot == nil)

        // Kept tunes appear (copied in by hand): the chooser, still no model.
        for (d, title) in ["Blue Lamp", "Smoky Window", "Late Avenue"].enumerated() {
            try await rig.realKeptTune("Jazz", day: d + 1, title: title)
        }
        await rig.send(.refresh)
        seen = step("kept tunes, no model")
        #expect(seen.chooser?.chip == "A click plays what is kept")
        #expect(seen.chooser?.cells.map { "\($0.name) · \($0.sub)" } == ["Jazz · 3 kept", "Lo-fi · none yet"])

        // Picked without the model: the player, and the composer bar stands
        // in for the setup cards.
        await rig.send(.selectGenre(id: "jazz"))
        seen = step("picked without the model")
        var p = try #require(seen.player)
        #expect(rig.snap.setup == .missing && p.now.showsPause)
        let standIn = try #require(p.composer.standIn)
        #expect(standIn.text == "The music model is not on this Mac.")
        #expect(standIn.button.text == "Download" && standIn.command == .download)
        #expect(standIn.detail == Format.gib(rig.snap.need.downloadBytes, decimals: 2))
        #expect(!p.composer.showsSwitch)

        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        seen = step("download done")
        p = try #require(seen.player)
        #expect(p.composer.standIn == nil && p.composer.showsSwitch)
        #expect(p.now.suffix == "kept tunes" && p.now.genre.text == "Jazz")
        #expect(p.now.title == rig.snap.tune?.name && p.now.meta == "100 BPM · A minor")
        #expect(p.now.showsPause && p.now.next.enabled)
        #expect(p.next.head == Self.place(rig.snap) && p.next.head == "1 of 3")
        #expect(seen.composerText.first == "On, it makes new Jazz and keeps 2 ahead.")
        #expect(seen.status.text == "Jazz" && !seen.status.dim && seen.status.dot == nil)
        #expect(p.now.volume.level == 1 && p.now.volume.help == "Volume")

        // The slider dragged and let go: the panel's command, through the
        // engine, to the player and back on the card.
        await rig.send(try #require(Decide.volume(fraction: 0.437, dragging: true)))
        seen = step("volume dragged")
        p = try #require(seen.player)
        #expect(rig.player.volume == 0.44 && rig.snap.volume == 0.44)
        #expect(p.now.volume.level == 0.44 && p.now.volume.help == "Volume")
        await rig.send(try #require(Decide.volume(fraction: 0.3, dragging: false)))
        seen = step("volume let go")
        p = try #require(seen.player)
        #expect(rig.player.volume == 0.3 && p.now.volume.level == 0.3)
        #expect(SavedState.parse(Files.read(rig.paths.support.appending(path: "state.json"))).volume == 0.3)

        await rig.ace.set(runningPolls: 3)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        seen = step("writing")
        p = try #require(seen.player)
        #expect(p.making?.head == "joins the round when ready")
        #expect(p.making?.rows.contains { $0.kind == .job && $0.name == "Being written" && $0.right == "composing" } == true)
        #expect(!p.next.rows.contains { $0.kind == .job })
        #expect(p.composer.lines.first?.text == "Makes Jazz, keeps 2 ahead" && p.composer.lines.first?.right == "using 6.5 GiB of memory")
        #expect(p.composer.label == "on" && seen.status.dot == .cyan)

        #expect(await rig.run { rig.snap.model.state == .rendering })
        seen = step("rendering")
        p = try #require(seen.player)
        #expect(p.making?.rows.contains { $0.kind == .job && $0.name == "Being rendered" && $0.sub.contains("written in") } == true)

        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.model.state == .idle })
        seen = step("queue full")
        p = try #require(seen.player)
        #expect(p.next.head == Self.place(rig.snap))
        #expect(p.next.rows.filter { $0.tag == "new" }.count == 2 && !p.next.rows.contains { $0.kind == .job })
        // The new tunes join the end of the round, after the kept ones.
        #expect(p.next.rows.suffix(2).allSatisfy { $0.tag == "new" })
        #expect(p.composer.lines.first?.right == "resting, queue is full" && seen.status.dot == nil)

        // The kept tunes waiting before them play; the composer rests. Files,
        // not names: a kept tune deep in the queue shows its file stem until
        // it is read.
        func files() -> [String] {
            let s = rig.snap
            return s.played.map(\.file) + (s.tune.map { [$0.file] } ?? []) + s.queue.map(\.file)
        }
        let fullRound = files()
        while rig.snap.tune?.new != true {
            rig.player.finish()
            await rig.settle()
            #expect(files() == fullRound)
            if rig.snap.tune?.kept == true { #expect(rig.snap.model.state == .idle) }
        }
        seen = step("first new tune playing")
        p = try #require(seen.player)
        #expect(p.now.title == rig.snap.tune?.name && rig.snap.tune?.new == true && p.now.suffix == "")
        #expect(p.next.head == Self.place(rig.snap))

        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.model.state == .idle })
        // A hold applies when a job is next due: the queue must have room.
        rig.holds.hold = .power
        rig.player.finish()
        await rig.settle()
        seen = step("held for low power")
        p = try #require(seen.player)
        #expect(p.composer.label == "held for low power")
        #expect(seen.composerText.contains("Low Power Mode is on. Composing waits and carries on by itself when it is off; tunes already made keep playing."))
        #expect(seen.status.dot == .orange)

        await rig.ace.set(kinds: [.fail])
        rig.holds.hold = nil
        #expect(await rig.run { rig.snap.model.state == .failed })
        seen = step("failed")
        p = try #require(seen.player)
        #expect(p.composer.label == "failed" && p.composer.retry?.text == "Try now")
        #expect(seen.composerText.contains("Failed: the song job failed. 1 failure in a row. Trying again in 3 s."))
        #expect(seen.status.dot == .red)
        #expect(await rig.run { rig.snap.model.state == .writing })
        seen = step("retried")
        #expect(seen.player?.composer.retry == nil && seen.status.dot == .cyan)

        let playing = try #require(rig.snap.tune)
        await rig.send(.scrapPlaying(name: playing.name))
        seen = step("scrapped")
        guard case .undo(let text, let button)? = seen.footer else {
            Issue.record("no undo line: \(seen.dump)")
            return
        }
        #expect(text == "Scrapped \(playing.name)." && button.text == "Undo · 10 s")
        rig.clock.now += 3
        seen = step("scrapped, 3 s later")
        if case .undo(_, let b)? = seen.footer { #expect(b.text == "Undo · 7 s") } else { Issue.record("no undo line") }
        await rig.send(.undo)
        seen = step("undone")
        #expect(seen.footer == nil)
        // The tune brought back plays next, right after the playing row.
        let undone = try #require(seen.player?.next)
        let at = try #require(undone.playing)
        #expect(undone.rows[at].name == rig.snap.tune?.name)
        #expect(undone.rows[at + 1].name == playing.name)

        // Previous, within the first 3 s: the last played tune plays again.
        // The list does not move, so no tune's number changes.
        func numbers() -> [String: String] {
            let rows = see(rig).player?.next.rows ?? []
            return Dictionary(rows.filter { !$0.number.isEmpty }.map { ($0.name, $0.number) }, uniquingKeysWith: { a, _ in a })
        }
        let roundBefore = Self.round(rig.snap)
        let numbersBefore = numbers()
        #expect(numbersBefore.count >= Self.round(rig.snap).count - 1, "\(numbersBefore)")
        let wasPlaying = try #require(rig.snap.tune)
        let backTo = try #require(rig.snap.played.last)
        rig.player.position = 1
        await rig.send(.refresh)
        await rig.send(.previous)
        seen = step("previous")
        #expect(rig.snap.tune?.file == backTo.file && rig.snap.queue.first?.file == wasPlaying.file)
        #expect(Self.round(rig.snap) == roundBefore)
        #expect(seen.player?.next.head == Self.place(rig.snap))
        let numbersAfterPrevious = numbers()
        for (name, n) in numbersBefore where name != backTo.name && name != wasPlaying.name {
            #expect(numbersAfterPrevious[name] == n, "\(name) moved from \(n)")
        }

        // Play it again: the first played tune; the rest return to the queue.
        let first = try #require(rig.snap.played.first)
        await rig.send(.playPlayed(index: 0, name: first.name))
        seen = step("play it again")
        #expect(rig.snap.tune?.file == first.file && rig.snap.played.isEmpty)
        #expect(Self.round(rig.snap) == roundBefore)
        #expect(seen.player?.next.head == "1 of \(roundBefore.count)")
        let numbersAfterAgain = numbers()
        for (name, n) in numbersBefore where name != first.name && name != wasPlaying.name {
            #expect(numbersAfterAgain[name] == n, "\(name) moved from \(n)")
        }

        await rig.send(.setComposer(on: false))
        await rig.send(.setRepeat(.off))
        for _ in 0..<20 where !rig.snap.ended {
            rig.player.finish()
            await rig.settle()
        }
        seen = step("ended")
        p = try #require(seen.player)
        #expect(p.now.title == "Played all \(rig.snap.keptTotal) Jazz tunes" && p.now.meta == "Play starts over. Repeat is off.")
        #expect(p.now.playPause.enabled && !p.now.showsPause && !p.now.next.enabled)
        // Ended: played holds the whole round.
        #expect(rig.snap.played.count == rig.snap.keptTotal)
        #expect(p.next.head == "\(rig.snap.keptTotal) tunes" && p.now.repeat.text == "off" && !p.now.repeat.lit)

        await rig.send(.play)
        let before = try #require(rig.snap.tune)
        let renamed = await rig.engine.renameTune(TuneTarget(name: before.name, index: nil), to: "Evening Walk")
        #expect(renamed == .success("Evening Walk"))
        await rig.settle()
        seen = step("renamed")
        p = try #require(seen.player)
        #expect(p.now.title == "Evening Walk" && p.now.scrap.help == "Scrap Evening Walk")
        #expect(p.now.scrapCommand == .scrapPlaying(name: "Evening Walk"))
        #expect(p.now.shareRequest?.target.name == "Evening Walk" && p.now.shareRequest?.file == before.file)

        let request = try #require(see(rig).player?.now.shareRequest)
        var panel = Panel().openingShare(request)
        let info = try await rig.engine.shareInfo(for: request.target).get()
        panel = panel.described(.success(info), target: request.target, now: rig.clock.now)
        seen = see(rig, panel)
        log.append("== share\n\(seen.dump)")
        let share = try #require(seen.share)
        #expect(share.head == "Jazz" && share.name == info.name && share.meta.hasSuffix("AAC, \(Format.size(info.bytes))"))
        #expect(share.rows.map(\.title) == ["Share…", "Copy its path", "Show it in Finder", "Export a copy", "Keep it for good"])
        #expect(share.rows.last?.on == false && share.rows.last?.sub == "never removed by the newest-50 rule")
        #expect(share.rows.first { $0.action == .export }?.sub == "to \(info.exportPath.path)")

        // The model removed: composing stops, what plays plays on.
        let calls = rig.player.calls
        await rig.send(.removeModel)
        #expect(rig.snap.setup == .missing && rig.snap.need.onDiskBytes == 0 && !rig.snap.composing)
        #expect(rig.snap.player == .playing && rig.player.calls == calls)
        seen = step("model removed")
        // With kept tunes the player stays; the composer bar stands in for
        // the setup cards.
        #expect(seen.player?.composer.standIn?.text == "The music model is not on this Mac.", "\(seen.dump)")

        // The whole session, kept for a reader of a failure.
        if ProcessInfo.processInfo.environment["TUNES_SESSION_LOG"] != nil {
            print(log.joined(separator: "\n"))
        }
        await rig.close()
    }

    /// A first run on a 16 GiB Mac: Small suggested and fetched, a tune made
    /// with it, then Large added from the models card, used, and Small
    /// removed.
    @Test func aFirstRunOnA16GiBMac() async throws {
        let rig = try await Rig(ready: false, memory: 16 << 30)
        var log: [String] = []
        func step(_ name: String, _ panel: Panel = Panel()) -> Seen {
            let seen = see(rig, panel)
            log.append("== \(name)\n\(seen.dump)")
            return seen
        }
        func row(_ c: ModelsCard, _ id: String) throws -> ModelsCard.Row { try #require(c.rows.first { $0.id == id }) }
        func models(_ seen: Seen) throws -> ModelsCard {
            guard case .models(let c) = seen.card else { throw CardMissing() }
            return c
        }
        struct CardMissing: Error {}
        func small(_ s: Snapshot) throws -> ModelChoice { try #require(s.models.first { $0.id == "small" }) }
        func large(_ s: Snapshot) throws -> ModelChoice { try #require(s.models.first { $0.id == "large" }) }
        let smallFile = rig.smallFile.name
        let largeFile = "fake-lm.gguf"

        // First launch: the two models under the sentence, Small suggested
        // and chosen, the download its size.
        var seen = step("first launch")
        var setup = try #require(seen.setup)
        var s = rig.snap
        #expect(setup.kind == .missing && setup.title == "SwiftTunes needs a music model")
        #expect(setup.models.map { "\($0.name) \($0.variant) \($0.chosen) \($0.tag)" } == ["Small 0.6B Q8 true Suggested", "Large 4B Q8 false "])
        #expect(setup.models.map(\.sub) == [
            "\(Format.gib(try small(s).downloadBytes, decimals: 2)) download · about 4 GiB of memory",
            "\(Format.gib(try large(s).downloadBytes, decimals: 2)) download · about 8 GiB of memory",
        ])
        #expect(setup.models.map(\.command) == [.chooseModel(id: "small"), .chooseModel(id: "large")])
        #expect(setup.modelsNote == "This Mac has 16 GiB of memory. Large follows the prompt and the words more closely; Small is quicker and lighter. You can add the other later.")
        #expect(setup.rows.map { "\($0.label): \($0.value)" } == [
            "download: \(Format.gib(try small(s).downloadBytes, decimals: 2))", "free on disk: \(Format.gib(s.need.diskFreeBytes))",
        ])
        #expect(try s.need.downloadBytes == small(s).downloadBytes)
        #expect(setup.button.text == "Download" && setup.command == .download)

        // Download: Small and the shared files, then ready.
        await rig.send(setup.command)
        #expect(await rig.run { rig.snap.setup == .ready })
        s = rig.snap
        #expect(try small(s).onDisk && small(s).chosen && !large(s).onDisk)
        #expect(Files.list(rig.paths.models).sorted() == [smallFile, "fake-dit.gguf", "fake-text.gguf", "fake-vae.gguf"].sorted())
        #expect(rig.snapshots.contains { $0.download?.model == "small" && $0.download?.files == 4 })
        seen = step("downloaded")
        #expect(seen.chooser != nil)

        // The composer on: a tune made with Small, the capsule naming it.
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.tune != nil })
        seen = step("a tune with Small")
        var p = try #require(seen.player)
        #expect(p.composer.lines.compactMap(\.models).map(\.text) == ["Small"])
        #expect(p.composer.lines.compactMap(\.models).first?.help == "Music models")
        let withSmall = await rig.ace.lmModels
        #expect(!withSmall.isEmpty && withSmall.allSatisfy { $0 == smallFile })

        // The models card: Small ticked and removable as the only one, Large
        // to download.
        let panel = Panel().openingModels()
        seen = step("models card", panel)
        var card = try models(seen)
        s = rig.snap
        #expect(card.label == "MUSIC MODELS" && card.title == "Music models")
        #expect(card.detail == "New tunes are made with the ticked one. A change applies from the next tune.")
        #expect(try row(card, "small").ticked && !row(card, "large").ticked)
        #expect(try row(card, "small").sub == "\(Format.gib(small(s).fileBytes, decimals: 2)) on this Mac · about 4 GiB of memory")
        #expect(try row(card, "large").sub == "\(Format.gib(large(s).downloadBytes, decimals: 2)) to download · about 8 GiB of memory")
        #expect(try row(card, "small").buttons.map(\.control.text) == ["Remove"])
        let download = try #require(row(card, "large").buttons.first)
        #expect(download.control.text == "Download" && download.command == .downloadModel(id: "large"))

        // Download Large: its own file only, composing carries on.
        await rig.send(download.command)
        #expect(await rig.run { (try? large(rig.snap).onDisk) == true && rig.snap.download == nil })
        #expect(await rig.host.requests.filter { $0.hasSuffix(".gguf") }.last == "/resolve/rev/" + largeFile)
        #expect(rig.snapshots.contains { $0.download?.model == "large" && $0.download?.files == 1 })
        seen = step("Large downloaded", panel)
        card = try models(seen)
        #expect(try row(card, "small").ticked && row(card, "small").buttons.isEmpty)
        #expect(try row(card, "large").buttons.map(\.control.text) == ["Use", "Remove"])
        #expect(rig.snap.composing && rig.snap.setup == .ready)

        // Use Large: the next tune names its file.
        let use = try #require(row(card, "large").buttons.first)
        #expect(use.command == .chooseModel(id: "large"))
        await rig.send(use.command)
        seen = step("Large used", panel)
        card = try models(seen)
        #expect(try row(card, "large").ticked && row(card, "large").buttons.isEmpty)
        #expect(try row(card, "small").buttons.map(\.control.text) == ["Use", "Remove"])
        let before = await rig.ace.lmModels.count
        rig.player.finish()
        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.job == nil })
        let after = await rig.ace.lmModels.dropFirst(before)
        #expect(!after.isEmpty && after.allSatisfy { $0 == largeFile })
        p = try #require(step("a tune with Large").player)
        #expect(p.composer.lines.compactMap(\.models).map(\.text) == ["Large"])

        // Remove Small: asked first, then only its file goes.
        let remove = try #require(row(card, "small").buttons.last)
        let ask = try #require(remove.ask)
        s = rig.snap
        let frees = Format.gib(try small(s).fileBytes, decimals: 2)
        #expect(ask.alertTitle == "Remove Small?" && ask.alertText == "It frees \(frees). Your tunes stay.")
        #expect(remove.command == .removeOneModel(id: "small"))
        await rig.send(remove.command)
        seen = step("Small removed", panel)
        card = try models(seen)
        #expect(Files.list(rig.paths.models).sorted() == [largeFile, "fake-dit.gguf", "fake-text.gguf", "fake-vae.gguf"].sorted())
        #expect(try row(card, "small").buttons.map(\.control.text) == ["Download"])
        #expect(try row(card, "large").ticked && row(card, "large").buttons.map(\.control.text) == ["Remove"])
        #expect(rig.snap.composing && rig.snap.setup == .ready && rig.snap.error == nil)

        if ProcessInfo.processInfo.environment["TUNES_SESSION_LOG"] != nil {
            print(log.joined(separator: "\n"))
        }
        await rig.close()
    }

    /// A sung genre with twelve kept tunes: the whole round in the queue card,
    /// a plan written again for thin words, a sung tune and its words, and a
    /// tune with the user's own words.
    @Test func aSungSession() async throws {
        let rig = try await Rig(genres: SingingTests.sungGenres)
        for d in 1...12 { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.selectGenre(id: "jazz"))

        // Twelve kept: one plays, eleven wait; the player lists the whole
        // round, numbered in play order, the playing tune first.
        var p = try #require(see(rig).player)
        #expect(rig.snap.queue.count == 11 && rig.snap.roundLeft == 11 && rig.snap.played.isEmpty)
        #expect(p.next.rows.map(\.number) == (1...Self.round(rig.snap).count).map(String.init))
        #expect(p.next.playing == 0)
        #expect(p.next.rows.map(\.name) == Self.round(rig.snap))

        // A sung tune: the first plan's words are too thin and it is written again.
        await rig.send(.stop)
        await rig.ace.set(kinds: [.thin, .normal])
        await rig.ace.set(runningPolls: 2)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.thinWords })
        p = try #require(see(rig).player)
        #expect(p.composer.lines.map(\.text).contains("Writing again: the last plan had too few sung lines."))
        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.model.state == .idle })
        p = try #require(see(rig).player)
        // The new tunes join the end of the round, after the kept ones.
        #expect(p.next.rows.suffix(2).allSatisfy { $0.tag == "new" && $0.sub.hasSuffix(" · sung") })
        let firstNew = p.next.rows.first { $0.tag == "new" }
        #expect(firstNew?.name == rig.snap.queue.first(where: \.new)?.name)

        // The user's words: made before the genre's own, shown as theirs.
        await rig.ace.set(runningPolls: 3)
        #expect(refusal(await rig.engine.composeWithWords("[Verse]\nmy own line", name: "Evening Walk")) == nil)
        #expect(await rig.run { rig.snap.job?.ownWords == true })
        p = try #require(see(rig).player)
        let row = try #require(p.making?.rows.first { $0.kind == .job })
        #expect(row.name == "Evening Walk" && row.sub.hasPrefix("with your words · being written"))
        #expect(await rig.run { rig.snap.ready == 3 && rig.snap.job == nil })
        #expect(see(rig).player?.next.rows.last?.name == "Evening Walk")
        let mine = try #require(rig.snap.queue.last)
        #expect(mine.name == "Evening Walk" && mine.new)

        // Played now from its row: its words show behind the Lyrics button.
        await rig.send(.playQueued(index: rig.snap.queue.count - 1, name: mine.name))
        #expect(rig.snap.tune?.name == "Evening Walk" && rig.snap.tune?.sung == true)
        p = try #require(see(rig).player)
        #expect(p.now.lyricsButton?.text == "Lyrics" && p.now.meta.contains("sung"))
        #expect(rig.snap.tune?.lyrics == "[Verse]\nmy own line")
        await rig.close()
    }
}
