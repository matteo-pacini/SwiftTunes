import Foundation
import TunesContract
import TunesRules

extension Engine {
    // MARK: - The switch

    func setComposer(_ on: Bool) {
        guard on else {
            composerOff()
            return
        }
        guard !composing, genre != nil, setup == .ready else { return }
        composing = true
        changed()
        maybeCompose()
    }

    func composerOff() {
        guard composing else { return }
        composing = false
        // A tune with the user's words is made with the switch off too.
        if job?.words != nil || ownWordsPending != nil {
            changed()
            return
        }
        cancelJob()
        stopServer()
        for t in ["retry", "hold_check", "poll"] { cancelTimer(t) }
        failures = 0
        retryAt = nil
        silenceS = nil
        thinWords = false
        setState(.unloaded)
        changed()
    }

    /// Forgets a tune with the user's words, made or waiting: its genre is
    /// no longer the one picked.
    func dropOwnWords() {
        ownWordsPending = nil
        guard job?.words != nil else { return }
        cancelJob(keepOwnWords: false)
        if !composing {
            stopServer()
            for t in ["retry", "hold_check", "poll"] { cancelTimer(t) }
            failures = 0
            retryAt = nil
            silenceS = nil
            thinWords = false
            setState(.unloaded)
        }
    }

    func composeWithWords(_ words: String, name: String, model: String?) async -> Result<Void, Refusal> {
        if let why = WordsRules.wordsError(words) { return .failure(Refusal(field: nil, text: why)) }
        if let why = TuneRules.nameError(name) { return .failure(Refusal(field: nil, text: why)) }
        guard let g = genre, g.sung else { return .failure(Refusal(field: nil, text: "That genre is not sung.")) }
        if ownWordsPending != nil || job?.words != nil {
            return .failure(Refusal(field: nil, text: "A tune with your words is already being made."))
        }
        ownWordsPending = OwnWords(words: words, name: GenreRules.trim(name), genreID: g.id, model: model)
        changed()
        maybeCompose()
        return .success(())
    }

    func setState(_ new: ModelState, detail newDetail: String? = nil) {
        guard new != state || newDetail != detail else { return }
        state = new
        detail = newDetail
        since = clock.now
        changed()
    }

    func retry() {
        guard state == .failed || state == .noDevice else { return }
        cancelTimer("retry")
        retryAt = nil
        setState(.unloaded)
        maybeCompose()
    }

    var held: Bool { state == .heldMemory || state == .heldPower || state == .heldHeat }

    /// Something is to be made: the switch is on, or the user's words wait.
    var wanted: Bool { composing || ownWordsPending != nil }

    func canCompose() -> Bool {
        setup == .ready && genre != nil && wanted && state != .failed && state != .noDevice && !held
    }

    /// Starts what the composer needs next: the server, then a job, while
    /// fewer than `ahead` new tunes wait. A full queue rests the composer
    /// and stops the server. A tune with the user's words comes first, full
    /// queue or not; once made with the switch off, the server stops.
    func maybeCompose() {
        guard job == nil, !shuttingDown else { return }
        if !wanted {
            if server != nil || state == .starting || state == .writing || state == .rendering {
                stopServer()
                setState(.unloaded)
            }
            return
        }
        guard canCompose() else { return }
        if ownWordsPending == nil && newReady() >= (pins?.ahead ?? 2) {
            stopServer()
            setState(.idle)
            return
        }
        if let h = env.holds.current(memory: true) {
            enterHold(h)
            return
        }
        guard let s = server else {
            startServer()
            return
        }
        guard s.up else { return }
        startJob()
    }

    // MARK: - Holds

    static func state(for hold: Hold) -> ModelState {
        switch hold {
        case .memory: .heldMemory
        case .power: .heldPower
        case .heat: .heldHeat
        }
    }

    func enterHold(_ hold: Hold) {
        cancelJob()
        stopServer()
        silenceS = nil
        thinWords = false
        setState(Self.state(for: hold))
        setTimer("hold_check", Rules.holdWaiting) { [weak self] in self?.holdTick() }
    }

