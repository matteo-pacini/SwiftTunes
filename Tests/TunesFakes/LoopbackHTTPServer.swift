import Foundation
import Network

/// A request as the loopback server read it.
public struct HTTPRequest: Sendable {
    public var method: String
    /// The path with its query, as sent.
    public var target: String
    /// Header names in lower case.
    public var headers: [String: String]
    public var body: Data

    public var path: String { String(target.split(separator: "?", maxSplits: 1).first ?? "") }

    public var query: [String: String] {
        guard let q = target.split(separator: "?", maxSplits: 1).dropFirst().first else { return [:] }
        var out: [String: String] = [:]
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            out[String(kv[0])] = kv.count > 1 ? String(kv[1]) : ""
        }
        return out
    }
}

/// A reply; the body is sent in `parts`, with `between` awaited after each
/// part but the last, so a test can hold a reply half sent.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [(String, String)]
    public var parts: [Data]
    public var between: (@Sendable (Int) async -> Void)?
    /// Close the connection without answering.
    public var drop: Bool

    public init(status: Int, headers: [(String, String)] = [], body: Data = Data(), drop: Bool = false) {
        self.status = status
        self.headers = headers
        self.parts = [body]
        self.drop = drop
    }

    public static func json(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "application/json")], body: Data(text.utf8))
    }

    public static let dropped = HTTPResponse(status: 0, drop: true)
}

/// An HTTP/1.1 server on 127.0.0.1, one request per connection.
public final class LoopbackHTTPServer: Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "loopback-http")
    let acceptor: Task<Void, Never>
    public let port: UInt16

    /// Listens on `port` (0 for any) and answers every request with `handler`.
    public init(port: UInt16 = 0, handler: @escaping @Sendable (HTTPRequest) async -> HTTPResponse) async throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        let (connections, accept) = AsyncStream<NWConnection>.makeStream()
        listener.newConnectionHandler = { accept.yield($0) }
        let (states, stateChanges) = AsyncStream<NWListener.State>.makeStream()
        listener.stateUpdateHandler = { stateChanges.yield($0) }
        listener.start(queue: queue)
        for await state in states {
            if case .ready = state { break }
            if case .failed(let error) = state { throw error }
        }
        listener.stateUpdateHandler = nil
        self.listener = listener
        self.port = listener.port?.rawValue ?? 0
        let queue = self.queue
        acceptor = Task {
            await withDiscardingTaskGroup { group in
                for await connection in connections {
                    group.addTask { await Self.serve(connection, queue: queue, handler: handler) }
                }
            }
        }
    }

    public func stop() {
        listener.cancel()
        acceptor.cancel()
    }

    static func serve(_ c: NWConnection, queue: DispatchQueue, handler: @Sendable (HTTPRequest) async -> HTTPResponse) async {
        c.start(queue: queue)
        defer { c.cancel() }
        var buffer = Data()
        let headEnd = Data("\r\n\r\n".utf8)
        var request: HTTPRequest?
        while request == nil {
            guard let chunk = await receive(c) else { return }
            buffer.append(chunk)
            guard let r = buffer.range(of: headEnd) else { continue }
            let head = String(decoding: buffer[..<r.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let first = head[0].split(separator: " ")
            guard first.count >= 2 else { return }
            var headers: [String: String] = [:]
            for line in head.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            var body = Data(buffer[r.upperBound...])
            let length = Int(headers["content-length"] ?? "0") ?? 0
            while body.count < length {
                guard let more = await receive(c) else { return }
                body.append(more)
            }
            request = HTTPRequest(method: String(first[0]), target: String(first[1]), headers: headers, body: body)
        }
        let response = await handler(request!)
        if response.drop { return }
        let total = response.parts.reduce(0) { $0 + $1.count }
        var head = "HTTP/1.1 \(response.status) \(response.status < 300 ? "OK" : "Error")\r\n"
        var names = Set<String>()
        for (k, v) in response.headers {
            head += "\(k): \(v)\r\n"
            names.insert(k.lowercased())
        }
        if !names.contains("content-length") { head += "Content-Length: \(total)\r\n" }
        head += "Connection: close\r\n\r\n"
        guard await send(c, Data(head.utf8)) else { return }
        for (i, part) in response.parts.enumerated() {
            guard await send(c, part) else { return }
            if i < response.parts.count - 1 { await response.between?(i) }
        }
    }

    static func receive(_ c: NWConnection) async -> Data? {
        await withCheckedContinuation { cont in
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, done, error in
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else {
                    cont.resume(returning: done || error != nil ? nil : Data())
                }
            }
        }
    }

    static func send(_ c: NWConnection, _ data: Data) async -> Bool {
        await withCheckedContinuation { cont in
            c.send(content: data, completion: .contentProcessed { error in cont.resume(returning: error == nil) })
        }
    }
}
