import CoreMIDI
import Foundation

/// Communication channel to Logic Pro via the Scripter MIDI FX plugin.
///
/// Uses dedicated CoreMIDI virtual ports (separate from CoreMIDIChannel) to send
/// CC commands to the Scripter bridge and receive SysEx responses back.
///
/// The Scripter bridge must be loaded on a track in Logic Pro for this channel
/// to be available. Availability is determined by a successful ping/pong handshake.
public actor ScripterChannel: Channel {

    // MARK: - Channel Protocol

    public nonisolated let name: String = "Scripter"

    public var isAvailable: Bool {
        hasHandshake && clientRef != 0
    }

    // MARK: - CoreMIDI Refs

    private var clientRef: MIDIClientRef = 0
    private var sourceRef: MIDIEndpointRef = 0
    private var destinationRef: MIDIEndpointRef = 0

    // MARK: - State

    private var hasHandshake: Bool = false
    private var pendingResponse: CheckedContinuation<ScripterResponse, any Error>?
    private let responseTimeout: Duration = .seconds(2)

    // MARK: - Config

    private let sourcePortName: String
    private let destPortName: String

    // MARK: - Init

    public init(config: ServerConfig) {
        self.sourcePortName = "LPM Scripter Out"
        self.destPortName = "LPM Scripter In"
    }

    // MARK: - Setup

    /// Initialize CoreMIDI ports and attempt handshake with the Scripter bridge.
    public func setup() async {
        setupMIDI()

        if clientRef != 0 {
            hasHandshake = await performHandshake()
        }
    }

    private func setupMIDI() {
        var client: MIDIClientRef = 0
        let clientStatus = MIDIClientCreateWithBlock(
            "LogicProMCP-Scripter" as CFString,
            &client
        ) { _ in }

        guard clientStatus == noErr else {
            fputs("[Scripter] Failed to create MIDI client: \(clientStatus)\n", stderr)
            return
        }
        clientRef = client

        // Virtual source: commands flow from here to Logic Pro's Scripter
        var source: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreate(clientRef, sourcePortName as CFString, &source)
        guard sourceStatus == noErr else {
            fputs("[Scripter] Failed to create virtual source: \(sourceStatus)\n", stderr)
            return
        }
        sourceRef = source

        // Virtual destination: SysEx responses flow from Scripter to here
        var dest: MIDIEndpointRef = 0
        let destStatus = MIDIDestinationCreateWithBlock(
            clientRef,
            destPortName as CFString,
            &dest
        ) { packetList, _ in
            let packets = packetList.pointee
            var packet = packets.packet
            for _ in 0..<packets.numPackets {
                let length = Int(packet.length)
                let data = withUnsafeBytes(of: &packet.data) { raw in
                    Array(raw.prefix(length).bindMemory(to: UInt8.self))
                }
                Task { await self.handleIncomingMIDI(data) }
                packet = MIDIPacketNext(&packet).pointee
            }
        }
        guard destStatus == noErr else {
            fputs("[Scripter] Failed to create virtual destination: \(destStatus)\n", stderr)
            return
        }
        destinationRef = dest

        fputs("[Scripter] MIDI ports initialized\n", stderr)
    }

    // MARK: - Incoming MIDI

    private func handleIncomingMIDI(_ bytes: [UInt8]) {
        guard let response = ScripterProtocol.parseResponse(bytes) else { return }

        if let continuation = pendingResponse {
            pendingResponse = nil
            continuation.resume(returning: response)
        }
    }

    // MARK: - Handshake

    private func performHandshake() async -> Bool {
        do {
            let response = try await sendCommandAndWait(.ping)
            let success = response.type == .pong
            if success {
                fputs("[Scripter] Handshake OK\n", stderr)
            }
            return success
        } catch {
            fputs("[Scripter] Handshake failed: \(error.localizedDescription)\n", stderr)
            return false
        }
    }

    /// Re-attempt the handshake. Called when the channel was previously unavailable
    /// and the user may have loaded the Scripter bridge since then.
    public func retryHandshake() async {
        hasHandshake = await performHandshake()
    }

    // MARK: - Channel Send

    public func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        switch operation {
        case .transport(let op):
            return try await handleTransportQuery(op)
        default:
            return .fail("Scripter channel does not handle \(operation)")
        }
    }

    // MARK: - Transport Queries (read-only via Scripter)

    private func handleTransportQuery(_ op: TransportOp) async throws -> ChannelResult {
        // Scripter can provide authoritative timing info
        switch op {
        case .play, .stop, .record, .pause, .rewind, .forward, .toggleCycle, .toggleMetronome:
            // Scripter cannot control transport — let other channels handle that
            return .fail("Scripter channel is read-only for transport control")
        case .setBPM:
            return .fail("Scripter channel cannot set BPM")
        case .setPosition:
            return .fail("Scripter channel cannot set position")
        }
    }

    /// Query timing info from the Scripter bridge. Returns parsed timing data
    /// that can be used to populate TransportState.
    public func getTimingInfo() async throws -> ScripterTimingInfo? {
        let response = try await sendCommandAndWait(.getTimingInfo)
        guard response.type == .timingInfo else { return nil }
        return response.decode(ScripterTimingInfo.self)
    }

    /// Start capturing MIDI notes passing through the Scripter track.
    public func startNoteCapture() async throws {
        let messages = ScripterProtocol.encodeCommand(.startNoteCapture)
        for bytes in messages {
            try sendRawBytes(bytes)
        }
    }

    /// Stop capturing and retrieve the captured note events.
    public func stopNoteCapture() async throws -> [ScripterCapturedNote] {
        let response = try await sendCommandAndWait(.stopNoteCapture)
        guard response.type == .noteCaptureData else { return [] }
        return response.decode([ScripterCapturedNote].self) ?? []
    }

    // MARK: - Command/Response

    private func sendCommandAndWait(_ command: ScripterCommand) async throws -> ScripterResponse {
        let messages = ScripterProtocol.encodeCommand(command)

        return try await withThrowingTaskGroup(of: ScripterResponse.self) { group in
            group.addTask {
                // Register continuation, then send command — both on the actor.
                // handleIncomingMIDI cannot interleave because actor serializes access.
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        await self.setPendingContinuationAndSend(
                            continuation: continuation,
                            messages: messages
                        )
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: self.responseTimeout)
                throw ScripterChannelError.responseTimeout
            }

            guard let result = try await group.next() else {
                throw ScripterChannelError.responseTimeout
            }
            group.cancelAll()
            return result
        }
    }

    /// Atomic set-continuation-then-send. Runs on the actor so no response
    /// can arrive between storing the continuation and sending the command.
    private func setPendingContinuationAndSend(
        continuation: CheckedContinuation<ScripterResponse, any Error>,
        messages: [[UInt8]]
    ) {
        setPendingContinuation(continuation)
        do {
            for bytes in messages {
                try sendRawBytes(bytes)
            }
        } catch {
            pendingResponse = nil
            continuation.resume(throwing: error)
        }
    }

    private func setPendingContinuation(
        _ continuation: CheckedContinuation<ScripterResponse, any Error>
    ) {
        // Cancel any existing pending continuation
        if let existing = pendingResponse {
            existing.resume(throwing: ScripterChannelError.superseded)
        }
        pendingResponse = continuation
    }

    // MARK: - Raw MIDI Send

    private func sendRawBytes(_ bytes: [UInt8]) throws {
        guard sourceRef != 0 else {
            throw ScripterChannelError.notInitialized
        }

        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        MIDIPacketListAdd(&packetList, 1024, packet, 0, bytes.count, bytes)

        let status = MIDIReceived(sourceRef, &packetList)
        guard status == noErr else {
            throw ScripterChannelError.midiSendFailed(status)
        }
    }

    // MARK: - Teardown

    public func teardown() {
        if let continuation = pendingResponse {
            continuation.resume(throwing: ScripterChannelError.shutdown)
            pendingResponse = nil
        }
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
        hasHandshake = false
    }

    // MARK: - Bridge Script Access

    /// Returns the JavaScript source code for the Scripter bridge plugin.
    /// The user pastes this into a Scripter MIDI FX instance in Logic Pro.
    public static var bridgeScriptSource: String {
        BridgeScript.generate()
    }
}

