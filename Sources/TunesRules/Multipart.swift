import Foundation

public enum Multipart {
    public enum Failure: Error, Equatable, CustomStringConvertible {
        case notMultipart, noAudioPart
        public var description: String {
            switch self {
            case .notMultipart: "not multipart"
            case .noAudioPart: "no audio part"
            }
        }
    }

    /// The first audio part of the server's multipart/mixed synth result.
    /// The boundary is the body's first line.
    public static func audio(_ body: Data) throws(Failure) -> Data {
        let bytes = [UInt8](body)
        guard bytes.starts(with: [0x2D, 0x2D]) else { throw .notMultipart }
        let crlf: [UInt8] = [0x0D, 0x0A]
        guard let lineEnd = find(crlf, in: bytes, from: 0) else { throw .notMultipart }
        let boundary = Array(bytes[0..<lineEnd])
        let separator = crlf + boundary
        var parts: [ArraySlice<UInt8>] = []
        var start = 0
        while let at = find(separator, in: bytes, from: start) {
            parts.append(bytes[start..<at])
            start = at + separator.count
        }
        parts.append(bytes[start...])
        for var part in parts {
            if part.starts(with: boundary) { part = part.dropFirst(boundary.count) }
            let flat = Array(part)
            guard let split = find([0x0D, 0x0A, 0x0D, 0x0A], in: flat, from: 0) else { continue }
            let head = String(decoding: flat[0..<split], as: UTF8.self).lowercased()
            if head.contains("content-type: audio/") {
                return Data(flat[(split + 4)...])
            }
        }
        throw .noAudioPart
    }

    private static func find(_ needle: [UInt8], in hay: [UInt8], from: Int) -> Int? {
        guard !needle.isEmpty, needle.count <= hay.count, from <= hay.count - needle.count else { return nil }
        var i = from
        let last = hay.count - needle.count
        while i <= last {
            if hay[i] == needle[0] && hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
            i += 1
        }
        return nil
    }
}
