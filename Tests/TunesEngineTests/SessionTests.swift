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
        case .setup(let c): out += ["setup \(c.kind)", c.title, c.detail] + c.rows.map { "\($0.label): \($0.value)" } + ["[\(c.button.text) \(c.button.enabled)]"]
        case .chooser(let c): out += ["chooser", c.title, c.chip, c.strip ?? "-"] + c.cells.map { "\($0.name) · \($0.sub)" }
        case .editor(let e): out += ["editor", e.title]
        case .share(let c): out += ["share", c.head, c.name, c.meta] + c.rows.map { "\($0.title) / \($0.sub) \($0.on.map { "\($0)" } ?? "")" }
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

    func see(_ rig: Rig, _ panel: Panel = Panel()) -> Seen {
        let s = rig.snap
        let now = rig.clock.now
        return Seen(card: Decide.card(s, panel, now: now, home: Self.home),
                    footer: Decide.footer(s, panel, now: now), status: Decide.statusItem(s))
    }

    @Test func aSession() async throws {
        let rig = try await Rig(ready: false)
        for d in 1...3 { try rig.keptTune("Jazz", day: d) }
        rig.make()
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
        #expect(seen.setup?.rows.contains { $0.label == "memory while composing" && $0.value == "about 8 GiB of memory" } == true)
        #expect(seen.setup?.button.text == "Download" && seen.setup?.command == .download)
        #expect(seen.status.dim && seen.status.dot == nil)

        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        seen = step("download done")
        #expect(seen.chooser?.chip == "A click plays what is kept")
        #expect(seen.chooser?.cells.map { "\($0.name) · \($0.sub)" } == ["Jazz · 3 kept", "Lo-fi · none yet"])
        #expect(seen.status.dim)

        await rig.send(.selectGenre(id: "jazz"))
        seen = step("genre picked")
        var p = try #require(seen.player)
        #expect(p.now.suffix == "kept tunes" && p.now.genre.text == "Jazz")
        #expect(p.now.title == rig.snap.tune?.name && p.now.meta == "100 BPM · A minor")
        #expect(p.now.showsPause && p.now.next.enabled)
        #expect(p.next.head == "from 3 kept, shuffled")
        #expect(seen.composerText.first == "On, it makes new Jazz and keeps 2 ahead.")
        #expect(seen.status.text == "Jazz" && !seen.status.dim && seen.status.dot == nil)

        await rig.ace.set(runningPolls: 3)
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.model.state == .writing })
        seen = step("writing")
        p = try #require(seen.player)
        #expect(p.next.rows.contains { $0.kind == .job && $0.name == "Being written" && $0.right == "composing" })
        #expect(p.composer.lines.first?.text == "Makes Jazz, keeps 2 ahead" && p.composer.lines.first?.right == "using 6.5 GiB of memory")
        #expect(p.composer.label == "on" && seen.status.dot == .cyan)

        #expect(await rig.run { rig.snap.model.state == .rendering })
        seen = step("rendering")
        p = try #require(seen.player)
        #expect(p.next.rows.contains { $0.kind == .job && $0.name == "Being rendered" && $0.sub.contains("written in") })

        #expect(await rig.run { rig.snap.ready == 2 && rig.snap.model.state == .idle })
        seen = step("queue full")
        p = try #require(seen.player)
        #expect(p.next.head == "2 ready")
        #expect(p.next.rows.filter { $0.tag == "new" }.count == 2 && !p.next.rows.contains { $0.kind == .job })
        #expect(p.composer.lines.first?.right == "resting, queue is full" && seen.status.dot == nil)

        rig.player.finish()
        await rig.settle()
        seen = step("first new tune playing")
        p = try #require(seen.player)
        #expect(p.now.title == rig.snap.tune?.name && rig.snap.tune?.new == true && p.now.suffix == "")
        #expect(p.next.head == "1 ready")

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
        #expect(seen.player?.next.rows.first?.name == playing.name)

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
        #expect(p.next.head == "nothing" && p.now.repeat.text == "off" && !p.now.repeat.lit)

        await rig.send(.play)
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

        // The whole session, kept for a reader of a failure.
        if ProcessInfo.processInfo.environment["TUNES_SESSION_LOG"] != nil {
            print(log.joined(separator: "\n"))
        }
        await rig.close()
    }
}
