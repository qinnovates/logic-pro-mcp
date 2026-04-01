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

// MARK: - Plugin Chain

public struct PluginChain: Codable, Sendable {
    public let trackIndex: Int
    public var slots: [PluginSlot]

    public init(trackIndex: Int, slots: [PluginSlot] = []) {
        self.trackIndex = trackIndex
        self.slots = slots
    }
}

// MARK: - Plugin Slot

public struct PluginSlot: Codable, Sendable {
    public let slotIndex: Int
    public var name: String
    public var manufacturer: String
    public var type: String  // "instrument", "effect", "midi_effect"
    public var isBypassed: Bool = false
    public var currentPreset: String?
    public var parameters: [PluginParam]

    public init(slotIndex: Int, name: String, manufacturer: String, type: String, parameters: [PluginParam] = []) {
        self.slotIndex = slotIndex
        self.name = name
        self.manufacturer = manufacturer
        self.type = type
        self.parameters = parameters
    }
}

// MARK: - Plugin Parameter

public struct PluginParam: Codable, Sendable {
    public let id: Int
    public let name: String
    public var value: Double
    public let minValue: Double
    public let maxValue: Double
    public let unit: String
    public var displayValue: String
}

// MARK: - Available Plugin Info

public struct AvailablePlugin: Codable, Sendable {
    public let name: String
    public let manufacturer: String
    public let type: String  // "instrument", "effect", "midi_effect"
    public let componentType: String  // "aumu", "aufx", "aumi"
}

// MARK: - Track Automation

public struct TrackAutomation: Codable, Sendable {
    public let trackIndex: Int
    public var mode: String
    public var lanes: [AutomationLane]

    public init(trackIndex: Int, mode: String = "off", lanes: [AutomationLane] = []) {
        self.trackIndex = trackIndex
        self.mode = mode
        self.lanes = lanes
    }
}

// MARK: - Automation Lane

public struct AutomationLane: Codable, Sendable {
    public let parameter: String
    public var points: [AutomationPoint]
}

// MARK: - Automation Point

public struct AutomationPoint: Codable, Sendable {
    public let position: String      // bars.beats.divisions.ticks
    public let value: Double          // normalized 0.0-1.0
    public var displayValue: String   // "-6.0 dB", "L32"
    public var curveType: String      // "linear", "curved"
}

// MARK: - Track Regions

public struct TrackRegions: Codable, Sendable {
    public let trackIndex: Int
    public var regions: [RegionInfo]

    public init(trackIndex: Int, regions: [RegionInfo] = []) {
        self.trackIndex = trackIndex
        self.regions = regions
    }
}

// MARK: - Region Info

public struct RegionInfo: Codable, Sendable {
    public let index: Int
    public var name: String
    public var type: String  // "midi", "audio", "drummer", "pattern"
    public var position: String
    public var length: String
    public var isSelected: Bool = false
}

// MARK: - MIDI Note Event

public struct MIDINoteEvent: Codable, Sendable {
    public let note: Int        // 0-127
    public let name: String     // "C4", "F#3"
    public let velocity: Int
    public let position: String
    public let duration: String
    public let channel: Int     // 1-16
}
