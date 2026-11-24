import Testing
import TunesContract
@testable import TunesPanel

/// A kept tune for round tests.
func kept(_ n: Int, name: String? = nil, pinned: Bool = false, read: Bool = true) -> QueuedTune {
    let file = String(format: "20261101-%06d-90bpm-C-major", n)
    return QueuedTune(name: name ?? (read ? "Kept Tune \(n)" : file), file: file, bpm: 90, key: "C major", length: read ? 170 : nil,
                      kept: true, new: false, pinned: pinned, pos: nil)
}

/// The tune `q` playing, as the engine reports it.
func playing(_ q: QueuedTune) -> PlayingTune {
    PlayingTune(name: q.name, file: q.file, bpm: q.bpm, key: q.key, length: q.length, kept: q.kept, new: q.new, pinned: q.pinned, pos: q.pos, wave: [])
}

/// The playing tune as a queue entry.
func queued(_ t: PlayingTune) -> QueuedTune {
    QueuedTune(name: t.name, file: t.file, bpm: t.bpm, key: t.key, length: t.length, kept: t.kept, new: t.new, pinned: t.pinned, pos: t.pos)
}

@Suite("The round")
struct RoundTests {
    /// Jazz: `played` kept tunes played, Lazy Avenue playing, then `fresh`
    /// new tunes and `keptCount` kept ones queued.
    func snapshot(played: Int = 0, fresh: Int, keptCount: Int, shuffle: Bool = true, repeatMode: RepeatMode = .all) throws -> Snapshot {
        var s = try Fixture.load("05-queue-full")
        s.played = (0..<played).map { kept(100 + $0) }
        s.queue = Array(s.queue.prefix(fresh)) + (0..<keptCount).map { kept($0 + 1) }
        s.ready = fresh
        s.shuffle = shuffle
        s.repeat = repeatMode
        s.roundLeft = keptCount
        return s
    }

    /// Twelve kept tunes: the fifth playing, four played before it.
    func twelve() throws -> Snapshot {
        var s = try snapshot(fresh: 0, keptCount: 0)
        let all = (1...12).map { kept($0) }
        s.played = Array(all[0..<4])
        s.tune = playing(all[4])
        s.queue = Array(all[5...])
        return s
    }

    @Test("the round is played, then playing, then queued, numbered from 1 in that order")
    func list() throws {
        let s = try twelve()
        let round = Decide.round(played: s.played, tune: s.tune, queue: s.queue)
        #expect(round.map(\.number) == Array(1...12))
        #expect(round.map(\.name) == (1...12).map { "Kept Tune \($0)" })
        #expect(round.map(\.state) == Array(repeating: .played, count: 4) + [.playing] + Array(repeating: .waiting, count: 7))
        #expect(round.map(\.index) == [0, 1, 2, 3, 0, 0, 1, 2, 3, 4, 5, 6])
        #expect(Set(round.map(\.id)).count == 12)
        let none = Decide.round(played: s.played, tune: nil, queue: s.queue)
        #expect(none.map(\.number) == Array(1...11) && !none.contains { $0.state == .playing })
    }

    @Test("a tune queued twice keeps a row of its own each time")
    func twice() {
        let a = kept(1)
        let round = Decide.round(played: [a], tune: nil, queue: [a])
        #expect(round.map(\.id) == ["\(a.file)#0", "\(a.file)#1"])
    }

    @Test("walking a round of twelve forwards two and back one: no tune's number changes")
    func walk() throws {
        var s = try twelve()
        func numbers() -> [String: Int] {
            Dictionary(uniqueKeysWithValues: Decide.round(played: s.played, tune: s.tune, queue: s.queue).map { ($0.file, $0.number) })
        }
        func next() {
            s.played.append(queued(s.tune!))
            s.tune = playing(s.queue.removeFirst())
        }
        func previous() {
            s.queue.insert(queued(s.tune!), at: 0)
            s.tune = playing(s.played.removeLast())
        }
        let before = numbers()
        var heads = [try player(s).next.head]
        next(); #expect(numbers() == before); heads.append(try player(s).next.head)
        next(); #expect(numbers() == before); heads.append(try player(s).next.head)
        previous(); #expect(numbers() == before); heads.append(try player(s).next.head)
        #expect(heads == ["5 of 12", "6 of 12", "7 of 12", "6 of 12"])
        #expect(try player(s).next.rows.map(\.number) == ["6", "7", "8"])
    }

