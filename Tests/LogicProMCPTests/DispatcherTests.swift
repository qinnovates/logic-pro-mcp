import Testing
@testable import LogicProMCPLib

@Suite("Dispatcher & Schema Validation")
struct DispatcherTests {

    // MARK: - Resource Provider Consistency

    @Test func resourceProviderReturnsAllExpectedResources() {
        let resources = ResourceProvider.allResources()

        // Should have at least the core resources
        let names = resources.map(\.name)
        #expect(names.contains("transport_state"))
        #expect(names.contains("tracks"))
        #expect(names.contains("mixer"))
        #expect(names.contains("project"))
        #expect(names.contains("health"))
    }

    @Test func resourceURIsAreUnique() {
        let resources = ResourceProvider.allResources()
        let uris = resources.map(\.uri)
        let uniqueURIs = Set(uris)
        #expect(uris.count == uniqueURIs.count, "All resource URIs should be unique")
    }

    @Test func resourceNamesAreUnique() {
        let resources = ResourceProvider.allResources()
        let names = resources.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "All resource names should be unique")
    }

    @Test func allResourcesHaveMimeType() {
        let resources = ResourceProvider.allResources()
        for resource in resources {
            #expect(
                resource.mimeType != nil && !resource.mimeType!.isEmpty,
                "Resource '\(resource.name)' should have a MIME type"
            )
        }
    }

    @Test func allResourceURIsUseLogicProScheme() {
        let resources = ResourceProvider.allResources()
        for resource in resources {
            #expect(
                resource.uri.hasPrefix("logicpro://"),
                "Resource '\(resource.name)' URI should use logicpro:// scheme, got: \(resource.uri)"
            )
        }
    }

    // MARK: - Server Config Defaults

    @Test func serverConfigHasDefaults() async {
        let config = ServerConfig()
        let name = ServerConfig.serverName
        let version = ServerConfig.serverVersion

        #expect(!name.isEmpty, "Server name should not be empty")
        #expect(!version.isEmpty, "Server version should not be empty")
        #expect(name == "logic-pro-mcp")

        let threshold = await config.circuitBreakerFailureThreshold
        #expect(threshold > 0, "Circuit breaker threshold should be positive")

        let ttl = await config.stateCacheTTL
        #expect(ttl > 0, "Cache TTL should be positive")
    }

    // MARK: - Channel Operation Domain Coverage

    @Test func allChannelOperationDomainsExist() {
        // Verify that all ChannelOperation cases can be constructed
        let ops: [ChannelOperation] = [
            .transport(.play),
            .track(.create(type: "audio")),
            .mixer(.setVolume(channel: 0, value: 0.0)),
            .midi(.sendNote(note: 60, velocity: 100, channel: 0, duration: 0.5)),
            .edit(.undo),
            .navigate(.zoomIn),
            .project(.save),
            .system(.healthCheck),
        ]
        #expect(ops.count == 8, "Should cover all 8 channel operation domains")
    }

    // MARK: - Channel Result

    @Test func channelResultOk() {
        let result = ChannelResult.ok(["key": "value"])
        #expect(result.success == true)
        #expect(result.data["key"] == "value")
        #expect(result.error == nil)
    }

    @Test func channelResultFail() {
        let result = ChannelResult.fail("Something broke")
        #expect(result.success == false)
        #expect(result.data.isEmpty)
        #expect(result.error == "Something broke")
    }

    @Test func channelResultOkDefaultData() {
        let result = ChannelResult.ok()
        #expect(result.success == true)
        #expect(result.data.isEmpty)
    }
}
