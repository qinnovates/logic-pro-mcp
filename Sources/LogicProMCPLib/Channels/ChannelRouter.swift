import Foundation

/// Routes operations to the best available channel with automatic
/// fallback and circuit-breaker protection.
public actor ChannelRouter {

    // MARK: - Types

    private struct ChannelState {
        var failureCount: Int = 0
        var lastFailureTime: Date? = nil
    }

    // MARK: - Properties

    private let channels: [String: any Channel]
    private var channelStates: [String: ChannelState] = [:]
    private let failureThreshold: Int
    private let resetTimeout: TimeInterval

    /// Ordered fallback chains per operation domain.
    /// Channel names must match the `name` property of registered channels.
    private let fallbackChains: [String: [String]] = [
        "transport": ["CoreMIDI", "CGEvent", "AX"],
        "track":     ["AX", "CGEvent"],
        "mixer":     ["OSC", "AX"],
        "midi":      ["CoreMIDI"],
        "edit":      ["CGEvent"],
        "navigate":  ["CGEvent", "AX"],
        "project":   ["AppleScript", "CGEvent"],
        "system":    ["Internal"],
    ]

    // MARK: - Init

    public init(channels: [any Channel], config: ServerConfig) async {
        var map: [String: any Channel] = [:]
        for channel in channels {
            let channelName = await channel.name
            map[channelName] = channel
        }
        self.channels = map
        self.failureThreshold = config.circuitBreakerFailureThreshold
        self.resetTimeout = config.circuitBreakerResetTimeout
    }

    // MARK: - Routing

    /// Route an operation through the fallback chain, skipping
    /// channels that are circuit-broken or unavailable.
    public func route(_ operation: ChannelOperation) async throws -> ChannelResult {
        let domain = Self.domain(for: operation)

        // Handle system operations internally
        if domain == "system" {
            return await handleSystem(operation)
        }

        guard let chain = fallbackChains[domain] else {
            return .fail("No fallback chain for domain: \(domain)")
        }

        var lastError: String = "No channels available for \(domain)"

        for channelName in chain {
            // Skip circuit-broken channels
            if isCircuitBroken(channelName) {
                continue
            }

            guard let channel = channels[channelName] else {
                continue
            }

            // Skip unavailable channels
            guard await channel.isAvailable else {
                continue
            }

            do {
                let result = try await channel.send(operation)
                if result.success {
                    recordSuccess(channelName)
                    return result
                } else {
                    lastError = result.error ?? "Unknown error from \(channelName)"
                    recordFailure(channelName)
                }
            } catch {
                lastError = "\(channelName): \(error.localizedDescription)"
                recordFailure(channelName)
            }
        }

        return .fail(lastError)
    }

    /// Reset the circuit breaker for a specific channel.
    public func resetCircuitBreaker(for channelName: String) {
        channelStates[channelName] = ChannelState()
    }

    /// Get health information for all registered channels.
    public func channelHealths() async -> [ChannelHealthInfo] {
        var results: [ChannelHealthInfo] = []
        for (name, channel) in channels {
            let state = channelStates[name] ?? ChannelState()
            let available = await channel.isAvailable
            results.append(ChannelHealthInfo(
                name: name,
                isAvailable: available,
                failureCount: state.failureCount,
                isCircuitBroken: isCircuitBroken(name),
                lastError: nil
            ))
        }
        return results.sorted { $0.name < $1.name }
    }

    // MARK: - Circuit Breaker

    private func isCircuitBroken(_ channelName: String) -> Bool {
        guard let state = channelStates[channelName] else { return false }
        guard state.failureCount >= failureThreshold else { return false }

        // Check if enough time has passed to allow a retry
        if let lastFailure = state.lastFailureTime,
           Date().timeIntervalSince(lastFailure) >= resetTimeout {
            return false  // Allow a retry (half-open)
        }
        return true
    }

    private func recordFailure(_ channelName: String) {
        var state = channelStates[channelName] ?? ChannelState()
        state.failureCount += 1
        state.lastFailureTime = Date()
        channelStates[channelName] = state
    }

    private func recordSuccess(_ channelName: String) {
        // Reset on success (full close of circuit breaker)
        channelStates[channelName] = ChannelState()
    }

    // MARK: - Domain Mapping

    private static func domain(for operation: ChannelOperation) -> String {
        switch operation {
        case .transport: return "transport"
        case .track:     return "track"
        case .mixer:     return "mixer"
        case .midi:      return "midi"
        case .edit:      return "edit"
        case .navigate:  return "navigate"
        case .project:   return "project"
        case .system:    return "system"
        }
    }

    // MARK: - Internal System Handler

    private func handleSystem(_ operation: ChannelOperation) async -> ChannelResult {
        guard case .system(let op) = operation else {
            return .fail("Expected system operation")
        }
        switch op {
        case .healthCheck:
            let healths = await channelHealths()
            let summary = healths.map { "\($0.name): available=\($0.isAvailable) failures=\($0.failureCount)" }
            return .ok(["status": "ok", "channels": summary.joined(separator: "; ")])
        case .checkPermissions:
            let ax = PermissionChecker.checkAccessibility()
            let running = PermissionChecker.isLogicProRunning()
            return .ok([
                "accessibility": String(ax),
                "logicProRunning": String(running),
            ])
        }
    }
}

/// Lightweight struct for reporting channel health outside the actor.
public struct ChannelHealthInfo: Sendable {
    public let name: String
    public let isAvailable: Bool
    public let failureCount: Int
    public let isCircuitBroken: Bool
    public let lastError: String?
}
