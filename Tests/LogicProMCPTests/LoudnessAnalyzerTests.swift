import Foundation
import Testing
@testable import LogicProMCPLib

@Suite("Loudness Analyzer")
struct LoudnessAnalyzerTests {

    // MARK: - LUFS

    @Test func lufsWithSilenceReturnsFloor() {
        let sampleRate = 48000.0
        let sampleCount = Int(sampleRate) // 1 second of silence
        let silence = [Float](repeating: 0.0, count: sampleCount)

        let lufs = LoudnessAnalyzer.calculateLUFS(silence, sampleRate: sampleRate)
        #expect(lufs == -120.0, "Silence should return -120 LUFS, got \(lufs)")
    }

    @Test func lufsWithTooFewSamplesReturnsFloor() {
        // Less than one 400ms block at 48kHz = 19200 samples
        let shortBuffer = [Float](repeating: 0.5, count: 100)
        let lufs = LoudnessAnalyzer.calculateLUFS(shortBuffer, sampleRate: 48000.0)
        #expect(lufs == -120.0, "Too few samples should return -120 LUFS")
    }

    @Test func lufsWithKnownSineWave() {
        // Generate a 1kHz sine wave at full scale (amplitude 1.0) for 1 second
        let sampleRate = 48000.0
        let frequency = 1000.0
        let sampleCount = Int(sampleRate)
        var samples = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            samples[i] = Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
        }

        let lufs = LoudnessAnalyzer.calculateLUFS(samples, sampleRate: sampleRate)

        // A full-scale sine wave has RMS = 1/sqrt(2) => mean_square = 0.5
        // LUFS = -0.691 + 10*log10(0.5) = -0.691 + (-3.010) = -3.701
        // Allow ±1 LU tolerance (simplified K-weighting)
        #expect(lufs > -5.0, "Full-scale sine LUFS should be around -3.7, got \(lufs)")
        #expect(lufs < -2.0, "Full-scale sine LUFS should be around -3.7, got \(lufs)")
    }

    @Test func lufsWithQuietSignalIsLowerThanLoud() {
        let sampleRate = 48000.0
        let sampleCount = Int(sampleRate)

        var loud = [Float](repeating: 0, count: sampleCount)
        var quiet = [Float](repeating: 0, count: sampleCount)

        for i in 0..<sampleCount {
            let phase = Float(2.0 * .pi * 1000.0 * Double(i) / sampleRate)
            loud[i] = sin(phase)
            quiet[i] = 0.1 * sin(phase) // -20 dB quieter
        }

        let lufsLoud = LoudnessAnalyzer.calculateLUFS(loud, sampleRate: sampleRate)
        let lufsQuiet = LoudnessAnalyzer.calculateLUFS(quiet, sampleRate: sampleRate)

        #expect(lufsLoud > lufsQuiet, "Louder signal should have higher LUFS")
    }

    // MARK: - True Peak

    @Test func truePeakWithFlatSignal() {
        // DC signal at 0.5 — true peak should equal sample peak
        let flat = [Float](repeating: 0.5, count: 1000)
        let truePeak = LoudnessAnalyzer.calculateTruePeak(flat)
        #expect(truePeak >= 0.5 - 0.001, "True peak of DC signal should be ~0.5, got \(truePeak)")
        #expect(truePeak <= 0.5 + 0.001, "True peak of DC signal should be ~0.5, got \(truePeak)")
    }

    @Test func truePeakWithEmptyInput() {
        // calculatePeak uses vDSP_maxv which returns -inf for empty input,
        // and calculateTruePeak delegates to calculatePeak for count <= 1.
        let truePeak = LoudnessAnalyzer.calculateTruePeak([])
        #expect(truePeak.isInfinite, "Empty input peak is -inf from vDSP_maxv")
        #expect(truePeak < 0, "Empty input peak should be negative infinity")
    }

    @Test func truePeakWithSingleSample() {
        let truePeak = LoudnessAnalyzer.calculateTruePeak([0.75])
        #expect(truePeak == 0.75, "Single sample peak should be its absolute value")
    }

    @Test func truePeakGteqSamplePeak() {
        // Generate a sine wave — inter-sample peaks can exceed sample peaks
        let sampleRate = 48000.0
        let sampleCount = 4800 // 100ms
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = Float(sin(2.0 * .pi * 1000.0 * Double(i) / sampleRate))
        }

        let truePeak = LoudnessAnalyzer.calculateTruePeak(samples)

        // Calculate sample peak manually
        var samplePeak: Float = 0
        for sample in samples {
            let absSample = abs(sample)
            if absSample > samplePeak {
                samplePeak = absSample
            }
        }

        #expect(
            truePeak >= samplePeak,
            "True peak (\(truePeak)) should be >= sample peak (\(samplePeak))"
        )
    }

    @Test func truePeakDetectsInterSamplePeak() {
        // Construct a case where inter-sample peak exceeds sample values.
        // Two adjacent samples that bracket a peak: sin at phases just before
        // and after the peak will have sample values < 1.0, but interpolation
        // should find a value closer to 1.0.
        let sampleRate = 44100.0
        // Frequency chosen so peak falls between samples
        let frequency = 997.0
        let sampleCount = Int(sampleRate / frequency) * 2 // ~2 cycles
        var samples = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
        }

        let truePeak = LoudnessAnalyzer.calculateTruePeak(samples)
        // True peak should be very close to 1.0 (full scale sine)
        #expect(truePeak > 0.99, "Inter-sample peak of full-scale sine should be near 1.0, got \(truePeak)")
    }

    @Test func truePeakWithNegativeValues() {
        // Signal with negative peak larger than positive peak
        let samples: [Float] = [0.0, 0.3, 0.1, -0.8, -0.2, 0.0]
        let truePeak = LoudnessAnalyzer.calculateTruePeak(samples)
        #expect(truePeak >= 0.8, "True peak should capture negative excursion, got \(truePeak)")
    }
}