    func holdTick() {
        guard genre != nil, wanted, held else { return }
        if let h = env.holds.current(memory: true) {
            setState(Self.state(for: h))
            setTimer("hold_check", Rules.holdWaiting) { [weak self] in self?.holdTick() }
        } else {
            setState(.unloaded)
            maybeCompose()
        }
    }

    /// While a job runs memory pressure is not checked: the server's own
    /// load raises it, and would hold every tune.
    func runningHoldTick() {
        guard job != nil else { return }
        if let h = env.holds.current(memory: false) {
            enterHold(h)
        } else {
            setTimer("hold_check", Rules.holdRunning) { [weak self] in self?.runningHoldTick() }
        }
    }

    // MARK: - The server

    func startServer() {
        guard pins != nil else { return }
        let port = env.freePort()
        let record = ServerRecord(port: port, client: ServerClient(host: env.host, port: port))
        server = record
        silenceS = nil
        thinWords = false
        setState(.starting)
        setTimer("server_start", Rules.startTimeout) { [weak self] in
            self?.failure("the model server did not start in time")
        }
        let args = ["--models", env.paths.models.path, "--device", ServerLog.device, "--host", env.host, "--port", String(port)]
        do {
            let process = try env.launcher.launch(
                arguments: args,
                onLine: { [weak self, weak record] line in
                    guard let self, let record else { return }
                    self.serverLine(record, line)
                },
                onExit: { [weak self, weak record] status in
                    guard let self, let record else { return }
                    self.serverExited(record, status)
                }
            )
            record.process = process
            exiting[ObjectIdentifier(record)] = process
            // A line seen during the launch may have stopped it already.
            if record.stopping || server !== record { process.stop() }
        } catch {
            if server === record { server = nil }
            failure("the model server could not be started: \(error)")
        }
    }

    func serverLine(_ record: ServerRecord, _ line: String) {
        record.lines.append(line)
        if record.lines.count > 400 { record.lines.removeFirst(record.lines.count - 400) }
        guard record === server, !record.stopping else { return }
        if let name = ServerLog.metalDevice(line) {
            record.device = name
            if lastDevice != name {
                lastDevice = name
                changed()
            }
        }
        if ServerLog.isListening(line) && !record.confirmed {
            record.confirmed = true
            guard record.device != nil else {
                cancelTimer("server_start")
                stopServer()
                setState(.noDevice, detail: ServerLog.missingDevice(record.lines))
                return
            }
            serverHealth(record)
        }
    }

    func serverHealth(_ record: ServerRecord) {
        spawn { [weak self] in
            let reply = try? await record.client.json("GET", "/health")
            guard let self, record === self.server, !record.stopping else { return }
            guard reply?["status"] == .string("ok") else {
                self.setTimer("server_health", Rules.healthGap) { [weak self] in self?.serverHealth(record) }
                return
            }
            self.cancelTimer("server_start")
            record.up = true
            self.maybeCompose()
        }
    }

    func serverExited(_ record: ServerRecord, _ status: Int32) {
        record.exitStatus = status
        exiting[ObjectIdentifier(record)] = nil
        guard record === server else { return }
        server = nil
        if record.stopping { return }
        cancelTimer("server_start")
        cancelTimer("server_health")
        if ServerLog.saysNoDevice(record.lines) {
            cancelJob()
            setState(.noDevice, detail: ServerLog.missingDevice(record.lines))
            return
        }
        failure(ServerLog.exited(status: status, lines: record.lines))
    }

    func stopServer() {
        cancelTimer("server_start")
        cancelTimer("server_health")
        guard let s = server, !s.stopping else { return }
        s.stopping = true
        server = nil
        changed()
        if s.cancelling == nil && !s.cancelPending {
            s.process?.stop()
        } else {
            // A job is being cancelled: the server ends it within a second,
            // where SIGTERM mid-job would wait out the kill grace. One still
            // running then (a cancel waits for a model load to finish) is
            // killed: the server ignores SIGTERM for the whole job.
            setTimer("drain:\(s.port)", Rules.drainMax) { [weak self] in
                self?.cancelTimer("drain-poll:\(s.port)")
                s.process?.kill()
            }
        }
    }