// MARK: - Errors

public enum ScripterChannelError: Error, LocalizedError, Sendable {
    case notInitialized
    case midiSendFailed(OSStatus)
    case responseTimeout
    case superseded
    case shutdown

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Scripter MIDI ports not initialized"
        case .midiSendFailed(let status):
            return "Scripter MIDI send failed with status \(status)"
        case .responseTimeout:
            return "Scripter bridge did not respond within timeout"
        case .superseded:
            return "Response superseded by a newer command"
        case .shutdown:
            return "Scripter channel shutting down"
        }
    }
}

// MARK: - Timing Info Model

/// Timing information returned by the Scripter bridge's GetTimingInfo() call.
public struct ScripterTimingInfo: Codable, Sendable {
    public let tempo: Double
    public let meterNumerator: Int
    public let meterDenominator: Int
    public let blockStartBeat: Double
    public let blockEndBeat: Double
    public let blockLength: Double
    public let isPlaying: Bool
    public let isCycling: Bool
    public let leftCycleBeat: Double
    public let rightCycleBeat: Double
}

// MARK: - Captured Note Model

/// A MIDI note event captured by the Scripter bridge during note capture mode.
public struct ScripterCapturedNote: Codable, Sendable {
    public let pitch: Int
    public let velocity: Int
    public let beat: Double
    public let type: String  // "on" or "off"
}
