import Foundation
import MCP

extension LogicProServer {

    static func allToolsV2() -> [Tool] {
        [
            audioAnalyzeTool,
            pluginTool,
            automationTool,
            midiEditTool,
        ]
    }

    // MARK: - Audio Analyze

    private static var audioAnalyzeTool: Tool {
        Tool(
            name: "audio_analyze",
            description: "Analyze an audio file for loudness, peak levels, LUFS, true peak, and spectral content",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Absolute path to the audio file"),
                    ]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: .init(
                title: "Audio Analysis",
                readOnlyHint: true,
                openWorldHint: false
            )
        )
    }

    // MARK: - Plugin

    private static var pluginTool: Tool {
        Tool(
            name: "plugin",
            description: "Manage Audio Unit plugins on tracks (list available, insert, remove, get/set parameters, presets)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("list_available"), .string("insert"), .string("remove"),
                            .string("get_params"), .string("set_param"),
                            .string("load_preset"), .string("list_presets"),
                        ]),
                        "description": .string("The plugin action to perform"),
                    ]),
                    "track_index": .object([
                        "type": .string("integer"),
                        "description": .string("Track index (0-based)"),
                    ]),
                    "slot_index": .object([
                        "type": .string("integer"),
                        "description": .string("Plugin slot index (0-based)"),
                    ]),
                    "plugin_name": .object([
                        "type": .string("string"),
                        "description": .string("Plugin name (for insert)"),
                    ]),
                    "param_name": .object([
                        "type": .string("string"),
                        "description": .string("Parameter name (for set_param)"),
                    ]),
                    "param_value": .object([
                        "type": .string("number"),
                        "description": .string("Parameter value (for set_param)"),
                    ]),
                    "preset_name": .object([
                        "type": .string("string"),
                        "description": .string("Preset name (for load_preset)"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "Plugin Management",
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - Automation

    private static var automationTool: Tool {
        Tool(
            name: "automation",
            description: "Read and write track automation (mode, points, parameters)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("get_mode"), .string("set_mode"),
                            .string("add_point"), .string("get_points"),
                            .string("clear"), .string("list_parameters"),
                        ]),
                        "description": .string("The automation action to perform"),
                    ]),
                    "track_index": .object([
                        "type": .string("integer"),
                        "description": .string("Track index (0-based)"),
                    ]),
                    "parameter": .object([
                        "type": .string("string"),
                        "description": .string("Automation parameter name (volume, pan, or plugin param)"),
                    ]),
                    "mode": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("off"), .string("read"), .string("touch"),
                            .string("latch"), .string("write"),
                        ]),
                        "description": .string("Automation mode (for set_mode)"),
                    ]),
                    "position": .object([
                        "type": .string("string"),
                        "description": .string("Position as bars.beats.divisions.ticks"),
                    ]),
                    "value": .object([
                        "type": .string("number"),
                        "description": .string("Normalized value 0.0-1.0 (for add_point)"),
                    ]),
                    "curve": .object([
                        "type": .string("string"),
                        "enum": .array([.string("linear"), .string("curved")]),
                        "description": .string("Curve type for automation point"),
                    ]),
                ]),
                "required": .array([.string("action"), .string("track_index")]),
            ]),
            annotations: .init(
                title: "Automation Control",
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }

    // MARK: - MIDI Edit

    private static var midiEditTool: Tool {
        Tool(
            name: "midi_edit",
            description: "Edit MIDI regions and notes in the piano roll (list regions, get/add/delete notes, quantize)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("list_regions"), .string("get_notes"),
                            .string("add_note"), .string("delete_note"),
                            .string("move_note"), .string("set_velocity"),
                            .string("quantize"),
                        ]),
                        "description": .string("The MIDI edit action to perform"),
                    ]),
                    "track_index": .object([
                        "type": .string("integer"),
                        "description": .string("Track index (0-based)"),
                    ]),
                    "region_index": .object([
                        "type": .string("integer"),
                        "description": .string("Region index within the track"),
                    ]),
                    "note": .object([
                        "type": .string("integer"),
                        "description": .string("MIDI note number 0-127"),
                    ]),
                    "velocity": .object([
                        "type": .string("integer"),
                        "description": .string("Note velocity 0-127"),
                    ]),
                    "position": .object([
                        "type": .string("string"),
                        "description": .string("Note position as bars.beats.divisions.ticks"),
                    ]),
                    "duration": .object([
                        "type": .string("string"),
                        "description": .string("Note duration in beats (e.g. '1.0', '0.5', '0.25')"),
                    ]),
                    "quantize_value": .object([
                        "type": .string("string"),
                        "enum": .array([
                            .string("1/4"), .string("1/8"), .string("1/16"),
                            .string("1/32"), .string("1/6"), .string("1/12"),
                        ]),
                        "description": .string("Quantize grid value"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(
                title: "MIDI Region Editing",
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        )
    }
}
