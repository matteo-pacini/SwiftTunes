import CryptoKit
import Foundation
import TunesRules

/// One of the model files the pins name.
nonisolated struct ModelFile: Sendable, Equatable {
    var role: String
    var name: String
    var sha256: String
    var bytes: Int64
}

/// One music model the pins list.
nonisolated struct ModelPin: Sendable, Equatable {
    var id: String
    var name: String
    var variant: String
    /// Its own file, the language model: what `/lm` names in `lm_model`.
    var file: ModelFile
    var ramBytes: Int64
    /// The installed memory from which it is suggested.
    var suggestedFrom: Int64
}

/// The pins file: the models and the composer's numbers.
nonisolated struct Pins: Sendable {
    var name: String
    var baseURL: String
    var revision: String
    /// The files every model needs.
    var shared: [ModelFile]
    /// Smallest first.
    var choices: [ModelPin]
    var silenceCode: Int
    var keep: Int
    var ahead: Int
    var duration: Int

    /// Every file the pins name: the models' own, then the shared ones.
    var files: [ModelFile] { choices.map(\.file) + shared }

    func choice(_ id: String) -> ModelPin? { choices.first { $0.id == id } }

    struct Mistake: Error, CustomStringConvertible {
        var description: String
    }

    static func parse(_ text: String) throws(Mistake) -> Pins {
        guard let raw = try? JSONValue.parse(text), let m = raw["model"] else { throw Mistake(description: "no model") }
        func string(_ v: JSONValue?, _ key: String) throws(Mistake) -> String {
            guard case .string(let s)? = v, !s.isEmpty else { throw Mistake(description: key) }
            return s
        }
        func int(_ v: JSONValue?, _ key: String, zero: Bool = false) throws(Mistake) -> Int {
            guard case .int(let n)? = v, n > 0 || zero && n == 0 else { throw Mistake(description: key) }
            return n
        }
        func file(_ f: JSONValue?, _ at: String) throws(Mistake) -> ModelFile {
            let role = try string(f?["role"], "\(at).role")
            guard Rules.roleWords[role] != nil else { throw Mistake(description: "\(at).role") }
            let name = try string(f?["name"], "\(at).name")
            guard !name.hasPrefix("."), !name.contains("/") else { throw Mistake(description: "\(at).name") }
            return ModelFile(role: role, name: name, sha256: try string(f?["sha256"], "\(at).sha256").lowercased(),
                             bytes: Int64(try int(f?["bytes"], "\(at).bytes")))
        }
        guard case .array(let sharedList)? = m["shared"], !sharedList.isEmpty else { throw Mistake(description: "model.shared") }
        var shared: [ModelFile] = []
        for (i, f) in sharedList.enumerated() { shared.append(try file(f, "model.shared[\(i)]")) }
        guard case .array(let choiceList)? = m["choices"], !choiceList.isEmpty else { throw Mistake(description: "model.choices") }
        var choices: [ModelPin] = []
        for (i, c) in choiceList.enumerated() {
            let at = "model.choices[\(i)]"
            let id = try string(c["id"], "\(at).id")
            guard !choices.contains(where: { $0.id == id }) else { throw Mistake(description: "\(at).id") }
            let own = try file(c["file"], "\(at).file")
            guard own.role == "lm" else { throw Mistake(description: "\(at).file.role") }
            choices.append(ModelPin(
                id: id, name: try string(c["name"], "\(at).name"), variant: try string(c["variant"], "\(at).variant"), file: own,
                ramBytes: Int64(try int(c["ram_bytes"], "\(at).ram_bytes")),
                suggestedFrom: Int64(try int(c["suggested_from_bytes"], "\(at).suggested_from_bytes", zero: true))
            ))
        }
        return Pins(
            name: try string(m["name"], "model.name"),
            baseURL: try string(m["base_url"], "model.base_url"), revision: try string(m["revision"], "model.revision"),
            shared: shared, choices: choices, silenceCode: try int(m["silence_code"], "model.silence_code", zero: true),
            keep: try int(raw["keep"], "keep"), ahead: try int(raw["ahead"], "ahead"), duration: try int(raw["duration"], "duration")
        )
    }
}

/// What the download tells the engine as it goes.
nonisolated enum DownloadEvent: Sendable {
    /// File `index` (1-based) is being fetched; `done` bytes over all files.
    case progress(index: Int, done: Int64, total: Int64, block: Int64)
}

nonisolated enum DownloadOutcome: Sendable, Equatable {
    case done
    case cancelled
    case failed(String)
}

