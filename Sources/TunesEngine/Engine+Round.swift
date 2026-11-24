import Foundation
import TunesContract
import TunesRules

/// A place in what will play: a kept tune by its file name, or a new tune
/// not yet played, which carries its object.
struct QueueItem {
    var name: String
    var tune: Tune?
}

/// The round is one list in a fixed order: `played`, the playing tune, then
/// `upcoming`. Nothing leaves it when it ends; it changes only by a new tune
/// inserted after the playing one, a scrap and its undo, and a redraw of
/// what is still to come when shuffle changes.
extension Engine {
    /// The new tunes not yet played.
    var ready: [Tune] { upcoming.compactMap(\.tune) }

    func newReady() -> Int { upcoming.filter { $0.tune != nil }.count }

    /// One object for a kept tune while it is what plays next, so its file
    /// is read once and the read reaches it.
    func cachedKept(_ name: String) -> Tune? {
        guard let g = genre else { return nil }
        if let c = nextKeptCache, c.file == name,
           c.path.deletingLastPathComponent().standardizedFileURL == genreDir(g).standardizedFileURL {
            return c
        }
        let t = keptTune(genreDir(g).appending(path: name))
        nextKeptCache = t
        return t
    }

    /// The kept tune that plays next, when the next is a kept one.
    var nextKept: Tune? {
        if let first = upcoming.first { return first.tune == nil ? cachedKept(first.name) : nil }
        return nextRound?.first.flatMap(cachedKept)
    }

    func nextCandidate() -> Tune? {
        guard genre != nil else { return nil }
        syncRound()
        if let first = upcoming.first { return first.tune ?? nextKept }
        return nextKept
    }

    /// Brings the list up to date with the folder: tunes gone leave it, kept
    /// tunes it has not met join the end in the order made. With nothing left
    /// to play and repeat on, the next round is drawn for the player; with
    /// nothing playing either, it starts.
    func syncRound() {
        guard genre != nil else {
            upcoming = []
            played = []
            nextRound = nil
            return
        }
        let kept = keptNames()
        let present = Set(kept)
        upcoming.removeAll { !present.contains($0.name) }
        played.removeAll { !present.contains($0) }
        nextRound = nextRound?.filter(present.contains)
        var met = Set(played).union(upcoming.map(\.name))
        if let c = current { met.insert(c.file) }
        if nextRound == nil {
            upcoming += kept.filter { !met.contains($0) }.map { QueueItem(name: $0, tune: nil) }
        }
        if !upcoming.isEmpty {
            nextRound = nil
            return
        }
        guard nextRound == nil, repeatMode != .off else { return }
        if let c = current {
            // A lone tune cannot open a round after itself: nothing is next,
            // and the round starts again once it ends.
            guard kept != [c.file] else { return }
            nextRound = Rounds.draw(kept, shuffle: shuffle, anchor: nil, avoid: c.file, rng: &rng)
        } else if wantsPlay && loading == nil && !kept.isEmpty && !played.isEmpty {
            newRound(avoid: lastStarted)
        }
    }

    /// Starts a round: its order drawn over the kept tunes, behind the new
    /// tunes not yet played, never starting with `avoid`.
    func newRound(avoid: String? = nil) {
        played = []
        nextRound = nil
        putBack = nil
        nextKeptCache = nil
        anchor = nil
        guard genre != nil else {
            upcoming = []
            return
        }
        let new = upcoming.filter { $0.tune != nil }
        let newNames = Set(new.map(\.name))
        let order = Rounds.draw(keptNames().filter { !newNames.contains($0) }, shuffle: shuffle, anchor: nil, avoid: avoid, rng: &rng)
        upcoming = new + order.map { QueueItem(name: $0, tune: nil) }
    }

    /// Shuffle changed: only what is still to come is redrawn, new tunes
    /// first as they were.
    func redrawQueue(shuffle newShuffle: Bool) {
        let new = upcoming.filter { $0.tune != nil }
        let kept = upcoming.filter { $0.tune == nil }.map(\.name)
        let order = Rounds.draw(kept, shuffle: newShuffle, anchor: current?.file ?? anchor, avoid: nil, rng: &rng)
        upcoming = new + order.map { QueueItem(name: $0, tune: nil) }
        putBack = nil
        nextKeptCache = nil
        nextRound = nil
    }

