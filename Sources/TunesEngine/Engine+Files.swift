import Foundation
import TunesContract
import TunesRules

extension Engine {
    // MARK: - Scrap and undo

    /// A tune file named as ours, directly in a genre's folder.
    func scrappable(_ path: URL) -> Bool {
        let dir = path.deletingLastPathComponent().standardizedFileURL
        let music = env.paths.music.standardizedFileURL
        return TuneFiles.isTune(path.lastPathComponent) && dir.deletingLastPathComponent().standardizedFileURL == music && dir != music
    }

    /// Moves a tune's file aside and offers its undo; the previous scrap is
    /// finalised only once the move is done. False when the tune is not ours
    /// or cannot be moved (said in `error`).
    func setAside(_ tune: Tune) -> Bool {
        guard scrappable(tune.path) else { return false }
        let dest = scrappedDir.appending(path: tune.file)
        // Two genre folders can hold the same file name.
        if scrap?.to == dest { finaliseScrap() }
        do {
            try Files.makeDirectory(scrappedDir)
            try Files.move(tune.path, dest)
        } catch {
            fileError = "could not scrap \(tune.name): \(Files.reason(error))"
            changed()
            return false
        }
        fileError = nil
        finaliseScrap()
        let mark = tune.path.deletingLastPathComponent().appending(path: TuneFiles.pinMark(tune.file))
        let wasPinned = Files.exists(mark)
        if wasPinned { Files.remove(mark) }
        scrap = Scrap(tune: tune, from: tune.path, to: dest, pinned: wasPinned, until: clock.now + Rules.scrapHold)
        setTimer("scrap", Rules.scrapHold) { [weak self] in self?.finaliseScrap() }
        changed()
        return true
    }

    func finaliseScrap() {
        guard let s = scrap else { return }
        scrap = nil
        cancelTimer("scrap")
        Files.remove(s.to)
        Files.remove(waveFile(s.from))
        changed()
    }

    func scrapPlaying(_ name: String) {
        guard let t = current, t.named(name), setAside(t) else { return }
        current = nil
        currentToken = nil
        appended = nil
        if let cand = nextCandidate() {
            playNow(cand)
        } else {
            loading = nil
            player.stop()
        }
        changed()
        maybeCompose()
    }

    func scrapQueued(_ i: Int, _ name: String) {
        let q = queueNow()
        guard i >= 0, i < q.count, q[i].named(name), setAside(q[i]) else { return }
        if i < ready.count {
            ready.remove(at: i)
        } else if q[i] === nextKept {
            nextKept = nil
            nextWraps = false
        }
        syncPlaylist()
        changed()
        maybeCompose()
    }

    func scrapJob() {
        guard let j = job else { return }
        if j.step == .finish { scrappedJobs.insert(j.token) }
        cancelJob()
        silenceS = nil
        changed()
        maybeCompose()
    }

    func undo() {
        guard let s = scrap else { return }
        // The undo stays offered until the file is back.
        do {
            try Files.move(s.to, s.from)
        } catch {
            fileError = "could not bring \(s.tune.name) back: \(Files.reason(error))"
            changed()
            return
        }
        fileError = nil
        scrap = nil
        cancelTimer("scrap")
        if s.pinned {
            try? Files.touch(s.from.deletingLastPathComponent().appending(path: TuneFiles.pinMark(s.from.lastPathComponent)))
        }
        changed()
        if let g = genre, s.from.deletingLastPathComponent().standardizedFileURL == genreDir(g).standardizedFileURL {
            s.tune.path = s.from
            ready.insert(s.tune, at: 0)
            syncPlaylist()
        }
    }

    // MARK: - Keep for good, share, export

    /// The playing tune (index nil) or queue entry `index`, if `name` names
    /// it and its file is ours and there. With no index and the playing tune
    /// not named, a tune of the selected genre whose file stem is `name`.
    func tuneAt(_ target: TuneTarget) -> Tune? {
        var t: Tune?
        if let i = target.index {
            let q = queueNow()
            t = i >= 0 && i < q.count ? q[i] : nil
        } else {
            t = current
            if t == nil || !(t!.named(target.name)), let g = genre, !target.name.isEmpty {
                t = keptTune(genreDir(g).appending(path: "\(target.name).\(Rules.tuneExtension)"), decode: false)
            }
        }
        guard let t, t.named(target.name), scrappable(t.path), Files.isFile(t.path) else { return nil }
        return t
    }

