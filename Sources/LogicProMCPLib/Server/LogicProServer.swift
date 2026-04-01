import Foundation
import MCP

/// Wires together the MCP Server, channel router, state cache, and
/// state poller. Registers all tool and resource handlers.
public actor LogicProServer {

    // MARK: - Properties

    private let mcpServer: Server
    let router: ChannelRouter
    let cache: StateCache
    private let poller: StatePoller
    private let config: ServerConfig
    let logger: MCPLogger

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
                completions: .init(),
                logging: .init(),
                prompts: .init(listChanged: true),
                resources: .init(subscribe: true, listChanged: true),
                tools: .init(listChanged: true)
            )
        )
        self.router = router
        self.cache = cache
        self.poller = poller
        self.config = config
        self.logger = MCPLogger(name: "logic-pro-mcp")
    }

    // MARK: - Start

    public func start() async throws {
        await logger.attach(to: mcpServer)
        await registerLogging(on: mcpServer)
        await registerTools(on: mcpServer)
        await registerResources(on: mcpServer)
        await registerPrompts(on: mcpServer)
        await registerCompletions(on: mcpServer)

        let transport = StdioTransport()
        try await mcpServer.start(transport: transport)

        await poller.start()
        await logger.info("Server started on stdio")

        await mcpServer.waitUntilCompleted()
    }

    // MARK: - Logging Registration

    private func registerLogging(on server: Server) async {
        let loggerRef = logger

        await server.withMethodHandler(SetLoggingLevel.self) { params in
            await loggerRef.setMinimumLevel(params.level)
            await loggerRef.info("Log level set to \(params.level.rawValue)")
            return Empty()
        }
    }

    // MARK: - Tool Registration

    private func registerTools(on server: Server) async {
        let routerRef = router
        let cacheRef = cache
        let loggerRef = logger

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: LogicProServer.allTools())
        }

        await server.withMethodHandler(CallTool.self) { params in
            let args = params.arguments ?? [:]
            let action = args["action"]?.stringValue

            // Audit log destructive operations before execution
            if LogicProServer.isDestructive(tool: params.name, action: action) {
                let detail = action.map { "\(params.name)/\($0)" } ?? params.name
                await loggerRef.info("Destructive operation: \(detail)")
            }

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
            case "audio_analyze":
                return try await LogicProServer.handleAudioAnalyze(args: args)
            case "plugin":
                return try await LogicProServer.handlePlugin(args: args, router: routerRef, cache: cacheRef)
            case "automation":
                return try await LogicProServer.handleAutomation(args: args, router: routerRef, cache: cacheRef)
            case "midi_edit":
                return try await LogicProServer.handleMIDIEdit(args: args, router: routerRef, cache: cacheRef)
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
        let routerRef = router

        await server.withMethodHandler(ListResources.self) { _ in
            ListResources.Result(resources: ResourceProvider.allResources())
        }

        // Look up the MIDIEngine from the CoreMIDI channel if available
        // For now pass nil — MIDIEngine is internal to CoreMIDIChannel
        await server.withMethodHandler(ReadResource.self) { params in
            try await ResourceHandlers.handleRead(
                uri: params.uri,
                cache: cacheRef,
                router: routerRef,
                midiEngine: nil
            )
        }
    }

    // MARK: - Destructive Operation Detection

    private static let destructiveActions: [String: Set<String>] = [
        "track": ["delete"],
        "edit": ["delete", "split"],
        "project": ["close", "bounce"],
        "plugin": ["insert", "remove", "set_param", "load_preset"],
        "automation": ["set_mode", "add_point", "clear"],
        "midi_edit": ["add_note", "delete_note", "move_note", "set_velocity", "quantize"],
    ]

    static func isDestructive(tool: String, action: String?) -> Bool {
        guard let action, let actions = destructiveActions[tool] else { return false }
        return actions.contains(action)
    }
}
