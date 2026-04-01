import Foundation

/// Factory methods for MIDI and MMC (MIDI Machine Control) sysex messages.
/// All methods return raw byte arrays ready to send over CoreMIDI.
public struct MMCCommands: Sendable {

    // MARK: - MMC Transport Commands (Sysex)

    /// MMC Play: F0 7F 7F 06 02 F7
    public static let play: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x02, 0xF7]

    /// MMC Stop: F0 7F 7F 06 01 F7
    public static let stop: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x01, 0xF7]

    /// MMC Record Strobe: F0 7F 7F 06 06 F7
    public static let record: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x06, 0xF7]

    /// MMC Pause: F0 7F 7F 06 09 F7
    public static let pause: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x09, 0xF7]

    /// MMC Rewind: F0 7F 7F 06 05 F7
    public static let rewind: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x05, 0xF7]

    /// MMC Fast Forward: F0 7F 7F 06 04 F7
    public static let forward: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x04, 0xF7]

    // MARK: - MMC Locate (Sysex)

    /// MMC Locate to a specific SMPTE time code position.
    /// Format: F0 7F 7F 06 44 06 01 hr mn sc fr sf F7
    public static func locate(
        hours: UInt8,
        minutes: UInt8,
        seconds: UInt8,
        frames: UInt8,
        subframes: UInt8 = 0
    ) -> [UInt8] {
        [
            0xF0, 0x7F, 0x7F, 0x06, 0x44, 0x06, 0x01,
            hours & 0x1F,       // 5 bits for hours (0-23)
            minutes & 0x3F,     // 6 bits for minutes (0-59)
            seconds & 0x3F,     // 6 bits for seconds (0-59)
            frames & 0x1F,      // 5 bits for frames (0-29)
            subframes & 0x7F,   // 7 bits for subframes
            0xF7,
        ]
    }

    // MARK: - Channel Voice Messages

    /// Note On: 9n kk vv
    public static func noteOn(note: UInt8, velocity: UInt8, channel: UInt8) -> [UInt8] {
        [0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
    }

    /// Note Off: 8n kk 00
    public static func noteOff(note: UInt8, channel: UInt8) -> [UInt8] {
        [0x80 | (channel & 0x0F), note & 0x7F, 0x00]
    }

    /// Control Change: Bn cc vv
    public static func cc(controller: UInt8, value: UInt8, channel: UInt8) -> [UInt8] {
        [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
    }

    /// Program Change: Cn pp
    public static func programChange(program: UInt8, channel: UInt8) -> [UInt8] {
        [0xC0 | (channel & 0x0F), program & 0x7F]
    }

    /// Pitch Bend: En ll mm  (14-bit value, 8192 = center)
    public static func pitchBend(value: UInt16, channel: UInt8) -> [UInt8] {
        let clamped = min(value, 16383)
        let lsb = UInt8(clamped & 0x7F)
        let msb = UInt8((clamped >> 7) & 0x7F)
        return [0xE0 | (channel & 0x0F), lsb, msb]
    }
}
