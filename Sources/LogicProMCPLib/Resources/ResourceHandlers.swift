import Foundation
import MCP

/// Handles MCP resource read requests, dispatching to the appropriate
/// data source based on the resource URI.
public struct ResourceHandlers: Sendable {

    /// Handle a resource read request and return the appropriate result.
    public static func handleRead(
        uri: String,
        cache: StateCache,
        router: ChannelRouter,
        midiEngine: MIDIEngine?
    ) async throws -> ReadResource.Result {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Parse URI and optional query parameters
        let (basePath, queryParams) = parseURI(uri)

        switch basePath {

        // --- Transport State ---
        case "logicpro://state/transport":
            let state = await cache.getTransport()
            let json = try encoder.encode(state)
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "{}",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        // --- Track List ---
        case "logicpro://state/tracks":
            let tracks = await cache.getTracks()
            let json = try encoder.encode(tracks)
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "[]",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        // --- Track Detail ---
        case "logicpro://state/tracks/detail":
            guard let indexStr = queryParams["index"],
                  let index = Int(indexStr) else {
                return errorResult(uri: uri, message: "Missing or invalid 'index' query parameter")
            }
            let tracks = await cache.getTracks()
            guard index >= 0 && index < tracks.count else {
                return errorResult(uri: uri, message: "Track index \(index) out of range (0..<\(tracks.count))")
            }
            let json = try encoder.encode(tracks[index])
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "{}",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        // --- Mixer State ---
        case "logicpro://state/mixer":
            let mixer = await cache.getMixer()
            let json = try encoder.encode(mixer)
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "{}",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        // --- Project Info ---
        case "logicpro://state/project":
            let project = await cache.getProject()
            let json = try encoder.encode(project)
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "{}",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        // --- System Health ---
        case "logicpro://system/health":
            let running = PermissionChecker.isLogicProRunning()
            let ax = PermissionChecker.checkAccessibility()
            let age = await cache.cacheAge()
            let channelHealths = await router.channelHealths()

            let health = SystemHealth(
                serverVersion: ServerConfig.serverVersion,
                channels: channelHealths.map { info in
                    ChannelHealth(
                        name: info.name,
                        isAvailable: info.isAvailable,
                        failureCount: info.failureCount,
                        isCircuitBroken: info.isCircuitBroken,
                        lastError: info.lastError
                    )
                },
                cacheAge: age,
                logicProRunning: running,
                permissionsOk: ax && running
            )
            let json = try encoder.encode(health)
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "{}",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        // --- MIDI Ports ---
        case "logicpro://midi/ports":
            if let engine = midiEngine {
                let ports = await engine.listPorts()
                let json = try encoder.encode(ports)
                return ReadResource.Result(contents: [
                    .text(
                        String(data: json, encoding: .utf8) ?? "[]",
                        uri: uri,
                        mimeType: "application/json"
                    ),
                ])
            } else {
                return errorResult(uri: uri, message: "MIDI engine not available")
            }

        // --- Audio Analysis ---
        case "logicpro://audio/analysis":
            guard let path = queryParams["path"] else {
                return errorResult(uri: uri, message: "Missing 'path' query parameter for audio analysis")
            }
            // Validate path
            guard !path.contains("..") else {
                return errorResult(uri: uri, message: "Directory traversal not allowed in audio path")
            }
            guard path.hasPrefix("/") else {
                return errorResult(uri: uri, message: "Audio path must be absolute")
            }
            let analysis = try await AudioAnalyzer.analyze(fileAt: path)
            let json = try encoder.encode(analysis)
            return ReadResource.Result(contents: [
                .text(
                    String(data: json, encoding: .utf8) ?? "{}",
                    uri: uri,
                    mimeType: "application/json"
                ),
            ])

        default:
            return errorResult(uri: uri, message: "Unknown resource: \(uri)")
        }
    }

    // MARK: - URI Parsing

    /// Parse a URI into its base path and query parameters.
    /// Example: "logicpro://state/tracks/detail?index=3" -> ("logicpro://state/tracks/detail", ["index": "3"])
    private static func parseURI(_ uri: String) -> (String, [String: String]) {
        guard let questionMark = uri.firstIndex(of: "?") else {
            return (uri, [:])
        }

        let basePath = String(uri[uri.startIndex..<questionMark])
        let queryString = String(uri[uri.index(after: questionMark)...])

        var params: [String: String] = [:]
        let pairs = queryString.split(separator: "&")
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                params[key] = value
            }
        }

        return (basePath, params)
    }

    // MARK: - Error Helper

    private static func errorResult(uri: String, message: String) -> ReadResource.Result {
        ReadResource.Result(contents: [
            .text(message, uri: uri),
        ])
    }
}
