import Foundation
import TunesContract

/// A colour as sRGB components in 0…1.
public struct RGB: Sendable, Equatable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(1, max(0, r))
        self.g = min(1, max(0, g))
        self.b = min(1, max(0, b))
    }

    /// `#RRGGBB`, case ignored; nil for anything else.
    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard s.count == 6, s.allSatisfy(\.isHexDigit), let v = UInt32(s, radix: 16) else { return nil }
        self.init(Double(v >> 16 & 0xFF) / 255, Double(v >> 8 & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// `#RRGGBB`, upper case.
    public var hex: String {
        func byte(_ c: Double) -> Int { Int((c * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// Relative luminance as WCAG 2 defines it.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// The WCAG 2 contrast ratio between two colours, 1…21.
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (x, y) = (a.luminance, b.luminance)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func scaled(_ k: Double) -> RGB { RGB(r * k, g * k, b * k) }
    func mixed(with o: RGB, _ t: Double) -> RGB { RGB(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t) }

    static func hsl(_ hue: Double, _ s: Double, _ l: Double) -> RGB {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return RGB(channel(h + 1.0 / 3), channel(h), channel(h - 1.0 / 3))
    }
}

/// A genre's four colours: the first is the field's base, the other three
/// its lights.
public struct Palette: Sendable, Equatable, Hashable {
    public var colors: [RGB]

    public init(colors: [RGB]) { self.colors = colors }

    /// Text on the dark field.
    public static let darkText = RGB(1, 1, 1)
    /// Text on the light field.
    public static let lightText = RGB(20.0 / 255, 20.0 / 255, 28.0 / 255)

    /// The colours `hex` gives when they are four `#RRGGBB` colours, else
    /// four made from `name`.
    public static func of(name: String, hex: [String]?) -> Palette {
        if let hex, hex.count == 4 {
            let colors = hex.compactMap(RGB.init(hex:))
            if colors.count == 4 { return Palette(colors: colors) }
        }
        return made(from: name)
    }

    /// Four colours from a name, the same name always giving the same four.
    public static func made(from name: String) -> Palette {
        let h = Seed.of(name)
        let hue = Double(h % 360)
        let turn = Double((h >> 9) % 120) + 120
        return Palette(colors: [
            .hsl(hue, 0.45, 0.10),
            .hsl(hue + 20, 0.65, 0.45),
            .hsl(hue - 50, 0.55, 0.38),
            .hsl(hue + turn, 0.55, 0.36),
        ])
    }

    /// The colours the backdrop draws: darkened in dark appearance until
    /// white text reads on each, made paler in light appearance until
    /// near-black text does. Contrast is at least 4.5:1 against every one.
    public func field(dark: Bool) -> [RGB] {
        colors.map { dark ? Self.darkened($0) : Self.lightened($0) }
    }

    /// Below this luminance white has 5:1 or better.
    static let darkCeiling = 0.16
    /// Above this luminance near-black has 5:1 or better.
    static let lightFloor = 0.30

    static func darkened(_ c: RGB) -> RGB {
        guard c.luminance > darkCeiling else { return c }
        var lo = 0.0, hi = 1.0
        for _ in 0..<30 {
            let k = (lo + hi) / 2
            if c.scaled(k).luminance > darkCeiling { hi = k } else { lo = k }
        }
        return c.scaled(lo)
    }

    static func lightened(_ c: RGB) -> RGB {
        // The light field is a pale wash of the colour, never the colour itself.
        let wash = c.mixed(with: RGB(1, 1, 1), 0.62)
        guard wash.luminance < lightFloor else { return wash }
        var lo = 0.62, hi = 1.0
        for _ in 0..<30 {
            let t = (lo + hi) / 2
            if c.mixed(with: RGB(1, 1, 1), t).luminance < lightFloor { lo = t } else { hi = t }
        }
        return c.mixed(with: RGB(1, 1, 1), hi)
    }
}

/// A stable 64-bit hash (FNV-1a over UTF-8), so the same text always gives
/// the same colours and pictures on every run and every Mac.
enum Seed {
    static func of(_ text: String) -> UInt64 {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01B3
        }
        return h
    }

    /// A number in 0…1 from a seed and a salt.
    static func unit(_ seed: UInt64, _ salt: UInt64) -> Double {
        var x = seed ^ (salt &* 0x9E37_79B9_7F4A_7C15)
        x ^= x >> 33
        x = x &* 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33
        x = x &* 0xC4CE_B9FE_1A85_EC53
        x ^= x >> 33
        return Double(x >> 11) / Double(1 << 53)
    }
}

/// A tune's picture: a 3 × 3 mesh of the palette's colours and a small
/// mirrored dot wave, both from the tune's name, tempo and key. Nothing is
/// stored; the same tune always gives the same picture.
public struct Artwork: Sendable, Equatable {
    /// Row by row, 9 points in 0…1, corners fixed.
    public var points: [SIMD2<Double>]
    /// One per point: which of the palette's four colours it takes.
    public var indices: [Int]
    /// The dot wave's columns, each in 0…1.
    public var levels: [Double]

    public static let columns = 26

    /// The points' colours from the field drawn (`Palette.field(dark:)`).
    public func colors(_ field: [RGB]) -> [RGB] {
        indices.map { field.isEmpty ? RGB(0, 0, 0) : field[$0 % field.count] }
    }

    public static func recipe(name: String, bpm: Int?, key: String?, palette: Palette) -> Artwork {
        let seed = Seed.of("\(name)|\(bpm.map(String.init) ?? "")|\(key ?? "")")
        var points: [SIMD2<Double>] = []
        for row in 0..<3 {
            for col in 0..<3 {
                var x = Double(col) / 2
                var y = Double(row) / 2
                let i = UInt64(row * 3 + col)
                if col == 1 { x = 0.3 + 0.4 * Seed.unit(seed, i * 2) }
                if row == 1 { y = 0.3 + 0.4 * Seed.unit(seed, i * 2 + 1) }
                points.append(SIMD2(x, y))
            }
        }
        let count = max(1, palette.colors.count)
        let indices = (0..<9).map { i -> Int in
            // The corners lean to the base colour so the edges stay dark.
            let corner = [0, 2, 6, 8].contains(i)
            if corner && Seed.unit(seed, 100 + UInt64(i)) < 0.6 { return 0 }
            return Int(Seed.unit(seed, 200 + UInt64(i)) * Double(count)) % count
        }
        let tempo = Double(bpm ?? 100) / 100
        let levels = (0..<columns).map { i -> Double in
            let x = Double(i)
            let a = abs(sin(x * 0.7 * tempo + Seed.unit(seed, 300) * 6.28))
            let b = abs(cos(x * 0.23 * (1 + Seed.unit(seed, 301)) + 1))
            return min(1, 0.25 + 0.75 * a * b)
        }
        return Artwork(points: points, indices: indices, levels: levels)
    }
}

/// The forming wave: dots moving like a level meter while a tune is made.
/// Its height says the stage and nothing else; it never grows with time.
public enum Forming {
    /// Column `i` of `n` at time `t` seconds, in 0.06…1: low and loose while
    /// writing, taller while rendering.
    public static func level(column i: Int, of n: Int, at t: Double, stage: JobStage) -> Double {
        let x = (Double(i) + 0.5) / Double(max(1, n))
        let own = abs(sin(Double(i) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
        let amp = stage == .rendering ? 0.62 : 0.3
        let a = sin(2 * .pi * (x * 1.6 - t * 0.42))
        let b = sin(2 * .pi * (x * 3.1 - t * 0.27 + own))
        return min(1, max(0.06, amp * (0.55 + 0.3 * a + 0.15 * b) + 0.08 * own))
    }
}
