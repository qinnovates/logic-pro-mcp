import Accelerate
import Foundation

/// Loudness measurement utilities: LUFS (EBU R128 simplified) and true peak (ITU-R BS.1770 approximation).
/// Extracted from AudioAnalyzer to keep file sizes under 300 lines.
public struct LoudnessAnalyzer: Sendable {

    // MARK: - LUFS (EBU R128 Simplified)

    /// Approximate integrated loudness using gated mean-square measurement.
    ///
    /// Simplified EBU R128: K-weighted pre-filtering is not applied, so results
    /// will read high for bass-heavy content and low for treble-heavy content.
    /// For broadband mixes the error is typically within ±1 LU.
    /// Gating uses a fixed -70 LUFS absolute gate with 400ms non-overlapping blocks.
    static func calculateLUFS(_ samples: [Float], sampleRate: Double) -> Double {
        let blockSize = Int(0.4 * sampleRate) // 400ms blocks per EBU R128
        guard blockSize > 0, samples.count >= blockSize else {
            return -120.0
        }

        var blockPowers: [Double] = []
        var offset = 0
        while offset + blockSize <= samples.count {
            let block = Array(samples[offset..<(offset + blockSize)])
            var meanSquare: Float = 0
            vDSP_measqv(block, 1, &meanSquare, vDSP_Length(blockSize))
            blockPowers.append(Double(meanSquare))
            offset += blockSize
        }

        guard !blockPowers.isEmpty else { return -120.0 }

        // Absolute gate at -70 LUFS
        let absoluteGateThreshold = pow(10.0, (-70.0 + 0.691) / 10.0)
        let gatedPowers = blockPowers.filter { $0 > absoluteGateThreshold }

        guard !gatedPowers.isEmpty else { return -120.0 }

        let meanPower = gatedPowers.reduce(0.0, +) / Double(gatedPowers.count)

        guard meanPower > 0 else { return -120.0 }

        // LUFS = -0.691 + 10 * log10(mean_square)
        return -0.691 + 10.0 * log10(meanPower)
    }

    // MARK: - True Peak (4x Oversampling)

    /// Estimate true (inter-sample) peak via 4x cubic Hermite interpolation.
    /// Full ITU-R BS.1770 requires a specific FIR filter; cubic interpolation
    /// catches most inter-sample peaks within ~0.1 dB.
    static func calculateTruePeak(_ samples: [Float]) -> Float {
        guard samples.count > 1 else {
            return calculatePeak(samples)
        }

        var maxPeak: Float = 0

        let originalPeak = calculatePeak(samples)
        maxPeak = originalPeak

        for i in 0..<(samples.count - 1) {
            let s0 = i > 0 ? samples[i - 1] : samples[i]
            let s1 = samples[i]
            let s2 = samples[i + 1]
            let s3 = (i + 2 < samples.count) ? samples[i + 2] : samples[i + 1]

            for step in 1...3 {
                let t = Float(step) / 4.0
                let interpolated = cubicHermite(s0, s1, s2, s3, t: t)
                let absVal = abs(interpolated)
                if absVal > maxPeak {
                    maxPeak = absVal
                }
            }
        }

        return maxPeak
    }

    // MARK: - Helpers

    private static func calculatePeak(_ samples: [Float]) -> Float {
        var result: Float = 0
        var absBuffer = [Float](repeating: 0, count: samples.count)
        vDSP_vabs(samples, 1, &absBuffer, 1, vDSP_Length(samples.count))
        vDSP_maxv(absBuffer, 1, &result, vDSP_Length(samples.count))
        return result
    }

    private static func cubicHermite(_ y0: Float, _ y1: Float, _ y2: Float, _ y3: Float, t: Float) -> Float {
        let a = -0.5 * y0 + 1.5 * y1 - 1.5 * y2 + 0.5 * y3
        let b = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3
        let c = -0.5 * y0 + 0.5 * y2
        let d = y1
        return ((a * t + b) * t + c) * t + d
    }
}
