import ApplicationServices
import AppKit
import Foundation

/// Reads Logic Pro UI state and performs UI actions via the Accessibility (AX) API.
public actor AccessibilityChannel: Channel {

    // MARK: - Channel Protocol

    public nonisolated let name: String = "AX"

    public var isAvailable: Bool {
        AXIsProcessTrusted() && PermissionChecker.isLogicProRunning()
    }

    public init() {}

    // MARK: - Send

    public func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        guard isAvailable else {
            return .fail("Accessibility not available (check permissions and Logic Pro status)")
        }

        switch operation {
        case .track(let op):
            return await handleTrack(op)
        case .navigate(let op):
            return handleNavigate(op)
        default:
            return .fail("AX channel does not handle \(operation)")
        }
    }

    // MARK: - Track Operations

    private func handleTrack(_ op: TrackOp) async -> ChannelResult {
        // Stub: AX track operations will be implemented with UI element traversal
        switch op {
        case .select(let index):
            return .ok(["action": "select", "index": "\(index)"])
        case .rename(let index, let name):
            return .ok(["action": "rename", "index": "\(index)", "name": name])
        default:
            return .fail("AX channel: track operation not yet implemented")
        }
    }

    // MARK: - Navigate Operations

    private func handleNavigate(_ op: NavigateOp) -> ChannelResult {
        // Stub: AX navigation will be implemented with UI element interaction
        switch op {
        case .showMixer:
            return .ok(["action": "show_mixer"])
        case .showEditor:
            return .ok(["action": "show_editor"])
        case .showAutomation:
            return .ok(["action": "show_automation"])
        default:
            return .fail("AX channel: navigate operation not yet implemented")
        }
    }
}
