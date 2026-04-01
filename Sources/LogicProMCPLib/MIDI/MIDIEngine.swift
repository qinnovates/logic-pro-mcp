import CoreMIDI
import Foundation

// MARK: - MIDI Port Info

/// Describes an available MIDI port (virtual or hardware).
struct MIDIPortInfo: Codable, Sendable {
    let name: String
    let uniqueID: Int32
    let isVirtual: Bool
    let isOnline: Bool
}

// MARK: - MIDI Engine Errors

enum MIDIEngineError: Error, LocalizedError, Sendable {
    case clientNotInitialized
    case sourceNotInitialized
    case sendFailed(OSStatus)
    case invalidNoteData

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "MIDI client not initialized"
        case .sourceNotInitialized:
            return "MIDI virtual source not initialized"
        case .sendFailed(let status):
            return "MIDI send failed with status \(status)"
        case .invalidNoteData:
            return "Invalid MIDI note data"
        }
    }
}

// MARK: - MIDI Engine

/// Higher-level MIDI abstraction over CoreMIDI.
/// Creates virtual MIDI ports and provides methods for sending
/// timed note sequences, chords, and querying available ports.
public actor MIDIEngine {

    // MARK: - CoreMIDI Refs

    private var clientRef: MIDIClientRef = 0
    private var sourceRef: MIDIEndpointRef = 0
    private var destinationRef: MIDIEndpointRef = 0

    // MARK: - Config

    private let outputPortName: String
    private let inputPortName: String

    /// Callback invoked when MIDI data arrives at the virtual destination.
    /// Marked @Sendable to allow safe capture in CoreMIDI's nonisolated callback.
    private var receiveCallback: (@Sendable ([UInt8]) async -> Void)?

    // MARK: - Init

    public init(outputPortName: String, inputPortName: String) {
        self.outputPortName = outputPortName
        self.inputPortName = inputPortName
    }

    // MARK: - Setup

    /// Initialize CoreMIDI client and virtual ports.
    /// Call this once during startup.
    func setup(receiveHandler: (@Sendable ([UInt8]) async -> Void)? = nil) {
        self.receiveCallback = receiveHandler

        // Capture the callback locally so the CoreMIDI block doesn't
        // need to access actor-isolated state.
        let capturedCallback = receiveCallback

        var client: MIDIClientRef = 0
        let clientStatus = MIDIClientCreateWithBlock(
            "LogicProMCP-Engine" as CFString,
            &client
        ) { _ in }

        guard clientStatus == noErr else {
            fputs("[MIDIEngine] Failed to create MIDI client: \(clientStatus)\n", stderr)
            return
        }
        clientRef = client

        // Virtual source: data flows FROM here to Logic Pro
        var source: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreate(clientRef, outputPortName as CFString, &source)
        guard sourceStatus == noErr else {
            fputs("[MIDIEngine] Failed to create virtual source: \(sourceStatus)\n", stderr)
            return
        }
        sourceRef = source

        // Virtual destination: data flows FROM Logic Pro TO here
        var dest: MIDIEndpointRef = 0
        let destStatus = MIDIDestinationCreateWithBlock(
            clientRef,
            inputPortName as CFString,
            &dest
        ) { packetList, _ in
            let packets = packetList.pointee
            var packet = packets.packet
            for _ in 0..<packets.numPackets {
                let length = Int(packet.length)
                let data = withUnsafeBytes(of: &packet.data) { raw in
                    Array(raw.prefix(length).bindMemory(to: UInt8.self))
                }
                if let callback = capturedCallback {
                    Task {
                        await callback(data)
                    }
                }
                packet = MIDIPacketNext(&packet).pointee
            }
        }
        guard destStatus == noErr else {
            fputs("[MIDIEngine] Failed to create virtual destination: \(destStatus)\n", stderr)
            return
        }
        destinationRef = dest

        fputs("[MIDIEngine] Initialized: source='\(outputPortName)' dest='\(inputPortName)'\n", stderr)
    }

    var isAvailable: Bool {
        clientRef != 0 && sourceRef != 0
    }

    // MARK: - Send Notes (Timed Sequence)

    /// Send a sequence of timed notes. Each note has an independent start time
    /// (relative to now) and duration.
    func sendNotes(
        _ notes: [(note: UInt8, velocity: UInt8, channel: UInt8, startTime: Double, duration: Double)]
    ) async throws {
        guard sourceRef != 0 else { throw MIDIEngineError.sourceNotInitialized }

        // Sort notes by start time for sequential scheduling
        let sorted = notes.sorted { $0.startTime < $1.startTime }
        let startDate = ContinuousClock.now

        for entry in sorted {
            guard entry.note <= 127, entry.velocity <= 127, entry.channel <= 15 else {
                throw MIDIEngineError.invalidNoteData
            }

            // Wait until the scheduled start time
            let targetOffset = Duration.milliseconds(Int(entry.startTime * 1000))
            let elapsed = ContinuousClock.now - startDate
            if targetOffset > elapsed {
                try await Task.sleep(for: targetOffset - elapsed)
            }

            // Note On
            let noteOnBytes = MMCCommands.noteOn(
                note: entry.note, velocity: entry.velocity, channel: entry.channel
            )
            try sendRawBytes(noteOnBytes)

            // Schedule Note Off after duration
            let duration = entry.duration
            let noteNum = entry.note
            let ch = entry.channel
            Task {
                try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))
                let noteOffBytes = MMCCommands.noteOff(note: noteNum, channel: ch)
                try? self.sendRawBytes(noteOffBytes)
            }
        }
    }

    // MARK: - Send Chord

    /// Send multiple notes simultaneously (a chord) with the same velocity,
    /// channel, and duration.
    func sendChord(
        _ notes: [UInt8],
        velocity: UInt8,
        channel: UInt8,
        duration: Double
    ) async throws {
        guard sourceRef != 0 else { throw MIDIEngineError.sourceNotInitialized }

        // Send all Note Ons
        for note in notes {
            guard note <= 127 else { throw MIDIEngineError.invalidNoteData }
            let bytes = MMCCommands.noteOn(note: note, velocity: velocity, channel: channel)
            try sendRawBytes(bytes)
        }

        // Wait for duration, then send all Note Offs
        try await Task.sleep(for: .milliseconds(Int(duration * 1000)))

        for note in notes {
            let bytes = MMCCommands.noteOff(note: note, channel: channel)
            try sendRawBytes(bytes)
        }
    }

    // MARK: - Send Raw

    /// Send arbitrary MIDI bytes through the virtual source.
    func sendRawBytes(_ bytes: [UInt8]) throws {
        guard sourceRef != 0 else { throw MIDIEngineError.sourceNotInitialized }

        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)

        let status = MIDIReceived(sourceRef, &packetList)
        guard status == noErr else {
            throw MIDIEngineError.sendFailed(status)
        }
    }

    // MARK: - List Ports

    /// List all available MIDI source and destination ports
    /// (both virtual and hardware).
    func listPorts() -> [MIDIPortInfo] {
        var ports: [MIDIPortInfo] = []

        // Enumerate MIDI sources (things that produce MIDI data)
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let endpoint = MIDIGetSource(i)
            if let info = portInfo(for: endpoint) {
                ports.append(info)
            }
        }

        // Enumerate MIDI destinations (things that receive MIDI data)
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let endpoint = MIDIGetDestination(i)
            if let info = portInfo(for: endpoint) {
                // Avoid duplicates (same uniqueID can appear as both source and dest)
                if !ports.contains(where: { $0.uniqueID == info.uniqueID }) {
                    ports.append(info)
                }
            }
        }

        return ports
    }

    // MARK: - Teardown

    func teardown() {
        if destinationRef != 0 {
            MIDIEndpointDispose(destinationRef)
            destinationRef = 0
        }
        if sourceRef != 0 {
            MIDIEndpointDispose(sourceRef)
            sourceRef = 0
        }
        if clientRef != 0 {
            MIDIClientDispose(clientRef)
            clientRef = 0
        }
    }

    // MARK: - Private

    private func portInfo(for endpoint: MIDIEndpointRef) -> MIDIPortInfo? {
        guard endpoint != 0 else { return nil }

        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name)
        let portName = (name?.takeRetainedValue() as String?) ?? "Unknown"

        var uniqueID: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &uniqueID)

        // Check if virtual: virtual endpoints have no entity parent
        var entity: MIDIEntityRef = 0
        let entityStatus = MIDIEndpointGetEntity(endpoint, &entity)
        let isVirtual = (entityStatus != noErr || entity == 0)

        // Check if online
        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &offline)
        let isOnline = (offline == 0)

        return MIDIPortInfo(
            name: portName,
            uniqueID: uniqueID,
            isVirtual: isVirtual,
            isOnline: isOnline
        )
    }
}