    func shareInfo(for target: TuneTarget) async -> Result<ShareInfo, Refusal> {
        guard let t = tuneAt(target), let bytes = Files.size(t.path) else { return .failure(Refusal(field: nil, text: Rules.gone)) }
        let folder = t.path.deletingLastPathComponent().lastPathComponent
        let taken = Set(Files.list(exportsDir))
        return .success(ShareInfo(
            name: t.name, genre: folder, bpm: t.bpm, key: t.key, length: t.length, bytes: bytes, path: t.path,
            exportPath: exportsDir.appending(path: TuneFiles.exportName(genre: folder, title: t.name, taken: taken)),
            pinned: pinned(t)
        ))
    }

    func setPinned(_ on: Bool, for target: TuneTarget) async -> Result<PinResult, Refusal> {
        guard let t = tuneAt(target) else { return .failure(Refusal(field: nil, text: Rules.gone)) }
        let mark = t.path.deletingLastPathComponent().appending(path: TuneFiles.pinMark(t.file))
        do {
            if on {
                try Files.touch(mark)
            } else if unlink(mark.path) != 0 && errno != ENOENT {
                throw POSIXError(errno)
            }
        } catch {
            return .failure(Refusal(field: nil, text: "could not \(on ? "keep" : "unpin") \(t.name): \(Files.reason(error))"))
        }
        changed()
        return .success(PinResult(on: on, name: t.name))
    }

    func exportCopy(of target: TuneTarget) async -> Result<URL, Refusal> {
        guard let t = tuneAt(target) else { return .failure(Refusal(field: nil, text: Rules.gone)) }
        let folder = t.path.deletingLastPathComponent().lastPathComponent
        let name = t.name
        let source = t.path
        let dir = exportsDir
        return await tracked {
            do {
                return .success(try await AudioWork.exportCopy(of: source, into: dir, genre: folder, title: name))
            } catch {
                return .failure(Refusal(field: nil, text: "could not export \(name): \(Files.reason(error))"))
            }
        }
    }

    // MARK: - Editing genres

    /// The file's JSON, its genres and its text, read now so a hand edit
    /// since the last read is kept; or why it cannot be edited.
    func genresOnDisk() -> Result<GenresOnDisk, NotEditable> {
        guard Files.exists(genresFile) else { return .failure(NotEditable(why: "the genres file is missing")) }
        guard let data = FileManager.default.contents(atPath: genresFile.path) else {
            return .failure(NotEditable(why: "the genres file cannot be read (permission denied)"))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(NotEditable(why: "the genres file cannot be read (not valid UTF-8)"))
        }
        let genres: [Genre]
        do {
            genres = try GenresFile.parse(text).genres
        } catch {
            return .failure(NotEditable(why: "the genres file has a mistake (\(error.description))"))
        }
        guard let doc = try? JSONValue.parse(text) else {
            return .failure(NotEditable(why: "the genres file has a mistake (not valid JSON)"))
        }
        return .success(GenresOnDisk(doc: doc, genres: genres, text: text))
    }