    /// Asks the server whether the cancelled job has ended; closes its
    /// lifeline once it has, or once the wait is over.
    func drain(_ s: ServerRecord) {
        guard s.stopping, let id = s.cancelling else { return }
        spawn { [weak self] in
            let reply = try? await s.client.json("GET", ServerClient.jobPath(id))
            guard let self else { return }
            if reply?["status"] == .string("running") {
                self.setTimer("drain-poll:\(s.port)", Rules.drainPoll) { [weak self] in self?.drain(s) }
            } else {
                self.cancelTimer("drain:\(s.port)")
                s.process?.stop()
            }
        }
    }

    // MARK: - Jobs

    /// Ends the job. A tune with the user's words goes back to wait, to be
    /// made when the hold or the failure lifts, unless `keepOwnWords` is off.
    func cancelJob(keepOwnWords: Bool = true) {
        let j = job
        job = nil
        if let j, let words = j.words, keepOwnWords {
            ownWordsPending = OwnWords(words: words, name: j.name, genreID: j.genre.id, model: j.model?.id)
        }
        cancelTimer("poll")
        cancelTimer("lost")
        if !held { cancelTimer("hold_check") }
        if let j, let s = server, s.up {
            if j.posting {
                // The job's id is still on its way: it is cancelled when it comes.
                j.cancelWhenPosted = true
                s.cancelPending = true
            } else if let id = j.id {
                sendCancel(id, s)
            }
        }
        if j != nil { changed() }
    }

    func sendCancel(_ id: String, _ s: ServerRecord) {
        s.cancelling = id
        spawn { [weak self] in
            let sent = (try? await s.client.call("POST", ServerClient.jobPath(id, "&cancel=1"))) != nil
            guard let self else { return }
            guard s.stopping else {
                // The server stays: nothing waits on this job's end.
                if s.cancelling == id { s.cancelling = nil }
                return
            }
            if sent {
                self.drain(s)
            } else {
                self.cancelTimer("drain:\(s.port)")
                s.process?.stop()
            }
        }
    }

    /// After a job's POST answers: false when the job was cancelled while it
    /// was in flight, and its new id is cancelled now.
    func posted(_ j: JobRecord, _ s: ServerRecord, _ result: Result<String, any Error>) -> Bool {
        j.posting = false
        guard j.cancelWhenPosted else { return true }
        j.cancelWhenPosted = false
        s.cancelPending = false
        if case .success(let id) = result {
            sendCancel(id, s)
        } else if s.stopping {
            cancelTimer("drain:\(s.port)")
            s.process?.stop()
        }
        return false
    }

    /// With no job, `writing` and `rendering` do not stand: `idle` is only
    /// for a composer at rest with no server, which `maybeCompose` sets.
    func settleState() {
        guard job == nil, state == .writing || state == .rendering else { return }
        setState(server == nil ? .unloaded : .starting)
    }

    func startJob() {
        guard let g = genre, let s = server else { return }
        let own = ownWordsPending.flatMap { $0.genreID == g.id ? $0 : nil }
        ownWordsPending = nil
        let j = makeJob(g, own: own)
        job = j
        // Writing from the moment it starts, before the server answers.
        j.step = .lm
        setState(.writing)
        changed()
        setTimer("hold_check", Rules.holdRunning) { [weak self] in self?.runningHoldTick() }
        postLM(j, s)
    }

    /// A job for genre `g`: its tempo, caption and name drawn now; sung
    /// when the genre is, or with the user's words. Made with the chosen
    /// model, or the one the words ask for while it is on disk.
    func makeJob(_ g: Genre, own: OwnWords?) -> JobRecord {
        jobSeq += 1
        let sung = own != nil || g.sung
        let asked = own?.model.flatMap { pins?.choice($0) }.flatMap { onDisk($0) ? $0 : nil }
        return JobRecord(
            token: jobSeq, genre: g, bpm: Composing.bpm(g.bpm, rng: &rng),
            caption: Composing.caption(caption: g.caption, turns: g.turns, sung: sung, rng: &rng),
            name: own?.name ?? Composing.name(moods: g.moods, things: g.things, rng: &rng), writeAt: clock.now,
            sung: sung, words: own?.words, model: asked ?? chosenModel()
        )
    }

