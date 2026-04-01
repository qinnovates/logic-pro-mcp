import Foundation

// MARK: - State Type

public enum StateType: String, CaseIterable, Sendable {
    case transport
    case tracks
    case mixer
    case project
}

// MARK: - State Cache

/// Thread-safe cache for DAW state, backed by actor isolation.
public actor StateCache {

    // MARK: - Stored State

    private var transport: TransportState = TransportState()
    private var tracks: [TrackInfo] = []
    private var mixer: MixerState = MixerState()
    private var project: ProjectInfo = ProjectInfo()

    // MARK: - Timestamps & Dirty Flags

    private var lastUpdated: [StateType: Date] = [:]
    private var dirtyFlags: Set<StateType> = []
    private let ttl: TimeInterval

    // MARK: - Init

    public init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    // MARK: - Transport

    public func getTransport() -> TransportState {
        transport
    }

    public func setTransport(_ state: TransportState) {
        transport = state
        lastUpdated[.transport] = Date()
        dirtyFlags.remove(.transport)
    }

    // MARK: - Tracks

    public func getTracks() -> [TrackInfo] {
        tracks
    }

    public func setTracks(_ list: [TrackInfo]) {
        tracks = list
        lastUpdated[.tracks] = Date()
        dirtyFlags.remove(.tracks)
    }

    // MARK: - Mixer

    public func getMixer() -> MixerState {
        mixer
    }

    public func setMixer(_ state: MixerState) {
        mixer = state
        lastUpdated[.mixer] = Date()
        dirtyFlags.remove(.mixer)
    }

    // MARK: - Project

    public func getProject() -> ProjectInfo {
        project
    }

    public func setProject(_ info: ProjectInfo) {
        project = info
        lastUpdated[.project] = Date()
        dirtyFlags.remove(.project)
    }

    // MARK: - Dirty / Fresh

    public func markDirty(_ type: StateType) {
        dirtyFlags.insert(type)
    }

    public func isDirty(_ type: StateType) -> Bool {
        dirtyFlags.contains(type)
    }

    public func isFresh(_ type: StateType) -> Bool {
        guard !dirtyFlags.contains(type) else { return false }
        guard let updated = lastUpdated[type] else { return false }
        return Date().timeIntervalSince(updated) < ttl
    }

    /// Seconds since the oldest state type was updated.
    /// Returns 0 if nothing has been cached yet.
    public func cacheAge() -> Double {
        guard let oldest = lastUpdated.values.min() else { return 0 }
        return Date().timeIntervalSince(oldest)
    }
}
