import Testing
import TunesContract
@testable import TunesPanel

/// A kept tune for queue tests.
func kept(_ n: Int, name: String? = nil, pinned: Bool = false, read: Bool = true) -> QueuedTune {
    let file = String(format: "20261101-%06d-90bpm-C-major", n)
    return QueuedTune(name: name ?? (read ? "Kept Tune \(n)" : file), file: file, bpm: 90, key: "C major", length: read ? 170 : nil,
                      kept: true, new: false, pinned: pinned, pos: nil)
}

@Suite("The queue")
struct QueueTests {
    /// Jazz playing, `fresh` new tunes then `keptCount` kept ones queued.
    func snapshot(fresh: Int, keptCount: Int, shuffle: Bool = true, repeatMode: RepeatMode = .all) throws -> Snapshot {
        var s = try Fixture.load("05-queue-full")
        s.queue = Array(s.queue.prefix(fresh)) + (0..<keptCount).map { kept($0 + 1) }
        s.ready = fresh
        s.shuffle = shuffle
        s.repeat = repeatMode
        s.roundLeft = keptCount
        return s
    }

    @Test("UP NEXT: finished tunes only, numbered from 1, three rows")
    func numbered() throws {
        let p = try player(snapshot(fresh: 2, keptCount: 10))
        #expect(p.next.rows.map(\.number) == ["1", "2", "3"])
        #expect(p.next.rows.map(\.name) == ["Brass Lantern", "Quiet Ledger", "Kept Tune 1"])
        #expect(p.next.rows.map(\.tag) == ["new", "new", ""])
        #expect(p.next.rows.allSatisfy { $0.kind == .tune })
    }

    @Test("then N more this round · Show all, only when more wait", arguments: [(0, 2, nil), (2, 1, nil), (2, 10, 9), (0, 50, 47)] as [(Int, Int, Int?)])
    func more(_ fresh: Int, _ keptCount: Int, _ hidden: Int?) throws {
        let p = try player(snapshot(fresh: fresh, keptCount: keptCount))
        #expect(p.next.more == hidden.map { Control(text: "then \($0) more this round · Show all", help: "Show all") })
    }

    @Test("the right-hand text", arguments: [
        (2, 3, true, RepeatMode.all, "2 new, then kept"),
        (1, 3, false, .all, "1 new, then kept"),
        (2, 0, true, .all, "2 new"),
        (0, 3, true, .all, "from 14 kept, shuffled"),
        (0, 3, false, .off, "14 kept, in the order made"),
        (2, 3, true, .one, "after the repeat"),
        (0, 0, true, .all, "nothing"),
    ])
    func head(_ fresh: Int, _ keptCount: Int, _ shuffle: Bool, _ mode: RepeatMode, _ head: String) throws {
        let s = try snapshot(fresh: fresh, keptCount: keptCount, shuffle: shuffle, repeatMode: mode)
        #expect(try player(s).next.head == head)
        #expect(Decide.queueCard(s, now: NOW).head == head)
    }

    @Test("BEING MADE: the job and the places not started, plays next when ready; absent with the composer off")
    func making() throws {
        let first = try player(Fixture.load("06-first-tune"))
        let m = try #require(first.making)
        #expect(m.head == "plays next when ready")
        #expect(m.rows.map(\.kind) == [.job, .placeholder])
        #expect(m.rows[0].stage == .rendering && m.rows[0].artwork == nil)
        #expect(m.rows.map(\.number) == ["", ""])
        #expect(first.next.rows.isEmpty)
        #expect(try player(Fixture.load("13-held-memory")).making?.rows.map(\.name) == ["Not started", "Not started"])
        #expect(try player(Fixture.load("05-queue-full")).making?.rows == [])
        #expect(try player(Fixture.load("07-composer-off-kept")).making == nil)
        var off = try Fixture.load("10-writing")
        off.composing = false
        #expect(try player(off).making == nil)
    }

    @Test("the queue card: every row numbered, the label, the title, BEING MADE under it")
    func card() throws {
        let s = try snapshot(fresh: 2, keptCount: 10)
        let p = Panel().openingQueue()
        guard case .queue(let q) = Decide.card(s, p, now: NOW, home: HOME) else { Issue.record("not the queue"); return }
        #expect(q.label == "QUEUE · 12 THIS ROUND")
        #expect(q.title == "Up next" && q.back == Control(text: "Jazz", help: "Back"))
        #expect(q.rows.map(\.number) == (1...12).map(String.init))
        #expect(q.making?.head == "plays next when ready")
        #expect(q.last == "after these, the round starts over")
        #expect(q.rows.allSatisfy { $0.playNow != nil && $0.share != nil && $0.scrap != nil })
        #expect(q.rows[5].scrapCommand == .scrapQueued(index: 5, name: "Kept Tune 4"))
        let (back, close) = p.escaping(s)
        #expect(!close && back.mode == .player)
        #expect(p.backToPlayer().mode == .player)
        #expect(Panel().openingChooser().openingQueue().mode == .chooser)
    }

    @Test("its last line: the round starts over, or with repeat off where it ends", arguments: [
        (RepeatMode.all, "after these, the round starts over"), (.one, "after these, the round starts over"), (.off, "The round ends after Kept Tune 12."),
    ])
    func last(_ mode: RepeatMode, _ line: String) throws {
        #expect(Decide.queueCard(try snapshot(fresh: 0, keptCount: 12, repeatMode: mode), now: NOW).last == line)
    }

    @Test("an empty queue has no last line")
    func empty() throws {
        #expect(Decide.queueCard(try snapshot(fresh: 0, keptCount: 0), now: NOW).last == nil)
    }

    @Test("the edge cases: a pinned star, a long name, an unread tune showing its stem and no length")
    func edges() throws {
        var s = try snapshot(fresh: 0, keptCount: 0)
        let long = "A Much Longer Name Than The List Has Room For Tonight"
        s.queue = [kept(1, pinned: true), kept(2, name: long), kept(3, read: false)]
        let rows = try player(s).next.rows
        #expect(rows[0].star && !rows[1].star)
        #expect(rows[1].name == long)
        #expect(rows[2].name == "20261101-000003-90bpm-C-major" && rows[2].right == "")
        #expect(rows[2].sub == "90 BPM · C major")
    }

    @Test("fifty in the round: three in the player, fifty on the card", arguments: [12, 50])
    func many(_ n: Int) throws {
        let s = try snapshot(fresh: 0, keptCount: n)
        #expect(try player(s).next.rows.count == 3)
        let q = Decide.queueCard(s, now: NOW)
        #expect(q.rows.count == n && q.label == "QUEUE · \(n) THIS ROUND")
        #expect(Set(q.rows.map(\.id)).count == n)
    }

    @Test("the tick runs on the queue card while a job's time counts")
    func tick() throws {
        let p = Panel().openingQueue()
        #expect(Decide.needsTick(try Fixture.load("10-writing"), p, now: NOW))
        #expect(!Decide.needsTick(try Fixture.load("07-composer-off-kept"), p, now: NOW))
    }
}
