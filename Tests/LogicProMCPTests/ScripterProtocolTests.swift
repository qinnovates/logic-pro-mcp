import Testing
@testable import LogicProMCPLib

@Suite("Scripter Protocol")
struct ScripterProtocolTests {

    // MARK: - 7-bit Encode/Decode Round-Trip

    @Test func roundTripEmptyPayload() {
        let original: [UInt8] = []
        let encoded = ScripterProtocol.encode7Bit(original)
        let decoded = ScripterProtocol.decode7Bit(encoded)
        #expect(decoded == original)
    }

    @Test func roundTripShortPayload() {
        let original: [UInt8] = [0x48, 0x65, 0x6C, 0x6C, 0x6F] // "Hello"
        let encoded = ScripterProtocol.encode7Bit(original)
        let decoded = ScripterProtocol.decode7Bit(encoded)
        #expect(decoded == original)
    }

    @Test func roundTripExactlySevenBytes() {
        // Exactly one chunk boundary
        let original: [UInt8] = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]
        let encoded = ScripterProtocol.encode7Bit(original)
        let decoded = ScripterProtocol.decode7Bit(encoded)
        #expect(decoded == original)
    }

    @Test func roundTripLongPayloadAcrossChunks() {
        // 15 bytes = 2 full chunks (7) + 1 partial chunk (1)
        let original: [UInt8] = Array(0..<15)
        let encoded = ScripterProtocol.encode7Bit(original)
        let decoded = ScripterProtocol.decode7Bit(encoded)
        #expect(decoded == original)
    }

    @Test func roundTripHighBitBytes() {
        // All bytes with high bit set — tests the high-bit packing logic
        let original: [UInt8] = [0x80, 0xFF, 0xAB, 0xCD, 0xEF, 0x90, 0xFE, 0x81]
        let encoded = ScripterProtocol.encode7Bit(original)
        let decoded = ScripterProtocol.decode7Bit(encoded)
        #expect(decoded == original)
    }

    @Test func roundTripMixedHighAndLowBits() {
        let original: [UInt8] = [0x00, 0xFF, 0x7F, 0x80, 0x01, 0xFE, 0x55]
        let encoded = ScripterProtocol.encode7Bit(original)
        let decoded = ScripterProtocol.decode7Bit(encoded)
        #expect(decoded == original)
    }

    @Test func encodedBytesAreMIDISafe() {
        // After encoding, all bytes should be <= 0x7F (MIDI-safe)
        let original: [UInt8] = [0xFF, 0xFE, 0xFD, 0x80, 0x81, 0x82, 0x83, 0x84, 0x85]
        let encoded = ScripterProtocol.encode7Bit(original)
        for byte in encoded {
            #expect(byte <= 0x7F, "Encoded byte \(byte) exceeds MIDI-safe range")
        }
    }

    // MARK: - encodeCommand

    @Test func encodeCommandPingNoParams() {
        let messages = ScripterProtocol.encodeCommand(.ping)
        // Ping has no params, so only the command CC should be sent
        #expect(messages.count == 1)

        // Command CC: channel 15 (0-indexed), CC 119, value = command ID 1
        let commandMsg = messages[0]
        #expect(commandMsg[0] == 0xBF) // CC on channel 15
        #expect(commandMsg[1] == 119)  // CC number
        #expect(commandMsg[2] == 1)    // Command ID for ping
    }

    @Test func encodeCommandWithParams() {
        let command = ScripterCommand(id: 10, param1: 42, param2: 99)
        let messages = ScripterProtocol.encodeCommand(command)

        // Should have 3 messages: param1 CC, param2 CC, command CC
        #expect(messages.count == 3)

        // Param1: CC 118 on channel 15
        #expect(messages[0][0] == 0xBF)
        #expect(messages[0][1] == 118)
        #expect(messages[0][2] == 42)

        // Param2: CC 117 on channel 15
        #expect(messages[1][0] == 0xBF)
        #expect(messages[1][1] == 117)
        #expect(messages[1][2] == 99)

        // Command: CC 119 on channel 15
        #expect(messages[2][0] == 0xBF)
        #expect(messages[2][1] == 119)
        #expect(messages[2][2] == 10)
    }

    @Test func encodeCommandParamHighBitMasked() {
        // Param values > 0x7F should be masked to 7 bits
        let command = ScripterCommand(id: 5, param1: 0xFF, param2: nil)
        let messages = ScripterProtocol.encodeCommand(command)
        #expect(messages.count == 2) // param1 + command
        #expect(messages[0][2] == 0x7F) // 0xFF & 0x7F = 0x7F
    }

    @Test func encodeCommandSendsCommandLast() {
        let command = ScripterCommand(id: 7, param1: 1, param2: 2)
        let messages = ScripterProtocol.encodeCommand(command)
        // Last message should be the command CC (CC 119)
        let lastMsg = messages.last!
        #expect(lastMsg[1] == 119, "Command CC should be sent last")
    }

    // MARK: - parseResponse: Valid SysEx

    @Test func parseResponseValidPong() {
        // F0 00 7E 4C 01 F7 — pong with empty payload
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x01, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response != nil)
        #expect(response?.type == .pong)
        #expect(response?.payload.isEmpty == true)
    }

    @Test func parseResponseTimingInfo() {
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x02, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response?.type == .timingInfo)
    }

    @Test func parseResponseNoteCaptureData() {
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x03, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response?.type == .noteCaptureData)
    }

    @Test func parseResponseVersionInfo() {
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x05, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response?.type == .versionInfo)
    }

    @Test func parseResponseError() {
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x7F, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response?.type == .error)
    }

    @Test func parseResponseWithPayload() {
        // Build a valid SysEx with 7-bit encoded payload
        let jsonBytes: [UInt8] = Array("{}".utf8)
        let encoded = ScripterProtocol.encode7Bit(jsonBytes)
        var sysex: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x02] // timingInfo
        sysex.append(contentsOf: encoded)
        sysex.append(0xF7)

        let response = ScripterProtocol.parseResponse(sysex)
        #expect(response != nil)
        #expect(response?.type == .timingInfo)
        #expect(response?.jsonString == "{}")
    }

    // MARK: - parseResponse: Invalid Inputs

    @Test func parseResponseTooShort() {
        // Less than 6 bytes
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response == nil)
    }

    @Test func parseResponseWrongPrefix() {
        // Invalid manufacturer ID
        let bytes: [UInt8] = [0xF0, 0x00, 0x00, 0x00, 0x01, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response == nil)
    }

    @Test func parseResponseMissingTerminator() {
        // No 0xF7 at the end
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x01, 0x00]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response == nil)
    }

    @Test func parseResponseUnknownType() {
        // Response type 0x04 is not defined in ScripterResponseType
        let bytes: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C, 0x04, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response == nil)
    }

    @Test func parseResponseDoesNotStartWithSysEx() {
        let bytes: [UInt8] = [0x90, 0x00, 0x7E, 0x4C, 0x01, 0xF7]
        let response = ScripterProtocol.parseResponse(bytes)
        #expect(response == nil)
    }
}
