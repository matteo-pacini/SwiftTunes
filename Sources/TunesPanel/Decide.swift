import Foundation
import TunesContract

/// Every decision about what the popover and the status item show, from a
/// snapshot, the panel's own state and the time now (Unix seconds).
public enum Decide {
    /// Bars in the waveform.
    public static let waveBars = 78

    // MARK: Which card

    /// The setup cards while the model is not in place and no genre has a
    /// kept tune; then the editor, the share sheet, the chooser (also while
    /// no genre is picked), the player. Without the model, kept tunes still
    /// play and the composer bar stands in for the setup cards.
    public static func card(_ s: Snapshot, _ p: Panel, now: Double, home: String) -> Card {
        if setupShows(s) { return .setup(setup(s)) }
        if p.mode == .editor, let e = p.editor { return .editor(editor(s, e)) }
        if p.mode == .share, let sh = p.share { return .share(share(s, sh, home: home)) }
        if p.mode == .chooser || s.genre == nil { return .chooser(chooser(s)) }
        if p.mode == .queue { return .queue(queueCard(s, now: now)) }
        if p.mode == .words, let w = p.following(s).words { return .words(wordsCard(s, w)) }
        return .player(player(s, p.following(s), now: now))
    }

    // MARK: Setup

    /// Whether the setup cards take the whole popover.
    static func setupShows(_ s: Snapshot) -> Bool {
        s.setup != .ready && !s.genres.contains { $0.kept > 0 }
    }

    static func setup(_ s: Snapshot) -> SetupCard {
        let d = s.download
        let downloaded = d.map { SetupCard.Row(label: "downloaded", value: "\(Format.gibNumber($0.done)) of \(Format.gib($0.total, decimals: 2))") }
        switch s.setup {
        case .downloading:
            var rows: [SetupCard.Row] = []
            if let downloaded { rows.append(downloaded) }
            if let d { rows.append(.init(label: "speed", value: Format.rate(d.rate))) }
            let what = d.map { $0.files > 0 ? "File \($0.file) of \($0.files)\($0.name.isEmpty ? "" : ": the \($0.name)")." : "" } ?? ""
            let progress = d.map { $0.total > 0 ? min(1, max(0, Double($0.done) / Double($0.total))) : 0 } ?? 0
            return SetupCard(kind: .downloading, title: "Downloading the music model", detail: what, rows: rows, progress: progress,
                             button: Control(text: "Cancel", help: "Cancel"), command: .cancelDownload)
        case .failed:
            let why = d?.error ?? s.error ?? "The download did not finish."
            return SetupCard(kind: .failed, title: "The download stopped", detail: "\(Format.sentence(why)) Finished files are kept.",
                             rows: downloaded.map { [$0] } ?? [], progress: nil,
                             button: Control(text: "Resume", help: "Resume"), command: .download)
        case .missing, .ready:
            let rows: [SetupCard.Row] = [
                .init(label: "download", value: Format.gib(s.need.downloadBytes, decimals: 2)),
                .init(label: "free on disk", value: Format.gib(s.need.diskFreeBytes)),
                .init(label: "memory while composing", value: "about \(Format.gib(s.need.ramBytes)) of memory"),
            ]
            let model = s.model.name.isEmpty ? "The music model" : s.model.name
            return SetupCard(kind: .missing, title: "SwiftTunes needs a music model",
                             detail: "\(model) composes on this computer. Nothing is sent anywhere after the download.",
                             rows: rows, progress: nil, button: Control(text: "Download", help: "Download"), command: .download)
        }
    }

    // MARK: Chooser

    static func chooser(_ s: Snapshot) -> ChooserCard {
        let selected = s.genres.first { $0.id == s.genre }
        let cells = s.genres.map { g -> ChooserCard.Cell in
            let current = g.id == s.genre
            let sub: String
            if current {
                sub = s.player == .playing ? "playing now" : s.player == .paused ? "paused" : "selected"
            } else {
                sub = g.kept > 0 ? "\(g.kept) kept" : "none yet"
            }
            return ChooserCard.Cell(id: g.id, name: g.name, sub: sub, current: current,
                                    pick: Control(help: current ? "Back to \(g.name)" : "Play \(g.name)"),
                                    edit: Control(help: "Edit \(g.name)"))
        }
        return ChooserCard(
            back: selected.map { Control(text: $0.name, help: "Back") },
            title: "Genre",
            chip: "A click plays what is kept",
            cells: cells,
            add: Control(text: "+ New genre", help: "Add a genre"),
            empty: s.genres.isEmpty ? "The genres file lists no genres." : "",
            strip: s.error
        )
    }