    /// Replaces the genres file with `doc`, unless that is its text already:
    /// written beside it with the same mode and renamed over it, so a crash
    /// leaves the old file or the new one.
    func writeGenres(_ doc: JSONValue, old: String) throws {
        let text = GenresFile.format(doc)
        if text != old {
            let path = genresFile
            let tmp = genresTmp
            var st = stat()
            let mode = stat(path.path, &st) == 0 ? st.st_mode & 0o7777 : 0o644
            let fd = open(tmp.path, O_WRONLY | O_CREAT | O_TRUNC, mode)
            guard fd >= 0 else { throw POSIXError(errno) }
            let bytes = Array(text.utf8)
            let ok = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) == $0.count } && fchmod(fd, mode) == 0 && fsync(fd) == 0
            let code = errno
            close(fd)
            guard ok else {
                Files.remove(tmp)
                throw POSIXError(code)
            }
            do {
                try Files.rename(tmp, path)
            } catch {
                Files.remove(tmp)
                throw error
            }
            // The file is replaced by now; a failure here only weakens the
            // rename's durability across a crash, so the save stands.
            let dfd = open(path.deletingLastPathComponent().path, O_RDONLY)
            if dfd >= 0 {
                fsync(dfd)
                close(dfd)
            }
        }
        genresSig = nil
        readGenres()
        if let g = genre { genre = genreByID(g.id) ?? g }
        changed()
    }

    func genre(id: String) async -> Result<GenreFields, Refusal> {
        readGenres()
        guard let g = genreByID(id) else { return .failure(Refusal(field: nil, text: Rules.genreGone)) }
        return .success(g.fields)
    }

    func saveGenre(id: String?, fields: GenreFields, base: GenreFields?) async -> Result<GenreSaved, Refusal> {
        let disk: GenresOnDisk
        switch genresOnDisk() {
        case .failure(let e): return .failure(Refusal(field: nil, text: "Nothing was saved: \(e.why)."))
        case .success(let d): disk = d
        }
        let onDisk = id.flatMap { gid in disk.genres.first { $0.id == gid } }
        if id != nil && onDisk == nil { return .failure(Refusal(field: nil, text: Rules.genreGone)) }
        if let onDisk, let base, base != onDisk.fields {
            return .failure(Refusal(field: nil, text: "\(onDisk.name) was changed in the file since you opened it."))
        }
        let others = disk.genres.filter { $0.id != id }.map(\.name)
        if let bad = GenresFile.fieldError(fields, others: others) { return .failure(bad) }
        let edited = GenresFile.edited(fields)
        var doc = disk.doc
        var gid = id ?? ""
        var moved: (URL, URL)?
        var renamed: Renamed?
        if let onDisk {
            if onDisk.name != edited.name {
                renamed = Renamed(from: onDisk.name, to: edited.name)
                let old = env.paths.music.appending(path: onDisk.name, directoryHint: .isDirectory)
                let new = env.paths.music.appending(path: edited.name, directoryHint: .isDirectory)
                if Files.exists(new) {
                    return .failure(Refusal(field: .name, text: "A folder called \(edited.name) already exists in ~/Music/Tunes."))
                }
                if Files.isDirectory(old) {
                    do {
                        try Files.rename(old, new)
                    } catch {
                        return .failure(Refusal(field: nil, text: "Nothing was saved: its folder could not be moved (\(Files.reason(error)))."))
                    }
                    moved = (old, new)
                }
            }
            doc = GenresFile.updating(doc, id: onDisk.id, with: edited)
        } else {
            gid = GenresFile.newID(for: edited.name, taken: Set(disk.genres.map(\.id)))
            doc = GenresFile.appending(doc, GenresFile.object(id: gid, edited))
        }
        do {
            try writeGenres(doc, old: disk.text)
        } catch {
            if let (old, new) = moved { try? Files.rename(new, old) }
            return .failure(Refusal(field: nil, text: "Nothing was saved: \(Files.reason(error))."))
        }
        if let (old, new) = moved { followRename(old, new) }
        return .success(GenreSaved(id: gid, renamed: renamed))
    }

    func deleteGenre(id: String) async -> Result<Void, Refusal> {
        let disk: GenresOnDisk
        switch genresOnDisk() {
        case .failure(let e): return .failure(Refusal(field: nil, text: "Nothing was deleted: \(e.why)."))
        case .success(let d): disk = d
        }
        guard disk.genres.contains(where: { $0.id == id }) else { return .failure(Refusal(field: nil, text: Rules.genreGone)) }
        guard disk.genres.count > 1 else { return .failure(Refusal(field: nil, text: "The last genre cannot be deleted.")) }
        do {
            try writeGenres(GenresFile.removing(disk.doc, id: id), old: disk.text)
        } catch {
            return .failure(Refusal(field: nil, text: "Nothing was deleted: \(Files.reason(error))."))
        }
        if genre?.id == id {
            if let j = job, j.step == .finish { scrappedJobs.insert(j.token) }
            composerOff()
            genre = nil
            ready = []
            newRound()
            wantsPlay = false
            loading = nil
            haltPlayer()
            changed()
        }
        return .success(())
    }

    /// Points every tune the engine holds in folder `old` at `new`.
    func followRename(_ old: URL, _ new: URL) {
        let oldDir = old.standardizedFileURL
        func moved(_ p: URL) -> URL {
            p.deletingLastPathComponent().standardizedFileURL == oldDir ? new.appending(path: p.lastPathComponent) : p
        }
        for t in ([current, nextKept, scrap?.tune] + ready).compactMap({ $0 }) { t.path = moved(t.path) }
        loading = loading.map { Ask(token: $0.token, path: moved($0.path)) }
        appended = appended.map { Ask(token: $0.token, path: moved($0.path)) }
        if let from = scrap?.from { scrap?.from = moved(from) }
        metaPending = Set(metaPending.map { moved(URL(filePath: $0)).path })
        // The player keeps the playing file open, but the next item is a
        // path, so it is set again.
        if current != nil && appended != nil {
            appended = nil
            syncPlaylist()
        }
        changed()
    }
}

struct GenresOnDisk {
    var doc: JSONValue
    var genres: [Genre]
    var text: String
}

/// Why the genres file cannot be edited now.
struct NotEditable: Error {
    var why: String
}
