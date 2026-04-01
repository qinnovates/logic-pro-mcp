import Testing
@testable import LogicProMCPLib

@Suite("Plugin Discovery")
struct PluginDiscoveryTests {

    @Test func listAvailableReturnsPlugins() {
        let plugins = PluginDiscovery.listAvailable()
        // macOS always has built-in Audio Units (AUAudioFilePlayer, DynamicsProcessor, etc.)
        #expect(!plugins.isEmpty, "macOS should have at least one built-in Audio Unit")
    }

    @Test func pluginsHaveNonEmptyNames() {
        let plugins = PluginDiscovery.listAvailable()
        for plugin in plugins {
            #expect(!plugin.name.isEmpty, "Plugin should have a non-empty name")
        }
    }

    @Test func pluginsHaveNonEmptyManufacturer() {
        let plugins = PluginDiscovery.listAvailable()
        for plugin in plugins {
            #expect(!plugin.manufacturer.isEmpty, "Plugin \(plugin.name) should have a non-empty manufacturer")
        }
    }

    @Test func pluginsHaveValidType() {
        let validTypes: Set<String> = ["instrument", "effect", "midi_effect"]
        let plugins = PluginDiscovery.listAvailable()
        for plugin in plugins {
            #expect(
                validTypes.contains(plugin.type),
                "Plugin \(plugin.name) has unexpected type: \(plugin.type)"
            )
        }
    }

    @Test func pluginsAreSortedByName() {
        let plugins = PluginDiscovery.listAvailable()
        guard plugins.count > 1 else { return }
        for i in 0..<(plugins.count - 1) {
            let comparison = plugins[i].name.localizedCaseInsensitiveCompare(plugins[i + 1].name)
            #expect(
                comparison != .orderedDescending,
                "Plugins should be sorted: '\(plugins[i].name)' should come before '\(plugins[i + 1].name)'"
            )
        }
    }

    @Test func searchWithQueryFiltersResults() {
        let allPlugins = PluginDiscovery.listAvailable()
        guard !allPlugins.isEmpty else { return }

        // Use the first plugin's name as a search query
        let query = allPlugins[0].name
        let filtered = PluginDiscovery.search(query: query)

        #expect(!filtered.isEmpty, "Search for '\(query)' should return at least one result")
        #expect(
            filtered.count <= allPlugins.count,
            "Filtered results should be <= total plugins"
        )
    }

    @Test func searchWithEmptyQueryReturnsNone() {
        // Swift's String.contains("") returns false (Foundation range-based search),
        // so an empty query matches nothing.
        let searchResult = PluginDiscovery.search(query: "")
        #expect(searchResult.isEmpty, "Empty query should return no results due to String.contains(\"\") == false")
    }

    @Test func searchIsCaseInsensitive() {
        let allPlugins = PluginDiscovery.listAvailable()
        guard !allPlugins.isEmpty else { return }

        let pluginName = allPlugins[0].name
        let upperResult = PluginDiscovery.search(query: pluginName.uppercased())
        let lowerResult = PluginDiscovery.search(query: pluginName.lowercased())

        #expect(
            upperResult.count == lowerResult.count,
            "Case-insensitive search should return same count for upper/lower"
        )
    }

    @Test func searchWithNonsenseQueryReturnsEmpty() {
        let results = PluginDiscovery.search(query: "zzzxxx_nonexistent_plugin_12345")
        #expect(results.isEmpty, "Nonsense query should return no results")
    }
}
