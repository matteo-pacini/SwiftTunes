import Testing
import TunesContract
@testable import TunesPanel

@Suite("Setup cards")
struct SetupTests {
    @Test("not set up: what the download needs")
    func notSetUp() throws {
        let c = try setup(Fixture.load("01-not-set-up"))
        #expect(c.kind == .missing)
        #expect(c.title == "SwiftTunes needs a music model")
        #expect(c.detail == "ACE-Step 1.5 Turbo composes on this computer. Nothing is sent anywhere after the download.")
        #expect(c.rows.map { [$0.label, $0.value] } == [["download", "7.57 GiB"], ["free on disk", "226 GiB"], ["memory while composing", "about 8 GiB of memory"]])
        #expect(c.button.text == "Download")
        #expect(c.command == .download)
    }

    @Test("downloading: the file, the amounts, the speed, Cancel")
    func downloading() throws {
        let s = try Fixture.load("02-downloading")
        let c = try setup(s)
        #expect(c.title == "Downloading the music model")
        #expect(c.detail == "File 2 of 4: the language model.")
        #expect(c.rows.map { [$0.label, $0.value] } == [["downloaded", "2.9 of 7.57 GiB"], ["speed", "28 MB/s"]])
        #expect(c.progress != nil)
        #expect(c.button.text == "Cancel")
        #expect(c.command == .cancelDownload)
        #expect(Decide.statusItem(s) == StatusItem(dim: true, text: "", dot: .cyan, help: "SwiftTunes"))
    }

    @Test("a download that stopped: its error, Resume")
    func failed() throws {
        let c = try setup(Fixture.load("03-download-failed"))
        #expect(c.title == "The download stopped")
        #expect(c.detail == "checksum mismatch on the language model. Finished files are kept.")
        #expect(c.button.text == "Resume")
        #expect(c.command == .download)
    }

    @Test("the setup cards come before any other, whatever the panel holds")
    func first() throws {
        let s = try Fixture.load("01-not-set-up")
        for p in [Panel().openingChooser(), Panel().addingGenre()] {
            guard case .setup = card(s, p) else { Issue.record("not setup"); continue }
        }
    }
}

