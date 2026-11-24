import Foundation
import Testing
import TunesContract
@testable import TunesEngine
import TunesFakes
import TunesRules

@Suite(.serialized) struct GenreEditingTests {
    var genresFile: (Rig) -> URL { { $0.paths.support.appending(path: "genres.json") } }

    @Test func handEditsBrokenAndMissingFiles() async throws {
        let rig = try await Rig()
        let file = genresFile(rig)
        let edited = Rig.genresText.replacingOccurrences(of: "\"name\": \"Lo-fi\"", with: "\"name\": \"Chill\"")
        try Data(edited.utf8).write(to: file)
        await rig.send(.refresh)
        #expect(rig.snap.genres.map(\.name) == ["Jazz", "Chill"])

        try Data("{".utf8).write(to: file)
        await rig.send(.refresh)
        #expect(rig.snap.error == "genres.json: not valid JSON")
        #expect(rig.snap.genres.map(\.name) == ["Jazz", "Chill"])

        try FileManager.default.removeItem(at: file)
        await rig.send(.refresh)
        #expect(rig.snap.error == "the genres file is missing")

        let exports = Rig.genresText.replacingOccurrences(of: "\"name\": \"Lo-fi\"", with: "\"name\": \"EXPORTS\"")
        try Data(exports.utf8).write(to: file)
        await rig.send(.refresh)
        #expect(rig.snap.error == "The genre EXPORTS is skipped: that name is the folder for exported copies.")
        #expect(rig.snap.genres.map(\.name) == ["Jazz"])
        await rig.close()
    }

    @Test func aNoOpSaveLeavesTheFileAlone() async throws {
        let rig = try await Rig()
        let fields = try await rig.engine.genre(id: "jazz").get()
        let before = Files.signature(genresFile(rig))
        let saved = await rig.engine.saveGenre(id: "jazz", fields: fields, base: fields)
        #expect(saved == .success(GenreSaved(id: "jazz", renamed: nil)))
        #expect(Files.signature(genresFile(rig)) == before)
        await rig.close()
    }

    @Test func refusals() async throws {
        let rig = try await Rig()
        let jazz = try await rig.engine.genre(id: "jazz").get()
        #expect(await rig.engine.genre(id: "nope") == .failure(Refusal(field: nil, text: "That genre no longer exists.")))
        var f = jazz
        f.name = "lo-FI"
        #expect(await rig.engine.saveGenre(id: "jazz", fields: f, base: jazz) == .failure(Refusal(field: .name, text: "There is already a genre called Lo-fi.")))
        f = jazz
        f.turns = ["", String(repeating: "x", count: 121)]
        #expect(await rig.engine.saveGenre(id: "jazz", fields: f, base: jazz) == .failure(Refusal(field: .turns, text: "Line 2 is longer than 120 characters.")))
        #expect(await rig.engine.saveGenre(id: "gone", fields: jazz, base: jazz) == .failure(Refusal(field: nil, text: "That genre no longer exists.")))
        var stale = jazz
        stale.caption = "an older caption"
        #expect(await rig.engine.saveGenre(id: "jazz", fields: jazz, base: stale) == .failure(Refusal(field: nil, text: "Jazz was changed in the file since you opened it.")))
        try FileManager.default.createDirectory(at: rig.genreDir("Bebop"), withIntermediateDirectories: true)
        f = jazz
        f.name = "Bebop"
        #expect(await rig.engine.saveGenre(id: "jazz", fields: f, base: jazz) == .failure(Refusal(field: .name, text: "A folder called Bebop already exists in ~/Music/Tunes.")))
        try Data("{".utf8).write(to: genresFile(rig))
        #expect(await rig.engine.saveGenre(id: "jazz", fields: jazz, base: jazz) == .failure(Refusal(field: nil, text: "Nothing was saved: the genres file has a mistake (not valid JSON).")))
        #expect(refusal(await rig.engine.deleteGenre(id: "jazz")) == Refusal(field: nil, text: "Nothing was deleted: the genres file has a mistake (not valid JSON)."))
        await rig.close()
    }

