import Testing
import TunesContract
@testable import TunesPanel

@Suite("Without the music model")
struct RemovalTests {
    @Test("the setup cards only while no genre has a kept tune", arguments: ["01-not-set-up", "02-downloading", "03-download-failed"])
    func firstLaunch(_ name: String) throws {
        guard case .setup = card(try Fixture.load(name)) else { Issue.record("not setup"); return }
    }

    @Test("with kept tunes: the player, the composer bar standing in, no switch", arguments: [
        ("41-no-model-kept", "The music model is not on this Mac.", "7.57 GiB", Double?.none, "Download", Command.download),
        ("42-downloading-kept", "File 2 of 4: the language model.", "2.9 of 7.57 GiB · 28 MB/s", 3113851290.0 / 8128225608, "Cancel", .cancelDownload),
        ("43-download-failed-kept", "the connection broke. Finished files are kept.", "2.9 of 7.57 GiB", nil, "Resume", .download),
    ])
    func standIn(_ name: String, _ text: String, _ detail: String, _ progress: Double?, _ button: String, _ command: Command) throws {
        let s = try Fixture.load(name)
        let p = try player(s)
        #expect(p.now.title == "Brass Lantern")
        let c = p.composer
        #expect(!c.showsSwitch && c.lines.isEmpty && c.pill == nil && c.words == nil && c.retry == nil)
        let stand = try #require(c.standIn)
        #expect(stand.text == text && stand.detail == detail && stand.button.text == button && stand.command == command)
        if let progress { #expect(abs((stand.progress ?? -1) - progress) < 1e-9) } else { #expect(stand.progress == nil) }
    }

    @Test("with the model ready: no stand-in, the switch")
    func ready() throws {
        let c = try player(Fixture.load("07-composer-off-kept")).composer
        #expect(c.showsSwitch && c.standIn == nil)
    }

    @Test("Sing my words… waits for the model")
    func words() throws {
        var s = try Fixture.load("41-no-model-kept")
        s.genres[4].sung = true
        #expect(try player(s).composer.words == nil)
    }

    @Test("the status item shows the genre playing without the model too")
    func statusItem() throws {
        #expect(Decide.statusItem(try Fixture.load("41-no-model-kept")) == StatusItem(dim: false, text: "Jazz", dot: nil, help: "SwiftTunes"))
        #expect(Decide.statusItem(try Fixture.load("42-downloading-kept")).dot == .cyan)
        #expect(Decide.statusItem(try Fixture.load("01-not-set-up")).dim)
    }

    @Test("Remove Music Model…: enabled while anything is on disk; the alert says how much it frees", arguments: [
        ("44-model-on-disk", true, "It frees 7.57 GiB. Composing stops until it is downloaded again; your tunes stay."),
        ("42-downloading-kept", true, "It frees 2.9 GiB. Composing stops until it is downloaded again; your tunes stay."),
        ("41-no-model-kept", false, "It frees 0 GiB. Composing stops until it is downloaded again; your tunes stay."),
    ])
    func removal(_ name: String, _ enabled: Bool, _ text: String) throws {
        let r = Decide.modelRemoval(try Fixture.load(name))
        #expect(r.menuTitle == "Remove Music Model…" && r.enabled == enabled)
        #expect(r.alertTitle == "Remove the music model?" && r.alertText == text)
        #expect(r.remove == "Remove" && r.cancel == "Cancel" && r.command == .removeModel)
    }
}
