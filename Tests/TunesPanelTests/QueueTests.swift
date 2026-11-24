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

/// A round of `size` kept tunes with the one at `position` (from 0) playing.
func roundOf(_ size: Int, playing position: Int) throws -> Snapshot {
    var s = try Fixture.load("05-queue-full")
    let all = (1...size).map { kept($0) }
    s.played = Array(all[..<position])
    s.tune = playing(all[position])
    s.queue = Array(all[(position + 1)...])
    s.ready = 0
    return s
}

@Suite("The round")
struct RoundTests {
    /// Twelve kept tunes: the fifth playing, four played before it.
    func twelve() throws -> Snapshot {
        try roundOf(12, playing: 4)
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

    @Test("the player lists the whole round: every row, fixed numbers, the playing one marked", arguments: [1, 2, 3, 4, 5, 12, 50])
    func whole(_ size: Int) throws {
        for position in 0..<size {
            let next = try player(roundOf(size, playing: position)).next
            #expect(next.rows.map(\.number) == (1...size).map(String.init))
            #expect(next.rows.map(\.name) == (1...size).map { "Kept Tune \($0)" })
            #expect(next.playing == position && next.rows[position].state == .playing)
            #expect(next.rows.map(\.dim) == (0..<size).map { $0 < position })
            #expect(next.head == "\(position + 1) of \(size)")
        }
    }

    @Test("walking forwards two and back one: the same rows in the same order, only the highlight moves")
    func walk() throws {
        var s = try twelve()
        func next() {
            s.played.append(queued(s.tune!))
            s.tune = playing(s.queue.removeFirst())
        }
        func previous() {
            s.queue.insert(queued(s.tune!), at: 0)
            s.tune = playing(s.played.removeLast())
        }
        let order = try player(s).next.rows.map(\.id)
        var seen = [try player(s).next]
        next(); seen.append(try player(s).next)
        next(); seen.append(try player(s).next)
        previous(); seen.append(try player(s).next)
        #expect(seen.allSatisfy { $0.rows.map(\.id) == order && $0.rows.map(\.number) == (1...12).map(String.init) })
        #expect(seen.map(\.playing) == [4, 5, 6, 5])
        #expect(seen.map(\.head) == ["5 of 12", "6 of 12", "7 of 12", "6 of 12"])
    }

    @Test("a new tune joins the end, tagged new: every earlier row keeps its number, only the length grows")
    func joining() throws {
        var s = try twelve()
        let before = try player(s).next
        s.queue.append(QueuedTune(name: "Paper Kite", file: "20261124-090000-92bpm-E-minor", bpm: 92, key: "E minor", length: 171, kept: false, new: true, pinned: false, pos: nil))
        s.ready = 1
        let after = try player(s).next
        let last = try #require(after.rows.last)
        #expect(after.rows.count == 13 && last.name == "Paper Kite" && last.number == "13" && last.tag == "new" && last.state == .waiting)
        #expect(Array(after.rows.prefix(12)) == before.rows)
        #expect(after.head == "5 of 13" && after.playing == before.playing)
    }

    @Test("a genre that starts with no tunes: new tunes are numbered 1, 2, 3 in the order made, each keeping its number")
    func fromNothing() throws {
        var s = try Fixture.load("06-first-tune")
        let made = ["Paper Kite", "Neon Harbour", "Slow Signal", "Brass Lantern"].enumerated().map { i, name in
            QueuedTune(name: name, file: "20261124-09\(i)000-92bpm-E-minor", bpm: 92, key: "E minor", length: 171, kept: false, new: true, pinned: false, pos: nil)
        }
        var numbers: [String: String] = [:]
        func check() throws {
            for row in try player(s).next.rows {
                if let was = numbers[row.id] { #expect(row.number == was, "\(row.name)") }
                numbers[row.id] = row.number
            }
        }
        #expect(try player(s).next.rows.isEmpty)
        s.tune = playing(made[0]); s.player = .playing
        try check()
        s.queue.append(made[1])
        try check()
        s.queue.append(made[2])
        try check()
        s.played.append(queued(s.tune!)); s.tune = playing(s.queue.removeFirst())
        try check()
        s.queue.append(made[3])
        try check()
        let rows = try player(s).next.rows
        #expect(rows.map(\.name) == made.map(\.name))
        #expect(rows.map(\.number) == ["1", "2", "3", "4"])
        #expect(rows.map(\.state) == [.played, .playing, .waiting, .waiting])
    }

    @Test("nothing playing: every tune still listed, M tunes at the right; an empty round reads nothing")
    func idle() throws {
        var s = try twelve()
        s.tune = nil
        s.player = .none
        let p = try player(s)
        #expect(p.next.head == "11 tunes" && p.next.rows.count == 11 && p.next.playing == nil)
        #expect(p.next.rows.map(\.dim) == Array(repeating: true, count: 4) + Array(repeating: false, count: 7))
        var one = s
        one.played = []
        one.queue = [kept(1)]
        #expect(try player(one).next.head == "1 tune")
        one.queue = []
        #expect(try player(one).next.head == "nothing" && player(one).next.rows.isEmpty)
    }

    @Test("BEING MADE: the job and the places not started, joins the round when ready; absent with the composer off")
    func making() throws {
        let first = try player(Fixture.load("06-first-tune"))
        let m = try #require(first.making)
        #expect(m.head == "joins the round when ready")
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

    @Test("a row's actions by its state, each carrying its index and name as drawn")
    func actions() throws {
        let rows = try player(twelve()).next.rows
        let played = rows[1], now = rows[4], waiting = rows[6]
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
        #expect(rows.allSatisfy { $0.share != nil && $0.scrap != nil })
    }

    @Test("Play it again drawn before the round moved still carries the name it showed")
    func renderedName() throws {
        var s = try twelve()
        let drawn = try player(s).next.rows[3]
        // Previous: the last played tune plays again, so played[3] is gone.
        s.queue.insert(queued(s.tune!), at: 0)
        s.tune = playing(s.played.removeLast())
        #expect(drawn.playNowCommand == .playPlayed(index: 3, name: "Kept Tune 4"))
        #expect(!s.played.indices.contains(3))
    }

    @Test("a share sheet opened on a played tune finds it wherever it is now")
    func shareMoves() throws {
        var s = try twelve()
        let row = try player(s).next.rows[2]
        let opened = Panel().openingShare(try #require(row.shareRequest))
        #expect(opened.shareTargetNow(s) == TuneTarget(name: "Kept Tune 3", index: 2, inPlayed: true))
        // Played again: it is the playing tune, the rest back in the queue.
        s.queue = s.played[3...] + [queued(s.tune!)] + s.queue
        s.tune = playing(s.played[2])
        s.played = Array(s.played[..<2])
        #expect(opened.shareTargetNow(s) == TuneTarget(name: "Kept Tune 3", index: nil))
        // A queued tune that has since been played is found in played.
        let waiting = Panel().openingShare(try #require(player(twelve()).next.rows[5].shareRequest))
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
        #expect(try player(s).next.rows.map(\.dim) == Array(repeating: true, count: 4) + [false] + Array(repeating: true, count: 7))
    }

    @Test("the edge cases: a pinned star, a long name, an unread tune showing its stem and no length")
    func edges() throws {
        var s = try Fixture.load("05-queue-full")
        let long = "A Much Longer Name Than The List Has Room For Tonight"
        s.tune = nil
        s.queue = [kept(1, pinned: true), kept(2, name: long), kept(3, read: false)]
        let rows = try player(s).next.rows
        #expect(rows[0].star && !rows[1].star)
        #expect(rows[1].name == long)
        #expect(rows[2].name == "20261101-000003-90bpm-C-major" && rows[2].right == "")
        #expect(rows[2].sub == "90 BPM · C major")
    }

    @Test("the level meter moves only while playing with the popover open, and not under Reduce Motion", arguments: [
        (PlayerState.playing, true, false, true), (.paused, true, false, false), (.playing, false, false, false), (.playing, true, true, false),
    ])
    func meter(_ state: PlayerState, _ open: Bool, _ reduce: Bool, _ moves: Bool) throws {
        var s = try twelve()
        s.player = state
        #expect(Decide.animating(s, Panel(), now: NOW, popoverOpen: open, reduceMotion: reduce, lowPower: false).meter == moves)
        s.tune = nil
        #expect(!Decide.animating(s, Panel(), now: NOW, popoverOpen: true, reduceMotion: false, lowPower: false).meter)
    }
}

@Suite("Where the list scrolls")
struct ListScrollTests {
    /// The rows in view after the decision: from the row it brings to the
    /// top, else from the top of the list, four at most.
    func visible(_ size: Int, _ top: Int?) -> Range<Int> {
        let first = top ?? 0
        return first..<min(size, first + Decide.listRows)
    }

    static let cases: [(Int, Int)] = [1, 2, 3, 4, 5, 12, 50].flatMap { size in (0..<size).map { (size, $0) } }

    @Test("the playing row always ends in view; second from the top when the round is long enough", arguments: cases)
    func follows(_ size: Int, _ position: Int) throws {
        let next = try player(roundOf(size, playing: position)).next
        let top = Decide.listTop(count: next.rows.count, playing: next.playing, pointerInside: false, userScrolledAt: nil, now: NOW)
        #expect(visible(size, top).contains(position))
        if size <= Decide.listRows {
            #expect(top == nil)
        } else {
            let wanted = position - 1
            #expect(top == max(0, min(wanted, size - Decide.listRows)))
            if wanted >= 0 && wanted <= size - Decide.listRows { #expect(top == wanted) }
        }
    }

    @Test("two tunes, the second playing: both rows shown, nothing to scroll")
    func ownersCase() throws {
        var s = try roundOf(2, playing: 0)
        s.played.append(queued(s.tune!))
        s.tune = playing(s.queue.removeFirst())
        let next = try player(s).next
        #expect(next.rows.map(\.number) == ["1", "2"] && next.rows.map(\.state) == [.played, .playing])
        #expect(next.rows[0].playNow?.help == "Play it again" && next.rows[0].scrap != nil && next.rows[0].share != nil)
        #expect(Decide.listTop(count: 2, playing: next.playing, pointerInside: false, userScrolledAt: nil, now: NOW) == nil)
    }

    @Test("hands off while the pointer is over the list or within 3 s of the user scrolling it", arguments: [
        (false, Double?.none, Int?.some(4)), (true, nil, nil), (false, NOW - 0.5, nil), (false, NOW - 2.99, nil), (false, NOW - 3, 4), (false, NOW - 60, 4),
    ])
    func handsOff(_ pointer: Bool, _ scrolledAt: Double?, _ top: Int?) {
        #expect(Decide.listTop(count: 12, playing: 5, pointerInside: pointer, userScrolledAt: scrolledAt, now: NOW) == top)
    }

    @Test("nothing playing: the list is left where it is")
    func idle() {
        #expect(Decide.listTop(count: 12, playing: nil, pointerInside: false, userScrolledAt: nil, now: NOW) == nil)
    }
}

@Suite("The round in the fixtures")
struct RoundFixtureTests {
    @Test("four played, the fifth playing: 5 of 12, every row listed")
    func played() throws {
        let p = try player(Fixture.load("45-round-played"))
        #expect(p.next.head == "5 of 12" && p.next.rows.count == 12 && p.next.playing == 4)
        #expect(p.next.rows[4].name == "Lazy Avenue")
        #expect(p.next.rows.prefix(4).allSatisfy { $0.state == .played && $0.dim })
    }

    @Test("twelve waiting: the kept tunes in the round's order, then the two new tunes last, tagged new")
    func newLast() throws {
        let rows = try player(Fixture.load("39-twelve-queue")).next.rows.filter { $0.state == .waiting }
        #expect(rows.count == 12)
        #expect(rows.map(\.tag) == Array(repeating: "", count: 10) + ["new", "new"])
    }

    @Test("a round of fifty: 11 of 50, every row listed, the list brought to the tenth")
    func fifty() throws {
        let p = try player(Fixture.load("47-round-fifty"))
        #expect(p.next.head == "11 of 50" && p.next.rows.count == 50 && p.next.playing == 10)
        #expect(Decide.listTop(count: 50, playing: p.next.playing, pointerInside: false, userScrolledAt: nil, now: NOW) == 9)
    }

    @Test("the round ended under repeat off: every tune played, none playing")
    func ended() throws {
        let p = try player(Fixture.load("46-round-ended"))
        #expect(p.next.head == "12 tunes" && p.next.rows.count == 12 && p.next.playing == nil)
        #expect(p.next.rows.allSatisfy { $0.state == .played })
    }
}

@Suite("Dim rows")
struct DimRowTests {
    @Test("a played row's content is drawn at 0.45, full while hovered; others always full")
    func opacity() throws {
        let rows = try player(Fixture.load("45-round-played")).next.rows
        #expect(rows.map { $0.contentOpacity(hovered: false) } == Array(repeating: 0.45, count: 4) + Array(repeating: 1, count: 8))
        #expect(rows.allSatisfy { $0.contentOpacity(hovered: true) == 1 })
    }
}

@Suite("Rows that join and leave")
struct RowMotionTests {
    @Test("a change in the set of rows animates the neighbours' slide; a reorder or no change does not", arguments: [
        (["a", "b", "c"], ["a", "b", "c", "d"], true),
        (["a", "b", "c"], ["a", "c"], true),
        (["a", "b", "c"], ["b", "c", "d"], true),
        (["a", "b", "c"], ["c", "a", "b"], false),
        (["a", "b", "c"], ["a", "b", "c"], false),
    ])
    func animates(_ old: [String], _ new: [String], _ expected: Bool) {
        #expect(Decide.animatesRows(from: old, to: new) == expected)
    }

    @Test("a new tune in a genre at its keep limit: one row leaves, one joins")
    func fullGenre() throws {
        var s = try roundOf(50, playing: 10)
        let before = try player(s).next.rows.map(\.id)
        s.played.removeFirst()
        s.queue.append(QueuedTune(name: "Paper Kite", file: "20261124-090000-92bpm-E-minor", bpm: 92, key: "E minor", length: 171, kept: false, new: true, pinned: false, pos: nil))
        s.ready = 1
        let after = try player(s).next.rows.map(\.id)
        let diff = after.difference(from: before)
        #expect(diff.removals.map { if case .remove(_, let id, _) = $0 { id } else { "" } } == [before[0]])
        #expect(diff.insertions.map { if case .insert(_, let id, _) = $0 { id } else { "" } } == [after[49]])
        #expect(Decide.animatesRows(from: before, to: after))
    }
}
