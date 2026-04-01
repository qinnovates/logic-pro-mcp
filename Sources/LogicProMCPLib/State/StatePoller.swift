import Foundation

/// Polling mode determines how frequently we read DAW state.
public enum PollingMode: Sendable {
    case active  // During playback — fast updates
    case light   // Logic focused but stopped — moderate updates
    case idle    // Logic not focused or not running — slow updates
}

/// Periodically polls Logic Pro state and pushes updates into the StateCache.
public actor StatePoller {

    // MARK: - Properties

    private let cache: StateCache
    private let router: ChannelRouter
    private let config: ServerConfig
    private var pollingTask: Task<Void, Never>?
    private var mode: PollingMode = .idle

    // MARK: - Init

    public init(cache: StateCache, router: ChannelRouter, config: ServerConfig) {
        self.cache = cache
        self.router = router
        self.config = config
    }

    // MARK: - Start / Stop

    public func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.pollLoop()
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Mode

    public func setMode(_ newMode: PollingMode) {
        mode = newMode
    }

    public func currentMode() -> PollingMode {
        mode
    }

    // MARK: - Poll Loop

    private func pollLoop() async {
        while !Task.isCancelled {
            let interval = await intervalForCurrentMode()

            // Poll transport state via the router (system/health is always internal)
            await pollTransportState()

            // Adapt mode based on what we learned
            await adaptMode()

            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func intervalForCurrentMode() async -> TimeInterval {
        switch mode {
        case .active: return config.axActiveInterval
        case .light:  return config.axLightInterval
        case .idle:   return config.axIdleInterval
        }
    }

    // MARK: - Polling Implementations

    private func pollTransportState() async {
        // Only poll if the cache is stale
        let fresh = await cache.isFresh(.transport)
        guard !fresh else { return }

        // In a full implementation this would read AX attributes from
        // Logic Pro's transport bar. For now we check if Logic is running
        // and mark the cache accordingly.
        let running = PermissionChecker.isLogicProRunning()
        if !running {
            // Nothing to poll — set defaults
            var state = TransportState()
            state.isPlaying = false
            state.isRecording = false
            await cache.setTransport(state)
            return
        }

        // Attempt to read transport state through the router.
        // The AX channel (once implemented) will populate real data.
        let result = try? await router.route(.system(.healthCheck))
        if let result, result.success {
            // Transport state will be populated by the AX channel
            // when it reads UI elements. For now, refresh the timestamp.
            let current = await cache.getTransport()
            await cache.setTransport(current)
        }
    }

    private func adaptMode() async {
        let transport = await cache.getTransport()
        let running = PermissionChecker.isLogicProRunning()

        if !running {
            mode = .idle
        } else if transport.isPlaying || transport.isRecording {
            mode = .active
        } else {
            mode = .light
        }
    }
}