    // MARK: Editor

    static func editor(_ s: Snapshot, _ e: Panel.Editor) -> EditorCard {
        let genre = e.id.flatMap { id in s.genres.first { $0.id == id } }
        let kept = genre?.kept ?? 0
        let problems = GenreRules.problems(e.values, others: Panel.otherNames(s, except: e.id))
        let errors = Dictionary(problems.map { ($0.field, $0.text) }, uniquingKeysWith: { first, _ in first })
        let tempoBoxes = problems.first { $0.field == .bpm }?.boxes ?? []
        let loaded = e.id != nil && !e.loading
        func shown(_ g: GenreField) -> Bool {
            loaded || e.tried || EditorField.allCases.contains { $0.group == g && e.touched.contains($0) }
        }
        let refusedAt: GenreField? = e.refused.map { $0.field ?? .bpm }
        func error(_ g: GenreField) -> String {
            if shown(g), let t = errors[g] { return t }
            if refusedAt == g, let r = e.refused { return r.text }
            return ""
        }
        let bpmShown = shown(.bpm) && errors[.bpm] != nil
        let bpmRefused = refusedAt == .bpm && !bpmShown
        func field(_ label: String, _ side: String = "", _ placeholder: String = "", for g: GenreField) -> EditorCard.Field {
            let err = error(g)
            return EditorCard.Field(label: label, side: side, placeholder: placeholder, error: err, bad: !err.isEmpty)
        }
        var hint = "Tune names come from a shared word list until this genre has its own."
        if e.id != nil {
            hint = "Changes apply to the next tune composed."
            if kept > 0 { hint += kept == 1 ? " The 1 kept tune stays as it is." : " The \(kept) kept tunes stay as they are." }
        }
        if let saved = e.base?.sung, saved != e.sung {
            hint = "Tunes already kept stay as they are; new ones will be \(e.sung ? "sung" : "instrumental")."
        }
        let name = genre?.name ?? e.name
        let anyError = EditorField.allCases.map(\.group).contains { shown($0) && errors[$0] != nil }
        let blocked = e.loading || e.busy || anyError || e.refused?.field != nil
        var ask: EditorCard.Ask?
        if e.asking {
            let words = kept == 0 ? "" : (kept == 1 ? "Its 1 kept tune stays in ~/Music/Tunes/\(name). " : "Its \(kept) kept tunes stay in ~/Music/Tunes/\(name). ")
            ask = EditorCard.Ask(title: "Delete \(name)?", detail: words + "Only the genre leaves the panel.",
                                 error: e.deleteError ?? "",
                                 keep: Control(enabled: !e.busy, text: "Keep it", help: "Keep it"),
                                 delete: Control(enabled: !e.busy, text: "Delete \(name)", help: "Delete \(name)"))
        }
        return EditorCard(
            back: Control(text: "Genres", help: "Back"),
            title: e.id == nil ? "New genre" : "Edit \(name)",
            chip: e.id == nil ? "" : (kept > 0 ? "\(kept) kept" : "none yet"),
            values: e.values,
            loading: e.loading,
            name: field("Name", for: .name),
            caption: field("Prompt", "what every tune has", "instruments, mood, style, in a few phrases", for: .caption),
            turns: field("Variations", e.id == nil ? "optional" : "one per line, two are picked per tune", "one per line", for: .turns),
            slowest: EditorCard.Field(label: "Slowest", side: "", placeholder: "", error: "", bad: bpmRefused || (shown(.bpm) && tempoBoxes.contains(.slowest))),
            fastest: EditorCard.Field(label: "Fastest", side: "", placeholder: "", error: "", bad: bpmRefused || (shown(.bpm) && tempoBoxes.contains(.fastest))),
            tempoError: error(.bpm),
            colours: e.palette ?? Palette.made(from: e.values.name.isEmpty ? name : e.values.name).colors.map(\.hex),
            coloursLabel: "Colours",
            singing: .init(label: "Singing", sub: "The model writes the words, in English. Say what the voice is like in the prompt.", on: e.sung),
            hint: hint,
            delete: e.id != nil && s.genres.count > 1 ? Control(enabled: !e.busy, text: "Delete genre…", help: "Delete genre…") : nil,
            cancel: Control(text: "Cancel", help: "Cancel"),
            save: Control(enabled: !blocked, text: "Save", help: "Save"),
            ask: ask
        )
    }

