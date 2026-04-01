import Foundation
import LogicProMCPLib

// MARK: - CLI Flags

let arguments = CommandLine.arguments

if arguments.contains("--version") {
    fputs("\(ServerConfig.serverName) \(ServerConfig.serverVersion)\n", stderr)
    exit(0)
}

if arguments.contains("--check-permissions") {
    PermissionChecker.printDiagnostics()
    exit(0)
}

// MARK: - Bootstrap

fputs("[logic-pro-mcp] Starting v\(ServerConfig.serverVersion)...\n", stderr)

let config = ServerConfig()

let coremidi = await CoreMIDIChannel(config: config)
let cgevent = await CGEventChannel(config: config)
let ax = AccessibilityChannel()
let applescript = await AppleScriptChannel(config: config)
let osc = await OSCChannel(config: config)
let scripter = ScripterChannel(config: config)
await scripter.setup()

let channels: [any Channel] = [coremidi, cgevent, ax, applescript, osc, scripter]

let router = await ChannelRouter(channels: channels, config: config)
let cache = StateCache(ttl: await config.stateCacheTTL)
let poller = StatePoller(cache: cache, router: router, config: config)

let server = LogicProServer(
    router: router,
    cache: cache,
    poller: poller,
    config: config
)

do {
    try await server.start()
} catch {
    fputs("[logic-pro-mcp] Fatal: \(error.localizedDescription)\n", stderr)
    exit(1)
}