    @Test("a new tune goes in after the playing one: only the tunes after it move down")
    func insertion() throws {
        var s = try twelve()
        let before = Decide.round(played: s.played, tune: s.tune, queue: s.queue)
        s.queue.insert(QueuedTune(name: "Paper Kite", file: "20261124-090000-92bpm-E-minor", bpm: 92, key: "E minor", length: 171, kept: false, new: true, pinned: false, pos: nil), at: 0)
        let after = Decide.round(played: s.played, tune: s.tune, queue: s.queue)
        #expect(after.count == 13 && after[5].name == "Paper Kite" && after[5].number == 6)
        #expect(Array(after.prefix(5)) == Array(before.prefix(5)))
        #expect(after.dropFirst(6).map(\.number) == before.dropFirst(5).map { $0.number + 1 })
        #expect(after.dropFirst(6).map(\.id) == before.dropFirst(5).map(\.id))
    }

    @Test("the player: the playing tune and the next two, N of M at the right")
    func window() throws {
        let p = try player(twelve())
        #expect(p.next.label == "THIS ROUND" && p.next.head == "5 of 12")
        #expect(p.next.rows.map(\.number) == ["5", "6", "7"])
        #expect(p.next.rows.map(\.state) == [.playing, .waiting, .waiting])
        #expect(p.next.rows.map(\.dim) == [false, false, false])
        #expect(p.next.more == Control(text: "then 5 more this round · Show all", help: "Show all"))
    }

    @Test("nothing playing: the next three, M tunes at the right")
    func windowIdle() throws {
        var s = try twelve()
        s.tune = nil
        s.player = .none
        let p = try player(s)
        #expect(p.next.head == "11 tunes")
        #expect(p.next.rows.map(\.number) == ["5", "6", "7"])
        #expect(p.next.rows.allSatisfy { $0.state == .waiting })
        #expect(p.next.more == Control(text: "then 4 more this round · Show all", help: "Show all"))
        var one = s
        one.played = []
        one.queue = [kept(1)]
        #expect(try player(one).next.head == "1 tune")
    }

