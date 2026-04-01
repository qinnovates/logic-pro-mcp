import Testing
@testable import LogicProMCPLib

@Suite("MMC Commands")
struct MMCCommandsTests {

    // MARK: - Transport Sysex Commands

    @Test func playCommand() {
        let expected: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x02, 0xF7]
        #expect(MMCCommands.play == expected)
    }

    @Test func stopCommand() {
        let expected: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x01, 0xF7]
        #expect(MMCCommands.stop == expected)
    }

    @Test func recordCommand() {
        let expected: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x06, 0xF7]
        #expect(MMCCommands.record == expected)
    }

    @Test func pauseCommand() {
        let expected: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x09, 0xF7]
        #expect(MMCCommands.pause == expected)
    }

    @Test func rewindCommand() {
        let expected: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x05, 0xF7]
        #expect(MMCCommands.rewind == expected)
    }

    @Test func forwardCommand() {
        let expected: [UInt8] = [0xF0, 0x7F, 0x7F, 0x06, 0x04, 0xF7]
        #expect(MMCCommands.forward == expected)
    }

    // MARK: - Note On

    @Test func noteOnMessage() {
        // Channel 0: status byte = 0x90
        let msg = MMCCommands.noteOn(note: 60, velocity: 100, channel: 0)
        #expect(msg == [0x90, 60, 100])
    }

    @Test func noteOnChannelMasking() {
        // Channel 15: status byte = 0x9F
        let msg = MMCCommands.noteOn(note: 60, velocity: 127, channel: 15)
        #expect(msg[0] == 0x9F)

        // Channel value > 15 should be masked to lower nibble
        let msgOverflow = MMCCommands.noteOn(note: 60, velocity: 100, channel: 0xFF)
        #expect(msgOverflow[0] == 0x9F)
    }

    @Test func noteOnDataByteClamping() {
        // Note and velocity > 127 should be clamped to 7 bits
        let msg = MMCCommands.noteOn(note: 0xFF, velocity: 0xFF, channel: 0)
        #expect(msg[1] == 0x7F) // note clamped
        #expect(msg[2] == 0x7F) // velocity clamped
    }

    // MARK: - Note Off

    @Test func noteOffMessage() {
        let msg = MMCCommands.noteOff(note: 60, channel: 0)
        #expect(msg == [0x80, 60, 0x00])
    }

    @Test func noteOffChannelMasking() {
        let msg = MMCCommands.noteOff(note: 48, channel: 9)
        #expect(msg[0] == 0x89)
    }

    // MARK: - CC

    @Test func ccMessage() {
        let msg = MMCCommands.cc(controller: 7, value: 100, channel: 0)
        #expect(msg == [0xB0, 7, 100])
    }

    @Test func ccChannelAndDataClamping() {
        let msg = MMCCommands.cc(controller: 0xFF, value: 0xFF, channel: 15)
        #expect(msg[0] == 0xBF)
        #expect(msg[1] == 0x7F) // controller clamped
        #expect(msg[2] == 0x7F) // value clamped
    }

    // MARK: - Program Change

    @Test func programChangeMessage() {
        let msg = MMCCommands.programChange(program: 42, channel: 3)
        #expect(msg == [0xC3, 42])
    }

    @Test func programChangeClamping() {
        let msg = MMCCommands.programChange(program: 0xFF, channel: 0)
        #expect(msg[1] == 0x7F)
    }

    // MARK: - Pitch Bend

    @Test func pitchBendMessage() {
        // Center value 8192 = 0x2000 -> LSB = 0x00, MSB = 0x40
        let msg = MMCCommands.pitchBend(value: 8192, channel: 0)
        #expect(msg[0] == 0xE0)
        #expect(msg[1] == 0x00) // LSB
        #expect(msg[2] == 0x40) // MSB
    }

    @Test func pitchBendLSBMSBSplit() {
        // Value 0x1234 = 4660
        // LSB = 0x34 & 0x7F = 0x34
        // MSB = (0x1234 >> 7) & 0x7F = 0x24
        let msg = MMCCommands.pitchBend(value: 0x1234, channel: 0)
        #expect(msg[1] == 0x34) // LSB
        #expect(msg[2] == 0x24) // MSB
    }

    @Test func pitchBendClampingAboveMax() {
        // Values > 16383 should be clamped
        let msg = MMCCommands.pitchBend(value: 0xFFFF, channel: 0)
        // 16383 = 0x3FFF -> LSB = 0x7F, MSB = 0x7F
        #expect(msg[1] == 0x7F)
        #expect(msg[2] == 0x7F)
    }

    @Test func pitchBendMinValue() {
        let msg = MMCCommands.pitchBend(value: 0, channel: 5)
        #expect(msg[0] == 0xE5)
        #expect(msg[1] == 0x00) // LSB
        #expect(msg[2] == 0x00) // MSB
    }

    // MARK: - Locate

    @Test func locateCommand() {
        let msg = MMCCommands.locate(hours: 1, minutes: 30, seconds: 15, frames: 10, subframes: 0)
        #expect(msg[0] == 0xF0) // Sysex start
        #expect(msg[1] == 0x7F) // Universal real-time
        #expect(msg[2] == 0x7F) // All devices
        #expect(msg[3] == 0x06) // MMC command
        #expect(msg[4] == 0x44) // Locate
        #expect(msg[5] == 0x06) // Sub-command length
        #expect(msg[6] == 0x01) // Sub-command type
        #expect(msg[7] == 1)    // hours
        #expect(msg[8] == 30)   // minutes
        #expect(msg[9] == 15)   // seconds
        #expect(msg[10] == 10)  // frames
        #expect(msg[11] == 0)   // subframes
        #expect(msg[12] == 0xF7) // Sysex end
    }

    @Test func locateHoursMasking() {
        // Hours uses 5 bits (0-31), so 0xFF & 0x1F = 31
        let msg = MMCCommands.locate(hours: 0xFF, minutes: 0, seconds: 0, frames: 0)
        #expect(msg[7] == 0x1F)
    }

    @Test func locateMinutesMasking() {
        // Minutes uses 6 bits (0-63), so 0xFF & 0x3F = 63
        let msg = MMCCommands.locate(hours: 0, minutes: 0xFF, seconds: 0, frames: 0)
        #expect(msg[8] == 0x3F)
    }
}