    /// The body of a job's /lm request. Sung: empty lyrics ask the model to
    /// write the words; given words are sent as given. Either way the
    /// language is asked for, since left free the model picks one, or none.
    func lmBody(_ j: JobRecord) -> JSONValue {
        var fields: [(key: String, value: JSONValue)] = [
            ("caption", .string(j.caption)), ("lyrics", .string(j.words ?? (j.sung ? "" : Rules.lyrics))),
            ("duration", .int(pins?.duration ?? 180)), ("bpm", .int(j.bpm)),
        ]
        if j.sung { fields.append(("vocal_language", .string(Rules.vocalLanguage))) }
        // Without it the server takes the first language model by file name.
        if let m = j.model { fields.append(("lm_model", .string(m.file.name))) }
        return .object(fields)
    }

    func postLM(_ j: JobRecord, _ s: ServerRecord) {
        let body = lmBody(j)
        j.posting = true
        spawn { [weak self] in
            let result: Result<String, any Error>
            do {
                result = .success(try ServerClient.jobID(try await s.client.json("POST", "/lm", body: body)))
            } catch {
                result = .failure(error)
            }
            guard let self, self.posted(j, s, result), self.job === j, self.server === s else { return }
            switch result {
            case .failure(let e):
                self.failure("the model server refused the song request: \(describe(e))")
            case .success(let id):
                j.id = id
                j.step = .lm
                self.setState(.writing)
                self.changed()
                self.setTimer("poll", Rules.poll) { [weak self] in self?.poll(j, s) }
            }
        }
    }

    func poll(_ j: JobRecord, _ s: ServerRecord) {
        guard let id = j.id else { return }
        spawn { [weak self] in
            let status: Result<String, any Error>
            do {
                let reply = try await s.client.json("GET", ServerClient.jobPath(id))
                guard case .string(let st)? = reply["status"] else { throw ServerClient.Failure(description: "the answer has no status") }
                status = .success(st)
            } catch {
                status = .failure(error)
            }
            guard let self, self.job === j, self.server === s else { return }
            switch status {
            case .failure(let e):
                self.pollFailed(j, s, e)
            case .success("running"):
                self.ramMoved()
                self.setTimer("poll", Rules.poll) { [weak self] in self?.poll(j, s) }
            case .success("done"):
                self.fetch(j, s, id)
            case .success(let other):
                let what = j.step == .lm ? "song" : "audio"
                self.failure("the \(what) job \(other)" + (ServerLog.lastError(s.lines).map { ": \($0)" } ?? ""))
            }
        }
    }

    /// Publishes the server's footprint when it moved by 0.1 GiB or more
    /// since the last snapshot: a stage's memory comes and goes inside it.
    func ramMoved() {
        let now = serverFootprint()
        switch (now, publishedRAM) {
        case let (n?, p?) where abs(n - p) < Rules.ramStep: return
        case (nil, nil): return
        default: changed()
        }
    }

    /// A poll that got no answer: the server's exit explains it if it comes
    /// within the grace; otherwise the server is lost.
    func pollFailed(_ j: JobRecord, _ s: ServerRecord, _ error: any Error) {
        setTimer("lost", Rules.lostGrace) { [weak self] in
            guard let self, self.job === j else { return }
            if let status = s.exitStatus {
                self.failure(ServerLog.exited(status: status, lines: s.lines))
            } else {
                self.failure("lost the model server: \(describe(error))")
            }
        }
    }

    func fetch(_ j: JobRecord, _ s: ServerRecord, _ id: String) {
        spawn { [weak self] in
            let body: Result<Data, any Error>
            do {
                body = .success(try await s.client.call("GET", ServerClient.jobPath(id, "&result=1"), timeout: 60))
            } catch {
                body = .failure(error)
            }
            guard let self, self.job === j, self.server === s else { return }
            switch body {
            case .failure(let e): self.failure("could not fetch the job's result: \(describe(e))")
            case .success(let data): j.step == .lm ? self.planDone(j, s, data) : self.synthDone(j, data)
            }
        }
    }