    // MARK: Share sheet

    static func share(_ s: Snapshot, _ sh: Panel.Share, home: String) -> ShareCard {
        let i = sh.info
        var meta = ""
        if let i {
            meta = [metaOf(bpm: i.bpm, key: i.key, sung: sh.sung), i.length.map { Format.clock($0) } ?? "", "AAC, \(Format.size(i.bytes))"]
                .filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let ready = i != nil
        let rowEnabled = ready && !sh.busy
        let rule = "never removed by the newest-\(s.keep) rule"
        let rows: [ShareCard.Row] = [
            .init(action: .share, title: "Share…", sub: "Mail, Messages, AirDrop and the rest", on: nil, control: Control(enabled: rowEnabled, help: "Share…")),
            .init(action: .copyPath, title: "Copy its path", sub: i.map { Format.tilde($0.path.path, home: home) } ?? "", on: nil, control: Control(enabled: rowEnabled, help: "Copy its path")),
            .init(action: .showInFinder, title: "Show it in Finder", sub: "", on: nil, control: Control(enabled: rowEnabled, help: "Show it in Finder")),
            .init(action: .export, title: "Export a copy", sub: i.map { "to \(Format.tilde($0.exportPath.path, home: home))" } ?? "", on: nil, control: Control(enabled: rowEnabled, help: "Export a copy")),
            .init(action: .keep, title: "Keep it for good", sub: rule, on: i?.pinned, control: Control(enabled: rowEnabled, lit: i?.pinned ?? false, help: "Keep it for good")),
        ]
        let genreName = s.genres.first { $0.id == s.genre }?.name ?? ""
        let artwork = i.map { Artwork.recipe(name: $0.name, bpm: $0.bpm, key: $0.key, palette: palette(s)) }
        return ShareCard(back: Control(text: "Back", help: "Back"), head: i?.genre ?? genreName, name: i?.name ?? sh.target.name, meta: meta,
                         hint: "Drag the picture to drop the tune anywhere", artwork: artwork, file: i?.path, rows: rows)
    }

    // MARK: Player

    static func genreName(_ s: Snapshot) -> String {
        s.genres.first { $0.id == s.genre }?.name ?? s.genre ?? ""
    }

    static func keptCount(_ s: Snapshot) -> Int {
        max(s.keptTotal, s.genres.first { $0.id == s.genre }?.kept ?? 0)
    }

    /// Whether play would start a tune when none is playing.
    static func canPlay(_ s: Snapshot) -> Bool {
        s.player == .none && s.genre != nil && (s.ready > 0 || !s.queue.isEmpty || keptCount(s) > 0)
    }

    /// `110 BPM · A minor`, with `· sung` for a tune that has words.
    static func metaOf(bpm: Int?, key: String?, sung: Bool = false) -> String {
        [bpm.map { "\($0) BPM" } ?? "", key ?? "", sung ? "sung" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The job is drawn while the composer is on, and an own-words tune
    /// whether or not it is.
    static func jobShown(_ s: Snapshot) -> Bool {
        guard let j = s.job else { return false }
        return s.composing || j.ownWords
    }

    static func undoActive(_ s: Snapshot, now: Double) -> Bool {
        guard let u = s.undo else { return false }
        return u.until > now
    }

    /// The playing tune's position now: the snapshot's, moved on while
    /// playing by the time since it was true, never past the tune's end.
    public static func position(_ s: Snapshot, now: Double) -> Double {
        guard let t = s.tune else { return 0 }
        var p = s.pos
        if s.player == .playing { p += max(0, now - s.posAt) }
        if let l = t.length { p = min(p, l) }
        return p
    }

    /// The wave resampled to `waveBars` by index, each level within 0…1.
    public static func waveLevels(_ wave: [Double]) -> [Double] {
        (0..<waveBars).map { i in
            guard !wave.isEmpty else { return 0 }
            let v = wave[min(wave.count - 1, i * wave.count / waveBars)]
            return v.isFinite ? min(1, max(0, v)) : 0
        }
    }

    /// A click on the waveform `fraction` of the way across: the seek, to a
    /// tenth of a second, or nil without a tune whose length is known.
    public static func seek(_ s: Snapshot, fraction: Double) -> Command? {
        guard let l = s.tune?.length, l > 0 else { return nil }
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        return .seek(to: (f * l * 10).rounded() / 10)
    }

    /// The selected genre's palette, or one made from its name.
    public static func palette(_ s: Snapshot) -> Palette {
        guard let g = s.genres.first(where: { $0.id == s.genre }) else { return Palette.made(from: s.genre ?? "") }
        return palette(of: g)
    }

    /// A genre's palette for its chooser tile and backdrop.
    public static func palette(of g: GenreSummary) -> Palette {
        Palette.of(name: g.name, hex: g.palette)
    }

    static func player(_ s: Snapshot, _ p: Panel = Panel(), now: Double) -> PlayerCard {
        PlayerCard(palette: palette(s), strip: s.error, now: nowSection(s, rename: p.rename, lyricsOf: p.lyricsOf, now: now), next: nextSection(s, now: now), making: making(s, now: now), composer: composer(s, now: now))
    }

    static func nowSection(_ s: Snapshot, rename: Panel.Rename? = nil, lyricsOf: String? = nil, now: Double) -> PlayerCard.Now {
        let t = s.tune
        let name = genreName(s)
        var suffix = ""
        if t != nil && s.repeat == .one {
            suffix = "repeating"
        } else if t?.kept == true {
            suffix = "kept tunes"
        }
        var title = ""
        var tone = Tone.soft
        var meta = ""
        var wave: PlayerCard.Wave?
        var time: PlayerCard.Clock?
        if let t {
            title = t.name
            tone = s.player == .paused ? .soft : .normal
            meta = [metaOf(bpm: t.bpm, key: t.key, sung: t.sung), s.player == .paused ? "paused" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            let pos = position(s, now: now)
            let played = t.length.map { $0 > 0 ? max(0, min(waveBars, Int((pos / $0 * Double(waveBars)).rounded(.down)))) : 0 } ?? 0
            wave = PlayerCard.Wave(levels: waveLevels(t.wave), played: played, help: "Seek")
            time = PlayerCard.Clock(left: Format.clock(pos), right: Format.clock(t.length))
        } else if s.ended {
            title = "Played all \(Format.plural(keptCount(s), "\(name) tune", "\(name) tunes"))"
            meta = "Play starts over. Repeat is off."
        } else if canPlay(s) {
            // Only the user's stop is worded as one: a genre just picked starts clean.
            title = s.stopped ? "Stopped." : "Nothing playing."
        } else if s.composing {
            title = "Nothing yet"
            if s.stopped {
                meta = "The player is stopped: play starts it once a tune is ready."
            } else if [.starting, .writing, .rendering, .idle].contains(s.model.state) {
                meta = "The first tune starts by itself when it is ready."
            }
        } else if keptCount(s) == 0 {
            title = "No \(name) tunes yet"
            meta = "Turn the composer on to make some."
        } else {
            title = "Nothing to play"
        }
        let playing = s.player == .playing
        let nextMode: RepeatMode = switch s.repeat {
        case .all: .one
        case .one: .off
        case .off: .all
        }
        return PlayerCard.Now(
            label: suffix.isEmpty ? "NOW PLAYING" : "NOW PLAYING · \(suffix.uppercased())",
            suffix: suffix,
            genre: Control(text: name, help: "Genre"),
            title: title,
            titleTone: tone,
            titleControl: t == nil ? nil : Control(help: "Rename"),
            rename: rename.map { r in
                PlayerCard.RenameField(
                    text: r.text,
                    error: TuneRules.nameError(r.text) ?? r.refused ?? "",
                    save: Control(enabled: !r.busy && TuneRules.nameError(r.text) == nil, help: "Save"),
                    cancel: Control(enabled: !r.busy, help: "Cancel")
                )
            },
            lyricsButton: t?.sung == true ? Control(lit: lyricsOf == t?.file, text: "Lyrics", help: "Lyrics") : nil,
            lyrics: t?.sung == true && lyricsOf == t?.file ? (t?.lyrics ?? "") : nil,
            lyricsHead: "LYRICS AS WRITTEN",
            badge: t?.pinned == true ? "★ kept for good" : "",
            meta: meta,
            wave: wave,
            forming: t == nil && jobShown(s) ? s.job?.stage : nil,
            repeatsOne: s.repeat == .one,
            time: time,
            playPause: Control(enabled: t != nil || canPlay(s) || s.ended, help: playing ? "Pause" : "Play"),
            showsPause: playing,
            previous: Control(enabled: t != nil, help: "Previous"),
            previousCommand: t == nil ? nil : .previous,
            next: Control(enabled: s.canNext, help: "Next"),
            shuffle: Control(lit: s.shuffle, help: "Shuffle"),
            repeat: Control(lit: s.repeat != .off, text: s.repeat.rawValue, help: "Repeat \(nextMode.rawValue)"),
            share: Control(enabled: t != nil, help: "Share"),
            scrap: Control(enabled: t != nil, help: t.map { "Scrap \($0.name)" } ?? "Scrap"),
            shareRequest: t.map { ShareRequest(target: TuneTarget(name: $0.name, index: nil), file: $0.file, sung: $0.sung) },
            scrapCommand: t.map { .scrapPlaying(name: $0.name) }
        )
    }

    /// "about 1:10 left" to the nearest 10 s, at least 0:10; "any moment
    /// now" once the estimate has run out.
    static func leftWords(expect: Double, spent: Double) -> String {
        let left = expect - spent
        if left <= 0 { return "any moment now" }
        return "about \(Format.clock(max(10, (left / 10).rounded() * 10))) left"
    }

    /// Rows THIS ROUND shows in the player.
    public static let upNextRows = 3

    /// The round's entries as rows. Each row's commands and share target
    /// carry its index and name as drawn.
    static func roundRows(_ s: Snapshot, _ entries: some Sequence<RoundEntry>) -> [PlayerCard.Row] {
        let colours = palette(s)
        return entries.map { e in
            let playNow: Control?
            let playNowCommand: Command?
            let scrapCommand: Command
            let target: TuneTarget
            switch e.state {
            case .played:
                playNow = Control(help: "Play it again")
                playNowCommand = .playPlayed(index: e.index, name: e.name)
                scrapCommand = .scrapPlayed(index: e.index, name: e.name)
                target = TuneTarget(name: e.name, index: e.index, inPlayed: true)
            case .playing:
                playNow = nil
                playNowCommand = nil
                scrapCommand = .scrapPlaying(name: e.name)
                target = TuneTarget(name: e.name, index: nil)
            case .waiting:
                playNow = Control(help: "Play it now")
                playNowCommand = .playQueued(index: e.index, name: e.name)
                scrapCommand = .scrapQueued(index: e.index, name: e.name)
                target = TuneTarget(name: e.name, index: e.index)
            }
            return PlayerCard.Row(
                id: "tune \(e.id)", kind: .tune, index: e.state == .playing ? nil : e.index, state: e.state, number: String(e.number),
                name: e.name, nameTone: .normal, tag: e.new ? "new" : "", star: e.pinned,
                // Under repeat one the waiting tunes wait behind the repeat.
                dim: e.state == .played || (e.state == .waiting && s.repeat == .one),
                sub: metaOf(bpm: e.bpm, key: e.key, sung: e.sung), right: e.length.map { Format.clock($0) } ?? "", rightTone: .dim, bar: nil,
                artwork: Artwork.recipe(name: e.name, bpm: e.bpm, key: e.key, palette: colours), stage: nil,
                playNow: playNow, share: Control(help: "Share"), scrap: Control(help: "Scrap \(e.name)"),
                playNowCommand: playNowCommand,
                scrapCommand: scrapCommand,
                shareRequest: ShareRequest(target: target, file: e.file, sung: e.sung)
            )
        }
    }

    static func round(_ s: Snapshot) -> [RoundEntry] {
        round(played: s.played, tune: s.tune, queue: s.queue)
    }

    static func nextSection(_ s: Snapshot, now: Double) -> PlayerCard.Next {
        let entries = round(s)
        let window = roundWindow(entries)
        return PlayerCard.Next(
            label: "THIS ROUND",
            head: roundCount(entries),
            rows: roundRows(s, window.rows),
            more: window.more > 0 ? Control(text: "then \(window.more) more this round · Show all", help: "Show all") : nil
        )
    }

    /// BEING MADE: the job and the places not started, while the composer is on.
    static func making(_ s: Snapshot, now: Double) -> PlayerCard.Making? {
        guard s.composing || s.job?.ownWords == true else { return nil }
        var rows: [PlayerCard.Row] = []
        if let j = s.job {
            let spent = max(0, now - j.started)
            var parts: [String] = []
            var bar: Double?
            if let e = j.expectS, e > 0 {
                parts.append(leftWords(expect: e, spent: spent))
                bar = min(1, spent / e)
            } else {
                parts.append("\(Format.clock(spent)) so far")
            }
            if j.stage == .rendering, let w = j.writtenS { parts.append("written in \(Format.clock(w))") }
            let rendering = j.stage == .rendering
            var name = rendering ? "Being rendered" : "Being written"
            if j.ownWords {
                name = j.name ?? name
                parts.insert("with your words · \(rendering ? "being rendered" : "being written")", at: 0)
            }
            rows.append(PlayerCard.Row(
                id: "job", kind: .job, index: nil, number: "", name: name, nameTone: .soft,
                tag: "", star: false, dim: false, sub: parts.joined(separator: " · "), right: "composing", rightTone: .cyan, bar: bar,
                artwork: nil, stage: j.stage,
                playNow: nil, share: nil, scrap: Control(help: rendering ? "Scrap the tune being rendered" : "Scrap the tune being written"),
                playNowCommand: nil, scrapCommand: .scrapJob, shareRequest: nil
            ))
        }
        // An own-words tune does not take one of the genre's places.
        let missing = s.composing ? s.ahead - s.ready - (s.job != nil && s.job?.ownWords != true ? 1 : 0) : 0
        for n in 0..<max(0, missing) {
            rows.append(PlayerCard.Row(
                id: "placeholder \(n)", kind: .placeholder, index: nil, number: "", name: "Not started", nameTone: .dim, tag: "", star: false, dim: false,
                sub: s.job != nil ? "after the one above" : "", right: "", rightTone: .dim, bar: nil, artwork: nil, stage: nil, playNow: nil, share: nil, scrap: nil,
                playNowCommand: nil, scrapCommand: nil, shareRequest: nil
            ))
        }
        return PlayerCard.Making(head: "plays next when ready", rows: rows)
    }

    static func wordsCard(_ s: Snapshot, _ w: Panel.Words) -> WordsCard {
        let sung = WordsRules.sungLines(w.text).count
        let chars = w.text.unicodeScalars.count
        let wordsError = WordsRules.wordsError(w.text)
        let nameError = TuneRules.nameError(w.name)
        return WordsCard(
            back: Control(text: "Back", help: "Back"),
            label: "SING MY WORDS",
            title: "A tune in \(genreName(s))",
            inserts: Panel.marks.map { Control(enabled: !w.busy, text: $0.button, help: $0.button) },
            text: w.text,
            caret: w.caret,
            counter: "\(Format.plural(sung, "sung line", "sung lines")) · \(Format.grouped(chars)) of \(Format.grouped(WordsRules.max)) characters",
            counterRight: "English sings best",
            wordsError: w.touched ? wordsError ?? "" : "",
            nameLabel: "Name",
            name: w.name,
            nameError: nameError ?? "",
            note: "It is made once, with the genre's sound, and plays next when ready. The model may not sing every word as written.",
            refused: w.refused ?? "",
            cancel: Control(enabled: !w.busy, text: "Cancel", help: "Cancel"),
            compose: Control(enabled: !w.busy && wordsError == nil && nameError == nil, text: "Compose", help: "Compose")
        )
    }

    static func queueCard(_ s: Snapshot, now: Double) -> QueueCard {
        let entries = round(s)
        let last: String? = entries.last.map { t in
            s.repeat == .off ? "The round ends after \(t.name)." : "after these, a new round is drawn"
        }
        let rows = roundRows(s, entries)
        return QueueCard(
            back: Control(text: genreName(s), help: "Back"),
            label: "THIS ROUND · \(Format.plural(entries.count, "tune", "tunes").uppercased())",
            title: "This round",
            head: roundModes(shuffle: s.shuffle, repeat: s.repeat),
            rows: rows,
            scrollTo: roundScrollTarget(rows),
            last: last,
            making: making(s, now: now),
            palette: palette(s)
        )
    }

    /// The composer bar without the model: what to download, the download
    /// going, or why it stopped; no switch.
    static func standingIn(_ s: Snapshot) -> PlayerCard.Composer {
        let card = setup(s)
        let standIn: PlayerCard.StandIn
        switch card.kind {
        case .missing:
            standIn = .init(text: "The music model is not on this Mac.", detail: Format.gib(s.need.downloadBytes, decimals: 2),
                            progress: nil, button: card.button, command: card.command)
        case .downloading, .failed:
            standIn = .init(text: card.detail, detail: card.rows.map(\.value).joined(separator: " · "),
                            progress: card.progress, button: card.button, command: card.command)
        }
        return PlayerCard.Composer(on: false, label: "", labelTone: .soft, pill: nil, pillTone: .soft, toggle: Control(enabled: false, help: "Composer on"),
                                   lines: [], retry: nil, words: nil, showsSwitch: false, standIn: standIn)
    }

    /// Whether the selected genre is sung.
    static func sung(_ s: Snapshot) -> Bool {
        s.genres.first { $0.id == s.genre }?.sung ?? false
    }

    /// `Sing my words…` on a sung genre's composer bar; off while a tune with
    /// the user's words is being made.
    static func wordsControl(_ s: Snapshot) -> Control? {
        guard sung(s), s.setup == .ready else { return nil }
        return Control(enabled: s.job?.ownWords != true, text: "Sing my words…", help: "Sing my words…")
    }

    static func composer(_ s: Snapshot, now: Double) -> PlayerCard.Composer {
        if s.setup != .ready { return standingIn(s) }
        let m = s.model
        let name = genreName(s)
        let newWaiting = s.queue.filter(\.new).count
        let waiting = s.repeat == .one && newWaiting > 0
            ? PlayerCard.Line(newWaiting == 1 ? "1 new tune waits until the repeat ends." : "\(newWaiting) new tunes wait until the repeat ends.")
            : nil
        let memory = Format.gib(s.need.ramBytes)
        if !s.composing {
            let kept = keptCount(s) > 0
            var lines = [PlayerCard.Line(kept ? "On, it makes new " : "On, it makes ", em: name, post: " and keeps \(s.ahead) ahead.")]
            if let waiting { lines.append(waiting) }
            if !kept {
                if let e = s.expect {
                    let minutes = max(1, Int(((e.writingS + e.renderingS) / 60).rounded()))
                    lines.append(.init("A tune takes about \(minutes) min and \(memory) of memory while it is made."))
                } else {
                    lines.append(.init("A tune takes about \(memory) of memory while it is made."))
                }
            }
            return PlayerCard.Composer(on: false, label: "off", labelTone: .soft, pill: "off", pillTone: .soft, toggle: Control(help: "Composer on"), lines: lines, retry: nil, words: wordsControl(s))
        }
        var right = ""
        var rightTone = Tone.dim
        switch m.state {
        case .idle:
            right = "resting, queue is full"
            rightTone = .green
        case .starting:
            right = "starting the model"
            rightTone = .cyan
        case .writing, .rendering:
            if let used = m.ramUsedBytes { right = "using \(Format.gib(used)) of memory" }
        default:
            break
        }
        var lines = [PlayerCard.Line("Makes ", em: name, post: ", keeps \(s.ahead) ahead", right: right, rightTone: rightTone)]
        if let waiting { lines.append(waiting) }
        if m.state == .writing, let silence = m.silenceS {
            lines.append(.init("Writing again: the last plan had \(silence) s of silence."))
        }
        if m.state == .writing, m.thinWords {
            lines.append(.init("Writing again: the last plan had too few sung lines."))
        }
        var label = "on"
        var labelTone = Tone.soft
        switch m.state {
        case .heldPower:
            lines.append(.init("Low Power Mode is on. Composing waits and carries on by itself when it is off; tunes already made keep playing.", tone: .orange))
            label = "held for low power"
            labelTone = .orange
        case .heldHeat:
            lines.append(.init("This Mac is running hot. Composing waits and carries on by itself when it has cooled; tunes already made keep playing.", tone: .orange))
            label = "held for heat"
            labelTone = .orange
        case .heldMemory:
            lines.append(.init("Memory is under pressure. Composing carries on by itself when there is room.", tone: .orange))
            label = "held for memory"
            labelTone = .orange
        case .failed:
            var text = Format.sentence("Failed" + (m.detail.map { ": \($0)" } ?? ""))
            text += " \(Format.plural(m.failures, "failure", "failures")) in a row."
            if let at = m.retryAt {
                let left = Int((at - now).rounded(.up))
                text += left > 0 ? " Trying again in \(left) s." : " Trying again now."
            }
            lines.append(.init(text, tone: .red))
            label = "failed"
            labelTone = .red
        case .noDevice:
            lines.append(.init("The model server did not find a Metal device" + (m.detail.map { ": \(Format.sentence($0))" } ?? "."), tone: .red))
            label = "no device"
            labelTone = .red
        default:
            break
        }
        if [.starting, .writing, .rendering, .failed].contains(m.state) && !m.name.isEmpty {
            lines.append(.init([m.name, m.variant, m.device].filter { !$0.isEmpty }.joined(separator: " · ")))
        }
        let canRetry = m.state == .failed || m.state == .noDevice
        let pill: String? = label != "on" ? label : (right.isEmpty ? nil : right)
        return PlayerCard.Composer(on: true, label: label, labelTone: labelTone, pill: pill, pillTone: label != "on" ? labelTone : rightTone,
                                   toggle: Control(lit: true, help: "Composer off"),
                                   lines: lines, retry: canRetry ? Control(text: "Try now", help: "Try now") : nil, words: wordsControl(s))
    }

    // MARK: Footer, status item, tick

    /// The footer: a notice for its time in the chooser or the player (not
    /// while the delete question is open), else in the player the undo line
    /// while undo is offered; nil when there is nothing to say.
    public static func footer(_ s: Snapshot, _ p: Panel, now: Double) -> Footer? {
        let shows = card(s, p, now: now, home: "")
        let inPlayer: Bool
        let inChooser: Bool
        switch shows {
        case .player: (inPlayer, inChooser) = (true, false)
        case .chooser: (inPlayer, inChooser) = (false, true)
        default: (inPlayer, inChooser) = (false, false)
        }
        if let n = p.notice, n.until > now, inPlayer || inChooser {
            return .notice(n.text)
        }
        if inPlayer, undoActive(s, now: now), let u = s.undo {
            let left = Int((u.until - now).rounded(.up))
            return .undo(text: "Scrapped \(u.name).", button: Control(text: "Undo · \(left) s", help: "Undo"))
        }
        return nil
    }

    /// Whether anything on screen changes with the clock alone, so the 1 s
    /// tick must run.
    public static func needsTick(_ s: Snapshot, _ p: Panel, now: Double) -> Bool {
        if case .notice = footer(s, p, now: now) { return true }
        switch card(s, p, now: now, home: "") {
        case .player: break
        case .queue: return jobShown(s)
        default: return false
        }
        if s.player == .playing || undoActive(s, now: now) { return true }
        if jobShown(s) { return true }
        return s.composing && s.model.state == .failed && s.model.retryAt != nil
    }

    /// What moves on the card showing: nothing while the popover is closed or
    /// Reduce Motion is on; the backdrop also holds still in Low Power Mode.
    /// A forming wave moves whenever it is drawn, from the first snapshot
    /// that has the job.
    public static func animating(_ s: Snapshot, _ p: Panel, now: Double, popoverOpen: Bool, reduceMotion: Bool, lowPower: Bool) -> Animating {
        let allowed = popoverOpen && !reduceMotion
        var hero = false
        var job = false
        var meterShown = false
        switch card(s, p, now: now, home: "") {
        case .player(let c):
            hero = c.now.forming != nil
            job = c.making?.rows.contains { $0.kind == .job } ?? false
            meterShown = c.next.rows.contains { $0.state == .playing }
        case .queue(let c):
            job = c.making?.rows.contains { $0.kind == .job } ?? false
            meterShown = c.rows.contains { $0.state == .playing }
        default:
            break
        }
        return Animating(backdrop: allowed && !lowPower, heroForming: allowed && hero, jobForming: allowed && job,
                         meter: allowed && meterShown && s.player == .playing)
    }

    /// `Remove Music Model…`: enabled while anything of the model is on
    /// disk; its alert says how much removing frees.
    public static func modelRemoval(_ s: Snapshot) -> ModelRemoval {
        ModelRemoval(
            menuTitle: "Remove Music Model…",
            enabled: s.need.onDiskBytes > 0,
            alertTitle: "Remove the music model?",
            alertText: "It frees \(Format.gib(s.need.onDiskBytes, decimals: 2)). Composing stops until it is downloaded again; your tunes stay.",
            remove: "Remove",
            cancel: "Cancel",
            command: .removeModel
        )
    }

    /// The menu bar item.
    public static func statusItem(_ s: Snapshot) -> StatusItem {
        let m = s.model.state
        var dot: Tone?
        if s.setup == .downloading || (s.composing && [.starting, .writing, .rendering].contains(m)) {
            dot = .cyan
        } else if s.composing && [.heldPower, .heldHeat, .heldMemory].contains(m) {
            dot = .orange
        } else if s.composing && (m == .failed || m == .noDevice) {
            dot = .red
        }
        guard !setupShows(s), s.genre != nil else {
            return StatusItem(dim: true, text: "", dot: dot, help: "SwiftTunes")
        }
        return StatusItem(dim: s.player == .none, text: s.player == .playing ? genreName(s) : "", dot: dot, help: "SwiftTunes")
    }
}
