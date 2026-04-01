import AVFoundation
import Foundation

/// Discovers installed Audio Unit plugins using AVAudioUnitComponentManager.
/// This is a system-level query that works without Logic Pro running.
public struct PluginDiscovery: Sendable {

    /// List all available Audio Unit plugins on the system.
    /// Filters to instrument (aumu), effect (aufx), and MIDI processor (aumi) types.
    public static func listAvailable() -> [AvailablePlugin] {
        let manager = AVAudioUnitComponentManager.shared()
        var plugins: [AvailablePlugin] = []

        let componentTypes: [(AudioComponentDescription, String)] = [
            (audioComponentDescription(type: kAudioUnitType_MusicDevice), "instrument"),
            (audioComponentDescription(type: kAudioUnitType_Effect), "effect"),
            (audioComponentDescription(type: kAudioUnitType_MIDIProcessor), "midi_effect"),
        ]

        for (description, typeName) in componentTypes {
            let components = manager.components(matching: description)
            for component in components {
                let fourCC = fourCharCode(component.audioComponentDescription.componentType)
                plugins.append(AvailablePlugin(
                    name: component.name,
                    manufacturer: component.manufacturerName,
                    type: typeName,
                    componentType: fourCC
                ))
            }
        }

        return plugins.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Search available plugins by name (case-insensitive partial match).
    public static func search(query: String) -> [AvailablePlugin] {
        let lowered = query.lowercased()
        return listAvailable().filter {
            $0.name.lowercased().contains(lowered) ||
            $0.manufacturer.lowercased().contains(lowered)
        }
    }

    // MARK: - Helpers

    private static func audioComponentDescription(type: OSType) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: type,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    private static func fourCharCode(_ value: OSType) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