@Suite("Player")
struct PlayerTests {
    @Test("queue full: the composer rests")
    func queueFull() throws {
        let s = try Fixture.load("05-queue-full")
        let p = try player(s)
        #expect(p.strip == nil)
        #expect([p.now.suffix, p.now.genre.text, p.now.title, p.now.meta] == ["", "Jazz", "Lazy Avenue", "139 BPM · C major"])
        #expect(p.now.titleTone == .normal)
        #expect(p.now.time?.left == "2:25" && p.now.time?.right == "2:57")
        #expect(p.now.wave?.levels.count == 78)
        #expect(p.now.wave?.played == Int(145.0 / 177 * 78))
        #expect(p.now.showsPause && p.now.playPause.enabled && p.now.next.enabled)
        #expect([p.now.playPause.help, p.now.next.help, p.now.shuffle.help, p.now.repeat.help, p.now.share.help, p.now.scrap.help]
            == ["Pause", "Next", "Shuffle", "Repeat one", "Share", "Scrap Lazy Avenue"])
        #expect(p.next.head == "2 ready")
        #expect(rows(p) == [["", "Brass Lantern", "112 BPM · F major", "2:54"], ["", "Quiet Ledger", "96 BPM · D minor", "2:49"]])
        #expect(p.next.rows.allSatisfy { $0.kind == .tune && $0.tag == "new" })
        #expect(p.next.rows.map { $0.scrap?.help } == ["Scrap Brass Lantern", "Scrap Quiet Ledger"])
        #expect(p.next.rows.map { $0.playNow?.help } == ["Play it now", "Play it now"])
        #expect(p.composer.on && p.composer.label == "on")
        #expect(lines(p) == ["Makes Jazz, keeps 2 ahead | resting, queue is full"])
        #expect(p.composer.lines[0].em == "Jazz")
        #expect(p.composer.lines[0].rightTone == .green)
        #expect(p.composer.retry == nil)
        #expect(Decide.footer(s, Panel(), now: NOW) == nil)
        #expect(Decide.statusItem(s) == StatusItem(dim: false, text: "Jazz", dot: nil, help: "SwiftTunes"))
        #expect(Decide.needsTick(s, Panel(), now: NOW))
    }

    @Test("the first tune of a genre: being rendered, with an estimate")
    func firstTune() throws {
        let s = try Fixture.load("06-first-tune")
        let p = try player(s)
        #expect([p.now.title, p.now.meta] == ["Nothing yet", "The first tune starts by itself when it is ready."])
        #expect(p.now.titleTone == .soft)
        #expect(p.now.wave == nil && p.now.time == nil)
        #expect(!p.now.playPause.enabled && !p.now.next.enabled && !p.now.share.enabled && !p.now.scrap.enabled)
        #expect(p.next.head == "0 ready")
        // 58 s expected, 18 s spent: 40 s left.
        #expect(rows(p) == [["", "Being rendered", "about 0:40 left · written in 1:04", "composing"], ["", "Not started", "after the one above", ""]])
        let job = p.next.rows[0]
        #expect(job.kind == .job && job.rightTone == .cyan)
        #expect(abs((job.bar ?? 0) - 18.0 / 58) < 1e-9)
        #expect(job.scrap?.help == "Scrap the tune being rendered")
        #expect(job.playNow == nil && job.share == nil)
        #expect(p.next.rows[1].kind == .placeholder)
        #expect(lines(p) == ["Makes Jazz, keeps 2 ahead | using 3.9 GiB of memory", "ACE-Step 1.5 Turbo · 4B Q8 · Apple M4 Pro"])
        #expect(Decide.statusItem(s) == StatusItem(dim: true, text: "", dot: .cyan, help: "SwiftTunes"))
        #expect(Decide.needsTick(s, Panel(), now: NOW))
    }

    @Test("the job row's time left: rounded to 10 s, at least 0:10, then any moment now", arguments: [
        (0.0, "about 1:10 left"), (3, "about 1:10 left"), (6, "about 1:00 left"), (68, "about 0:10 left"),
        (69.9, "about 0:10 left"), (70, "any moment now"), (500, "any moment now"), (-200, "about 2:00 left"),
    ] as [(Double, String)])
    func timeLeft(_ offset: Double, _ sub: String) throws {
        let p = try player(Fixture.load("10-writing"), now: NOW + offset)
        #expect(p.next.rows[0].sub == sub)
        #expect(p.next.rows[0].scrap?.help == "Scrap the tune being written")
    }

    @Test("the job's bar: spent over the estimate, within 0…1")
    func jobBar() throws {
        let s = try Fixture.load("10-writing")
        #expect(try player(s, now: NOW + 500).next.rows[0].bar == 1)
        #expect(try player(s, now: NOW - 200).next.rows[0].bar == 0)
    }

    @Test("no estimate: the stage and the time spent")
    func noEstimate() throws {
        let r = try player(Fixture.load("22-writing-again"), now: NOW + 5).next.rows[0]
        #expect([r.name, r.sub] == ["Being written", "0:35 so far"])
        #expect(r.bar == nil)
    }

    @Test("the placeholder rows: only with the switch on, up to ahead")
    func placeholders() throws {
        let writing = try player(Fixture.load("10-writing"))
        #expect(rows(writing) == [["", "Being written", "about 1:10 left", "composing"], ["", "Not started", "after the one above", ""]])
        #expect(writing.next.rows.map(\.nameTone) == [.soft, .dim])
        #expect(try rows(player(Fixture.load("12-held-power"))) == [["", "Dusty Notebook", "88 BPM · A major", "2:52"], ["", "Not started", "", ""]])
        #expect(try rows(player(Fixture.load("13-held-memory"))).map { $0[1] } == ["Not started", "Not started"])
        var three = try Fixture.load("13-held-memory")
        three.ahead = 3
        #expect(try player(three).next.rows.count == 3)
        #expect(try rows(player(Fixture.load("08-nothing-kept"))).isEmpty)
        #expect(try rows(player(Fixture.load("07-composer-off-kept"))) == [["1", "Lazy Avenue", "139 BPM · C major", "2:57"]])
        var off = try Fixture.load("10-writing")
        off.composing = false
        #expect(try rows(player(off)).isEmpty)
    }

    @Test("composer off, kept tunes playing")
    func composerOffKept() throws {
        let s = try Fixture.load("07-composer-off-kept")
        let p = try player(s)
        #expect([p.now.suffix, p.now.title, p.now.meta] == ["kept tunes", "Brass Lantern", "112 BPM · F major"])
        #expect(p.now.time?.left == "0:35" && p.now.time?.right == "2:54")
        #expect(p.next.head == "from 14 kept, shuffled")
        #expect(!p.composer.on && p.composer.label == "off")
        #expect(p.composer.toggle.help == "Composer on")
        #expect(lines(p) == ["On, it makes new Jazz and keeps 2 ahead."])
        #expect(Actions.composer(s) == .setComposer(on: true))
        #expect(Decide.statusItem(s) == StatusItem(dim: false, text: "Jazz", dot: nil, help: "SwiftTunes"))
        let lofi = try player(Fixture.load("09-kept-tunes"))
        #expect([lofi.now.genre.text, lofi.now.suffix, lofi.next.head] == ["Lo-fi", "kept tunes", "from 31 kept, shuffled"])
        #expect(lines(lofi) == ["On, it makes new Lo-fi and keeps 2 ahead."])
    }

    @Test("a kept tune playing with a new one ready: the heading counts the new one")
    func keptPlayingNewReady() throws {
        let s = try Fixture.load("25-kept-playing-new-ready")
        let p = try player(s)
        #expect(p.now.suffix == "kept tunes")
        #expect(p.next.head == "1 ready")
        #expect(rows(p).map { $0[1] } == ["Paper Kite", "Being written"])
        var flagged = s
        flagged.keptPlaying = true
        #expect(try player(flagged).next.head == "1 ready")
        var undone = flagged
        undone.ready = 0
        undone.queue[0].kept = true
        undone.queue[0].new = false
        #expect(try player(undone).next.head == "from 14 kept, shuffled")
    }

    @Test("a genre with nothing kept: nothing happens by itself")
    func nothingKept() throws {
        let s = try Fixture.load("08-nothing-kept")
        let p = try player(s)
        #expect([p.now.genre.text, p.now.title, p.now.meta] == ["Synthwave", "No Synthwave tunes yet", "Turn the composer on to make some."])
        #expect(!p.now.playPause.enabled && !p.now.next.enabled && p.now.wave == nil)
        #expect(p.next.head == "nothing")
        // 62 + 58 s is 2 min.
        #expect(lines(p) == ["On, it makes Synthwave and keeps 2 ahead.", "A tune takes about 2 min and 8 GiB of memory while it is made."])
        #expect(Decide.statusItem(s) == StatusItem(dim: true, text: "", dot: nil, help: "SwiftTunes"))
        #expect(!Decide.needsTick(s, Panel(), now: NOW))
    }

    @Test("the time a tune takes: minutes rounded, at least one; only memory without medians", arguments: [
        (Expect?.none, "A tune takes about 8 GiB of memory while it is made."),
        (Expect(writingS: 10, renderingS: 5), "A tune takes about 1 min and 8 GiB of memory while it is made."),
        (Expect(writingS: 100, renderingS: 95), "A tune takes about 3 min and 8 GiB of memory while it is made."),
    ])
    func tuneTakes(_ expect: Expect?, _ line: String) throws {
        var s = try Fixture.load("08-nothing-kept")
        s.expect = expect
        #expect(try lines(player(s))[1] == line)
    }

    @Test("just after a scrap: the undo line counts down", arguments: [
        (0.0, "Undo · 10 s"), (2.5, "Undo · 8 s"), (9.9, "Undo · 1 s"),
    ] as [(Double, String)])
    func undoCountdown(_ offset: Double, _ button: String) throws {
        let s = try Fixture.load("11-after-scrap")
        #expect(Decide.footer(s, Panel(), now: NOW + offset) == .undo(text: "Scrapped Lazy Avenue.", button: Control(text: button, help: "Undo")))
        #expect(Actions.undo(s, now: NOW + offset) == .undo)
    }

    @Test("after a scrap: the next tune, the job, the undo gone after 10 s")
    func afterScrap() throws {
        let s = try Fixture.load("11-after-scrap")
        let p = try player(s)
        #expect([p.now.title, p.now.time?.left, p.next.head] == ["Brass Lantern", "0:03", "1 ready"])
        #expect(rows(p) == [["", "Quiet Ledger", "96 BPM · D minor", "2:49"], ["", "Being written", "about 1:50 left", "composing"]])
        #expect(lines(p) == ["Makes Jazz, keeps 2 ahead | using 5.8 GiB of memory", "ACE-Step 1.5 Turbo · 4B Q8 · Apple M4 Pro"])
        #expect(Decide.footer(s, Panel(), now: NOW + 10) == nil)
        #expect(Actions.undo(s, now: NOW + 10) == nil)
        // Not in the chooser.
        #expect(Decide.footer(s, Panel().openingChooser(), now: NOW) == nil)
        // The countdown alone keeps the tick on.
        var paused = s
        paused.player = .paused
        paused.job = nil
        paused.composing = false
        #expect(Decide.needsTick(paused, Panel(), now: NOW))
        #expect(!Decide.needsTick(paused, Panel(), now: NOW + 10))
    }

    @Test("the composer's label and switch in each state", arguments: [
        ("08-nothing-kept", false, "off", Tone.soft, "Composer on"),
        ("10-writing", true, "on", .soft, "Composer off"),
        ("05-queue-full", true, "on", .soft, "Composer off"),
        ("12-held-power", true, "held for low power", .orange, "Composer off"),
        ("13-held-memory", true, "held for memory", .orange, "Composer off"),
        ("15-failed-playing", true, "failed", .red, "Composer off"),
        ("14-no-device", true, "no device", .red, "Composer off"),
    ])
    func composerLabel(_ name: String, _ on: Bool, _ label: String, _ tone: Tone, _ help: String) throws {
        let s = try Fixture.load(name)
        let c = try player(s).composer
        #expect(c.on == on && c.label == label && c.labelTone == tone && c.toggle.help == help)
        #expect(Actions.composer(s) == .setComposer(on: !s.composing))
    }

    @Test("held for low power, for heat and for memory")
    func held() throws {
        let power = try Fixture.load("12-held-power")
        let p = try player(power)
        #expect(p.strip == nil)
        #expect([p.now.title, p.now.time?.left] == ["Paper Lantern", "0:22"])
        #expect(lines(p) == ["Makes Lo-fi, keeps 2 ahead", "Low Power Mode is on. Composing waits and carries on by itself when it is off; tunes already made keep playing."])
        #expect(p.composer.lines[1].tone == .orange)
        #expect(Decide.statusItem(power) == StatusItem(dim: false, text: "Lo-fi", dot: .orange, help: "SwiftTunes"))
        var heat = power
        heat.model.state = .heldHeat
        let h = try player(heat)
        #expect(h.composer.label == "held for heat")
        #expect(lines(h)[1] == "This Mac is running hot. Composing waits and carries on by itself when it has cooled; tunes already made keep playing.")
        let memory = try Fixture.load("13-held-memory")
        let m = try player(memory)
        #expect([m.now.title, m.now.meta] == ["Nothing yet", ""])
        #expect(lines(m)[1] == "Memory is under pressure. Composing carries on by itself when there is room.")
        #expect(Decide.statusItem(memory) == StatusItem(dim: true, text: "", dot: .orange, help: "SwiftTunes"))
        #expect(!Decide.needsTick(memory, Panel(), now: NOW))
    }

    @Test("failed: the composer says so, Try now")
    func failed() throws {
        let s = try Fixture.load("15-failed-playing")
        let p = try player(s)
        #expect(p.now.title == "Dusty Notebook")
        #expect(lines(p) == [
            "Makes Lo-fi, keeps 2 ahead",
            "Failed: ggml_metal: device lost. 2 failures in a row. Trying again in 30 s.",
            "ACE-Step 1.5 Turbo · 4B Q8 · Apple M4 Pro",
        ])
        #expect(p.composer.lines[1].tone == .red)
        #expect(p.composer.retry == Control(text: "Try now", help: "Try now"))
        #expect(try lines(player(s, now: NOW + 31))[1] == "Failed: ggml_metal: device lost. 2 failures in a row. Trying again now.")
        #expect(Actions.retry(s) == .retry)
        #expect(Actions.retry(try Fixture.load("05-queue-full")) == nil)
        #expect(Decide.statusItem(s) == StatusItem(dim: false, text: "Lo-fi", dot: .red, help: "SwiftTunes"))
        var later = s
        later.player = .none
        later.tune = nil
        later.model.retryAt = nil
        later.model.detail = nil
        later.model.failures = 1
        #expect(try lines(player(later))[1] == "Failed. 1 failure in a row.")
        #expect(!Decide.needsTick(later, Panel(), now: NOW))
        var counting = s
        counting.player = .none
        counting.tune = nil
        #expect(Decide.needsTick(counting, Panel(), now: NOW))
    }

    @Test("writing again after a silence")
    func writingAgain() throws {
        #expect(try lines(player(Fixture.load("22-writing-again"))) == [
            "Makes Jazz, keeps 2 ahead | using 5.8 GiB of memory",
            "Writing again: the last plan had 39 s of silence.",
            "ACE-Step 1.5 Turbo · 4B Q8 · Apple M4 Pro",
        ])
    }

    @Test("paused: the position stays")
    func paused() throws {
        let s = try Fixture.load("17-paused")
        let p = try player(s, now: NOW + 60)
        #expect([p.now.title, p.now.meta, p.now.time?.left] == ["Lazy Avenue", "139 BPM · C major · paused", "2:25"])
        #expect(p.now.titleTone == .soft)
        #expect(!p.now.showsPause && p.now.playPause.enabled && p.now.playPause.help == "Play")
        #expect(Decide.statusItem(s) == StatusItem(dim: false, text: "", dot: nil, help: "SwiftTunes"))
        #expect(!Decide.needsTick(s, Panel(), now: NOW))
    }

    @Test("the position between snapshots", arguments: [(10.5, 155.5), (-5, 145), (1000, 177)] as [(Double, Double)])
    func position(_ offset: Double, _ pos: Double) throws {
        #expect(Decide.position(try Fixture.load("05-queue-full"), now: NOW + offset) == pos)
    }

    @Test("at the end the whole wave is played")
    func playedAll() throws {
        #expect(try player(Fixture.load("05-queue-full"), now: NOW + 1000).now.wave?.played == 78)
    }

    @Test("a click on the waveform seeks to a tenth of a second", arguments: [(0.5, 88.5), (1.4, 177), (-1, 0)] as [(Double, Double)])
    func seek(_ fraction: Double, _ to: Double) throws {
        #expect(Decide.seek(try Fixture.load("05-queue-full"), fraction: fraction) == .seek(to: to))
    }

    @Test("no seek without a tune whose length is known")
    func noSeek() throws {
        #expect(Decide.seek(try Fixture.load("06-first-tune"), fraction: 0.5) == nil)
    }

    @Test("stopped by the user: nothing starts by itself")
    func stopped() throws {
        let s = try Fixture.load("21-stopped")
        let p = try player(s)
        #expect(p.now.title == "Stopped.")
        #expect(p.now.playPause.enabled && !p.now.showsPause)
        #expect(p.strip == "The tune could not be played: audio output initialization failed")
        #expect(Actions.playPause(s) == .toggle)
        var wait = try Fixture.load("06-first-tune")
        wait.stopped = true
        let w = try player(wait)
        #expect([w.now.title, w.now.meta] == ["Nothing yet", "The player is stopped: play starts it once a tune is ready."])
        var kept = try Fixture.load("08-nothing-kept")
        kept.genre = "lofi"
        kept.keptTotal = 31
        kept.stopped = true
        #expect(try player(kept).now.title == "Stopped.")
    }

    @Test("a genre change starts clean: paused or stopped does not carry over", arguments: ["23-pick-after-pause", "24-pick-after-stop"])
    func pickStartsClean(_ name: String) throws {
        let all = try Fixture.snapshots(name)
        let before = try player(all[0]).now
        #expect(before.meta.hasSuffix("paused") || before.title == "Stopped.")
        let none = try player(all[1]).now
        #expect([none.genre.text, none.title, none.meta] == ["Synthwave", "No Synthwave tunes yet", "Turn the composer on to make some."])
        #expect(!none.playPause.enabled)
        #expect(Decide.statusItem(all[1]) == StatusItem(dim: true, text: "", dot: nil, help: "SwiftTunes"))
        let kept = try player(all[3]).now
        #expect([kept.genre.text, kept.suffix, kept.title, kept.meta] == ["Classical", "kept tunes", "Amber Stair", "72 BPM · G major"])
        #expect(kept.showsPause)
        #expect(Decide.statusItem(all[3]) == StatusItem(dim: false, text: "Classical", dot: nil, help: "SwiftTunes"))
    }

    @Test("kept tunes not started yet in a fresh genre: not worded as a stop")
    func notAStop() throws {
        var s = try Fixture.load("24-pick-after-stop")
        s.player = .none
        s.tune = nil
        s.stopped = false
        #expect(try player(s).now.title == "Nothing playing.")
    }

    @Test("a queue entry and a tune not read yet")
    func unread() throws {
        var s = try Fixture.load("05-queue-full")
        s.queue = [QueuedTune(name: "20260105-100000-70bpm-G-major", file: "20260105-100000-70bpm-G-major", bpm: nil, key: nil, length: nil, kept: true, new: false, pinned: false, pos: nil)]
        s.tune?.length = nil
        s.tune?.bpm = nil
        s.tune?.key = nil
        s.tune?.wave = []
        let p = try player(s)
        #expect(rows(p)[0] == ["1", "20260105-100000-70bpm-G-major", "", ""])
        #expect(p.now.meta == "")
        #expect(p.now.time?.left == "2:25" && p.now.time?.right == "–:––")
        #expect(Decide.seek(s, fraction: 0.5) == nil)
    }

    @Test("a broken genres file: the strip over the player and the chooser")
    func brokenGenres() throws {
        let s = try Fixture.load("16-genres-error")
        #expect(try player(s).strip == "genres file: line 4: expected a comma")
        #expect(try chooser(s).strip == "genres file: line 4: expected a comma")
    }

    @Test("no device: the player stays, the composer says why")
    func noDevice() throws {
        let s = try Fixture.load("14-no-device")
        let p = try player(s)
        #expect(p.now.title == "Nothing playing." && p.now.playPause.enabled)
        #expect(lines(p) == ["Makes Lo-fi, keeps 2 ahead", "The model server did not find a Metal device: 1 device, not this one."])
        #expect(p.composer.lines[1].tone == .red)
        #expect(p.composer.retry?.text == "Try now")
        #expect(Actions.retry(s) == .retry)
        var bare = s
        bare.model.detail = nil
        #expect(try lines(player(bare))[1] == "The model server did not find a Metal device.")
        #expect(Decide.statusItem(s) == StatusItem(dim: true, text: "", dot: .red, help: "SwiftTunes"))
        #expect(!Decide.needsTick(s, Panel(), now: NOW))
    }

    @Test("outside text passes through unchanged")
    func outsideText() throws {
        let s = try Fixture.load("19-outside-text")
        let p = try player(s)
        #expect(p.now.genre.text == "<b>Bold</b> & co")
        #expect(p.now.title == "<i>Name</i> & <font color=red>tag</font>")
        #expect(p.now.meta == "88 BPM · B♭ minor")
        #expect(p.now.scrap.help == "Scrap <i>Name</i> & <font color=red>tag</font>")
        #expect(p.next.rows[0].name == "<u>Queued</u>")
        #expect(p.composer.lines[0].em == "<b>Bold</b> & co")
        #expect(lines(p)[1] == "Failed: <u>server</u> said: oops. 1 failure in a row. Trying again in 30 s.")
        #expect(Decide.footer(s, Panel(), now: NOW) == .undo(text: "Scrapped <s>Gone</s>.", button: Control(text: "Undo · 6 s", help: "Undo")))
        #expect(Decide.statusItem(s) == StatusItem(dim: false, text: "<b>Bold</b> & co", dot: .red, help: "SwiftTunes"))
    }

    @Test("a session: chooser, a genre with nothing kept, the composer on, the first tune")
    func session() throws {
        let all = try Fixture.snapshots("20-session")
        let seen: [[String]] = try all.map { s in
            switch card(s) {
            case .chooser: return ["chooser"]
            case .player(let p): return [p.now.title, p.composer.label]
            default:
                Issue.record("unexpected card")
                throw CancellationError()
            }
        }
        #expect(seen == [["chooser"], ["No Synthwave tunes yet", "off"], ["Nothing yet", "on"], ["Nothing yet", "on"], ["Neon Harbour", "on"]])
        let starting = try player(all[2])
        #expect(lines(starting)[0] == "Makes Synthwave, keeps 2 ahead | starting the model")
        #expect(rows(starting).map { $0[1] } == ["Not started", "Not started"])
        #expect(Decide.statusItem(all[2]) == StatusItem(dim: true, text: "", dot: .cyan, help: "SwiftTunes"))
        #expect(Decide.statusItem(all[4]) == StatusItem(dim: false, text: "Synthwave", dot: .cyan, help: "SwiftTunes"))
    }

    @Test("the tick runs only while something on screen counts", arguments: [
        ("05-queue-full", false, true), ("05-queue-full", true, false), ("07-composer-off-kept", false, true),
        ("08-nothing-kept", false, false), ("12-held-power", false, true), ("06-first-tune", false, true),
        ("01-not-set-up", false, false), ("02-downloading", false, false), ("17-paused", false, false), ("21-stopped", false, false),
    ])
    func tick(_ name: String, _ inChooser: Bool, _ ticks: Bool) throws {
        let p = inChooser ? Panel().openingChooser() : Panel()
        #expect(Decide.needsTick(try Fixture.load(name), p, now: NOW) == ticks)
    }
}