    func planDone(_ j: JobRecord, _ s: ServerRecord, _ body: Data) {
        let plan: JSONValue
        let verdict: PlanVerdict
        do {
            guard case .array(let list) = try JSONValue.parse(String(decoding: body, as: UTF8.self)), let first = list.first,
                  case .object = first
            else { throw ServerClient.Failure(description: "no plan in the answer") }
            plan = first
            guard case .string(let codes)? = plan["audio_codes"] else { throw Silence.NoCodes() }
            verdict = Silence.verdict(try Silence.parseCodes(codes), silence: pins?.silenceCode ?? 0)
        } catch let e as Silence.NoCodes {
            failure("the song plan could not be read: \(e.description)")
            return
        } catch let e as ServerClient.Failure {
            failure("the song plan could not be read: \(e.description)")
            return
        } catch {
            failure("the song plan could not be read: not JSON")
            return
        }
        if let rewrite = verdict.rewrite {
            j.rewrites += 1
            if j.rewrites >= Rules.rewritesMax {
                failure("\(Rules.rewritesMax) plans in a row had long silences")
                return
            }
            silenceS = Int(rewrite.rounded(.toNearestOrEven))
            thinWords = false
            changed()
            postLM(j, s)
            return
        }
        // The model's own words must be enough to sing; given words are not judged.
        if j.sung && j.words == nil {
            var words = ""
            if case .string(let w)? = plan["lyrics"] { words = w }
            if WordsRules.tooThin(words) {
                j.thinRewrites += 1
                if j.thinRewrites >= Rules.rewritesMax {
                    failure("\(Rules.rewritesMax) plans in a row had too few sung lines")
                    return
                }
                silenceS = nil
                thinWords = true
                changed()
                postLM(j, s)
                return
            }
        }
        silenceS = nil
        thinWords = false
        j.cut = verdict.cut
        j.plan = plan
        guard case .object(var fields) = plan else { return }
        fields.removeAll { $0.key == "output_format" }
        fields.append(("output_format", .string("wav16")))
        j.posting = true
        spawn { [weak self] in
            let result: Result<String, any Error>
            do {
                result = .success(try ServerClient.jobID(try await s.client.json("POST", "/synth", body: .object(fields))))
            } catch {
                result = .failure(error)
            }
            guard let self, self.posted(j, s, result), self.job === j, self.server === s else { return }
            switch result {
            case .failure(let e):
                self.failure("the model server refused the audio request: \(describe(e))")
            case .success(let id):
                j.id = id
                j.step = .synth
                j.renderAt = self.clock.now
                j.writtenS = Timings.tenth(j.renderAt - j.writeAt)
                self.setState(.rendering)
                self.changed()
                self.setTimer("poll", Rules.poll) { [weak self] in self?.poll(j, s) }
            }
        }
    }

    func synthDone(_ j: JobRecord, _ body: Data) {
        let audio: Data
        do {
            audio = try Multipart.audio(body)
        } catch {
            failure("the audio result could not be read: \(error.description)")
            return
        }
        j.step = .finish
        cancelTimer("hold_check")
        var bpm = j.bpm
        if case .int(let b)? = j.plan["bpm"], b > 0 { bpm = b }
        var key = ""
        if case .string(let k)? = j.plan["keyscale"] { key = k }
        let wav = workDir.appending(path: "job-\(j.token).wav")
        // Encoded in the cache and placed in the genre's folder only when
        // done, under the name the genre has then: a rename can come between.
        let encoded = workDir.appending(path: "job-\(j.token).m4a")
        do {
            try Files.makeDirectory(workDir)
            try audio.write(to: wav)
        } catch {
            failure("cannot write the tune: \(Files.reason(error))")
            return
        }
        let g = j.genre
        var lyrics: String?
        if j.sung, case .string(let w)? = j.plan["lyrics"], !WordsRules.sungLines(w).isEmpty { lyrics = w }
        let tags = TuneTags(title: j.name, genre: g.name, bpm: bpm, key: key.isEmpty ? nil : key, lyrics: lyrics,
                            model: j.model.map { "\(pins?.name ?? "") \($0.variant)" })
        let token = j.token
        let cut = j.cut
        spawn { [weak self] in
            let result: Result<TuneMeta, AudioFailure>
            do throws(AudioFailure) {
                result = .success(try await AudioWork.finish(wav: wav, target: encoded, cut: cut, tags: tags))
            } catch {
                result = .failure(error)
            }
            self?.tuneDone(token, g, encoded, bpm, key, result)
        }
    }

