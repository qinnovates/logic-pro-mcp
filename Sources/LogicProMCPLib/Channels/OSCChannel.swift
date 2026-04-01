import Foundation
import Network

/// Sends OSC messages over UDP for mixer control in Logic Pro.
/// Builds OSC packets manually and transmits via NWConnection.
public actor OSCChannel: Channel {

    // MARK: - Channel Protocol

    public nonisolated let name: String = "OSC"

    public var isAvailable: Bool {
        get async {
            connection != nil && connectionReady
        }
    }

    // MARK: - Properties

    private let host: String
    private let port: UInt16
    private var connection: NWConnection?
    private var connectionReady: Bool = false

    // MARK: - Init

    public init(config: ServerConfig) async {
        self.host = config.oscHost
        self.port = config.oscPort
        setupConnection()
    }

    // MARK: - Connection Setup

    private func setupConnection() {
        let nwHost = NWEndpoint.Host(host)
        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: nwHost, port: nwPort, using: .udp)

        conn.stateUpdateHandler = { [weak self] state in
            Task { [weak self] in
                await self?.handleStateChange(state)
            }
        }

        conn.start(queue: DispatchQueue(label: "com.logicpromcp.osc"))
        connection = conn
    }

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionReady = true
            fputs("[OSC] Connected to \(host):\(port)\n", stderr)
        case .failed(let error):
            connectionReady = false
            fputs("[OSC] Connection failed: \(error)\n", stderr)
        case .cancelled:
            connectionReady = false
        default:
            break
        }
    }

    // MARK: - Send

    public func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        switch operation {
        case .mixer(let op):
            return await handleMixer(op)
        default:
            return .fail("OSC channel only handles mixer operations")
        }
    }

    // MARK: - Mixer Operations

    private func handleMixer(_ op: MixerOp) async -> ChannelResult {
        switch op {
        case .setVolume(let channel, let value):
            let address = "/track/\(channel + 1)/volume"
            let packet = buildOSCFloat(address: address, value: Float(value))
            return await sendPacket(packet, description: "setVolume ch=\(channel) val=\(value)")

        case .setPan(let channel, let value):
            let address = "/track/\(channel + 1)/pan"
            let packet = buildOSCFloat(address: address, value: Float(value))
            return await sendPacket(packet, description: "setPan ch=\(channel) val=\(value)")

        case .setMute(let channel, let state):
            let address = "/track/\(channel + 1)/mute"
            let packet = buildOSCInt(address: address, value: state ? 1 : 0)
            return await sendPacket(packet, description: "setMute ch=\(channel) state=\(state)")
        }
    }

    // MARK: - OSC Packet Building

    /// Build an OSC message with a float argument.
    /// Format: address (null-padded to 4-byte boundary), type tag ",f\0\0", float (big-endian)
    private func buildOSCFloat(address: String, value: Float) -> Data {
        var data = Data()
        data.append(oscString(address))
        data.append(oscString(",f"))
        data.append(oscFloat(value))
        return data
    }

    /// Build an OSC message with an int32 argument.
    /// Format: address (null-padded to 4-byte boundary), type tag ",i\0\0", int32 (big-endian)
    private func buildOSCInt(address: String, value: Int32) -> Data {
        var data = Data()
        data.append(oscString(address))
        data.append(oscString(",i"))
        data.append(oscInt32(value))
        return data
    }

    /// Encode a string as OSC string (null-terminated, padded to 4-byte boundary).
    private func oscString(_ string: String) -> Data {
        var data = Data(string.utf8)
        data.append(0)  // null terminator
        // Pad to 4-byte boundary
        while data.count % 4 != 0 {
            data.append(0)
        }
        return data
    }

    /// Encode a float as big-endian 4 bytes.
    private func oscFloat(_ value: Float) -> Data {
        var bigEndian = value.bitPattern.bigEndian
        return Data(bytes: &bigEndian, count: 4)
    }

    /// Encode an int32 as big-endian 4 bytes.
    private func oscInt32(_ value: Int32) -> Data {
        var bigEndian = value.bigEndian
        return Data(bytes: &bigEndian, count: 4)
    }

    // MARK: - Network Send

    private func sendPacket(_ data: Data, description: String) async -> ChannelResult {
        guard let connection, connectionReady else {
            return .fail("OSC connection not ready (host=\(host) port=\(port))")
        }

        return await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(returning: .fail("OSC send failed: \(error.localizedDescription)"))
                } else {
                    continuation.resume(returning: .ok(["osc": description, "bytes": "\(data.count)"]))
                }
            })
        }
    }
}
