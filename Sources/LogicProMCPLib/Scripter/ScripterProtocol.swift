import Foundation

/// Defines the bidirectional communication protocol between the MCP server
/// and the Logic Pro Scripter MIDI FX plugin.
///
/// **Outbound (Server → Scripter):** CC messages on channel 16.
/// - CC 119 = command type (see `ScripterCommand`)
/// - CC 118 = parameter byte 1
/// - CC 117 = parameter byte 2
/// Commands are sent as a CC 119 message; the Scripter bridge script
/// interprets the value as the command ID.
///
/// **Inbound (Scripter → Server):** SysEx messages with a custom manufacturer ID.
/// Format: F0 00 7E 4C <responseType> <payload...> F7
/// - Manufacturer ID: 00 7E 4C ("LPM" — Logic Pro MCP, non-commercial/educational)
/// - Response type: see `ScripterResponseType`
/// - Payload: 7-bit encoded JSON bytes
public enum ScripterProtocol {

    // MARK: - Constants

    /// MIDI channel used for Scripter bridge communication (0-indexed, channel 16)
    static let midiChannel: UInt8 = 15

    /// CC number for command dispatch
    static let commandCC: UInt8 = 119

    /// CC number for parameter byte 1
    static let paramCC1: UInt8 = 118

    /// CC number for parameter byte 2
    static let paramCC2: UInt8 = 117

    /// SysEx manufacturer ID prefix: 00 7E 4C
    static let sysExPrefix: [UInt8] = [0xF0, 0x00, 0x7E, 0x4C]

    /// SysEx terminator
    static let sysExEnd: UInt8 = 0xF7

    // MARK: - Commands (Server → Scripter)

    /// Build CC bytes for a command. Returns an array of MIDI byte arrays
    /// (one CC message per parameter, command CC sent last to trigger execution).
    static func encodeCommand(_ command: ScripterCommand) -> [[UInt8]] {
        var messages: [[UInt8]] = []

        // Send parameter bytes first (if any)
        if let param1 = command.param1 {
            messages.append(MMCCommands.cc(
                controller: paramCC1,
                value: param1 & 0x7F,
                channel: midiChannel
            ))
        }
        if let param2 = command.param2 {
            messages.append(MMCCommands.cc(
                controller: paramCC2,
                value: param2 & 0x7F,
                channel: midiChannel
            ))
        }

        // Send command CC last (triggers execution in Scripter)
        messages.append(MMCCommands.cc(
            controller: commandCC,
            value: command.id,
            channel: midiChannel
        ))

        return messages
    }

    // MARK: - Response Parsing (Scripter → Server)

    /// Attempt to parse a SysEx byte array as a Scripter bridge response.
    /// Returns nil if the bytes don't match the expected prefix.
    static func parseResponse(_ bytes: [UInt8]) -> ScripterResponse? {
        // Minimum: F0 00 7E 4C <type> F7 = 6 bytes
        guard bytes.count >= 6 else { return nil }
        guard bytes[0] == 0xF0,
              bytes[1] == 0x00,
              bytes[2] == 0x7E,
              bytes[3] == 0x4C else { return nil }
        guard bytes.last == sysExEnd else { return nil }

        let responseTypeRaw = bytes[4]
        guard let responseType = ScripterResponseType(rawValue: responseTypeRaw) else {
            return nil
        }

        // Payload is bytes[5..<(count-1)], 7-bit encoded
        let payloadBytes = Array(bytes[5..<(bytes.count - 1)])
        let decoded = decode7Bit(payloadBytes)

        return ScripterResponse(type: responseType, payload: decoded)
    }

    // MARK: - 7-bit Encoding/Decoding

    /// Encode arbitrary 8-bit data into 7-bit safe MIDI bytes.
    /// Every 7 bytes of input become 8 bytes of output (high bits packed into a header byte).
    static func encode7Bit(_ data: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var index = 0
        while index < data.count {
            let chunkEnd = min(index + 7, data.count)
            let chunk = Array(data[index..<chunkEnd])
            var highBits: UInt8 = 0
            for (bitIndex, byte) in chunk.enumerated() {
                if byte & 0x80 != 0 {
                    highBits |= (1 << UInt8(bitIndex))
                }
            }
            output.append(highBits)
            for byte in chunk {
                output.append(byte & 0x7F)
            }
            index = chunkEnd
        }
        return output
    }

    /// Decode 7-bit MIDI-safe bytes back to 8-bit data.
    static func decode7Bit(_ encoded: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        var index = 0
        while index < encoded.count {
            let highBits = encoded[index]
            index += 1
            let chunkEnd = min(index + 7, encoded.count)
            for (bitIndex, encodedByte) in encoded[index..<chunkEnd].enumerated() {
                var restored = encodedByte
                if highBits & (1 << UInt8(bitIndex)) != 0 {
                    restored |= 0x80
                }
                output.append(restored)
            }
            index = chunkEnd
        }
        return output
    }
}

// MARK: - Command Types

/// Commands sent from the MCP server to the Scripter bridge.
public struct ScripterCommand: Sendable {
    let id: UInt8
    let param1: UInt8?
    let param2: UInt8?

    /// Ping — expects a pong SysEx back. Used for handshake and health checks.
    static let ping = ScripterCommand(id: 1, param1: nil, param2: nil)

    /// Request timing info (tempo, position, time signature, cycle state).
    static let getTimingInfo = ScripterCommand(id: 2, param1: nil, param2: nil)

    /// Request to start capturing MIDI note events passing through the track.
    static let startNoteCapture = ScripterCommand(id: 3, param1: nil, param2: nil)

    /// Stop capturing and send accumulated note data as SysEx.
    static let stopNoteCapture = ScripterCommand(id: 4, param1: nil, param2: nil)

    /// Request the Scripter to report its version/capabilities.
    static let getVersion = ScripterCommand(id: 5, param1: nil, param2: nil)
}

// MARK: - Response Types

/// Response types sent from the Scripter bridge to the MCP server.
public enum ScripterResponseType: UInt8, Sendable {
    case pong = 1
    case timingInfo = 2
    case noteCaptureData = 3
    case versionInfo = 5
    case error = 127
}

// MARK: - Parsed Response

/// A parsed response from the Scripter bridge.
public struct ScripterResponse: Sendable {
    let type: ScripterResponseType
    /// Decoded payload bytes (8-bit restored). Typically UTF-8 JSON.
    let payload: [UInt8]

    /// Attempt to decode the payload as a UTF-8 JSON string.
    var jsonString: String? {
        String(bytes: payload, encoding: .utf8)
    }

    /// Attempt to decode the payload as a specific Codable type.
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard !payload.isEmpty else { return nil }
        let data = Data(payload)
        return try? JSONDecoder().decode(type, from: data)
    }
}
