import Foundation
import MCP

extension LogicProServer {

    // MARK: - Transport

    static func handleTransport(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let op: TransportOp
        switch actionStr {
        case "play":             op = .play
        case "stop":             op = .stop
        case "record":           op = .record
        case "pause":            op = .pause
        case "rewind":           op = .rewind
        case "forward":          op = .forward
        case "toggle_cycle":     op = .toggleCycle
        case "toggle_metronome": op = .toggleMetronome
        case "set_bpm":
            guard let bpm = Double(args["value"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing or invalid 'value' for set_bpm")], isError: true)
            }
            op = .setBPM(bpm)
        case "set_position":
            let bars = Int(args["bars"] ?? .null) ?? 1
            let beats = Int(args["beats"] ?? .null) ?? 1
            let ticks = Int(args["ticks"] ?? .null) ?? 0
            op = .setPosition(bars: bars, beats: beats, ticks: ticks)
        default:
            return CallTool.Result(content: [.text("Unknown transport action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.transport(op))
        await cache.markDirty(.transport)
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Track

    static func handleTrack(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let op: TrackOp
        switch actionStr {
        case "create":
            let type = args["type"]?.stringValue ?? "software_instrument"
            op = .create(type: type)
        case "delete":
            guard let idx = Int(args["index"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'index' for delete")], isError: true)
            }
            op = .delete(index: idx)
        case "rename":
            guard let idx = Int(args["index"] ?? .null),
                  let name = args["name"]?.stringValue else {
                return CallTool.Result(content: [.text("Missing 'index' or 'name' for rename")], isError: true)
            }
            op = .rename(index: idx, name: name)
        case "select":
            guard let idx = Int(args["index"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'index' for select")], isError: true)
            }
            op = .select(index: idx)
        case "mute":
            guard let idx = Int(args["index"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'index' for mute")], isError: true)
            }
            let state = Bool(args["state"] ?? .bool(true)) ?? true
            op = .mute(index: idx, state: state)
        case "solo":
            guard let idx = Int(args["index"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'index' for solo")], isError: true)
            }
            let state = Bool(args["state"] ?? .bool(true)) ?? true
            op = .solo(index: idx, state: state)
        case "arm":
            guard let idx = Int(args["index"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'index' for arm")], isError: true)
            }
            let state = Bool(args["state"] ?? .bool(true)) ?? true
            op = .arm(index: idx, state: state)
        default:
            return CallTool.Result(content: [.text("Unknown track action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.track(op))
        await cache.markDirty(.tracks)
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Mixer

    static func handleMixer(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }
        guard let channel = Int(args["channel"] ?? .null) else {
            return CallTool.Result(content: [.text("Missing required parameter: channel")], isError: true)
        }

        let op: MixerOp
        switch actionStr {
        case "set_volume":
            guard let val = Double(args["value"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'value' for set_volume")], isError: true)
            }
            op = .setVolume(channel: channel, value: val)
        case "set_pan":
            guard let val = Double(args["value"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'value' for set_pan")], isError: true)
            }
            op = .setPan(channel: channel, value: val)
        case "set_mute":
            let state = Bool(args["state"] ?? .bool(true)) ?? true
            op = .setMute(channel: channel, state: state)
        default:
            return CallTool.Result(content: [.text("Unknown mixer action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.mixer(op))
        await cache.markDirty(.mixer)
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - MIDI

    static func handleMIDI(
        args: [String: Value], router: ChannelRouter
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let ch = UInt8(clamping: Int(args["channel"] ?? .int(1)) ?? 1)
        let midiChannel = max(1, min(16, ch)) - 1

        let op: MIDIOp
        switch actionStr {
        case "note":
            let note = UInt8(clamping: Int(args["note"] ?? .int(60)) ?? 60)
            let vel = UInt8(clamping: Int(args["velocity"] ?? .int(100)) ?? 100)
            let dur = Double(args["duration"] ?? .double(0.5)) ?? 0.5
            op = .sendNote(note: note, velocity: vel, channel: midiChannel, duration: dur)
        case "cc":
            let ctrl = UInt8(clamping: Int(args["controller"] ?? .int(1)) ?? 1)
            let val = UInt8(clamping: Int(args["value"] ?? .int(64)) ?? 64)
            op = .sendCC(controller: ctrl, value: val, channel: midiChannel)
        case "program_change":
            let prog = UInt8(clamping: Int(args["value"] ?? .int(0)) ?? 0)
            op = .sendProgramChange(program: prog, channel: midiChannel)
        case "pitch_bend":
            let val = UInt16(clamping: Int(args["value"] ?? .int(8192)) ?? 8192)
            op = .sendPitchBend(value: val, channel: midiChannel)
        default:
            return CallTool.Result(content: [.text("Unknown MIDI action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.midi(op))
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Edit

    static func handleEdit(
        args: [String: Value], router: ChannelRouter
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let op: EditOp
        switch actionStr {
        case "undo":     op = .undo
        case "redo":     op = .redo
        case "quantize": op = .quantize
        case "split":    op = .split
        case "join":     op = .join
        case "copy":     op = .copy
        case "paste":    op = .paste
        case "delete":   op = .deleteSelection
        default:
            return CallTool.Result(content: [.text("Unknown edit action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.edit(op))
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Navigate

    static func handleNavigate(
        args: [String: Value], router: ChannelRouter
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let op: NavigateOp
        switch actionStr {
        case "goto_bar":
            guard let bar = Int(args["bar"] ?? .null) else {
                return CallTool.Result(content: [.text("Missing 'bar' for goto_bar")], isError: true)
            }
            op = .gotoBar(bar)
        case "goto_marker":
            guard let name = args["name"]?.stringValue else {
                return CallTool.Result(content: [.text("Missing 'name' for goto_marker")], isError: true)
            }
            op = .gotoMarker(name)
        case "create_marker":
            guard let name = args["name"]?.stringValue else {
                return CallTool.Result(content: [.text("Missing 'name' for create_marker")], isError: true)
            }
            op = .createMarker(name)
        case "zoom_in":         op = .zoomIn
        case "zoom_out":        op = .zoomOut
        case "show_mixer":      op = .showMixer
        case "show_editor":     op = .showEditor
        case "show_automation": op = .showAutomation
        default:
            return CallTool.Result(content: [.text("Unknown navigate action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.navigate(op))
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Project

    static func handleProject(
        args: [String: Value], router: ChannelRouter
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let op: ProjectOp
        switch actionStr {
        case "new":   op = .new
        case "save":  op = .save
        case "close": op = .close
        case "bounce": op = .bounce
        case "open":
            guard let path = args["path"]?.stringValue else {
                return CallTool.Result(content: [.text("Missing 'path' for open")], isError: true)
            }
            guard !path.contains("..") else {
                return CallTool.Result(content: [.text("Invalid path: directory traversal not allowed")], isError: true)
            }
            op = .open(path: path)
        default:
            return CallTool.Result(content: [.text("Unknown project action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.project(op))
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - System

    static func handleSystem(
        args: [String: Value], router: ChannelRouter, cache: StateCache
    ) async throws -> CallTool.Result {
        guard let actionStr = args["action"]?.stringValue else {
            return CallTool.Result(content: [.text("Missing required parameter: action")], isError: true)
        }

        let op: SystemOp
        switch actionStr {
        case "health":      op = .healthCheck
        case "permissions": op = .checkPermissions
        default:
            return CallTool.Result(content: [.text("Unknown system action: \(actionStr)")], isError: true)
        }

        let result = try await router.route(.system(op))
        return callToolResult(from: result, action: actionStr)
    }

    // MARK: - Result Conversion

    static func callToolResult(from result: ChannelResult, action: String) -> CallTool.Result {
        if result.success {
            var parts: [String] = ["\(action): OK"]
            for (key, value) in result.data.sorted(by: { $0.key < $1.key }) {
                parts.append("\(key): \(value)")
            }
            return CallTool.Result(content: [.text(parts.joined(separator: "\n"))])
        } else {
            return CallTool.Result(
                content: [.text("\(action) failed: \(result.error ?? "Unknown error")")],
                isError: true
            )
        }
    }
}
