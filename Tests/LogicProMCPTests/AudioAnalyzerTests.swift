import Foundation
import Testing
@testable import LogicProMCPLib

@Suite("Audio Analyzer")
struct AudioAnalyzerTests {

    // MARK: - Path Validation

    @Test func rejectsPathTraversal() async throws {
        await #expect(throws: AudioAnalysisError.self) {
            _ = try await AudioAnalyzer.analyze(fileAt: "/tmp/../etc/passwd")
        }
    }

    @Test func rejectsRelativePath() async throws {
        await #expect(throws: AudioAnalysisError.self) {
            _ = try await AudioAnalyzer.analyze(fileAt: "relative/path/file.wav")
        }
    }

    @Test func rejectsNonexistentFile() async throws {
        await #expect(throws: AudioAnalysisError.self) {
            _ = try await AudioAnalyzer.analyze(fileAt: "/tmp/nonexistent_audio_file_12345.wav")
        }
    }

    // MARK: - Real File Analysis

    @Test func analyzesWavFile() async throws {
        let testFilePath = "/Users/mac/Documents/PROJECTS/logic-pro-mcp/audio-import/kulhi-loach.wav"

        // Skip if test file is not available
        guard FileManager.default.fileExists(atPath: testFilePath) else {
            return
        }

        let result = try await AudioAnalyzer.analyze(fileAt: testFilePath)

        // Verify file path is preserved
        #expect(result.filePath == testFilePath)

        // Duration should be positive
        #expect(result.duration > 0, "Duration should be positive, got \(result.duration)")

        // Sample rate should be a standard audio sample rate
        #expect(result.sampleRate > 0, "Sample rate should be positive")
        let validSampleRates: [Double] = [8000, 11025, 16000, 22050, 44100, 48000, 88200, 96000]
        #expect(
            validSampleRates.contains(result.sampleRate),
            "Sample rate \(result.sampleRate) should be a standard rate"
        )

        // Channel count should be 1 (mono) or 2 (stereo)
        #expect(result.channelCount >= 1 && result.channelCount <= 2)

        // RMS should be a finite negative number (in dB, silence = -120)
        #expect(result.rms.isFinite, "RMS should be finite")
        #expect(result.rms > -120.0, "RMS should be above noise floor")
        #expect(result.rms <= 0.0, "RMS should be <= 0 dB")

        // Peak should be finite and >= RMS
        #expect(result.peak.isFinite, "Peak should be finite")
        #expect(result.peak >= result.rms, "Peak should be >= RMS")

        // Spectral centroid should be positive (in Hz)
        #expect(result.spectralCentroid > 0, "Spectral centroid should be positive")
        #expect(
            result.spectralCentroid < result.sampleRate / 2,
            "Spectral centroid should be below Nyquist"
        )

        // Should have frequency bins
        #expect(!result.frequencyBins.isEmpty, "Should have frequency bins")
        #expect(result.frequencyBins.count <= 20, "Should have at most 20 frequency bins")

        // All frequency bins should have positive frequencies
        for bin in result.frequencyBins {
            #expect(bin.frequency > 0, "Bin frequency should be positive")
            #expect(bin.magnitude.isFinite, "Bin magnitude should be finite")
        }
    }
}
