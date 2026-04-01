import Testing
@testable import LogicProMCPLib

@Suite("Input Sanitizer")
struct InputSanitizerTests {

    // MARK: - sanitizeName

    @Test func sanitizeNameValidNamePassesThrough() {
        let result = InputSanitizer.sanitizeName("Alchemy")
        #expect(result == "Alchemy")
    }

    @Test func sanitizeNameAlphanumericWithSpaces() {
        let result = InputSanitizer.sanitizeName("ES2 Synth Pad")
        #expect(result == "ES2 Synth Pad")
    }

    @Test func sanitizeNameNullByteRejected() {
        let result = InputSanitizer.sanitizeName("Evil\0Plugin")
        #expect(result == nil)
    }

    @Test func sanitizeNameEmptyStringRejected() {
        let result = InputSanitizer.sanitizeName("")
        #expect(result == nil)
    }

    @Test func sanitizeNameOverMaxLengthRejected() {
        let longName = String(repeating: "A", count: 257)
        let result = InputSanitizer.sanitizeName(longName)
        #expect(result == nil)
    }

    @Test func sanitizeNameExactlyMaxLengthAccepted() {
        let maxName = String(repeating: "A", count: 256)
        let result = InputSanitizer.sanitizeName(maxName)
        #expect(result != nil)
        #expect(result == maxName)
    }

    @Test func sanitizeNameEscapesDoubleQuotes() {
        let result = InputSanitizer.sanitizeName("My \"Plugin\"")
        #expect(result == "My \\\"Plugin\\\"")
    }

    @Test func sanitizeNameEscapesBackslashes() {
        let result = InputSanitizer.sanitizeName("Path\\To\\Plugin")
        #expect(result == "Path\\\\To\\\\Plugin")
    }

    @Test func sanitizeNameEscapesBothQuotesAndBackslashes() {
        let result = InputSanitizer.sanitizeName("A\\\"B")
        // Backslash escaped first, then quote: A\\"B -> A\\\\"B -> A\\\\"B
        // "\\" -> "\\\\" and "\"" -> "\\\""
        #expect(result == "A\\\\\\\"B")
    }

    // MARK: - sanitizePath

    @Test func sanitizePathValidAbsolutePathPasses() {
        let result = InputSanitizer.sanitizePath("/Users/mac/Music/song.wav")
        #expect(result != nil)
        #expect(result == "/Users/mac/Music/song.wav")
    }

    @Test func sanitizePathRelativePathRejected() {
        let result = InputSanitizer.sanitizePath("relative/path/file.wav")
        #expect(result == nil)
    }

    @Test func sanitizePathTraversalRejected() {
        let result = InputSanitizer.sanitizePath("/Users/mac/../etc/passwd")
        #expect(result == nil)
    }

    @Test func sanitizePathTraversalAtEndRejected() {
        let result = InputSanitizer.sanitizePath("/Users/mac/Music/..")
        #expect(result == nil)
    }

    @Test func sanitizePathNullByteRejected() {
        let result = InputSanitizer.sanitizePath("/Users/mac/\0evil")
        #expect(result == nil)
    }

    @Test func sanitizePathEmptyStringRejected() {
        let result = InputSanitizer.sanitizePath("")
        #expect(result == nil)
    }

    @Test func sanitizePathEscapesSpecialChars() {
        let result = InputSanitizer.sanitizePath("/Users/mac/Music/My \"Song\".wav")
        #expect(result != nil)
        #expect(result?.contains("\\\"") == true, "Quotes should be escaped")
    }

    @Test func sanitizePathRootPathAccepted() {
        let result = InputSanitizer.sanitizePath("/")
        #expect(result != nil)
    }
}
