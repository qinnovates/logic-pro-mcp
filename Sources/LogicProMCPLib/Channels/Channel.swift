import Foundation

// MARK: - Channel Protocol

/// A communication channel to Logic Pro. Each channel uses a different
/// macOS subsystem (CoreMIDI, Accessibility, CGEvent, AppleScript, OSC).
public protocol Channel: Actor {
    var name: String { get }
    var isAvailable: Bool { get async }
    func send(_ operation: ChannelOperation) async throws -> ChannelResult
}

// MARK: - Channel Operation

/// Every action the MCP server can perform on Logic Pro,
/// grouped by domain.
public enum ChannelOperation: Sendable {
    case transport(TransportOp)
    case track(TrackOp)
    case mixer(MixerOp)
    case midi(MIDIOp)
    case edit(EditOp)
    case navigate(NavigateOp)
    case project(ProjectOp)
    case system(SystemOp)
    case plugin(PluginOp)
    case automation(AutomationOp)
    case midiEdit(MIDIEditOp)
}

// MARK: - Transport

public enum TransportOp: Sendable {
    case play
    case stop
    case record
    case pause
    case rewind
    case forward
    case setBPM(Double)
    case setPosition(bars: Int, beats: Int, ticks: Int)
    case toggleCycle
    case toggleMetronome
}

// MARK: - Track

public enum TrackOp: Sendable {
    case create(type: String)
    case delete(index: Int)
    case rename(index: Int, name: String)
    case select(index: Int)
    case mute(index: Int, state: Bool)
    case solo(index: Int, state: Bool)
    case arm(index: Int, state: Bool)
}

// MARK: - Mixer

public enum MixerOp: Sendable {
    case setVolume(channel: Int, value: Double)
    case setPan(channel: Int, value: Double)
    case setMute(channel: Int, state: Bool)
}

// MARK: - MIDI

public enum MIDIOp: Sendable {
    case sendNote(note: UInt8, velocity: UInt8, channel: UInt8, duration: Double)
    case sendCC(controller: UInt8, value: UInt8, channel: UInt8)
    case sendProgramChange(program: UInt8, channel: UInt8)
    case sendPitchBend(value: UInt16, channel: UInt8)
}

// MARK: - Edit

public enum EditOp: Sendable {
    case undo
    case redo
    case quantize
    case split
    case join
    case copy
    case paste
    case deleteSelection
}

// MARK: - Navigate

public enum NavigateOp: Sendable {
    case gotoBar(Int)
    case gotoMarker(String)
    case createMarker(String)
    case zoomIn
    case zoomOut
    case showMixer
    case showEditor
    case showAutomation
}

// MARK: - Project

public enum ProjectOp: Sendable {
    case new
    case open(path: String)
    case save
    case close
    case bounce
}

// MARK: - System

public enum SystemOp: Sendable {
    case healthCheck
    case checkPermissions
}

// MARK: - Plugin

public enum PluginOp: Sendable {
    case listAvailable
    case insert(trackIndex: Int, pluginName: String, slotIndex: Int?)
    case remove(trackIndex: Int, slotIndex: Int)
    case getParams(trackIndex: Int, slotIndex: Int)
    case setParam(trackIndex: Int, slotIndex: Int, paramName: String, value: Double)
    case loadPreset(trackIndex: Int, slotIndex: Int, presetName: String)
    case listPresets(trackIndex: Int, slotIndex: Int)
}

// MARK: - Automation

public enum AutomationOp: Sendable {
    case getMode(trackIndex: Int)
    case setMode(trackIndex: Int, mode: String)
    case addPoint(trackIndex: Int, parameter: String, position: String, value: Double, curve: String)
    case getPoints(trackIndex: Int, parameter: String)
    case clear(trackIndex: Int, parameter: String)
    case listParameters(trackIndex: Int)
}

// MARK: - MIDI Edit

public enum MIDIEditOp: Sendable {
    case listRegions(trackIndex: Int)
    case getNotes(trackIndex: Int, regionIndex: Int)
    case addNote(trackIndex: Int, regionIndex: Int, note: UInt8, velocity: UInt8, position: String, duration: String)
    case deleteNote(trackIndex: Int, regionIndex: Int, note: UInt8, position: String)
    case moveNote(trackIndex: Int, regionIndex: Int, note: UInt8, position: String, newNote: UInt8, newPosition: String)
    case setVelocity(trackIndex: Int, regionIndex: Int, note: UInt8, position: String, velocity: UInt8)
    case quantize(trackIndex: Int, regionIndex: Int?, quantizeValue: String)
}

// MARK: - Channel Result

/// Uniform result type returned by every channel operation.
public struct ChannelResult: Sendable {
    public let success: Bool
    public let data: [String: String]
    public let error: String?

    public static func ok(_ data: [String: String] = [:]) -> ChannelResult {
        ChannelResult(success: true, data: data, error: nil)
    }

    public static func fail(_ error: String) -> ChannelResult {
        ChannelResult(success: false, data: [:], error: error)
    }
}
