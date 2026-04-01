import Foundation
import MCP

/// Wires together the MCP Server, channel router, state cache, and
/// state poller. Registers all tool and resource handlers.
public actor LogicProServer {

    // MARK: - Properties

    private let mcpServer: Server
    private let router: ChannelRouter
    private let cache: StateCache
    private let poller: StatePoller
    private let config: ServerConfig

    // MARK: - Init

    public init(router: ChannelRouter, cache: StateCache, poller: StatePoller, config: ServerConfig) {
        self.mcpServer = Server(
            name: ServerConfig.serverName,
            version: ServerConfig.serverVersion,
            title: "Logic Pro MCP",
            instructions: """
                Control Logic Pro from AI assistants. Provides transport control, \
                track management, MIDI I/O, mixer automation, and project operations \
                through multiple macOS subsystems with automatic fallback.
                """,
            capabilities: .init(
                resources: .init(subscribe: true, listChanged: true),
                tools: .init(listChanged: true)
            )
        )
        self.router = router
        self.cache = cache
        self.poller = poller
        self.config = config
    }

    // MARK: - Start

    public func start() async throws {
        await registerTools(on: mcpServer)
        await registerResources(on: mcpServer)

        let transport = StdioTransport()
        try await mcpServer.start(transport: transport)

        await poller.start()

        fputs("[logic-pro-mcp] Server started on stdio\n", stderr)

        await mcpServer.waitUntilCompleted()
    }

    // MARK: - Tool Registration

    private func registerTools(on server: Server) async {
        let routerRef = router
        let cacheRef = cache

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: LogicProServer.allTools())
        }

        await server.withMethodHandler(CallTool.self) { params in
            let args = params.arguments ?? [:]

            switch params.name {
            case "transport":
                return try await LogicProServer.handleTransport(args: args, router: routerRef, cache: cacheRef)
            case "track":
                return try await LogicProServer.handleTrack(args: args, router: routerRef, cache: cacheRef)
            case "mixer":
                return try await LogicProServer.handleMixer(args: args, router: routerRef, cache: cacheRef)
            case "midi_send":
                return try await LogicProServer.handleMIDI(args: args, router: routerRef)
            case "edit":
                return try await LogicProServer.handleEdit(args: args, router: routerRef)
            case "navigate":
                return try await LogicProServer.handleNavigate(args: args, router: routerRef)
            case "project":
                return try await LogicProServer.handleProject(args: args, router: routerRef)
            case "system":
                return try await LogicProServer.handleSystem(args: args, router: routerRef, cache: cacheRef)
            default:
                return CallTool.Result(
                    content: [.text("Unknown tool: \(params.name)")],
                    isError: true
                )
            }
        }
    }

    // MARK: - Resource Registration

    private func registerResources(on server: Server) async {
        let cacheRef = cache

        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: [
                Resource(
                    name: "transport_state",
                    uri: "logicpro://state/transport",
                    title: "Transport State",
                    description: "Current transport state (play/stop/record, tempo, position)",
                    mimeType: "application/json"
                ),
                Resource(
                    name: "tracks",
                    uri: "logicpro://state/tracks",
                    title: "Track List",
                    description: "All tracks with name, type, mute/solo/arm, volume, pan",
                    mimeType: "application/json"
                ),
                Resource(
                    name: "mixer",
                    uri: "logicpro://state/mixer",
                    title: "Mixer State",
                    description: "Channel strips with volume, pan, mute, solo, sends",
                    mimeType: "application/json"
                ),
                Resource(
                    name: "project",
                    uri: "logicpro://state/project",
                    title: "Project Info",
                    description: "Project metadata (name, sample rate, bit depth, tempo)",
                    mimeType: "application/json"
                ),
                Resource(
                    name: "health",
                    uri: "logicpro://system/health",
                    title: "System Health",
                    description: "Server health, channel status, permissions",
                    mimeType: "application/json"
                ),
            ])
        }

        await server.withMethodHandler(ReadResource.self) { params in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

            switch params.uri {
            case "logicpro://state/transport":
                let state = await cacheRef.getTransport()
                let json = try encoder.encode(state)
                return ReadResource.Result(contents: [
                    .text(String(data: json, encoding: .utf8) ?? "{}", uri: params.uri, mimeType: "application/json")
                ])

            case "logicpro://state/tracks":
                let tracks = await cacheRef.getTracks()
                let json = try encoder.encode(tracks)
                return ReadResource.Result(contents: [
                    .text(String(data: json, encoding: .utf8) ?? "[]", uri: params.uri, mimeType: "application/json")
                ])

            case "logicpro://state/mixer":
                let mixer = await cacheRef.getMixer()
                let json = try encoder.encode(mixer)
                return ReadResource.Result(contents: [
                    .text(String(data: json, encoding: .utf8) ?? "{}", uri: params.uri, mimeType: "application/json")
                ])

            case "logicpro://state/project":
                let project = await cacheRef.getProject()
                let json = try encoder.encode(project)
                return ReadResource.Result(contents: [
                    .text(String(data: json, encoding: .utf8) ?? "{}", uri: params.uri, mimeType: "application/json")
                ])

            case "logicpro://system/health":
                let running = PermissionChecker.isLogicProRunning()
                let ax = PermissionChecker.checkAccessibility()
                let age = await cacheRef.cacheAge()
                let health = SystemHealth(
                    serverVersion: ServerConfig.serverVersion,
                    channels: [],
                    cacheAge: age,
                    logicProRunning: running,
                    permissionsOk: ax && running
                )
                let json = try encoder.encode(health)
                return ReadResource.Result(contents: [
                    .text(String(data: json, encoding: .utf8) ?? "{}", uri: params.uri, mimeType: "application/json")
                ])

            default:
                return ReadResource.Result(contents: [
                    .text("Unknown resource: \(params.uri)", uri: params.uri)
                ])
            }
        }
    }
}