    /// Moves a finished tune from the cache into the folder its genre has
    /// now; its path and the genre as it is now.
    func place(_ encoded: URL, _ genre: Genre, _ bpm: Int, _ key: String) throws -> (URL, Genre) {
        let g = genreByID(genre.id) ?? genre
        let dir = genreDir(g)
        var when = Date(timeIntervalSince1970: clock.now)
        var target = dir.appending(path: TuneFiles.fileName(at: when, timeZone: env.timeZone, bpm: bpm, key: key))
        while Files.exists(target) {
            when += 1
            target = dir.appending(path: TuneFiles.fileName(at: when, timeZone: env.timeZone, bpm: bpm, key: key))
        }
        let part = dir.appending(path: TuneFiles.partName(target.lastPathComponent))
        do {
            try Files.makeDirectory(dir)
            try Files.copyFile(encoded, part)
            try Files.rename(part, target)
        } catch {
            Files.remove(part)
            Files.remove(encoded)
            throw error
        }
        Files.remove(encoded)
        return (target, g)
    }

    func tuneDone(_ token: Int, _ genre: Genre, _ encoded: URL, _ bpm: Int, _ key: String, _ result: Result<TuneMeta, AudioFailure>) {
        let mine = job?.token == token
        if scrappedJobs.remove(token) != nil {
            Files.remove(encoded)
            return
        }
        let meta: TuneMeta
        let target: URL
        let g: Genre
        switch result {
        case .failure(let e):
            if mine { failure(e.description) }
            return
        case .success(let m):
            do {
                (target, g) = try place(encoded, genre, bpm, key)
                meta = m
            } catch {
                if mine { failure("cannot write the tune: \(Files.reason(error))") }
                return
            }
        }
        let name = mine ? (job?.name ?? meta.name ?? "") : TuneFiles.stem(target.lastPathComponent)
        let tune = Tune(path: target, name: name, bpm: bpm, key: key.isEmpty ? nil : key, length: meta.length, kept: false, wave: meta.wave)
        tune.lyrics = meta.lyrics
        writeWave(target, TuneMeta(name: tune.name, length: meta.length, wave: meta.wave, lyrics: meta.lyrics))
        prune(g, fresh: target)
        changed()
        guard mine, let j = job else { return }
        if let id = j.model?.id {
            var t = stageTimings(id)
            t.writing = Timings.adding(j.writtenS ?? 0, to: t.writing)
            t.rendering = Timings.adding(clock.now - j.renderAt, to: t.rendering)
            timings[id] = t
        }
        saveState()
        job = nil
        failures = 0
        retryAt = nil
        if self.genre?.id == g.id {
            upcoming.append(QueueItem(name: tune.file, tune: tune))
        }
        syncPlaylist()
        changed()
        maybeCompose()
        settleState()
    }

    /// The keep rule over `genre`'s folder; `fresh`, a tune just placed, is
    /// never deleted.
    func prune(_ g: Genre, fresh: URL?) {
        // A deleted genre's folder is the user's now: its tunes stay.
        guard genreByID(g.id) != nil else { return }
        let dir = genreDir(g).standardizedFileURL
        // What plays, the new tunes, and the kept tunes the player shows next.
        var protected = Set((ready + [current].compactMap { $0 })
            .filter { $0.path.deletingLastPathComponent().standardizedFileURL == dir }.map(\.file))
        protected.formUnion(upcoming.prefix(Rules.keptShown).map(\.name))
        if let fresh { protected.insert(fresh.lastPathComponent) }
        let names = listTunes(g)
        let pinnedNames = Set(names.filter { Files.exists(dir.appending(path: TuneFiles.pinMark($0))) })
        for name in TuneFiles.keepVictims(names, keep: pins?.keep ?? 50, protected: protected, pinned: pinnedNames) {
            let path = dir.appending(path: name)
            Files.remove(waveFile(path))
            Files.remove(path)
        }
    }

