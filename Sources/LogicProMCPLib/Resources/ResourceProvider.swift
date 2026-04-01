import Foundation
import MCP

/// Centralizes MCP resource definitions for the Logic Pro MCP server.
/// Extracts the resource list from LogicProServer for cleaner organization.
public struct ResourceProvider: Sendable {

    /// Returns all resource definitions exposed by this server.
    public static func allResources() -> [Resource] {
        [
            Resource(
                name: "transport_state",
                uri: "logicpro://state/transport",
                title: "Transport State",
                description: "Current transport state (play/stop/record, tempo, position)",
                mimeType: "application/json"
            ),
            Resource(
                name: "tracks",
                uri: "logicpro://state/tracks",
                title: "Track List",
                description: "All tracks with name, type, mute/solo/arm, volume, pan",
                mimeType: "application/json"
            ),
            Resource(
                name: "mixer",
                uri: "logicpro://state/mixer",
                title: "Mixer State",
                description: "Channel strips with volume, pan, mute, solo, sends",
                mimeType: "application/json"
            ),
            Resource(
                name: "project",
                uri: "logicpro://state/project",
                title: "Project Info",
                description: "Project metadata (name, sample rate, bit depth, tempo)",
                mimeType: "application/json"
            ),
            Resource(
                name: "health",
                uri: "logicpro://system/health",
                title: "System Health",
                description: "Server health, channel status, permissions",
                mimeType: "application/json"
            ),
            Resource(
                name: "midi_ports",
                uri: "logicpro://midi/ports",
                title: "MIDI Ports",
                description: "Available MIDI ports (virtual and hardware)",
                mimeType: "application/json"
            ),
            Resource(
                name: "audio_analysis",
                uri: "logicpro://audio/analysis",
                title: "Audio Analysis",
                description: "Analyze an audio file: RMS, peak, spectral centroid, frequency peaks. Pass 'path' as query parameter.",
                mimeType: "application/json"
            ),
            Resource(
                name: "track_detail",
                uri: "logicpro://state/tracks/detail",
                title: "Track Detail",
                description: "Detailed info for a specific track. Pass 'index' as query parameter.",
                mimeType: "application/json"
            ),
        ]
    }
}
