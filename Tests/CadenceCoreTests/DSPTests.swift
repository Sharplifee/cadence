import XCTest
@testable import CadenceCore

final class DSPTests: XCTestCase {
    let sr: Float = 16_000

    private func sine(_ hz: Float, seconds: Float = 0.5, amp: Float = 0.5) -> [Float] {
        let n = Int(sr * seconds)
        return (0..<n).map { amp * sin(2 * .pi * hz * Float($0) / sr) }
    }

    func testRMSOfKnownAmplitude() {
        // A 0.5-amplitude sine has RMS 0.3536 -> -9.03 dBFS.
        XCTAssertEqual(DSP.rmsDBFS(sine(200)), -9.03, accuracy: 0.2)
    }

    func testSilenceFloors() {
        XCTAssertEqual(DSP.rmsDBFS([Float](repeating: 0, count: 8000)), -120, accuracy: 0.001)
    }

    func testPitchTracksFundamental() {
        for hz in [85, 120, 175, 240] as [Float] {
            let f0 = DSP.fundamental(sine(hz, seconds: 0.05), sampleRate: sr)
            XCTAssertEqual(f0, hz, accuracy: hz * 0.05, "f0 wrong for \(hz) Hz")
        }
    }

    func testPitchRejectsNoiseAsUnvoiced() {
        let noise = (0..<800).map { _ in Float.random(in: -0.3...0.3) }
        XCTAssertEqual(DSP.fundamental(noise, sampleRate: sr), 0)
    }

    func testPitchPrefersFundamentalOverHarmonic() {
        // 120 Hz plus a strong 240 Hz harmonic must still report 120.
        let n = Int(sr * 0.05)
        let x = (0..<n).map { i -> Float in
            let t = Float(i) / sr
            return 0.5 * sin(2 * .pi * 120 * t) + 0.4 * sin(2 * .pi * 240 * t)
        }
        XCTAssertEqual(DSP.fundamental(x, sampleRate: sr), 120, accuracy: 8)
    }

    func testSpectralCentroidRisesWithFrequency() {
        let low = DSP.spectralCentroid(sine(300, seconds: 0.064), sampleRate: sr)
        let high = DSP.spectralCentroid(sine(2000, seconds: 0.064), sampleRate: sr)
        XCTAssertLessThan(low, high)
        XCTAssertEqual(low, 300, accuracy: 120)
        XCTAssertEqual(high, 2000, accuracy: 250)
    }

    func testSyllableRateCountsEnvelopePeaks() {
        // 4 amplitude bursts per second -> ~4 syllables/sec.
        let n = Int(sr)
        let x = (0..<n).map { i -> Float in
            let t = Float(i) / sr
            let env: Float = sin(2 * .pi * 4 * t) > 0 ? 1 : 0.02
            return env * sin(2 * .pi * 150 * t)
        }
        XCTAssertEqual(DSP.syllableRate(x, sampleRate: sr), 4, accuracy: 1.2)
    }

    func testSemitones() {
        XCTAssertEqual(DSP.semitones(220, 110), 12, accuracy: 0.001)
        XCTAssertEqual(DSP.semitones(0, 110), 0)
    }

    func testZeroCrossingRateOfSineMatchesTheory() {
        // A 200 Hz sine crosses zero 400 times per second at 16 kHz -> 0.025.
        XCTAssertEqual(DSP.zeroCrossingRate(sine(200)), 0.025, accuracy: 0.002)
    }
}