    func failure(_ text: String) {
        cancelJob()
        stopServer()
        cancelTimer("hold_check")
        failures += 1
        let delay = Rules.retryDelay(failures: failures)
        retryAt = clock.now + delay
        silenceS = nil
        thinWords = false
        setState(.failed, detail: text)
        changed()
        setTimer("retry", delay) { [weak self] in self?.retryDue() }
    }

    func retryDue() {
        retryAt = nil
        guard state == .failed else { return }
        setState(.unloaded)
        maybeCompose()
    }

    // MARK: - The models

    func complete(_ f: ModelFile) -> Bool {
        Files.size(env.paths.models.appending(path: f.name)) == f.bytes
    }

    /// Its own file and the shared files are complete.
    func onDisk(_ c: ModelPin) -> Bool {
        complete(c.file) && (pins?.shared ?? []).allSatisfy(complete)
    }

    func suggestedModel() -> ModelPin? {
        guard let pins else { return nil }
        return pins.choices[ModelRules.suggested(from: pins.choices.map(\.suggestedFrom), memory: memoryBytes)]
    }

    /// The model new tunes are made with, or, while none is on disk, the
    /// one `download` fetches.
    func chosenModel() -> ModelPin? {
        guard let pins else { return nil }
        let suggested = ModelRules.suggested(from: pins.choices.map(\.suggestedFrom), memory: memoryBytes)
        return pins.choices[ModelRules.chosen(saved: chosenID, ids: pins.choices.map(\.id), onDisk: pins.choices.map(onDisk),
                                              suggested: suggested)]
    }

    func stageTimings(_ id: String?) -> StageTimings {
        id.flatMap { timings[$0] } ?? StageTimings()
    }

    /// From the next tune on; a tune being made keeps its model.
    func chooseModel(_ id: String) {
        guard let pins, let c = pins.choice(id), chosenID != id else { return }
        guard onDisk(c) || !pins.choices.contains(where: onDisk) else { return }
        chosenID = id
        saveState()
        checkSetup()
        changed()
    }

    // MARK: - Download

    /// Fetches what the chosen model lacks, and saves it as chosen.
    func download() {
        guard let c = chosenModel(), !onDisk(c) else { return }
        // Unsaved, a suggested Small would give way to a Large added later:
        // a state file without a model means the largest on disk.
        if chosenID != c.id {
            chosenID = c.id
            saveState()
        }
        startDownload(c)
    }

    /// Fetches another model's own file and any shared file missing; a
    /// failed or cancelled one carries on from its part.
    func downloadModel(_ id: String) {
        guard let c = pins?.choice(id), !onDisk(c) else { return }
        startDownload(c)
    }

    func startDownload(_ c: ModelPin) {
        guard dlTask == nil, let pins else { return }
        let files = ([c.file] + pins.shared).filter { !complete($0) }
        removeError = nil
        dlToken += 1
        let token = dlToken
        dlFiles = files
        dl = Download(file: 1, files: files.count, name: Rules.roleWords[files[0].role] ?? "", done: 0,
                      total: files.reduce(0) { $0 + $1.bytes }, rate: 0, error: nil, model: c.id)
        dlRate = RateWindow()
        let previous = dlPrevious
        let models = env.paths.models
        dlTask = spawn { [weak self] in
            // One download writes at a time: a cancelled one finishes first.
            await previous?.value
            let (events, cont) = AsyncStream<DownloadEvent>.makeStream()
            async let outcome = Downloader.run(files: files, into: models, base: pins.baseURL, revision: pins.revision, events: cont)
            for await e in events { self?.downloadProgress(token, e) }
            self?.downloadDone(token, await outcome)
        }
        checkSetup()
        changed()
    }

    func downloadProgress(_ token: Int, _ event: DownloadEvent) {
        guard token == dlToken, dlTask != nil, var d = dl else { return }
        switch event {
        case .progress(let index, let done, let total, let block):
            d.file = index
            d.name = Rules.roleWords[dlFiles[index - 1].role] ?? ""
            d.done = done
            d.total = total
            d.rate = block > 0 ? dlRate.add(block, at: clock.now) : 0
        }
        dl = d
        let wait = dlLastSent + Rules.downloadGap - clock.now
        if wait <= 0 {
            dlLastSent = clock.now
            changed()
        } else if timers["download_flush"] == nil {
            setTimer("download_flush", wait) { [weak self] in
                guard let self else { return }
                self.dlLastSent = self.clock.now
                self.changed()
            }
        }
    }