    @Test func aMinimalDiffKeepsHandEdits() async throws {
        let rig = try await Rig()
        let jazz = try await rig.engine.genre(id: "jazz").get()
        var f = jazz
        f.caption = "  a quartet now \n"
        f.turns = ["a walking bass solo", "", "  new turn ", "new turn"]
        let r = await rig.engine.saveGenre(id: "jazz", fields: f, base: jazz)
        #expect(r == .success(GenreSaved(id: "jazz", renamed: nil)))
        let want = Rig.genresText
            .replacingOccurrences(of: "a late-night jazz trio, brushed drums, upright bass", with: "a quartet now")
            .replacingOccurrences(of: "\"a walking bass solo\",\n        \"muted trumpet\",\n        \"a vibraphone chorus\"", with: "\"a walking bass solo\",\n        \"new turn\"")
        let text = try #require(Files.read(genresFile(rig)))
        // The file's own layout is the repository's: the moods line stays.
        #expect(text.contains(#""moods": ["Blue", "Smoky"]"#))
        #expect(text.contains("\"caption\": \"a quartet now\""))
        #expect(try GenresFile.parse(text).genres == GenresFile.parse(want).genres)
        await rig.close()
    }

    @Test func addRenameWhilePlayingAndDelete() async throws {
        let rig = try await Rig()
        for d in 1...3 { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.setShuffle(on: false))
        await rig.send(.selectGenre(id: "jazz"))
        let added = await rig.engine.saveGenre(id: nil, fields: GenreFields(name: "Hard Bop!", caption: "fast", turns: [], bpm: [150, 200]), base: nil)
        #expect(added == .success(GenreSaved(id: "hard-bop", renamed: nil)))
        await rig.settle()
        #expect(rig.snap.genres.map(\.id) == ["jazz", "lofi", "hard-bop"])

        let jazz = try await rig.engine.genre(id: "jazz").get()
        var f = jazz
        f.name = "Night Jazz"
        let renamed = await rig.engine.saveGenre(id: "jazz", fields: f, base: jazz)
        #expect(renamed == .success(GenreSaved(id: "jazz", renamed: Renamed(from: "Jazz", to: "Night Jazz"))))
        await rig.settle()
        #expect(!Files.exists(rig.genreDir("Jazz")) && rig.tunes("Night Jazz").count == 3)
        #expect(rig.snap.genre == "jazz" && rig.snap.keptTotal == 3)
        #expect(rig.engine.current?.path.deletingLastPathComponent().lastPathComponent == "Night Jazz")
        #expect(rig.player.next?.url.deletingLastPathComponent().lastPathComponent == "Night Jazz")
        // Scrap still works on the moved file.
        await rig.send(.scrapPlaying(name: rig.snap.tune!.name))
        #expect(rig.tunes("Night Jazz").count == 2)

        #expect(refusal(await rig.engine.deleteGenre(id: "nope")) == Refusal(field: nil, text: "That genre no longer exists."))
        #expect(refusal(await rig.engine.deleteGenre(id: "jazz")) == nil)
        await rig.settle()
        #expect(rig.snap.genre == nil && rig.snap.player == .none)
        #expect(rig.tunes("Night Jazz").count == 2)
        #expect(refusal(await rig.engine.deleteGenre(id: "lofi")) == nil)
        #expect(refusal(await rig.engine.deleteGenre(id: "hard-bop")) == Refusal(field: nil, text: "The last genre cannot be deleted."))
        await rig.close()
    }

    @Test func palettes() async throws {
        let rig = try await Rig()
        let file = rig.paths.support.appending(path: "genres.json")
        // A file without palettes keeps working untouched.
        #expect(rig.snap.genres.allSatisfy { $0.palette == nil })
        let jazz = try await rig.engine.genre(id: "jazz").get()
        #expect(jazz.palette == nil)

        let p = ["#1a1230", "#b8562b", "#7a2848", "#23408f"]
        var f = jazz
        f.palette = p
        #expect(await rig.engine.saveGenre(id: "jazz", fields: f, base: jazz) == .success(GenreSaved(id: "jazz", renamed: nil)))
        await rig.settle()
        #expect(rig.snap.genres.first { $0.id == "jazz" }?.palette == p)
        #expect(try await rig.engine.genre(id: "jazz").get().palette == p)
        let text = try #require(Files.read(file))
        #expect(text.contains("      \"bpm\": [90, 140],\n      \"palette\": [\"#1a1230\", \"#b8562b\", \"#7a2848\", \"#23408f\"],\n      \"moods\""))
        // The base carries the palette: one opened before the change is stale.
        var other = jazz
        other.caption = "a new caption"
        #expect(await rig.engine.saveGenre(id: "jazz", fields: other, base: jazz)
            == .failure(Refusal(field: nil, text: "Jazz was changed in the file since you opened it.")))

