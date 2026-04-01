import Foundation

// MARK: - Transport State

public struct TransportState: Codable, Sendable {
    public var isPlaying: Bool = false
    public var isRecording: Bool = false
    public var isPaused: Bool = false
    public var tempo: Double = 120.0
    public var position: String = "1.1.1.1"  // bars.beats.divisions.ticks
    public var isCycleEnabled: Bool = false
    public var isMetronomeEnabled: Bool = false
    public var cycleStart: String? = nil
    public var cycleEnd: String? = nil
    public var timeSignature: String = "4/4"
    public var sampleRate: Int = 44100

    public init() {}
}

// MARK: - Track Info

public struct TrackInfo: Codable, Sendable {
    public let index: Int
    public var name: String
    public var type: String  // "audio", "software_instrument", "drummer", "aux", "bus", "master"
    public var isMuted: Bool = false
    public var isSoloed: Bool = false
    public var isArmed: Bool = false
    public var volume: Double = 0.0  // dB
    public var pan: Double = 0.0  // -1.0 to 1.0
    public var automationMode: String = "off"

    public init(index: Int, name: String, type: String) {
        self.index = index
        self.name = name
        self.type = type
    }
}

// MARK: - Mixer State

public struct MixerState: Codable, Sendable {
    public var channels: [ChannelStrip] = []

    public init() {}
}

// MARK: - Channel Strip

public struct ChannelStrip: Codable, Sendable {
    public let index: Int
    public var name: String
    public var volume: Double = 0.0
    public var pan: Double = 0.0
    public var isMuted: Bool = false
    public var isSoloed: Bool = false
    public var sends: [SendInfo] = []
}

// MARK: - Send Info

public struct SendInfo: Codable, Sendable {
    public let index: Int
    public var destination: String
    public var level: Double = 0.0
    public var isPreFader: Bool = false
}

// MARK: - Project Info

public struct ProjectInfo: Codable, Sendable {
    public var name: String = ""
    public var filePath: String = ""
    public var sampleRate: Int = 44100
    public var bitDepth: Int = 24
    public var tempo: Double = 120.0
    public var timeSignature: String = "4/4"
    public var frameRate: String? = nil

    public init() {}
}

// MARK: - System Health

public struct SystemHealth: Codable, Sendable {
    public var serverVersion: String
    public var channels: [ChannelHealth]
    public var cacheAge: Double  // seconds
    public var logicProRunning: Bool
    public var permissionsOk: Bool
}

// MARK: - Channel Health

public struct ChannelHealth: Codable, Sendable {
    let name: String
    var isAvailable: Bool
    var failureCount: Int
    var isCircuitBroken: Bool
    var lastError: String?
}