    func downloadDone(_ token: Int, _ outcome: DownloadOutcome) {
        guard token == dlToken, dlTask != nil else { return }
        dlTask = nil
        dlPrevious = nil
        cancelTimer("download_flush")
        switch outcome {
        case .done, .cancelled:
            dl = nil
        case .failed(let text):
            dl?.error = text
            dl?.rate = 0
        }
        checkSetup()
        changed()
        maybeCompose()
    }

    func cancelDownload() {
        guard let task = dlTask else { return }
        task.cancel()
        dlPrevious = task
        dlTask = nil
        dl = nil
        cancelTimer("download_flush")
        checkSetup()
        changed()
    }

    // MARK: - Removing the model

    /// What every listed model file and its part take on disk now.
    func modelBytesOnDisk() -> Int64 {
        (pins?.files ?? []).reduce(0) { sum, f in
            sum + (Files.size(env.paths.models.appending(path: f.name)) ?? 0)
                + (Files.size(env.paths.models.appending(path: f.name + ".part")) ?? 0)
        }
    }

    /// Stops all composing and deletes every listed file and its part,
    /// nothing else in the folder. What plays plays on.
    func removeModel() {
        // A download may not have written its first bytes yet: it counts.
        guard pins != nil, modelBytesOnDisk() > 0 || dlTask != nil else { return }
        dropOwnWords()
        composerOff()
        cancelDownload()
        let writing = dlPrevious
        spawn { [weak self] in
            // A cancelled download may still hold a part open: it ends first.
            await writing?.value
            self?.deleteModelFiles(self?.pins?.files ?? [])
        }
    }

    /// Deletes one model's own file and its part, nothing else. The chosen
    /// one goes only as the last on disk, and then as `removeModel`.
    func removeOneModel(_ id: String) {
        guard let pins, let c = pins.choice(id) else { return }
        if c.id == chosenModel()?.id {
            guard !pins.choices.contains(where: { $0.id != id && onDisk($0) }) else { return }
            removeModel()
            return
        }
        let fetching = dlTask != nil && dl?.model == id
        let names = [c.file.name, c.file.name + ".part"]
        guard fetching || names.contains(where: { Files.exists(env.paths.models.appending(path: $0)) }) else { return }
        if fetching { cancelDownload() }
        let writing = dlPrevious
        spawn { [weak self] in
            // A cancelled download may still hold a part open: it ends first.
            await writing?.value
            self?.deleteModelFiles([c.file], of: c)
        }
    }

    /// Deletes `files` and their parts; with `model`, only that model's
    /// download is forgotten and a failure names it.
    func deleteModelFiles(_ files: [ModelFile], of model: ModelPin? = nil) {
        var failure: Int32?
        for f in files {
            for name in [f.name, f.name + ".part"] where unlink(env.paths.models.appending(path: name).path) != 0 {
                if errno != ENOENT && failure == nil { failure = errno }
            }
        }
        // Whatever was deleted stays deleted.
        removeError = failure.map { "could not remove \(model?.name ?? "the music model"): \(String(cString: strerror($0)))" }
        if model == nil || dl?.model == model?.id { dl = nil }
        checkSetup()
        changed()
    }

    // MARK: - Shutdown

    func shutdown() async {
        guard !shuttingDown else { return }
        shuttingDown = true
        // A drag the pointer never let go of.
        saveState()
        dlTask?.cancel()
        dlPrevious?.cancel()
        let downloads = [dlTask, dlPrevious].compactMap { $0 }
        for name in Array(timers.keys) { cancelTimer(name) }
        cancelJob()
        stopServer()
        current = nil
        loading = nil
        appended = nil
        player.stop()
        for task in downloads { await task.value }
        for process in Array(exiting.values) { await process.waitForExit() }
        // What is still running (a request, a file's decode) is cancelled,
        // and waited for, so nothing the engine started outlives it.
        let running = Array(tasks.values)
        running.forEach { $0.cancel() }
        for task in running { await task.value }
    }
}