    @Test("then N more this round · Show all, only when more follow the window", arguments: [
        (0, 0, 1, nil), (0, 2, 0, nil), (0, 2, 1, 1), (3, 2, 10, 10), (0, 0, 50, 48),
    ] as [(Int, Int, Int, Int?)])
    func more(_ played: Int, _ fresh: Int, _ keptCount: Int, _ hidden: Int?) throws {
        let p = try player(snapshot(played: played, fresh: fresh, keptCount: keptCount))
        #expect(p.next.more == hidden.map { Control(text: "then \($0) more this round · Show all", help: "Show all") })
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

    @Test("the round card: label, title, the modes, every row in list order, played dimmed, the playing one to scroll to")
    func card() throws {
        let s = try twelve()
        let p = Panel().openingQueue()
        guard case .queue(let q) = Decide.card(s, p, now: NOW, home: HOME) else { Issue.record("not the round"); return }
        #expect(q.label == "THIS ROUND · 12 TUNES")
        #expect(q.title == "This round" && q.back == Control(text: "Jazz", help: "Back"))
        #expect(q.head == "shuffled · repeat all")
        #expect(q.rows.map(\.number) == (1...12).map(String.init))
        #expect(q.rows.map(\.dim) == Array(repeating: true, count: 4) + Array(repeating: false, count: 8))
        #expect(q.scrollTo == q.rows[4].id)
        #expect(Decide.roundScrollTarget(q.rows) == q.rows[4].id)
        #expect(q.making?.head == "plays next when ready")
        #expect(q.last == "after these, a new round is drawn")
        let (back, close) = p.escaping(s)
        #expect(!close && back.mode == .player)
        #expect(p.backToPlayer().mode == .player)
        #expect(Panel().openingChooser().openingQueue().mode == .chooser)
    }

    @Test("the modes", arguments: [
        (true, RepeatMode.all, "shuffled · repeat all"), (false, .one, "in the order made · repeat one"), (true, .off, "shuffled · repeat off"),
    ])
    func modes(_ shuffle: Bool, _ mode: RepeatMode, _ text: String) throws {
        #expect(Decide.queueCard(try snapshot(fresh: 0, keptCount: 2, shuffle: shuffle, repeatMode: mode), now: NOW).head == text)
    }

    @Test("its last line: a new round is drawn, or with repeat off where it ends", arguments: [
        (RepeatMode.all, "after these, a new round is drawn"), (.one, "after these, a new round is drawn"), (.off, "The round ends after Kept Tune 12."),
    ])
    func last(_ mode: RepeatMode, _ line: String) throws {
        #expect(Decide.queueCard(try snapshot(fresh: 0, keptCount: 12, repeatMode: mode), now: NOW).last == line)
    }

    @Test("an empty round has no last line and nothing to scroll to")
    func empty() throws {
        var s = try snapshot(fresh: 0, keptCount: 0)
        s.tune = nil
        let q = Decide.queueCard(s, now: NOW)
        #expect(q.last == nil && q.scrollTo == nil && q.rows.isEmpty && q.label == "THIS ROUND · 0 TUNES")
    }

    @Test("with the playing tune last, the last line names it")
    func lastPlaying() throws {
        var s = try twelve()
        s.repeat = .off
        s.played += [queued(s.tune!)] + s.queue.dropLast()
        s.tune = playing(s.queue.last!)
        s.queue = []
        #expect(Decide.queueCard(s, now: NOW).last == "The round ends after Kept Tune 12.")
    }

    @Test("a row's actions by its state, each carrying its index and name as drawn")
    func actions() throws {
        let q = Decide.queueCard(try twelve(), now: NOW)
        let played = q.rows[1], now = q.rows[4], waiting = q.rows[6]
        #expect(played.playNow?.help == "Play it again")
        #expect(played.playNowCommand == .playPlayed(index: 1, name: "Kept Tune 2"))
        #expect(played.scrapCommand == .scrapPlayed(index: 1, name: "Kept Tune 2"))
        #expect(played.shareRequest?.target == TuneTarget(name: "Kept Tune 2", index: 1, inPlayed: true))
        #expect(now.playNow == nil && now.playNowCommand == nil)
        #expect(now.scrapCommand == .scrapPlaying(name: "Kept Tune 5"))
        #expect(now.shareRequest?.target == TuneTarget(name: "Kept Tune 5", index: nil))
        #expect(waiting.playNow?.help == "Play it now")
        #expect(waiting.playNowCommand == .playQueued(index: 1, name: "Kept Tune 7"))
        #expect(waiting.scrapCommand == .scrapQueued(index: 1, name: "Kept Tune 7"))
        #expect(waiting.shareRequest?.target == TuneTarget(name: "Kept Tune 7", index: 1))
        #expect(q.rows.allSatisfy { $0.share != nil && $0.scrap != nil })
    }

    @Test("Play it again drawn before the round moved still carries the name it showed")
    func renderedName() throws {
        var s = try twelve()
        let drawn = Decide.queueCard(s, now: NOW).rows[3]
        // Previous: the last played tune plays again, so played[3] is gone.
        s.queue.insert(queued(s.tune!), at: 0)
        s.tune = playing(s.played.removeLast())
        #expect(drawn.playNowCommand == .playPlayed(index: 3, name: "Kept Tune 4"))
        #expect(!s.played.indices.contains(3))
    }

    @Test("a share sheet opened on a played tune finds it wherever it is now")
    func shareMoves() throws {
        var s = try twelve()
        let row = Decide.queueCard(s, now: NOW).rows[2]
        let opened = Panel().openingShare(try #require(row.shareRequest))
        #expect(opened.shareTargetNow(s) == TuneTarget(name: "Kept Tune 3", index: 2, inPlayed: true))
        // Played again: it is the playing tune, the rest back in the queue.
        s.queue = s.played[3...] + [queued(s.tune!)] + s.queue
        s.tune = playing(s.played[2])
        s.played = Array(s.played[..<2])
        #expect(opened.shareTargetNow(s) == TuneTarget(name: "Kept Tune 3", index: nil))
        // A queued tune that has since been played is found in played.
        let waiting = Panel().openingShare(try #require(Decide.queueCard(try twelve(), now: NOW).rows[5].shareRequest))
        var later = try twelve()
        later.played.append(queued(later.tune!))
        later.played.append(later.queue.removeFirst())
        later.tune = playing(later.queue.removeFirst())
        #expect(waiting.shareTargetNow(later) == TuneTarget(name: "Kept Tune 6", index: 5, inPlayed: true))
    }

    @Test("Previous: enabled with a tune, paused included, and sends previous; dimmed with none")
    func previous() throws {
        var s = try twelve()
        #expect(try player(s).now.previous == Control(help: "Previous"))
        #expect(try player(s).now.previousCommand == .previous)
        s.player = .paused
        #expect(try player(s).now.previous.enabled && player(s).now.previousCommand == .previous)
        s.tune = nil
        s.player = .none
        #expect(try !player(s).now.previous.enabled && player(s).now.previousCommand == nil)
    }

    @Test("repeat one: the waiting rows are dimmed behind the repeat")
    func repeatOne() throws {
        var s = try twelve()
        s.repeat = .one
        let q = Decide.queueCard(s, now: NOW)
        #expect(q.rows.map(\.dim) == Array(repeating: true, count: 4) + [false] + Array(repeating: true, count: 7))
    }

    @Test("the edge cases: a pinned star, a long name, an unread tune showing its stem and no length")
    func edges() throws {
        var s = try snapshot(fresh: 0, keptCount: 0)
        let long = "A Much Longer Name Than The List Has Room For Tonight"
        s.tune = nil
        s.queue = [kept(1, pinned: true), kept(2, name: long), kept(3, read: false)]
        let rows = try player(s).next.rows
        #expect(rows[0].star && !rows[1].star)
        #expect(rows[1].name == long)
        #expect(rows[2].name == "20261101-000003-90bpm-C-major" && rows[2].right == "")
        #expect(rows[2].sub == "90 BPM · C major")
    }

    @Test("fifty in the round: three in the player, all on the card, ids distinct", arguments: [12, 50])
    func many(_ n: Int) throws {
        let s = try snapshot(played: 4, fresh: 0, keptCount: n - 5)
        #expect(try player(s).next.rows.count == 3)
        let q = Decide.queueCard(s, now: NOW)
        #expect(q.rows.count == n && q.label == "THIS ROUND · \(n) TUNES")
        #expect(Set(q.rows.map(\.id)).count == n)
    }

    @Test("the level meter moves only while playing with the popover open, and not under Reduce Motion", arguments: [
        (PlayerState.playing, true, false, true), (.paused, true, false, false), (.playing, false, false, false), (.playing, true, true, false),
    ])
    func meter(_ state: PlayerState, _ open: Bool, _ reduce: Bool, _ moves: Bool) throws {
        var s = try twelve()
        s.player = state
        for p in [Panel(), Panel().openingQueue()] {
            #expect(Decide.animating(s, p, now: NOW, popoverOpen: open, reduceMotion: reduce, lowPower: false).meter == moves)
        }
        s.tune = nil
        #expect(!Decide.animating(s, Panel(), now: NOW, popoverOpen: true, reduceMotion: false, lowPower: false).meter)
    }

    @Test("the tick runs on the round card while a job's time counts")
    func tick() throws {
        let p = Panel().openingQueue()
        #expect(Decide.needsTick(try Fixture.load("10-writing"), p, now: NOW))
        #expect(!Decide.needsTick(try Fixture.load("07-composer-off-kept"), p, now: NOW))
    }
}