@Suite("Status item")
struct StatusItemTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var player: PlayerState
        var composing: Bool
        var state: ModelState
        var testDescription: String { "\(player) \(composing ? "on" : "off") \(state)" }
    }

    static let cases: [Case] = [PlayerState.playing, .paused, .none].flatMap { player in
        [ModelState.idle, .starting, .writing, .rendering, .heldPower, .heldHeat, .heldMemory, .failed, .noDevice].map { Case(player: player, composing: true, state: $0) }
            + [Case(player: player, composing: false, state: .unloaded), Case(player: player, composing: false, state: .writing)]
    }

    @Test("the note and the dot in every combination", arguments: cases)
    func item(_ c: Case) throws {
        var s = try Fixture.load("05-queue-full")
        s.player = c.player
        if c.player == .none { s.tune = nil }
        s.composing = c.composing
        s.model.state = c.state
        var dot: Tone?
        if c.composing {
            switch c.state {
            case .starting, .writing, .rendering: dot = .cyan
            case .heldPower, .heldHeat, .heldMemory: dot = .orange
            case .failed, .noDevice: dot = .red
            default: dot = nil
            }
        }
        #expect(Decide.statusItem(s) == StatusItem(dim: c.player == .none, text: c.player == .playing ? "Jazz" : "", dot: dot, help: "SwiftTunes"))
    }

    @Test("no genre yet: dim, no text")
    func noGenre() throws {
        #expect(Decide.statusItem(try Fixture.load("04-chooser-first")) == StatusItem(dim: true, text: "", dot: nil, help: "SwiftTunes"))
    }
}

