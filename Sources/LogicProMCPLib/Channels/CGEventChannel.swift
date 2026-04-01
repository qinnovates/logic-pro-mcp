import ApplicationServices
import AppKit
import Foundation

/// Sends keyboard shortcuts to Logic Pro via CGEvent,
/// simulating the user pressing key commands.
public actor CGEventChannel: Channel {

    // MARK: - Channel Protocol

    public nonisolated let name: String = "CGEvent"

    public var isAvailable: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Types

    struct KeyBinding: Codable, Sendable {
        let keyCode: UInt16
        let modifiers: [String]
    }

    // MARK: - Properties

    private let keyRepeatDelay: TimeInterval
    private var bindings: [String: [String: KeyBinding]] = [:]

    // MARK: - Default Bindings

    private static let defaultBindings: [String: [String: KeyBinding]] = [
        "transport": [
            "play":            KeyBinding(keyCode: 49, modifiers: []),
            "stop":            KeyBinding(keyCode: 49, modifiers: []),
            "record":          KeyBinding(keyCode: 15, modifiers: []),
            "rewind":          KeyBinding(keyCode: 44, modifiers: []),
            "forward":         KeyBinding(keyCode: 47, modifiers: []),
            "toggleCycle":     KeyBinding(keyCode: 8, modifiers: []),
            "toggleMetronome": KeyBinding(keyCode: 42, modifiers: ["command"]),
        ],
        "edit": [
            "undo":     KeyBinding(keyCode: 6, modifiers: ["command"]),
            "redo":     KeyBinding(keyCode: 6, modifiers: ["command", "shift"]),
            "copy":     KeyBinding(keyCode: 8, modifiers: ["command"]),
            "paste":    KeyBinding(keyCode: 9, modifiers: ["command"]),
            "delete":   KeyBinding(keyCode: 51, modifiers: []),
            "quantize": KeyBinding(keyCode: 12, modifiers: ["command", "option"]),
        ],
        "navigate": [
            "zoomIn":     KeyBinding(keyCode: 24, modifiers: ["command"]),
            "zoomOut":    KeyBinding(keyCode: 27, modifiers: ["command"]),
            "showMixer":  KeyBinding(keyCode: 7, modifiers: ["command"]),
            "showEditor": KeyBinding(keyCode: 4, modifiers: ["command"]),
        ],
        "project": [
            "save":   KeyBinding(keyCode: 1, modifiers: ["command"]),
            "new":    KeyBinding(keyCode: 45, modifiers: ["command"]),
            "open":   KeyBinding(keyCode: 31, modifiers: ["command"]),
            "close":  KeyBinding(keyCode: 13, modifiers: ["command"]),
            "bounce": KeyBinding(keyCode: 11, modifiers: ["command"]),
        ],
    ]

    // MARK: - Init

    public init(config: ServerConfig) async {
        self.keyRepeatDelay = config.cgEventKeyRepeatDelay
        self.bindings = Self.defaultBindings
        loadKeybindings(from: config.keybindingsFilePath)
    }

    // MARK: - Keybinding Loading

    private func loadKeybindings(from path: String) {
        // Try bundled resource first, then user config path
        let paths = [
            Bundle.module.url(forResource: "keybindings", withExtension: "json")?.path,
            path,
        ].compactMap { $0 }

        for filePath in paths {
            guard FileManager.default.fileExists(atPath: filePath),
                  let data = FileManager.default.contents(atPath: filePath) else {
                continue
            }

            do {
                let decoded = try JSONDecoder().decode(
                    [String: [String: KeyBinding]].self,
                    from: data
                )
                // Merge loaded bindings over defaults
                for (domain, domainBindings) in decoded {
                    if bindings[domain] != nil {
                        for (action, binding) in domainBindings {
                            bindings[domain]?[action] = binding
                        }
                    } else {
                        bindings[domain] = domainBindings
                    }
                }
                fputs("[CGEvent] Loaded keybindings from \(filePath)\n", stderr)
                return
            } catch {
                fputs("[CGEvent] Failed to parse keybindings at \(filePath): \(error)\n", stderr)
            }
        }

        fputs("[CGEvent] Using default keybindings\n", stderr)
    }

    // MARK: - Send

    public func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        switch operation {
        case .transport(let op):
            return await handleTransport(op)
        case .edit(let op):
            return await handleEdit(op)
        case .navigate(let op):
            return await handleNavigate(op)
        case .project(let op):
            return await handleProject(op)
        default:
            return .fail("CGEvent does not handle \(operation)")
        }
    }

    // MARK: - Transport

    private func handleTransport(_ op: TransportOp) async -> ChannelResult {
        let actionKey: String
        switch op {
        case .play:            actionKey = "play"
        case .stop:            actionKey = "stop"
        case .record:          actionKey = "record"
        case .rewind:          actionKey = "rewind"
        case .forward:         actionKey = "forward"
        case .toggleCycle:     actionKey = "toggleCycle"
        case .toggleMetronome: actionKey = "toggleMetronome"
        case .pause:           actionKey = "stop"  // Logic uses space for both
        default:
            return .fail("CGEvent cannot handle transport operation: \(op)")
        }

        return await sendBinding(domain: "transport", action: actionKey)
    }

    // MARK: - Edit

    private func handleEdit(_ op: EditOp) async -> ChannelResult {
        let actionKey: String
        switch op {
        case .undo:            actionKey = "undo"
        case .redo:            actionKey = "redo"
        case .copy:            actionKey = "copy"
        case .paste:           actionKey = "paste"
        case .deleteSelection: actionKey = "delete"
        case .quantize:        actionKey = "quantize"
        default:
            return .fail("CGEvent has no keybinding for edit operation: \(op)")
        }

        return await sendBinding(domain: "edit", action: actionKey)
    }

    // MARK: - Navigate

    private func handleNavigate(_ op: NavigateOp) async -> ChannelResult {
        let actionKey: String
        switch op {
        case .zoomIn:      actionKey = "zoomIn"
        case .zoomOut:     actionKey = "zoomOut"
        case .showMixer:   actionKey = "showMixer"
        case .showEditor:  actionKey = "showEditor"
        default:
            return .fail("CGEvent has no keybinding for navigate operation: \(op)")
        }

        return await sendBinding(domain: "navigate", action: actionKey)
    }

    // MARK: - Project

    private func handleProject(_ op: ProjectOp) async -> ChannelResult {
        let actionKey: String
        switch op {
        case .save:   actionKey = "save"
        case .new:    actionKey = "new"
        case .close:  actionKey = "close"
        case .bounce: actionKey = "bounce"
        default:
            return .fail("CGEvent has no keybinding for project operation: \(op)")
        }

        return await sendBinding(domain: "project", action: actionKey)
    }

    // MARK: - Key Sending

    private func sendBinding(domain: String, action: String) async -> ChannelResult {
        guard let binding = bindings[domain]?[action] else {
            return .fail("No keybinding found for \(domain).\(action)")
        }

        return await sendKeyPress(keyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    private func sendKeyPress(keyCode: UInt16, modifiers: [String]) async -> ChannelResult {
        // Activate Logic Pro first
        guard activateLogicPro() else {
            return .fail("Could not activate Logic Pro")
        }

        // Small delay to let Logic activate
        try? await Task.sleep(nanoseconds: 50_000_000)  // 50ms

        let flags = modifierFlags(from: modifiers)

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return .fail("Failed to create CGEvent")
        }

        keyDown.flags = flags
        keyUp.flags = flags

        keyDown.post(tap: .cgAnnotatedSessionEventTap)

        // Small delay between key down and key up
        try? await Task.sleep(nanoseconds: UInt64(keyRepeatDelay * 1_000_000_000))

        keyUp.post(tap: .cgAnnotatedSessionEventTap)

        return .ok(["keyCode": "\(keyCode)", "modifiers": modifiers.joined(separator: "+")])
    }

    // MARK: - Helpers

    private func activateLogicPro() -> Bool {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: ServerConfig.logicProBundleID
        ).first else {
            return false
        }
        return app.activate()
    }

    private func modifierFlags(from modifiers: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        for mod in modifiers {
            switch mod.lowercased() {
            case "command", "cmd":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "control", "ctrl":
                flags.insert(.maskControl)
            default:
                break
            }
        }
        return flags
    }
}
