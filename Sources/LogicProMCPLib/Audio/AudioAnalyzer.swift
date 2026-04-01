import Accelerate
import AVFoundation
import Foundation

// MARK: - Analysis Result

/// Complete audio analysis result for a file.
public struct AudioAnalysisResult: Codable, Sendable {
    public let filePath: String
    public let duration: Double
    public let sampleRate: Double
    public let channelCount: Int
    public let rms: Double            // Root mean square level in dB
    public let peak: Double           // Peak level in dB
    public let spectralCentroid: Double  // In Hz
    public let frequencyBins: [FrequencyBin]  // Top frequency peaks
}

/// A single frequency peak with magnitude.
public struct FrequencyBin: Codable, Sendable {
    public let frequency: Double  // Hz
    public let magnitude: Double  // dB
}

// MARK: - Errors

public enum AudioAnalysisError: Error, LocalizedError, Sendable {
    case fileNotFound(String)
    case invalidPath(String)
    case readFailed(String)
    case emptyBuffer
    case fftSetupFailed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidPath(let reason):
            return "Invalid audio path: \(reason)"
        case .readFailed(let reason):
            return "Failed to read audio: \(reason)"
        case .emptyBuffer:
            return "Audio buffer is empty"
        case .fftSetupFailed:
            return "Failed to create FFT setup"
        }
    }
}

// MARK: - Audio Analyzer

/// Performs audio analysis using AVFoundation for reading and
/// Accelerate/vDSP for signal processing (RMS, peak, FFT, spectral centroid).
public struct AudioAnalyzer: Sendable {

    /// Analyze an audio file and return level, spectral, and metadata info.
    public static func analyze(fileAt path: String) async throws -> AudioAnalysisResult {
        // Validate path: no traversal, must be absolute
        guard !path.contains("..") else {
            throw AudioAnalysisError.invalidPath("Directory traversal not allowed")
        }
        guard path.hasPrefix("/") else {
            throw AudioAnalysisError.invalidPath("Path must be absolute")
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw AudioAnalysisError.fileNotFound(path)
        }

        // Open the audio file
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw AudioAnalysisError.readFailed(error.localizedDescription)
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let frameCount = AVAudioFrameCount(audioFile.length)
        let duration = Double(frameCount) / sampleRate

        guard frameCount > 0 else {
            throw AudioAnalysisError.emptyBuffer
        }

        // Read into a PCM buffer
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw AudioAnalysisError.readFailed("Could not allocate PCM buffer")
        }

        do {
            try audioFile.read(into: buffer)
        } catch {
            throw AudioAnalysisError.readFailed(error.localizedDescription)
        }

        guard let floatData = buffer.floatChannelData else {
            throw AudioAnalysisError.readFailed("No float channel data available")
        }

        let count = Int(buffer.frameLength)
        guard count > 0 else {
            throw AudioAnalysisError.emptyBuffer
        }

        // Use channel 0 (mono or left channel) for analysis
        let samples = UnsafeBufferPointer(start: floatData[0], count: count)
        let samplesArray = Array(samples)

        // Calculate RMS
        let rmsLinear = calculateRMS(samplesArray)
        let rmsDB = linearToDecibels(rmsLinear)

        // Calculate Peak
        let peakLinear = calculatePeak(samplesArray)
        let peakDB = linearToDecibels(peakLinear)

        // Perform FFT and spectral analysis
        let (frequencyBins, spectralCentroid) = performSpectralAnalysis(
            samplesArray,
            sampleRate: sampleRate
        )

        return AudioAnalysisResult(
            filePath: path,
            duration: duration,
            sampleRate: sampleRate,
            channelCount: channelCount,
            rms: rmsDB,
            peak: peakDB,
            spectralCentroid: spectralCentroid,
            frequencyBins: frequencyBins
        )
    }

    // MARK: - RMS

    private static func calculateRMS(_ samples: [Float]) -> Float {
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    // MARK: - Peak

    private static func calculatePeak(_ samples: [Float]) -> Float {
        var result: Float = 0
        // Get absolute maximum (handles negative peaks)
        var absBuffer = [Float](repeating: 0, count: samples.count)
        vDSP_vabs(samples, 1, &absBuffer, 1, vDSP_Length(samples.count))
        vDSP_maxv(absBuffer, 1, &result, vDSP_Length(samples.count))
        return result
    }

    // MARK: - Spectral Analysis

    private static func performSpectralAnalysis(
        _ samples: [Float],
        sampleRate: Double
    ) -> ([FrequencyBin], Double) {
        // Choose FFT size: power of 2, up to 8192
        let maxFFTSize = 8192
        let fftSize = min(maxFFTSize, nearestPowerOfTwo(samples.count))

        guard fftSize >= 64 else {
            return ([], 0)
        }

        let log2n = vDSP_Length(log2(Double(fftSize)))

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return ([], 0)
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Prepare input: take first fftSize samples, apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        let copyCount = min(samples.count, fftSize)
        for i in 0..<copyCount {
            windowed[i] = samples[i]
        }
        vDSP_vmul(windowed, 1, window, 1, &windowed, 1, vDSP_Length(fftSize))

        // Pack into split complex format for real FFT
        let halfN = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        // Interleave even/odd samples into real/imag
        windowed.withUnsafeBufferPointer { inputPtr in
            realPart.withUnsafeMutableBufferPointer { realPtr in
                imagPart.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: realPtr.baseAddress!,
                        imagp: imagPtr.baseAddress!
                    )
                    inputPtr.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: halfN
                    ) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }
            }
        }

        // Perform forward FFT
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // Calculate magnitudes (in linear scale)
        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeBufferPointer { realPtr in
            imagPart.withUnsafeBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realPtr.baseAddress!),
                    imagp: UnsafeMutablePointer(mutating: imagPtr.baseAddress!)
                )
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Normalize magnitudes
        var scale = Float(2.0 / Float(fftSize))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

        // Frequency resolution
        let freqResolution = sampleRate / Double(fftSize)

        // Build frequency bins with dB magnitudes
        var allBins: [(frequency: Double, magnitudeLinear: Float, magnitudeDB: Double)] = []
        for i in 1..<halfN {  // Skip DC component (index 0)
            let freq = Double(i) * freqResolution
            let mag = magnitudes[i]
            let magDB = Double(linearToDecibels(mag))
            allBins.append((freq, mag, magDB))
        }

        // Sort by magnitude descending, take top 20
        allBins.sort { $0.magnitudeLinear > $1.magnitudeLinear }
        let topBins = allBins.prefix(20).map { bin in
            FrequencyBin(frequency: bin.frequency, magnitude: bin.magnitudeDB)
        }

        // Calculate spectral centroid: sum(freq * mag) / sum(mag)
        var weightedSum: Double = 0
        var magSum: Double = 0
        for bin in allBins {
            let linearMag = Double(bin.magnitudeLinear)
            weightedSum += bin.frequency * linearMag
            magSum += linearMag
        }
        let centroid = magSum > 0 ? weightedSum / magSum : 0

        return (Array(topBins), centroid)
    }

    // MARK: - Utilities

    private static func linearToDecibels(_ linear: Float) -> Double {
        guard linear > 0 else { return -120.0 }  // Floor at -120 dB
        return Double(20.0 * log10(linear))
    }

    private static func nearestPowerOfTwo(_ n: Int) -> Int {
        var v = n
        v -= 1
        v |= v >> 1
        v |= v >> 2
        v |= v >> 4
        v |= v >> 8
        v |= v >> 16
        v += 1
        return max(64, v)
    }
}
