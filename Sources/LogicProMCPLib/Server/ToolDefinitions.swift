import Foundation
import MCP

extension LogicProServer {

    static func allTools() -> [Tool] {
        [
            transportTool,
            trackTool,
            mixerTool,
            midiSendTool,
            editTool,
            navigateTool,
            projectTool,
            systemTool,
        ]
    }

    // MARK: - Transport

    private static var transportTool: Tool {
        Tool(
            name: "transport",
            description: "Control Logic Pro transport (play, stop, record, set tempo, etc.)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("play"), .string("stop"), .string("record"),
                            .string("pause"), .string("rewind"), .string("forward"),
                            .string("set_bpm"), .string("set_position"),
                            .string("toggle_cycle"), .string("toggle_metronome"),
                        ]),
                        "description": .string("The transport action to perform"),
                    ]),
                    "value": .object([
                        "type": .string("number"),
                        "description": .string("BPM value (for set_bpm)"),
                    ]),
                    "bars": .object([
                        "type": .string("integer"),
                        "description": .string("Bar number (for set_position)"),
                    ]),
                    "beats": .object([
                        "type": .string("integer"),
                        "description": .string("Beat number (for set_position)"),
                    ]),
                    "ticks": .object([
                        "type": .string("integer"),
                        "description": .string("Tick number (for set_position)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "Transport Control",
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - Track

    private static var trackTool: Tool {
        Tool(
            name: "track",
            description: "Manage Logic Pro tracks (create, delete, rename, mute, solo, arm)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("create"), .string("delete"), .string("rename"),
                            .string("select"), .string("mute"), .string("solo"), .string("arm"),
                        ]),
                        "description": .string("The track action to perform"),
                    ]),
                    "index": .object([
                        "type": .string("integer"),
                        "description": .string("Track index (0-based)"),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Track name (for create/rename)"),
                    ]),
                    "type": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("audio"), .string("software_instrument"), .string("drummer"),
                        ]),
                        "description": .string("Track type (for create)"),
                    ]),
                    "state": .object([
                        "type": .string("boolean"),
                        "description": .string("On/off state (for mute/solo/arm)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "Track Management",
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - Mixer

    private static var mixerTool: Tool {
        Tool(
            name: "mixer",
            description: "Control Logic Pro mixer (volume, pan, mute per channel)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("set_volume"), .string("set_pan"), .string("set_mute"),
                        ]),
                        "description": .string("The mixer action to perform"),
                    ]),
                    "channel": .object([
                        "type": .string("integer"),
                        "description": .string("Channel index (0-based)"),
                    ]),
                    "value": .object([
                        "type": .string("number"),
                        "description": .string("Value: dB for volume (-inf to +6), -1.0..1.0 for pan"),
                    ]),
                    "state": .object([
                        "type": .string("boolean"),
                        "description": .string("Mute on/off"),
                    ]),
                ]),
                "required": .array([.string("action"), .string("channel")]),
            ]),
            annotations: .init(
                title: "Mixer Control",
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        )
    }

    // MARK: - MIDI Send

    private static var midiSendTool: Tool {
        Tool(
            name: "midi_send",
            description: "Send MIDI messages to Logic Pro (notes, CC, program change, pitch bend)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("note"), .string("cc"),
                            .string("program_change"), .string("pitch_bend"),
                        ]),
                        "description": .string("MIDI message type"),
                    ]),
                    "note": .object([
                        "type": .string("integer"),
                        "description": .string("MIDI note number 0-127"),
                    ]),
                    "velocity": .object([
                        "type": .string("integer"),
                        "description": .string("Note velocity 0-127"),
                    ]),
                    "controller": .object([
                        "type": .string("integer"),
                        "description": .string("CC controller number 0-127"),
                    ]),
                    "value": .object([
                        "type": .string("integer"),
                        "description": .string("CC value 0-127, program number 0-127, or pitch bend 0-16383"),
                    ]),
                    "channel": .object([
                        "type": .string("integer"),
                        "description": .string("MIDI channel 1-16 (default 1)"),
                    ]),
                    "duration": .object([
                        "type": .string("number"),
                        "description": .string("Note duration in seconds (default 0.5)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "MIDI Output",
                destructiveHint: false,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - Edit

    private static var editTool: Tool {
        Tool(
            name: "edit",
            description: "Edit operations in Logic Pro (undo, redo, quantize, copy, paste, etc.)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("undo"), .string("redo"), .string("quantize"),
                            .string("split"), .string("join"), .string("copy"),
                            .string("paste"), .string("delete"),
                        ]),
                        "description": .string("The edit action to perform"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "Edit Operations",
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - Navigate

    private static var navigateTool: Tool {
        Tool(
            name: "navigate",
            description: "Navigate within Logic Pro (go to bar, markers, zoom, show views)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("goto_bar"), .string("goto_marker"),
                            .string("create_marker"), .string("zoom_in"),
                            .string("zoom_out"), .string("show_mixer"),
                            .string("show_editor"), .string("show_automation"),
                        ]),
                        "description": .string("The navigation action to perform"),
                    ]),
                    "bar": .object([
                        "type": .string("integer"),
                        "description": .string("Bar number (for goto_bar)"),
                    ]),
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Marker name (for goto_marker/create_marker)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "Navigation",
                readOnlyHint: true,
                openWorldHint: false
            )
        )
    }

    // MARK: - Project

    private static var projectTool: Tool {
        Tool(
            name: "project",
            description: "Project-level operations (new, open, save, close, bounce)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("new"), .string("open"), .string("save"),
                            .string("close"), .string("bounce"),
                        ]),
                        "description": .string("The project action to perform"),
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("File path (for open)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "Project Management",
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - System

    private static var systemTool: Tool {
        Tool(
            name: "system",
            description: "System diagnostics (health check, permissions, channel status)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("health"), .string("permissions"),
                        ]),
                        "description": .string("The system query to perform"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "System Diagnostics",
                readOnlyHint: true,
                openWorldHint: false
            )
        )
    }
}
