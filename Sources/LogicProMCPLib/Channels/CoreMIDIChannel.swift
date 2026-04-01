import CoreMIDI
import Foundation

/// Sends MIDI messages and MMC sysex to Logic Pro via CoreMIDI virtual ports.
public actor CoreMIDIChannel: Channel {

    // MARK: - Channel Protocol

    public nonisolated let name: String = "CoreMIDI"

    public var isAvailable: Bool {
        clientRef != 0
    }

    // MARK: - CoreMIDI Refs

    private var clientRef: MIDIClientRef = 0
    private var sourceRef: MIDIEndpointRef = 0
    private var destinationRef: MIDIEndpointRef = 0

    // MARK: - Config

    private let inputPortName: String
    private let outputPortName: String

    // MARK: - Init

    public init(config: ServerConfig) async {
        self.inputPortName = config.midiInputPortName
        self.outputPortName = config.midiOutputPortName
        setupMIDI()
    }

    // MARK: - Setup

    private func setupMIDI() {
        var client: MIDIClientRef = 0
        let clientStatus = MIDIClientCreateWithBlock(
            "LogicProMCP" as CFString,
            &client
        ) { [weak self] notification in
            // Handle MIDI setup changes if needed
            let _ = self
        }
        guard clientStatus == noErr else {
            fputs("[CoreMIDI] Failed to create MIDI client: \(clientStatus)\n", stderr)
            return
        }
        clientRef = client

        // Virtual source: we send data FROM here (Logic receives it)
        var source: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreate(clientRef, outputPortName as CFString, &source)
        guard sourceStatus == noErr else {
            fputs("[CoreMIDI] Failed to create virtual source: \(sourceStatus)\n", stderr)
            return
        }
        sourceRef = source

        // Virtual destination: Logic sends data TO here (we receive it)
        var destination: MIDIEndpointRef = 0
        let destStatus = MIDIDestinationCreateWithBlock(
            clientRef,
            inputPortName as CFString,
            &destination
        ) { [weak self] packetList, _ in
            let _ = self
            // Receive callback: parse incoming MIDI if needed in the future
        }
        guard destStatus == noErr else {
            fputs("[CoreMIDI] Failed to create virtual destination: \(destStatus)\n", stderr)
            return
        }
        destinationRef = destination

        fputs("[CoreMIDI] Initialized: source='\(outputPortName)' destination='\(inputPortName)'\n", stderr)
    }

    // MARK: - Send

    public func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        switch operation {
        case .transport(let op):
            return sendTransportMMC(op)
        case .midi(let op):
            return await sendMIDI(op)
        default:
            return .fail("CoreMIDI does not handle \(operation)")
        }
    }

    // MARK: - Transport via MMC Sysex

    private func sendTransportMMC(_ op: TransportOp) -> ChannelResult {
        let sysex: [UInt8]
        switch op {
        case .play:
            sysex = [0xF0, 0x7F, 0x7F, 0x06, 0x02, 0xF7]
        case .stop:
            sysex = [0xF0, 0x7F, 0x7F, 0x06, 0x01, 0xF7]
        case .record:
            sysex = [0xF0, 0x7F, 0x7F, 0x06, 0x06, 0xF7]
        case .pause:
            sysex = [0xF0, 0x7F, 0x7F, 0x06, 0x09, 0xF7]
        case .rewind:
            sysex = [0xF0, 0x7F, 0x7F, 0x06, 0x05, 0xF7]
        case .forward:
            sysex = [0xF0, 0x7F, 0x7F, 0x06, 0x04, 0xF7]
        default:
            return .fail("CoreMIDI MMC does not support \(op)")
        }

        return sendRawBytes(sysex, description: "MMC transport")
    }

    // MARK: - MIDI Messages

    private func sendMIDI(_ op: MIDIOp) async -> ChannelResult {
        switch op {
        case .sendNote(let note, let velocity, let channel, let duration):
            let noteOn: [UInt8] = [0x90 | (channel & 0x0F), note & 0x7F, velocity & 0x7F]
            let onResult = sendRawBytes(noteOn, description: "NoteOn")
            guard onResult.success else { return onResult }

            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            let noteOff: [UInt8] = [0x80 | (channel & 0x0F), note & 0x7F, 0]
            return sendRawBytes(noteOff, description: "NoteOff")

        case .sendCC(let controller, let value, let channel):
            let bytes: [UInt8] = [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
            return sendRawBytes(bytes, description: "CC")

        case .sendProgramChange(let program, let channel):
            let bytes: [UInt8] = [0xC0 | (channel & 0x0F), program & 0x7F]
            return sendRawBytes(bytes, description: "ProgramChange")

        case .sendPitchBend(let value, let channel):
            let clamped = min(value, 16383)
            let lsb = UInt8(clamped & 0x7F)
            let msb = UInt8((clamped >> 7) & 0x7F)
            let bytes: [UInt8] = [0xE0 | (channel & 0x0F), lsb, msb]
            return sendRawBytes(bytes, description: "PitchBend")
        }
    }

    // MARK: - Raw Send

    private func sendRawBytes(_ bytes: [UInt8], description: String) -> ChannelResult {
        guard sourceRef != 0 else {
            return .fail("CoreMIDI source not initialized")
        }

        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)

        let status = MIDIReceived(sourceRef, &packetList)
        if status == noErr {
            return .ok(["sent": description, "bytes": "\(bytes.count)"])
        } else {
            return .fail("MIDIReceived failed with status \(status)")
        }
    }
}