    /// What will play, in order; command indexes refer to it.
    func queueNow() -> [Tune] {
        syncRound()
        guard let g = genre else { return [] }
        return upcoming.enumerated().map { i, item in
            item.tune ?? (i == 0 ? cachedKept(item.name)! : keptTune(genreDir(g).appending(path: item.name), decode: false))
        }
    }

    /// The tunes played this round, oldest first.
    func playedNow() -> [Tune] {
        syncRound()
        guard let g = genre else { return [] }
        return played.map { keptTune(genreDir(g).appending(path: $0), decode: false) }
    }

    /// The kept tunes still to come this round.
    func roundLeft() -> [String] {
        syncRound()
        return upcoming.filter { $0.tune == nil }.map(\.name)
    }

    func ended() -> Bool {
        repeatMode == .off && genre != nil && current == nil && loading == nil && wantsPlay && upcoming.isEmpty
            && !listTunes(genre).isEmpty && roundLeft().isEmpty
    }

    /// The player moved on to `path`: the tune that was playing joins
    /// `played`, or the next round begins.
    func advance(to path: URL) {
        let name = path.lastPathComponent
        if let first = upcoming.first, first.name == name {
            if let c = current, c.path != path { played.append(c.file) }
            let t = first.tune ?? (current?.path == path ? current! : (cachedKept(name) ?? keptTune(path)))
            upcoming.removeFirst()
            if putBack == name { putBack = nil }
            nextKeptCache = nil
            current = t
        } else if let next = nextRound, next.first == name {
            played = []
            putBack = nil
            let t = cachedKept(name) ?? keptTune(path)
            upcoming = next.dropFirst().map { QueueItem(name: $0, tune: nil) }
            nextRound = nil
            nextKeptCache = nil
            current = t
        } else if current?.path != path {
            current = keptTune(path)
        }
    }

    /// Plays `tune` now in place of the playing one, which joins `played`.
    func jump(to tune: Tune) {
        current = tune
        wantsPlay = true
        paused = false
        setPosition(0)
        playNow(tune)
        changed()
    }

    func playQueued(_ i: Int, _ name: String) {
        let q = queueNow()
        guard i >= 0, i < q.count, q[i].named(name) else { return }
        upcoming.remove(at: i)
        nextKeptCache = nil
        if let c = current { played.append(c.file) }
        jump(to: q[i])
    }

    /// More than 3 s in, or with nothing played before it, the playing tune
    /// starts over. Within the first 3 s the last played tune plays again
    /// and the playing one goes back to the front of what is to come.
    func previous() {
        guard let c = current else { return }
        // The position as last sampled, moved on by the clock while it plays.
        let elapsed = loading != nil ? 0 : pos + (paused ? 0 : clock.now - posAt)
        guard elapsed <= Rules.previousGrace, let back = played.last, let g = genre else {
            player.seek(to: 0)
            setPosition(0)
            changed()
            return
        }
        played.removeLast()
        upcoming.insert(QueueItem(name: c.file, tune: nil), at: 0)
        putBack = c.file
        nextRound = nil
        nextKeptCache = nil
        jump(to: keptTune(genreDir(g).appending(path: back)))
    }

    /// Plays `played[i]` again: every tune after it in the list, the playing
    /// one included, goes back to what is to come, in list order.
    func playPlayed(_ i: Int, _ name: String) {
        guard let g = genre, i >= 0, i < playedNow().count else { return }
        let t = keptTune(genreDir(g).appending(path: played[i]))
        guard t.named(name) else { return }
        let back = Array(played[(i + 1)...]) + (current.map { [$0.file] } ?? [])
        played.removeSubrange(i...)
        upcoming = back.map { QueueItem(name: $0, tune: nil) } + upcoming
        putBack = nil
        nextRound = nil
        nextKeptCache = nil
        jump(to: t)
    }

    /// Where a new tune goes: right after the playing one, behind a tune
    /// Previous has just put back first.
    var newTuneIndex: Int {
        if let p = putBack, upcoming.first?.name == p { return 1 }
        return 0
    }
}