nonisolated enum Downloader {
    /// Fetches every file not yet in place: a part is resumed with Range and
    /// hashed as it grows; a finished part with the right sha256 takes the
    /// file's name.
    @concurrent static func run(files: [ModelFile], into directory: URL, base: String, revision: String,
                                events: AsyncStream<DownloadEvent>.Continuation) async -> DownloadOutcome {
        defer { events.finish() }
        let total = files.reduce(0) { $0 + $1.bytes }
        var done: Int64 = 0
        do {
            try Files.makeDirectory(directory)
        } catch {
            return .failed("download failed: \(Files.reason(error))")
        }
        for (i, f) in files.enumerated() {
            let final = directory.appending(path: f.name)
            let part = directory.appending(path: f.name + ".part")
            if Files.size(final) == f.bytes {
                done += f.bytes
                continue
            }
            var offset = DownloadRules.resumeOffset(partBytes: Files.size(part), expected: f.bytes)
            if offset == 0 { Files.remove(part) }
            var hash = SHA256()
            if offset > 0 {
                guard let h = try? hashFile(part) else { return .failed("download failed: cannot read \(f.name).part") }
                hash = h
            }
            if Task.isCancelled { return .cancelled }
            if offset == f.bytes {
                // All of it is here (a stop came after the last byte): there
                // is nothing to ask for, and a range past the end is refused.
                if hex(hash) != f.sha256 {
                    Files.remove(part)
                    return .failed(DownloadRules.checksumError(file: f.name))
                }
                do {
                    try Files.rename(part, final)
                } catch {
                    return .failed("download failed: \(Files.reason(error))")
                }
                done += f.bytes
                continue
            }
            guard let url = URL(string: "\(base)/resolve/\(revision)/\(f.name)") else {
                return .failed("download failed: the address is not valid")
            }
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            req.setValue("SwiftTunes", forHTTPHeaderField: "User-Agent")
            if let range = DownloadRules.rangeHeader(offset: offset) { req.setValue(range, forHTTPHeaderField: "Range") }

            let (stream, cont) = AsyncThrowingStream<Chunk, any Error>.makeStream()
            let delegate = ChunkDelegate(cont)
            let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
            let task = session.dataTask(with: req)
            defer { session.invalidateAndCancel() }
            task.resume()

            var got = offset
            var out: FileHandle?
            defer { try? out?.close() }
            var gotResponse = false
            do {
                for try await chunk in stream {
                    if Task.isCancelled {
                        task.cancel()
                        return .cancelled
                    }
                    switch chunk {
                    case .response(let response):
                        gotResponse = true
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        guard (200..<300).contains(status) else {
                            task.cancel()
                            return .failed(DownloadRules.httpError(file: f.name, status: status))
                        }
                        if offset > 0 && !DownloadRules.resumes(offset: offset, status: status) {
                            offset = 0
                            got = 0
                            hash = SHA256()
                        }
                        if offset == 0 {
                            Files.remove(part)
                            guard FileManager.default.createFile(atPath: part.path, contents: nil) else {
                                return .failed("download failed: cannot write \(f.name).part")
                            }
                        }
                        out = try FileHandle(forWritingTo: part)
                        try out?.seekToEnd()
                        events.yield(.progress(index: i + 1, done: done + got, total: total, block: 0))
                    case .data(let data):
                        try out?.write(contentsOf: data)
                        hash.update(data: data)
                        got += Int64(data.count)
                        events.yield(.progress(index: i + 1, done: done + got, total: total, block: Int64(data.count)))
                    }
                }
            } catch {
                if Task.isCancelled { return .cancelled }
                if let u = error as? URLError {
                    if u.code == .cancelled { return .cancelled }
                    return .failed(gotResponse
                        ? DownloadRules.brokeError(file: f.name, kind: u.localizedDescription)
                        : DownloadRules.reasonError(file: f.name, reason: u.localizedDescription))
                }
                return .failed("download failed: \(Files.reason(error))")
            }
            if Task.isCancelled { return .cancelled }
            try? out?.close()
            out = nil
            if got != f.bytes { return .failed(DownloadRules.shortError(file: f.name, got: got, expected: f.bytes)) }
            if hex(hash) != f.sha256 {
                Files.remove(part)
                return .failed(DownloadRules.checksumError(file: f.name))
            }
            do {
                try Files.rename(part, final)
            } catch {
                return .failed("download failed: \(Files.reason(error))")
            }
            done += f.bytes
        }
        return .done
    }

    static func hex(_ hash: SHA256) -> String {
        hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func hashFile(_ url: URL) throws -> SHA256 {
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        var hash = SHA256()
        while let block = try h.read(upToCount: 1 << 20), !block.isEmpty {
            hash.update(data: block)
        }
        return hash
    }
}

nonisolated enum Chunk: Sendable {
    case response(URLResponse)
    case data(Data)
}

/// Hands a data task's response and bytes to a stream as they arrive.
nonisolated final class ChunkDelegate: NSObject, URLSessionDataDelegate, Sendable {
    let cont: AsyncThrowingStream<Chunk, any Error>.Continuation

    init(_ cont: AsyncThrowingStream<Chunk, any Error>.Continuation) {
        self.cont = cont
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        cont.yield(.response(response))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        cont.yield(.data(data))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { cont.finish(throwing: error) } else { cont.finish() }
    }
}
