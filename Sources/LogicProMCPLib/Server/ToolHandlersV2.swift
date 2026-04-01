import Foundation
import MCP

extension LogicProServer {

    // MARK: - Audio Analyze

    static func handleAudioAnalyze(
        args: [String: Value]
    ) async throws -> CallTool.Result {
        guard let path = args["path"]?.stringValue else {
            return CallTool.Result(
                content: [.text(text: "Missing required parameter: path")],
                isError: true
            )
        }

        guard !path.contains("..") else {
            return CallTool.Result(
                content: [.text(text: "Invalid path: directory traversal not allowed")],
                isError: true
            )
        }

        guard path.hasPrefix("/") else {
            return CallTool.Result(
                content: [.text(text: "Path must be absolute")],
                isError: true
            )
        }

        do {
            let result = try await AudioAnalyzer.analyze(fileAt: path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = try encoder.encode(result)
            let jsonStr = String(data: json, encoding: .utf8) ?? "{}"
            return CallTool.Result(content: [.text(text: jsonStr)])
        } catch {
            return CallTool.Result(
                content: [.text(text: "Audio analysis failed: \(error.localizedDescription)")],
                isError: true
            )
        }
    }

    // MARK: - Plugin

    static func handlePlugin(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(
                content: [.text(text: "Missing required parameter: action")],
                isError: true
            )
        }

        let op: PluginOp
        switch actionStr {
        case "list_available":
            op = .listAvailable
        case "insert":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let rawPluginName = args["plugin_name"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' or 'plugin_name' for insert")],
                    isError: true
                )
            }
            guard let pluginName = InputSanitizer.sanitizeName(rawPluginName) else {
                return CallTool.Result(
                    content: [.text(text: "Invalid plugin_name: contains disallowed characters or is too long")],
                    isError: true
                )
            }
            let slotIdx = Int(args["slot_index"] ?? .null)
            op = .insert(trackIndex: trackIdx, pluginName: pluginName, slotIndex: slotIdx)
        case "remove":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let slotIdx = Int(args["slot_index"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' or 'slot_index' for remove")],
                    isError: true
                )
            }
            op = .remove(trackIndex: trackIdx, slotIndex: slotIdx)
        case "get_params":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let slotIdx = Int(args["slot_index"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' or 'slot_index' for get_params")],
                    isError: true
                )
            }
            op = .getParams(trackIndex: trackIdx, slotIndex: slotIdx)
        case "set_param":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let slotIdx = Int(args["slot_index"] ?? .null),
                  let rawParamName = args["param_name"]?.stringValue,
                  let paramValue = Double(args["param_value"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing required params for set_param")],
                    isError: true
                )
            }
            guard let paramName = InputSanitizer.sanitizeName(rawParamName) else {
                return CallTool.Result(
                    content: [.text(text: "Invalid param_name: contains disallowed characters or is too long")],
                    isError: true
                )
            }
            op = .setParam(trackIndex: trackIdx, slotIndex: slotIdx, paramName: paramName, value: paramValue)
        case "load_preset":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let slotIdx = Int(args["slot_index"] ?? .null),
                  let rawPresetName = args["preset_name"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing required params for load_preset")],
                    isError: true
                )
            }
            guard let presetName = InputSanitizer.sanitizeName(rawPresetName) else {
                return CallTool.Result(
                    content: [.text(text: "Invalid preset_name: contains disallowed characters or is too long")],
                    isError: true
                )
            }
            op = .loadPreset(trackIndex: trackIdx, slotIndex: slotIdx, presetName: presetName)
        case "list_presets":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let slotIdx = Int(args["slot_index"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' or 'slot_index' for list_presets")],
                    isError: true
                )
            }
            op = .listPresets(trackIndex: trackIdx, slotIndex: slotIdx)
        default:
            return CallTool.Result(
                content: [.text(text: "Unknown plugin action: \(actionStr)")],
                isError: true
            )
        }

        let result = try await router.route(.plugin(op))
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Automation

    static func handleAutomation(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(
                content: [.text(text: "Missing required parameter: action")],
                isError: true
            )
        }
        guard let trackIdx = Int(args["track_index"] ?? .null) else {
            return CallTool.Result(
                content: [.text(text: "Missing required parameter: track_index")],
                isError: true
            )
        }

        let op: AutomationOp
        switch actionStr {
        case "get_mode":
            op = .getMode(trackIndex: trackIdx)
        case "set_mode":
            guard let mode = args["mode"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'mode' for set_mode")],
                    isError: true
                )
            }
            op = .setMode(trackIndex: trackIdx, mode: mode)
        case "add_point":
            guard let param = args["parameter"]?.stringValue,
                  let position = args["position"]?.stringValue,
                  let value = Double(args["value"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'parameter', 'position', or 'value' for add_point")],
                    isError: true
                )
            }
            let curve = args["curve"]?.stringValue ?? "linear"
            op = .addPoint(trackIndex: trackIdx, parameter: param, position: position, value: value, curve: curve)
        case "get_points":
            guard let param = args["parameter"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'parameter' for get_points")],
                    isError: true
                )
            }
            op = .getPoints(trackIndex: trackIdx, parameter: param)
        case "clear":
            guard let param = args["parameter"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'parameter' for clear")],
                    isError: true
                )
            }
            op = .clear(trackIndex: trackIdx, parameter: param)
        case "list_parameters":
            op = .listParameters(trackIndex: trackIdx)
        default:
            return CallTool.Result(
                content: [.text(text: "Unknown automation action: \(actionStr)")],
                isError: true
            )
        }

        let result = try await router.route(.automation(op))
        await cache.markDirty(.tracks)
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - MIDI Edit

    static func handleMIDIEdit(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(
                content: [.text(text: "Missing required parameter: action")],
                isError: true
            )
        }

        let op: MIDIEditOp
        switch actionStr {
        case "list_regions":
            guard let trackIdx = Int(args["track_index"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' for list_regions")],
                    isError: true
                )
            }
            op = .listRegions(trackIndex: trackIdx)
        case "get_notes":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let regionIdx = Int(args["region_index"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' or 'region_index' for get_notes")],
                    isError: true
                )
            }
            op = .getNotes(trackIndex: trackIdx, regionIndex: regionIdx)
        case "add_note":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let regionIdx = Int(args["region_index"] ?? .null),
                  let note = Int(args["note"] ?? .null),
                  let velocity = Int(args["velocity"] ?? .null),
                  let position = args["position"]?.stringValue,
                  let duration = args["duration"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing required params for add_note")],
                    isError: true
                )
            }
            op = .addNote(
                trackIndex: trackIdx, regionIndex: regionIdx,
                note: UInt8(clamping: note), velocity: UInt8(clamping: velocity),
                position: position, duration: duration
            )
        case "delete_note":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let regionIdx = Int(args["region_index"] ?? .null),
                  let note = Int(args["note"] ?? .null),
                  let position = args["position"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing required params for delete_note")],
                    isError: true
                )
            }
            op = .deleteNote(trackIndex: trackIdx, regionIndex: regionIdx, note: UInt8(clamping: note), position: position)
        case "move_note":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let regionIdx = Int(args["region_index"] ?? .null),
                  let note = Int(args["note"] ?? .null),
                  let position = args["position"]?.stringValue else {
                return CallTool.Result(
                    content: [.text(text: "Missing required params for move_note")],
                    isError: true
                )
            }
            let newNote = Int(args["new_note"] ?? .null) ?? note
            let newPosition = args["new_position"]?.stringValue ?? position
            op = .moveNote(
                trackIndex: trackIdx, regionIndex: regionIdx,
                note: UInt8(clamping: note), position: position,
                newNote: UInt8(clamping: newNote), newPosition: newPosition
            )
        case "set_velocity":
            guard let trackIdx = Int(args["track_index"] ?? .null),
                  let regionIdx = Int(args["region_index"] ?? .null),
                  let note = Int(args["note"] ?? .null),
                  let position = args["position"]?.stringValue,
                  let velocity = Int(args["velocity"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing required params for set_velocity")],
                    isError: true
                )
            }
            op = .setVelocity(
                trackIndex: trackIdx, regionIndex: regionIdx,
                note: UInt8(clamping: note), position: position,
                velocity: UInt8(clamping: velocity)
            )
        case "quantize":
            guard let trackIdx = Int(args["track_index"] ?? .null) else {
                return CallTool.Result(
                    content: [.text(text: "Missing 'track_index' for quantize")],
                    isError: true
                )
            }
            let regionIdx = Int(args["region_index"] ?? .null)
            let quantizeValue = args["quantize_value"]?.stringValue ?? "1/8"
            op = .quantize(trackIndex: trackIdx, regionIndex: regionIdx, quantizeValue: quantizeValue)
        default:
            return CallTool.Result(
                content: [.text(text: "Unknown midi_edit action: \(actionStr)")],
                isError: true
            )
        }

        let result = try await router.route(.midiEdit(op))
        return callToolResult(from: result, action: actionStr)
    }
}
