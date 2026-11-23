import Foundation
import TunesRules

/// The model server's HTTP API, as this engine uses it.
nonisolated struct ServerClient: Sendable {
    let base: URL
    let session: URLSession

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// One session for every server the engine starts; it is never
    /// invalidated, since a late request on an invalidated session traps.
    static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 4
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    init(host: String, port: Int) {
        base = URL(string: "http://\(host):\(port)")!
        session = Self.sharedSession
    }

    /// The raw body of a request; `body` is sent as JSON.
    func call(_ method: String, _ path: String, body: JSONValue? = nil, timeout: Double = 10) async throws -> Data {
        var req = URLRequest(url: URL(string: path, relativeTo: base)!)
        req.httpMethod = method
        req.timeoutInterval = timeout
        if let body {
            req.httpBody = Data(body.dumps().utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure(description: "HTTP \(http.statusCode)")
        }
        return data
    }

    func json(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        let data = try await call(method, path, body: body)
        do {
            return try JSONValue.parse(String(decoding: data, as: UTF8.self))
        } catch {
            throw Failure(description: "the answer is not JSON")
        }
    }

    /// A job's id from a reply to `/lm` or `/synth`, as text for the query.
    static func jobID(_ reply: JSONValue) throws -> String {
        switch reply["id"] {
        case .int(let n)?: return String(n)
        case .string(let s)? where !s.isEmpty: return s
        default: throw Failure(description: "the answer has no job id")
        }
    }
}

/// An error's text as a failure line shows it.
nonisolated func describe(_ error: any Error) -> String {
    if let f = error as? ServerClient.Failure { return f.description }
    if let u = error as? URLError { return u.localizedDescription }
    return "\(error)"
}
