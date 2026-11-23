import Testing
import TunesContract
@testable import TunesPanel

@Suite("Renaming the playing tune")
struct RenameTests {
    func field(_ s: Snapshot, _ p: Panel) throws -> PlayerCard.RenameField? {
        try player(s, p).now.rename
    }

    @Test("a click on the name opens the field holding it; the name's tooltip is Rename")
    func begin() throws {
        let s = try Fixture.load("05-queue-full")
        #expect(try player(s).now.titleControl == Control(help: "Rename"))
        #expect(try player(s).now.rename == nil)
        let p = Panel().beginningRename(s)
        #expect(p.rename?.target == TuneTarget(name: "Lazy Avenue", index: nil))
        #expect(try field(s, p) == PlayerCard.RenameField(text: "Lazy Avenue", error: "", save: Control(help: "Save"), cancel: Control(help: "Cancel")))
        #expect(p.beginningRename(s) == p)
    }

    @Test("no tune, or another card: no field")
    func nothingToRename() throws {
        let first = try Fixture.load("06-first-tune")
        #expect(try player(first).now.titleControl == nil)
        #expect(Panel().beginningRename(first).rename == nil)
        #expect(Panel().openingChooser().beginningRename(try Fixture.load("05-queue-full")).rename == nil)
    }

    @Test("the local rule's sentence shows under the field as typed, and Save waits", arguments: [
        ("", "A tune needs a name."),
        ("  \t ", "A tune needs a name."),
        ("a\nb", "A name cannot hold control characters or line breaks."),
        (String(repeating: "x", count: 61), "A name is at most 60 characters; this one has 61."),
        (String(repeating: "x", count: 60), ""),
        ("Late Bloom", ""),
    ])
    func localRule(_ text: String, _ error: String) throws {
        let s = try Fixture.load("05-queue-full")
        let p = Panel().beginningRename(s).typedName(text)
        let f = try #require(try field(s, p))
        #expect(f.text == text && f.error == error && f.save.enabled == error.isEmpty)
        let (_, target, name) = p.savingRename()
        #expect((target == nil) == !error.isEmpty)
        #expect(name == (error.isEmpty ? text : nil))
    }

    @Test("save is pending until the engine answers; a second save waits; typing waits")
    func pending() throws {
        let s = try Fixture.load("05-queue-full")
        let (p, target, name) = Panel().beginningRename(s).typedName("Late Bloom").savingRename()
        #expect(target == TuneTarget(name: "Lazy Avenue", index: nil) && name == "Late Bloom")
        let f = try #require(try field(s, p))
        #expect(!f.save.enabled && !f.cancel.enabled)
        #expect(p.savingRename().1 == nil)
        #expect(p.typedName("Other") == p)
    }

    @Test("success closes the field; a refusal shows under it and the field stays open, cleared by typing")
    func answers() throws {
        let s = try Fixture.load("05-queue-full")
        let (p, target, _) = Panel().beginningRename(s).typedName("Late Bloom").savingRename()
        let t = try #require(target)
        #expect(p.renamed(.success("Late Bloom"), target: t).rename == nil)
        let refused = p.renamed(.failure(Refusal(field: nil, text: "could not rename Lazy Avenue: disk full")), target: t)
        let f = try #require(try field(s, refused))
        #expect(f.text == "Late Bloom" && f.error == "could not rename Lazy Avenue: disk full" && f.save.enabled)
        #expect(try field(s, refused.typedName("Late Bloom 2"))?.error == "")
        #expect(try field(s, p.renamed(.failure(Refusal(field: nil, text: "")), target: t))?.error == "The tune was not renamed.")
        // An answer about another tune changes nothing.
        #expect(p.renamed(.success("x"), target: TuneTarget(name: "Brass Lantern", index: nil)) == p)
    }

    @Test("cancel, the cross or Esc, puts the old name back")
    func cancel() throws {
        let s = try Fixture.load("05-queue-full")
        let p = Panel().beginningRename(s).typedName("Something else")
        #expect(p.cancellingRename().rename == nil)
        let (escaped, close) = p.escaping(s)
        #expect(!close && escaped.rename == nil && escaped.mode == .player)
        #expect(try player(s, escaped).now.title == "Lazy Avenue")
    }

    @Test("another tune starting while the field is open closes it without saving")
    func tuneChanged() throws {
        let a = try Fixture.load("05-queue-full")
        let p = Panel().beginningRename(a).typedName("Late Bloom")
        let b = try Fixture.load("11-after-scrap")
        #expect(p.following(b).rename == nil)
        #expect(try player(b, p).now.rename == nil)
        var stopped = a
        stopped.tune = nil
        stopped.player = .none
        #expect(p.following(stopped).rename == nil)
        // The same tune with its title read: still the same file, the field stays.
        var titled = a
        titled.tune?.name = "Lazy Avenue (title)"
        #expect(p.following(titled) == p)
    }
}
