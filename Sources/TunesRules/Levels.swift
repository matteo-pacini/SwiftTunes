import Foundation

/// Loudness and waveform over mono samples in -1…1.
public enum Levels {
    /// RMS level in dBFS of each window; silence is -120.
    public static func db(_ samples: [Float], rate: Double = Rules.decodeRate, window: Double = Rules.levelWindow) -> [Double] {
        let n = max(1, Int(rate * window))
        var out: [Double] = []
        out.reserveCapacity(samples.count / n + 1)
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + n)
            var power = 0.0
            for j in i..<end { power += Double(samples[j]) * Double(samples[j]) }
            power /= Double(end - i)
            out.append(power <= 0 ? -120 : 10 * log10(power))
            i = end
        }
        return out
    }

    /// Seconds of the longest run of windows under `Rules.quietDB` that is
    /// followed by a louder window: a quiet tail does not count.
    public static func quietMidRun(_ levels: [Double], window: Double = Rules.levelWindow) -> Double {
        var worst = 0
        var run = 0
        for v in levels {
            if v < Rules.quietDB {
                run += 1
            } else {
                worst = max(worst, run)
                run = 0
            }
        }
        return Double(worst) * window
    }

    /// Mean absolute level of `bars` equal slices, scaled to the loudest and
    /// rounded to three places. Fewer samples than bars repeat samples.
    public static func wave(_ samples: [Float], bars: Int = Rules.waveBars) -> [Double] {
        guard !samples.isEmpty else { return Array(repeating: 0, count: bars) }
        let n = samples.count
        var out: [Double] = []
        for b in 0..<bars {
            var lo = b * n / bars
            var hi = (b + 1) * n / bars
            if lo >= hi {
                lo = min(n - 1, lo)
                hi = lo + 1
            }
            var sum = 0.0
            for j in lo..<hi { sum += Double(abs(samples[j])) }
            out.append(sum / Double(hi - lo))
        }
        let top = out.max() ?? 0
        return out.map { top > 0 ? ($0 / top * 1000).rounded() / 1000 : 0 }
    }
}
