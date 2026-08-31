import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Every number the engine reasons about is produced here.
///
/// Each function has an Accelerate fast path for the device and a portable
/// Swift path that is numerically identical. That is not redundancy — it is
/// what makes this file testable off a Mac.
public enum DSP {

    public static func rmsDBFS(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return -120 }
        var meanSquare: Float = 0
        #if canImport(Accelerate)
        vDSP_measqv(x, 1, &meanSquare, vDSP_Length(x.count))
        #else
        meanSquare = x.reduce(0) { $0 + $1 * $1 } / Float(x.count)
        #endif
        let rms = sqrt(meanSquare)
        return rms > 1e-7 ? 20 * log10(rms) : -120
    }

    public static func zeroCrossingRate(_ x: [Float]) -> Float {
        guard x.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<x.count where (x[i] >= 0) != (x[i - 1] >= 0) { crossings += 1 }
        return Float(crossings) / Float(x.count - 1)
    }

    /// Autocorrelation pitch over 60–400 Hz. Returns 0 when unvoiced.
    ///
    /// Normalising each lag by the energy of the overlapping segment matters:
    /// raw autocorrelation decays with lag and biases the answer high, which
    /// on speech means reporting a harmonic instead of the fundamental.
    public static func fundamental(_ x: [Float], sampleRate: Float) -> Float {
        let minLag = max(1, Int(sampleRate / 400))
        let maxLag = min(Int(sampleRate / 60), x.count - 1)
        guard maxLag > minLag else { return 0 }

        var mean: Float = 0
        for v in x { mean += v }
        mean /= Float(x.count)
        let c = x.map { $0 - mean }

        var energy: Float = 0
        for v in c { energy += v * v }
        guard energy > 1e-6 else { return 0 }

        var bestLag = 0
        var bestScore: Float = 0
        for lag in minLag...maxLag {
            var sum: Float = 0, lagEnergy: Float = 0
            for i in 0..<(c.count - lag) {
                sum += c[i] * c[i + lag]
                lagEnergy += c[i + lag] * c[i + lag]
            }
            let denom = sqrt(energy * max(lagEnergy, 1e-9))
            guard denom > 1e-9 else { continue }
            let score = sum / denom
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestLag > 0, bestScore > 0.30 else { return 0 }
        return sampleRate / Float(bestLag)
    }

    /// Spectral centroid — a cheap timbre handle. The same voice at 30 cm sits
    /// lower than at 1.5 m, which is what the near-field speaker gate leans on.
    public static func spectralCentroid(_ x: [Float], sampleRate: Float) -> Float {
        var n = 1
        while n * 2 <= x.count { n *= 2 }
        guard n >= 64 else { return 0 }
        // Hann window first. Without it, spectral leakage from a rectangular
        // window smears energy across every bin and drags the centroid far
        // above the true frequency — measured at 1081 Hz for a 300 Hz tone.
        var frame = Array(x[0..<n])
        for i in 0..<n {
            frame[i] *= 0.5 * (1 - cos(2 * Float.pi * Float(i) / Float(n - 1)))
        }
        let mag = magnitudeSpectrum(frame)

        var weighted: Float = 0, total: Float = 0
        let binHz = sampleRate / Float(n)
        for i in 0..<mag.count {
            weighted += mag[i] * Float(i) * binHz
            total += mag[i]
        }
        return total > 1e-6 ? weighted / total : 0
    }

    /// Radix-2 magnitude spectrum, first half. Portable by design.
    static func magnitudeSpectrum(_ x: [Float]) -> [Float] {
        let n = x.count
        var real = x
        var imag = [Float](repeating: 0, count: n)

        // Bit-reversal permutation.
        var j = 0
        for i in 0..<n - 1 {
            if i < j { real.swapAt(i, j); imag.swapAt(i, j) }
            var k = n >> 1
            while k <= j { j -= k; k >>= 1 }
            j += k
        }

        var span = 2
        while span <= n {
            let half = span / 2
            let angle = -2 * Float.pi / Float(span)
            for start in stride(from: 0, to: n, by: span) {
                for k in 0..<half {
                    let theta = angle * Float(k)
                    let wr = cos(theta), wi = sin(theta)
                    let i0 = start + k, i1 = i0 + half
                    let tr = wr * real[i1] - wi * imag[i1]
                    let ti = wr * imag[i1] + wi * real[i1]
                    real[i1] = real[i0] - tr; imag[i1] = imag[i0] - ti
                    real[i0] += tr;          imag[i0] += ti
                }
            }
            span <<= 1
        }

        let half = n / 2
        var mag = [Float](repeating: 0, count: half)
        for i in 0..<half { mag[i] = sqrt(real[i] * real[i] + imag[i] * imag[i]) }
        return mag
    }

    /// Syllable rate from the amplitude envelope: rectify, smooth to ~20 ms,
    /// count peaks above an adaptive floor. Crude, cheap, and it tracks pace
    /// without ever running speech recognition or touching the network.
    public static func syllableRate(_ x: [Float], sampleRate: Float) -> Float {
        guard x.count > 32, sampleRate > 0 else { return 0 }
        let window = max(4, Int(sampleRate * 0.02))
        var smooth = [Float](repeating: 0, count: x.count)
        var acc: Float = 0
        for i in 0..<x.count {
            acc += abs(x[i])
            if i >= window { acc -= abs(x[i - window]) }
            smooth[i] = acc / Float(min(i + 1, window))
        }

        var mean: Float = 0
        for v in smooth { mean += v }
        mean /= Float(smooth.count)
        let threshold = mean * 1.35
        guard threshold > 1e-5 else { return 0 }

        var peaks = 0
        var armed = true
        for v in smooth {
            if armed && v > threshold { peaks += 1; armed = false }
            else if !armed && v < threshold * 0.7 { armed = true }
        }
        return Float(peaks) / (Float(x.count) / sampleRate)
    }

    public static func semitones(_ a: Float, _ b: Float) -> Float {
        guard a > 0, b > 0 else { return 0 }
        return 12 * log2(a / b)
    }
}
