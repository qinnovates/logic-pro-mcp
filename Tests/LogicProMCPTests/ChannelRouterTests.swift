import Testing
@testable import LogicProMCPLib

// MARK: - Mock Channel

/// A configurable mock channel for testing the ChannelRouter.
actor MockChannel: Channel {
    public nonisolated let name: String
    public var isAvailable: Bool
    private var shouldFail: Bool
    private(set) var callCount: Int = 0

    init(name: String, isAvailable: Bool = true, shouldFail: Bool = false) {
        self.name = name
        self.isAvailable = isAvailable
        self.shouldFail = shouldFail
    }

    func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        callCount += 1
        if shouldFail {
            return .fail("Mock failure from \(name)")
        }
        return .ok(["channel": name, "mock": "true"])
    }

    func setAvailable(_ available: Bool) {
        isAvailable = available
    }

    func setShouldFail(_ fail: Bool) {
        shouldFail = fail
    }
}

@Suite("Channel Router")
struct ChannelRouterTests {

    // MARK: - Helpers

    /// Create a ServerConfig for testing (uses defaults).
    private func makeConfig() -> ServerConfig {
        ServerConfig()
    }

    // MARK: - Basic Routing

    @Test func routesMIDIToCoreMIDI() async {
        let config = makeConfig()
        let mockMIDI = MockChannel(name: "CoreMIDI")
        let router = await ChannelRouter(channels: [mockMIDI], config: config)

        let result = try? await router.route(.midi(.sendNote(note: 60, velocity: 100, channel: 0, duration: 0.5)))
        #expect(result?.success == true)

        let count = await mockMIDI.callCount
        #expect(count == 1)
    }

    @Test func routesTransportWithFallback() async {
        let config = makeConfig()
        // CoreMIDI fails, CGEvent should catch it
        let mockMIDI = MockChannel(name: "CoreMIDI", shouldFail: true)
        let mockCGEvent = MockChannel(name: "CGEvent")
        let router = await ChannelRouter(channels: [mockMIDI, mockCGEvent], config: config)

        let result = try? await router.route(.transport(.play))
        #expect(result?.success == true)

        let cgCount = await mockCGEvent.callCount
        #expect(cgCount == 1, "CGEvent should have been used as fallback")
    }

    @Test func skipsUnavailableChannels() async {
        let config = makeConfig()
        let mockMIDI = MockChannel(name: "CoreMIDI", isAvailable: false)
        let mockCGEvent = MockChannel(name: "CGEvent")
        let router = await ChannelRouter(channels: [mockMIDI, mockCGEvent], config: config)

        let result = try? await router.route(.transport(.stop))
        #expect(result?.success == true)

        let midiCount = await mockMIDI.callCount
        #expect(midiCount == 0, "Unavailable channel should not be called")
    }

    @Test func returnsFailWhenNoChainsMatch() async {
        let config = makeConfig()
        // No channel named "CGEvent" for edit domain
        let mockMIDI = MockChannel(name: "CoreMIDI")
        let router = await ChannelRouter(channels: [mockMIDI], config: config)

        let result = try? await router.route(.edit(.undo))
        #expect(result?.success == false, "Should fail when no matching channel found")
    }

    // MARK: - Circuit Breaker

    @Test func circuitBreakerTripsAfterThreshold() async {
        let config = makeConfig()
        // Default threshold is 3 failures
        let mockMIDI = MockChannel(name: "CoreMIDI", shouldFail: true)
        let router = await ChannelRouter(channels: [mockMIDI], config: config)

        let threshold = await config.circuitBreakerFailureThreshold

        // Exhaust the failure threshold
        for _ in 0..<threshold {
            _ = try? await router.route(.midi(.sendCC(controller: 1, value: 64, channel: 0)))
        }

        let callsBefore = await mockMIDI.callCount
        #expect(callsBefore == threshold)

        // Next call should skip the circuit-broken channel entirely
        let result = try? await router.route(.midi(.sendCC(controller: 1, value: 64, channel: 0)))
        #expect(result?.success == false, "Should fail with circuit-broken channel")

        let callsAfter = await mockMIDI.callCount
        #expect(callsAfter == callsBefore, "Circuit-broken channel should not receive more calls")
    }

    @Test func circuitBreakerResets() async {
        let config = makeConfig()
        let mockMIDI = MockChannel(name: "CoreMIDI", shouldFail: true)
        let router = await ChannelRouter(channels: [mockMIDI], config: config)

        let threshold = await config.circuitBreakerFailureThreshold

        // Trip the circuit breaker
        for _ in 0..<threshold {
            _ = try? await router.route(.midi(.sendCC(controller: 1, value: 64, channel: 0)))
        }

        // Reset it
        await router.resetCircuitBreaker(for: "CoreMIDI")

        // Should be callable again (will still fail because shouldFail is true,
        // but it should actually be called)
        _ = try? await router.route(.midi(.sendCC(controller: 1, value: 64, channel: 0)))

        let totalCalls = await mockMIDI.callCount
        #expect(totalCalls == threshold + 1, "Channel should be called again after circuit breaker reset")
    }

    // MARK: - System Operations

    @Test func systemHealthCheckHandledInternally() async {
        let config = makeConfig()
        let router = await ChannelRouter(channels: [], config: config)

        let result = try? await router.route(.system(.healthCheck))
        #expect(result?.success == true, "System health check should be handled internally")
    }

    @Test func systemPermissionsCheckHandledInternally() async {
        let config = makeConfig()
        let router = await ChannelRouter(channels: [], config: config)

        let result = try? await router.route(.system(.checkPermissions))
        #expect(result?.success == true, "System permissions check should be handled internally")
    }

    // MARK: - Channel Health

    @Test func channelHealthsReportsAllChannels() async {
        let config = makeConfig()
        let mockA = MockChannel(name: "CoreMIDI")
        let mockB = MockChannel(name: "CGEvent", isAvailable: false)
        let router = await ChannelRouter(channels: [mockA, mockB], config: config)

        let healths = await router.channelHealths()
        #expect(healths.count == 2)

        let midiHealth = healths.first { $0.name == "CoreMIDI" }
        #expect(midiHealth?.isAvailable == true)
        #expect(midiHealth?.failureCount == 0)

        let cgHealth = healths.first { $0.name == "CGEvent" }
        #expect(cgHealth?.isAvailable == false)
    }
}