@Suite("Actions and Now Playing")
struct ActionTests {
    @Test("commands aimed at a tune carry its name; nothing to aim at, nothing sent")
    func names() throws {
        let s = try Fixture.load("05-queue-full")
        #expect(Actions.scrapPlaying(s) == .scrapPlaying(name: "Lazy Avenue"))
        #expect(Actions.scrapQueued(s, index: 1) == .scrapQueued(index: 1, name: "Quiet Ledger"))
        #expect(Actions.playQueued(s, index: 0) == .playQueued(index: 0, name: "Brass Lantern"))
        #expect(Actions.scrapQueued(s, index: 2) == nil)
        #expect(Actions.playQueued(s, index: -1) == nil)
        #expect(Actions.next(s) == .next)
        #expect(Actions.scrapJob(s) == nil)
        let first = try Fixture.load("06-first-tune")
        #expect(Actions.scrapPlaying(first) == nil)
        #expect(Actions.playPause(first) == nil)
        #expect(Actions.next(first) == nil)
        #expect(Actions.scrapJob(first) == .scrapJob)
        #expect(Actions.playPause(try Fixture.load("33-ended")) == .toggle)
    }

    @Test("Now Playing follows the player")
    func nowPlaying() throws {
        let playing = NowPlaying.of(try Fixture.load("05-queue-full"), now: NOW + 2)
        #expect(playing == NowPlaying(state: .playing, title: "Lazy Avenue", genre: "Jazz", duration: 177, elapsed: 147, rate: 1, canNext: true, canSeek: true))
        let paused = NowPlaying.of(try Fixture.load("17-paused"), now: NOW)
        #expect(paused.state == .paused && paused.rate == 0 && paused.elapsed == 145)
        let none = NowPlaying.of(try Fixture.load("06-first-tune"), now: NOW)
        #expect(none.state == .stopped && none.title == nil && !none.canNext)
    }
}
