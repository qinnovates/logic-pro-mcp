import Foundation

/// Parses inbound MIDI data from the virtual destination into
/// state updates on the StateCache. Handles MMC responses,
/// MTC quarter-frame messages, and channel voice data.
public actor MIDIFeedback {

    // MARK: - Properties

    private let cache: StateCache

    /// Last assembled MTC time (accumulated from quarter frames).
    private var mtcHours: UInt8 = 0
    private var mtcMinutes: UInt8 = 0
    private var mtcSeconds: UInt8 = 0
    private var mtcFrames: UInt8 = 0

    /// Quarter-frame accumulator (8 quarter frames = 1 full time code).
    private var quarterFrameBuffer: [UInt8] = Array(repeating: 0, count: 8)
    private var quarterFrameIndex: Int = 0

    // MARK: - Init

    public init(cache: StateCache) {
        self.cache = cache
    }

    // MARK: - Process Inbound MIDI

    /// Process a raw MIDI packet. Called by MIDIEngine's receive callback.
    func processPacket(_ data: [UInt8]) async {
        guard !data.isEmpty else { return }

        let statusByte = data[0]

        // Sysex message (starts with F0)
        if statusByte == 0xF0 {
            await processSysex(data)
            return
        }

        // MTC Quarter Frame (F1 nn)
        if statusByte == 0xF1, data.count >= 2 {
            await processQuarterFrame(data[1])
            return
        }

        // Channel voice messages
        let messageType = statusByte & 0xF0

        switch messageType {
        case 0x90:
            // Note On — could indicate playback activity
            if data.count >= 3 {
                await noteReceived(
                    note: data[1] & 0x7F,
                    velocity: data[2] & 0x7F,
                    channel: statusByte & 0x0F,
                    isNoteOn: true
                )
            }
        case 0x80:
            // Note Off
            if data.count >= 3 {
                await noteReceived(
                    note: data[1] & 0x7F,
                    velocity: 0,
                    channel: statusByte & 0x0F,
                    isNoteOn: false
                )
            }
        case 0xB0:
            // CC — could carry mixer feedback
            if data.count >= 3 {
                await ccReceived(
                    controller: data[1] & 0x7F,
                    value: data[2] & 0x7F,
                    channel: statusByte & 0x0F
                )
            }
        default:
            // Other message types ignored for now
            break
        }
    }

    // MARK: - Sysex Processing

    private func processSysex(_ data: [UInt8]) async {
        // Minimum sysex: F0 ... F7 (at least 3 bytes for an MMC response)
        guard data.count >= 5 else { return }

        // Check for MMC response: F0 7F 7F 07 xx F7
        // 07 = MMC Response sub-ID
        if data[1] == 0x7F && data[2] == 0x7F {
            let subCommand1 = data[3]

            switch subCommand1 {
            case 0x06:
                // MMC Command echo — the DAW is acknowledging
                if data.count >= 6 {
                    await processMMCCommandEcho(data[4])
                }
            case 0x07:
                // MMC Response — status update from the DAW
                if data.count >= 6 {
                    await processMMCResponse(data[4])
                }
            default:
                break
            }
        }
    }

    private func processMMCCommandEcho(_ command: UInt8) async {
        // The DAW echoed back our MMC command, confirming execution
        var transport = await cache.getTransport()

        switch command {
        case 0x01: // Stop
            transport.isPlaying = false
            transport.isRecording = false
            transport.isPaused = false
        case 0x02: // Play
            transport.isPlaying = true
            transport.isPaused = false
        case 0x04: // Fast Forward
            break
        case 0x05: // Rewind
            break
        case 0x06: // Record Strobe
            transport.isRecording = true
            transport.isPlaying = true
        case 0x09: // Pause
            transport.isPaused = true
            transport.isPlaying = false
        default:
            return
        }

        await cache.setTransport(transport)
    }

    private func processMMCResponse(_ status: UInt8) async {
        // MMC status response from the DAW
        var transport = await cache.getTransport()

        // Bit-field interpretation of MMC status byte
        transport.isPlaying = (status & 0x02) != 0
        transport.isRecording = (status & 0x04) != 0
        transport.isPaused = (status & 0x08) != 0

        await cache.setTransport(transport)
    }

    // MARK: - MTC Quarter Frame

    private func processQuarterFrame(_ dataByte: UInt8) async {
        let piece = (dataByte >> 4) & 0x07
        let nibble = dataByte & 0x0F

        quarterFrameBuffer[Int(piece)] = nibble
        quarterFrameIndex += 1

        // After receiving all 8 quarter frames, assemble full time code
        if quarterFrameIndex >= 8 {
            quarterFrameIndex = 0

            mtcFrames = quarterFrameBuffer[0] | (quarterFrameBuffer[1] << 4)
            mtcSeconds = quarterFrameBuffer[2] | (quarterFrameBuffer[3] << 4)
            mtcMinutes = quarterFrameBuffer[4] | (quarterFrameBuffer[5] << 4)
            mtcHours = quarterFrameBuffer[6] | ((quarterFrameBuffer[7] & 0x01) << 4)

            // Update transport position from MTC
            var transport = await cache.getTransport()
            let timeStr = String(
                format: "%02d:%02d:%02d:%02d",
                mtcHours, mtcMinutes, mtcSeconds, mtcFrames
            )
            transport.position = timeStr
            transport.isPlaying = true  // MTC only streams during playback
            await cache.setTransport(transport)
        }
    }

    // MARK: - Channel Voice Handlers

    private func noteReceived(
        note: UInt8,
        velocity: UInt8,
        channel: UInt8,
        isNoteOn: Bool
    ) async {
        // Note events indicate playback activity.
        // We use them to infer the transport is playing.
        if isNoteOn && velocity > 0 {
            let transport = await cache.getTransport()
            if !transport.isPlaying {
                var updated = transport
                updated.isPlaying = true
                await cache.setTransport(updated)
            }
        }
    }

    private func ccReceived(
        controller: UInt8,
        value: UInt8,
        channel: UInt8
    ) async {
        // Mackie Control protocol maps CCs to mixer state.
        // CC 7 = volume, CC 10 = pan on channels 0-7.
        let chIndex = Int(channel)

        switch controller {
        case 7:
            // Volume (0-127 mapped to approximately -inf to +6 dB)
            var mixer = await cache.getMixer()
            if chIndex < mixer.channels.count {
                let dbValue = Double(value) / 127.0 * 72.0 - 66.0  // rough -66 to +6 dB
                mixer.channels[chIndex].volume = dbValue
                await cache.setMixer(mixer)
            }
        case 10:
            // Pan (0=L, 64=C, 127=R mapped to -1.0 to 1.0)
            var mixer = await cache.getMixer()
            if chIndex < mixer.channels.count {
                let panValue = (Double(value) - 64.0) / 63.0
                mixer.channels[chIndex].pan = max(-1.0, min(1.0, panValue))
                await cache.setMixer(mixer)
            }
        default:
            break
        }
    }
}
