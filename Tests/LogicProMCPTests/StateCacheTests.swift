import Testing
@testable import LogicProMCPLib

@Suite("State Cache")
struct StateCacheTests {

    @Test func defaultTransportState() async {
        let cache = StateCache(ttl: 5.0)
        let transport = await cache.getTransport()
        #expect(transport.isPlaying == false)
        #expect(transport.isRecording == false)
        #expect(transport.isPaused == false)
        #expect(transport.tempo == 120.0)
        #expect(transport.position == "1.1.1.1")
        #expect(transport.isCycleEnabled == false)
        #expect(transport.isMetronomeEnabled == false)
        #expect(transport.timeSignature == "4/4")
        #expect(transport.sampleRate == 44100)
    }

    @Test func setAndGetTransport() async {
        let cache = StateCache(ttl: 5.0)

        var state = TransportState()
        state.isPlaying = true
        state.tempo = 140.0
        state.position = "4.2.1.0"

        await cache.setTransport(state)
        let retrieved = await cache.getTransport()

        #expect(retrieved.isPlaying == true)
        #expect(retrieved.tempo == 140.0)
        #expect(retrieved.position == "4.2.1.0")
    }

    @Test func markDirtyAndFresh() async {
        let cache = StateCache(ttl: 60.0)  // Long TTL so it stays fresh

        // Before any set, should not be fresh (never updated)
        let freshBeforeSet = await cache.isFresh(.transport)
        #expect(freshBeforeSet == false)

        // Set transport state
        await cache.setTransport(TransportState())

        // Should be fresh after set
        let freshAfterSet = await cache.isFresh(.transport)
        #expect(freshAfterSet == true)

        // Should not be dirty after set
        let dirtyAfterSet = await cache.isDirty(.transport)
        #expect(dirtyAfterSet == false)

        // Mark dirty
        await cache.markDirty(.transport)

        // Should be dirty now
        let dirtyAfterMark = await cache.isDirty(.transport)
        #expect(dirtyAfterMark == true)

        // Should not be fresh when dirty
        let freshWhenDirty = await cache.isFresh(.transport)
        #expect(freshWhenDirty == false)
    }

    @Test func cacheAgeIncreases() async {
        let cache = StateCache(ttl: 5.0)

        // Before any set, age should be 0
        let initialAge = await cache.cacheAge()
        #expect(initialAge == 0)

        // Set some state
        await cache.setTransport(TransportState())

        // Wait a small amount
        try? await Task.sleep(for: .milliseconds(50))

        // Age should be > 0 now
        let age = await cache.cacheAge()
        #expect(age > 0, "Cache age should increase after sleep, got \(age)")
    }

    @Test func tracksGetSet() async {
        let cache = StateCache(ttl: 5.0)

        // Default should be empty
        let defaultTracks = await cache.getTracks()
        #expect(defaultTracks.isEmpty)

        // Set tracks
        let tracks = [
            TrackInfo(index: 0, name: "Drums", type: "software_instrument"),
            TrackInfo(index: 1, name: "Bass", type: "audio"),
        ]
        await cache.setTracks(tracks)

        let retrieved = await cache.getTracks()
        #expect(retrieved.count == 2)
        #expect(retrieved[0].name == "Drums")
        #expect(retrieved[0].type == "software_instrument")
        #expect(retrieved[1].name == "Bass")
        #expect(retrieved[1].index == 1)
    }

    @Test func mixerGetSet() async {
        let cache = StateCache(ttl: 5.0)

        // Default should have empty channels
        let defaultMixer = await cache.getMixer()
        #expect(defaultMixer.channels.isEmpty)
    }

    @Test func projectGetSet() async {
        let cache = StateCache(ttl: 5.0)

        // Default should have empty name
        let defaultProject = await cache.getProject()
        #expect(defaultProject.name == "")
        #expect(defaultProject.tempo == 120.0)
    }

    @Test func staleAfterTTLExpires() async {
        let cache = StateCache(ttl: 0.05)  // 50ms TTL

        await cache.setTransport(TransportState())
        let freshImmediately = await cache.isFresh(.transport)
        #expect(freshImmediately == true)

        // Wait longer than TTL
        try? await Task.sleep(for: .milliseconds(100))

        let freshAfterTTL = await cache.isFresh(.transport)
        #expect(freshAfterTTL == false, "Should be stale after TTL expires")
    }

    @Test func independentStateTypes() async {
        let cache = StateCache(ttl: 60.0)

        await cache.setTransport(TransportState())
        await cache.markDirty(.tracks)

        // Transport should be fresh (just set)
        let transportFresh = await cache.isFresh(.transport)
        #expect(transportFresh == true)

        // Tracks should be dirty (explicitly marked)
        let tracksDirty = await cache.isDirty(.tracks)
        #expect(tracksDirty == true)

        // Mixer was never set, should not be fresh
        let mixerFresh = await cache.isFresh(.mixer)
        #expect(mixerFresh == false)
    }
}
