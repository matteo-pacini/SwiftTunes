import Accelerate
import AVFoundation
import Foundation
import TunesRules

/// The tags a kept tune carries.
nonisolated struct TuneTags: Sendable {
    var title: String
    var genre: String
    var bpm: Int?
    var key: String?
    /// The words, for a sung tune.
    var lyrics: String? = nil
    /// The id of the model that made it.
    var model: String? = nil
}

/// What reading a tune's audio gives.
nonisolated struct TuneMeta: Sendable, Equatable {
    var name: String?
    var length: Double
    var wave: [Double]
    /// The words in the file's lyrics tag, nil when it has none.
    var lyrics: String? = nil
}

nonisolated struct AudioFailure: Error, CustomStringConvertible {
    var description: String
}

nonisolated enum AudioWork {
    /// Turns the server's WAV into a tagged AAC file at `target`: cut at
    /// `cut` seconds with a 1.5 s fade before it, checked by the loudness
    /// backstop. Its length and waveform, or a failure line.
    @concurrent static func finish(wav: URL, target: URL, cut: Double?, tags: TuneTags) async throws(AudioFailure) -> TuneMeta {
        let untagged = target.deletingLastPathComponent().appending(path: "untagged-" + target.lastPathComponent)
        defer {
            Files.remove(wav)
            Files.remove(untagged)
        }
        let buffer: AVAudioPCMBuffer
        do {
            let file = try AVAudioFile(forReading: wav)
            guard let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                throw AudioFailure(description: "the audio result could not be read: no memory for it")
            }
            try file.read(into: b)
            buffer = b
        } catch let e as AudioFailure {
            throw e
        } catch {
            throw AudioFailure(description: "the audio result could not be read: \(error.localizedDescription)")
        }
        let rate = buffer.format.sampleRate
        if let cut {
            let end = min(AVAudioFrameCount((cut * rate).rounded()), buffer.frameLength)
            buffer.frameLength = end
            fadeOut(buffer, seconds: Rules.fade)
        }
        let mono = try monoSamples(buffer)
        let quiet = Levels.quietMidRun(Levels.db(mono))
        if quiet > Rules.quietMax {
            throw AudioFailure(description: "the rendered tune is silent for \(String(format: "%.0f", quiet)) s in the middle")
        }
        do {
            try encode(buffer, to: untagged)
            try await tag(untagged, to: target, tags: tags)
        } catch {
            Files.remove(target)
            throw AudioFailure(description: "the tune could not be encoded: \(error.localizedDescription)")
        }
        return TuneMeta(name: tags.title, length: Timings.tenth(Double(mono.count) / Rules.decodeRate), wave: Levels.wave(mono),
                        lyrics: tags.lyrics)
    }

    /// A kept tune's title, length and waveform, read from its file.
    @concurrent static func meta(of url: URL) async throws -> TuneMeta {
        let file = try AVAudioFile(forReading: url)
        guard let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioFailure(description: "no memory for the tune")
        }
        try file.read(into: b)
        let mono = try monoSamples(b)
        let asset = AVURLAsset(url: url)
        var title: String?
        var lyrics: String?
        if let items = try? await asset.load(.metadata) {
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataSongName).first
                ?? AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .commonIdentifierTitle).first {
                title = try? await item.load(.stringValue)
            }
            if let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .iTunesMetadataLyrics).first {
                lyrics = try? await item.load(.stringValue)
            }
        }
        if let l = lyrics, l.isEmpty { lyrics = nil }
        return TuneMeta(name: title, length: Timings.tenth(Double(mono.count) / Rules.decodeRate), wave: Levels.wave(mono),
                        lyrics: lyrics)
    }

    /// A linear fade to silence over the buffer's last `seconds`.
    static func fadeOut(_ buffer: AVAudioPCMBuffer, seconds: Double) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let n = min(frames, Int((seconds * buffer.format.sampleRate).rounded()))
        guard n > 0 else { return }
        var ramp = [Float](repeating: 0, count: n)
        var start: Float = 1
        var step: Float = -1 / Float(n)
        vDSP_vramp(&start, &step, &ramp, 1, vDSP_Length(n))
        for c in 0..<Int(buffer.format.channelCount) {
            let p = channels[c] + (frames - n)
            vDSP_vmul(p, 1, ramp, 1, p, 1, vDSP_Length(n))
        }
    }

    /// The buffer as mono at the decode rate, for the backstop and the waveform.
    static func monoSamples(_ buffer: AVAudioPCMBuffer) throws(AudioFailure) -> [Float] {
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Rules.decodeRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: buffer.format, to: target)
        else { throw AudioFailure(description: "the audio result could not be read: no converter") }
        converter.downmix = true
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * Rules.decodeRate / buffer.format.sampleRate) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw AudioFailure(description: "the audio result could not be read: no memory for it")
        }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = out.floatChannelData else {
            throw AudioFailure(description: "the audio result could not be read: \(error?.localizedDescription ?? "conversion failed")")
        }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(out.frameLength)))
    }

    /// AAC at 256 kbit/s in an .m4a, encoded by the system.
    static func encode(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        Files.remove(url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: buffer.format.sampleRate,
            AVNumberOfChannelsKey: buffer.format.channelCount,
            AVEncoderBitRateKey: 256_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    /// Copies the audio of `source` into `target` with the tags, no re-encode.
    static func tag(_ source: URL, to target: URL, tags: TuneTags) async throws {
        Files.remove(target)
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw AudioFailure(description: "no export session")
        }
        session.metadata = metadata(tags)
        try await session.export(to: target, as: .m4a)
    }

    static func metadata(_ tags: TuneTags) -> [AVMetadataItem] {
        func item(_ id: AVMetadataIdentifier, _ value: any NSCopying & NSObjectProtocol) -> AVMetadataItem {
            let m = AVMutableMetadataItem()
            m.identifier = id
            m.value = value
            m.extendedLanguageTag = "und"
            return m
        }
        var items = [
            item(.iTunesMetadataSongName, tags.title as NSString),
            item(.iTunesMetadataUserGenre, tags.genre as NSString),
        ]
        if let bpm = tags.bpm {
            let m = item(.iTunesMetadataBeatsPerMin, NSNumber(value: Int16(clamping: bpm)))
            items.append(m)
        }
        if let key = tags.key, !key.isEmpty {
            items.append(item(.iTunesMetadataUserComment, "key: \(key)" as NSString))
        }
        if let lyrics = tags.lyrics, !lyrics.isEmpty {
            items.append(item(.iTunesMetadataLyrics, lyrics as NSString))
        }
        if let model = tags.model {
            items.append(item(.iTunesMetadataEncodedBy, model as NSString))
        }
        return items
    }

    /// Rewrites a tune's title tag in place: the audio and every other tag
    /// are copied as they are into `part` (beside the file), which then
    /// replaces it in one rename. A failure leaves the file as it was and
    /// no part behind.
    @concurrent static func retitle(_ url: URL, to title: String, part: URL) async throws {
        Files.remove(part)
        do {
            let asset = AVURLAsset(url: url)
            var items = try await asset.load(.metadata).filter { $0.identifier != .iTunesMetadataSongName }
            let name = AVMutableMetadataItem()
            name.identifier = .iTunesMetadataSongName
            name.value = title as NSString
            name.extendedLanguageTag = "und"
            items.append(name)
            guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                throw AudioFailure(description: "no export session")
            }
            session.metadata = items
            try await session.export(to: part, as: .m4a)
            try Files.rename(part, url)
        } catch {
            Files.remove(part)
            throw error
        }
    }

    /// Copies a kept tune into `directory` under a free export name; the
    /// path written.
    @concurrent static func exportCopy(of source: URL, into directory: URL, genre: String, title: String) async throws -> URL {
        try Files.makeDirectory(directory)
        let part = directory.appending(path: ".export-\(getpid())-\(UUID().uuidString).m4a.part")
        defer { Files.remove(part) }
        try Files.copyFile(source, part)
        // link(2) fails on an existing name, so two exports never take one.
        while true {
            let taken = Set(Files.list(directory))
            let target = directory.appending(path: TuneFiles.exportName(genre: genre, title: title, taken: taken))
            if link(part.path, target.path) == 0 { return target }
            if errno != EEXIST { throw POSIXError(errno) }
        }
    }
}
