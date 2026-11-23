import Foundation

/// A JSON value that keeps the order of an object's keys, so a file edited
/// by hand is written back with its keys where they were.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    /// A number written without a fraction or exponent that fits an Int.
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    public static func == (a: JSONValue, b: JSONValue) -> Bool {
        switch (a, b) {
        case (.null, .null): true
        case let (.bool(x), .bool(y)): x == y
        case let (.int(x), .int(y)): x == y
        case let (.double(x), .double(y)): x == y
        case let (.string(x), .string(y)): x == y
        case let (.array(x), .array(y)): x == y
        case let (.object(x), .object(y)):
            x.count == y.count && zip(x, y).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        default: false
        }
    }

    /// The number as a Double, for either kind of number.
    public var number: Double? {
        switch self {
        case .int(let i): Double(i)
        case .double(let d): d
        default: nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields.first(where: { $0.key == key })?.value
    }

    public struct ParseError: Error, Equatable {}

    /// Parses strict JSON. A repeated key keeps its first place and its last
    /// value.
    public static func parse(_ text: String) throws(ParseError) -> JSONValue {
        var p = Parser(scalars: Array(text.unicodeScalars))
        p.skipSpace()
        let v = try p.value()
        p.skipSpace()
        guard p.i == p.scalars.count else { throw ParseError() }
        return v
    }

    /// Compact text with ", " and ": " separators and raw UTF-8: control
    /// characters, quotes and backslashes escaped, nothing else.
    public func dumps() -> String {
        var out = ""
        write(to: &out)
        return out
    }

    private func write(to out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .double(let d): out += JSONValue.format(d)
        case .string(let s): JSONValue.quote(s, into: &out)
        case .array(let a):
            out += "["
            for (n, v) in a.enumerated() {
                if n > 0 { out += ", " }
                v.write(to: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            for (n, f) in o.enumerated() {
                if n > 0 { out += ", " }
                JSONValue.quote(f.key, into: &out)
                out += ": "
                f.value.write(to: &out)
            }
            out += "}"
        }
    }

    /// A double as the shortest text that reads back the same, always with
    /// a fraction or exponent so it reads back as a double.
    static func format(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        let s = "\(d)"
        return s.contains(".") || s.contains("e") ? s : s + ".0"
    }

    static func quote(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 {
                    out += String(format: "\\u%04x", u.value)
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var i = 0

        mutating func skipSpace() {
            while i < scalars.count, [" ", "\t", "\n", "\r"].contains(scalars[i]) { i += 1 }
        }

        mutating func value() throws(ParseError) -> JSONValue {
            guard i < scalars.count else { throw ParseError() }
            switch scalars[i] {
            case "{": return try object()
            case "[": return try array()
            case "\"": return .string(try string())
            case "t": try literal("true"); return .bool(true)
            case "f": try literal("false"); return .bool(false)
            case "n": try literal("null"); return .null
            default: return try number()
            }
        }

        mutating func literal(_ word: String) throws(ParseError) {
            for u in word.unicodeScalars {
                guard i < scalars.count, scalars[i] == u else { throw ParseError() }
                i += 1
            }
        }

        mutating func object() throws(ParseError) -> JSONValue {
            i += 1
            var fields: [(key: String, value: JSONValue)] = []
            skipSpace()
            if i < scalars.count, scalars[i] == "}" { i += 1; return .object(fields) }
            while true {
                skipSpace()
                guard i < scalars.count, scalars[i] == "\"" else { throw ParseError() }
                let key = try string()
                skipSpace()
                guard i < scalars.count, scalars[i] == ":" else { throw ParseError() }
                i += 1
                skipSpace()
                let v = try value()
                if let at = fields.firstIndex(where: { $0.key == key }) {
                    fields[at].value = v
                } else {
                    fields.append((key, v))
                }
                skipSpace()
                guard i < scalars.count else { throw ParseError() }
                if scalars[i] == "," { i += 1; continue }
                if scalars[i] == "}" { i += 1; return .object(fields) }
                throw ParseError()
            }
        }

        mutating func array() throws(ParseError) -> JSONValue {
            i += 1
            var items: [JSONValue] = []
            skipSpace()
            if i < scalars.count, scalars[i] == "]" { i += 1; return .array(items) }
            while true {
                skipSpace()
                items.append(try value())
                skipSpace()
                guard i < scalars.count else { throw ParseError() }
                if scalars[i] == "," { i += 1; continue }
                if scalars[i] == "]" { i += 1; return .array(items) }
                throw ParseError()
            }
        }

        mutating func hex4() throws(ParseError) -> UInt32 {
            guard i + 4 <= scalars.count else { throw ParseError() }
            var v: UInt32 = 0
            for _ in 0..<4 {
                guard let d = hexDigit(scalars[i]) else { throw ParseError() }
                v = v * 16 + d
                i += 1
            }
            return v
        }

        func hexDigit(_ u: Unicode.Scalar) -> UInt32? {
            switch u.value {
            case 0x30...0x39: u.value - 0x30
            case 0x41...0x46: u.value - 0x41 + 10
            case 0x61...0x66: u.value - 0x61 + 10
            default: nil
            }
        }

        mutating func string() throws(ParseError) -> String {
            i += 1
            var out = String.UnicodeScalarView()
            while true {
                guard i < scalars.count else { throw ParseError() }
                let u = scalars[i]
                i += 1
                if u == "\"" { return String(out) }
                if u.value < 0x20 { throw ParseError() }
                guard u == "\\" else { out.append(u); continue }
                guard i < scalars.count else { throw ParseError() }
                let e = scalars[i]
                i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "u":
                    var code = try hex4()
                    if (0xD800...0xDBFF).contains(code), i + 1 < scalars.count, scalars[i] == "\\", scalars[i + 1] == "u" {
                        let save = i
                        i += 2
                        let low = try hex4()
                        if (0xDC00...0xDFFF).contains(low) {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            i = save
                        }
                    }
                    out.append(Unicode.Scalar(code) ?? "\u{FFFD}")
                default: throw ParseError()
                }
            }
        }

        mutating func number() throws(ParseError) -> JSONValue {
            let start = i
            var isInt = true
            if i < scalars.count, scalars[i] == "-" { i += 1 }
            guard i < scalars.count, isDigit(scalars[i]) else { throw ParseError() }
            if scalars[i] == "0" { i += 1 } else { while i < scalars.count, isDigit(scalars[i]) { i += 1 } }
            if i < scalars.count, scalars[i] == "." {
                isInt = false
                i += 1
                guard i < scalars.count, isDigit(scalars[i]) else { throw ParseError() }
                while i < scalars.count, isDigit(scalars[i]) { i += 1 }
            }
            if i < scalars.count, scalars[i] == "e" || scalars[i] == "E" {
                isInt = false
                i += 1
                if i < scalars.count, scalars[i] == "+" || scalars[i] == "-" { i += 1 }
                guard i < scalars.count, isDigit(scalars[i]) else { throw ParseError() }
                while i < scalars.count, isDigit(scalars[i]) { i += 1 }
            }
            var text = String.UnicodeScalarView()
            text.append(contentsOf: scalars[start..<i])
            let s = String(text)
            if isInt, let n = Int(s) { return .int(n) }
            guard let d = Double(s) else { throw ParseError() }
            return .double(d)
        }

        func isDigit(_ u: Unicode.Scalar) -> Bool { (0x30...0x39).contains(u.value) }
    }
}