        for bad in [["#1a1230"], ["#1a1230", "#b8562b", "#7a2848", "23408f"], [String]()] {
            var g = f
            g.palette = bad
            #expect(await rig.engine.saveGenre(id: "jazz", fields: g, base: f) == .failure(Refusal(field: nil, text: "A palette is four colours.")))
        }
        var none = f
        none.palette = nil
        #expect(await rig.engine.saveGenre(id: "jazz", fields: none, base: f) == .success(GenreSaved(id: "jazz", renamed: nil)))
        #expect(Files.read(file) == Rig.genresText)

        let added = await rig.engine.saveGenre(id: nil, fields: GenreFields(name: "Bossa", caption: "nylon guitar", turns: [], bpm: [80, 110], palette: p), base: nil)
        #expect(added == .success(GenreSaved(id: "bossa", renamed: nil)))
        await rig.settle()
        #expect(rig.snap.genres.last == GenreSummary(id: "bossa", name: "Bossa", kept: 0, palette: p))

        try Data(Rig.genresText.replacingOccurrences(of: "\"bpm\": [70, 92]", with: "\"bpm\": [70, 92],\n      \"palette\": [\"#123456\"]").utf8).write(to: file)
        await rig.send(.refresh)
        #expect(rig.snap.error == "genres.json: genre 2: palette must be four colours as #RRGGBB")
        await rig.close()
    }

    @Test func pickingAnUnknownOrTheSameGenreDoesNothing() async throws {
        let rig = try await Rig()
        await rig.send(.selectGenre(id: "jazz"))
        let n = rig.snapshots.count
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.selectGenre(id: "nope"))
        #expect(rig.snapshots.count == n)
        await rig.close()
    }
}

@Suite(.serialized) struct DownloadTests {
    @Test func downloadResumeAndVerify() async throws {
        let rig = try await Rig(ready: false)
        // Half of the first file is already there.
        let first = try #require(rig.modelFiles["fake-lm.gguf"])
        try FileManager.default.createDirectory(at: rig.paths.models, withIntermediateDirectories: true)
        try first.prefix(1000).write(to: rig.paths.models.appending(path: "fake-lm.gguf.part"))
        rig.make()
        let total = rig.modelFiles.values.reduce(0) { $0 + Int64($1.count) }
        #expect(rig.snap.need.downloadBytes == total - 1000)
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        #expect(rig.snap.download == nil && rig.snap.need.downloadBytes == 0)
        #expect(rig.snapshots.contains { $0.setup == .downloading && $0.download?.name == "language model" })
        #expect(await rig.host.ranges.first == "bytes=1000-")
        for (name, data) in rig.modelFiles {
            #expect(FileManager.default.contents(atPath: rig.paths.models.appending(path: name).path) == data)
        }
        await rig.close()
    }

    @Test func aRangeIgnoredStartsOver() async throws {
        let rig = try await Rig(ready: false)
        let first = try #require(rig.modelFiles["fake-lm.gguf"])
        try FileManager.default.createDirectory(at: rig.paths.models, withIntermediateDirectories: true)
        try first.prefix(1000).write(to: rig.paths.models.appending(path: "fake-lm.gguf.part"))
        await rig.host.set(ignoreRange: true)
        rig.make()
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        #expect(FileManager.default.contents(atPath: rig.paths.models.appending(path: "fake-lm.gguf").path) == first)
        await rig.close()
    }

    @Test(arguments: [
        (404, Set<String>(), "fake-lm.gguf: HTTP 404"),
        (0, Set(["fake-dit.gguf"]), "fake-dit.gguf: checksum mismatch"),
    ])
    func failures(status: Int, corrupt: Set<String>, text: String) async throws {
        let rig = try await Rig(ready: false)
        if status != 0 { await rig.host.set(failures: [status]) }
        await rig.host.set(corrupt: corrupt)
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .failed })
        #expect(rig.snap.download?.error == text)
        #expect(rig.snap.download?.rate == 0)
        #expect(!Files.exists(rig.paths.models.appending(path: "fake-dit.gguf.part")))
        // Resume: the finished files are kept and the rest fetched.
        await rig.host.set(corrupt: [])
        await rig.send(.download)
        #expect(await rig.run { rig.snap.setup == .ready })
        await rig.close()
    }

    @Test func theCancelRace() async throws {
        let rig = try await Rig(ready: false)
        await rig.host.set(holdAfter: 500)
        rig.engine.send(.download)
        await rig.host.untilHeld()
        rig.engine.send(.cancelDownload)
        #expect(rig.engine.dl == nil && rig.engine.setup == .missing)
        // A new download at once: it waits for the cancelled one to stop writing.
        await rig.host.set(holdAfter: nil)
        rig.engine.send(.download)
        #expect(rig.engine.setup == .downloading)
        await rig.host.release()
        #expect(await rig.run { rig.snap.setup == .ready })
        for (name, data) in rig.modelFiles {
            #expect(FileManager.default.contents(atPath: rig.paths.models.appending(path: name).path) == data)
        }
        await rig.close()
    }

    @Test func cancelLeavesThePartAndNoDownload() async throws {
        let rig = try await Rig(ready: false)
        await rig.host.set(holdAfter: 500)
        rig.engine.send(.download)
        await rig.host.untilHeld()
        await rig.send(.cancelDownload)
        await rig.host.release()
        await rig.settle()
        #expect(rig.snap.download == nil && rig.snap.setup == .missing)
        await rig.close()
    }
}

@Suite(.serialized) struct RestartTests {
    @Test func restartReadsStateBackAndPlaysNothing() async throws {
        let rig = try await Rig()
        for d in 1...2 { try rig.keptTune("Jazz", day: d) }
        rig.make()
        await rig.send(.selectGenre(id: "jazz"))
        await rig.send(.setShuffle(on: false))
        await rig.send(.setRepeat(.off))
        await rig.send(.setComposer(on: true))
        #expect(await rig.run { rig.snap.expect != nil })
        let expect = rig.snap.expect
        await rig.shutdown()
        #expect(rig.launcher.running == 0)

        let calls = rig.player.calls.count
        rig.make()
        await rig.settle()
        let s = rig.snap
        #expect(!s.shuffle && s.repeat == .off && s.expect == expect)
        #expect(s.genre == nil && s.player == .none && !s.composing)
        #expect(rig.player.calls.count == calls)
        #expect(rig.launcher.launches.count == 1)
        await rig.close()
    }

    @Test func theVolumeSurvivesARestartAndReachesThePlayerAtLaunch() async throws {
        let rig = try await Rig()
        try rig.keptTune("Jazz", day: 1)
        rig.make()
        await rig.send(.setVolume(to: 0.35, dragging: false))
        await rig.shutdown()

        // A new player starts at full.
        rig.player.volume = 1
        let calls = rig.player.calls.count
        rig.make()
        // Applied at launch, with nothing played yet.
        #expect(rig.player.volume == 0.35 && rig.player.calls.count == calls)
        await rig.send(.selectGenre(id: "jazz"))
        #expect(rig.snap.player == .playing && rig.snap.volume == 0.35 && rig.player.volume == 0.35)
        await rig.close()
    }

    @Test func staleFilesAreClearedAtStart() async throws {
        let rig = try await Rig()
        let dir = rig.genreDir("Jazz")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let kept = try rig.keptTune("Jazz", day: 1)
        let part = dir.appending(path: ".20260105-120000-90bpm-C-major.m4a.part")
        let orphan = dir.appending(path: ".20260106-120000-90bpm-C-major.m4a.pin")
        let pin = dir.appending(path: ".\(kept.lastPathComponent).pin")
        let mine = dir.appending(path: ".notes.part")
        for f in [part, orphan, pin, mine] { try Data().write(to: f) }
        rig.make()
        #expect(!Files.exists(part) && !Files.exists(orphan))
        #expect(Files.exists(pin) && Files.exists(mine) && Files.exists(kept))
        await rig.close()
    }
}

/// The refusal of a result, nil for a success.
func refusal<T>(_ r: Result<T, Refusal>) -> Refusal? {
    if case .failure(let e) = r { return e }
    return nil
}
