import Foundation
import MCP

extension LogicProServer {

    // MARK: - Prompt Definitions

    static func allPrompts() -> [Prompt] {
        [
            Prompt(
                name: "mix-check",
                title: "Mix Check",
                description: "Analyze current mix balance and suggest improvements based on track levels, panning, and frequency content",
                arguments: nil
            ),
            Prompt(
                name: "master-for-platform",
                title: "Master for Platform",
                description: "Bounce with platform-specific loudness targets (Spotify, YouTube, Apple Music, CD)",
                arguments: [
                    Prompt.Argument(
                        name: "platform",
                        title: "Target Platform",
                        description: "Target platform: spotify, youtube, apple_music, or cd",
                        required: true
                    ),
                ]
            ),
            Prompt(
                name: "session-overview",
                title: "Session Overview",
                description: "Full snapshot of the current project — tracks, mixer state, transport, and project metadata",
                arguments: nil
            ),
        ]
    }

    // MARK: - Prompt Registration

    func registerPrompts(on server: Server) async {
        let cacheRef = cache
        let routerRef = router

        await server.withMethodHandler(ListPrompts.self) { _ in
            ListPrompts.Result(prompts: LogicProServer.allPrompts())
        }

        await server.withMethodHandler(GetPrompt.self) { params in
            switch params.name {
            case "mix-check":
                return try await LogicProServer.handleMixCheckPrompt(cache: cacheRef, router: routerRef)
            case "master-for-platform":
                return try await LogicProServer.handleMasterForPlatformPrompt(
                    platform: params.arguments?["platform"] ?? "spotify",
                    cache: cacheRef
                )
            case "session-overview":
                return try await LogicProServer.handleSessionOverviewPrompt(cache: cacheRef)
            default:
                return GetPrompt.Result(
                    description: "Unknown prompt",
                    messages: [.user("Unknown prompt: \(params.name)")]
                )
            }
        }
    }

    // MARK: - Prompt Handlers

    private static func handleMixCheckPrompt(
        cache: StateCache, router: ChannelRouter
    ) async throws -> GetPrompt.Result {
        let tracks = await cache.getTracks()
        let mixer = await cache.getMixer()
        let transport = await cache.getTransport()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let tracksJSON = String(data: try encoder.encode(tracks), encoding: .utf8) ?? "[]"
        let mixerJSON = String(data: try encoder.encode(mixer), encoding: .utf8) ?? "{}"

        let prompt = """
            Analyze this Logic Pro mix and suggest improvements.

            **Transport:** \(transport.tempo) BPM, \(transport.timeSignature), \
            \(transport.sampleRate) Hz

            **Tracks:**
            \(tracksJSON)

            **Mixer:**
            \(mixerJSON)

            Review for:
            1. Level balance — are any tracks too loud or too quiet relative to the mix?
            2. Panning — is the stereo field well-utilized or too narrow/lopsided?
            3. Mute/solo state — anything accidentally muted or soloed?
            4. Track organization — naming, grouping, routing suggestions
            """

        return GetPrompt.Result(
            description: "Mix analysis based on current session state",
            messages: [.user(.text(text: prompt))]
        )
    }

    private static func handleMasterForPlatformPrompt(
        platform: String, cache: StateCache
    ) async throws -> GetPrompt.Result {
        let project = await cache.getProject()

        let targets: [String: (lufs: String, truePeak: String)] = [
            "spotify": (lufs: "-14 LUFS", truePeak: "-1 dBTP"),
            "youtube": (lufs: "-13 LUFS", truePeak: "-1 dBTP"),
            "apple_music": (lufs: "-16 LUFS", truePeak: "-1 dBTP"),
            "cd": (lufs: "-9 LUFS", truePeak: "-0.3 dBTP"),
        ]

        let target = targets[platform] ?? targets["spotify"]!

        let prompt = """
            Master this project for \(platform).

            **Project:** \(project.name)
            **Sample Rate:** \(project.sampleRate) Hz
            **Bit Depth:** \(project.bitDepth)

            **Target Loudness:** \(target.lufs) integrated
            **True Peak Ceiling:** \(target.truePeak)

            Steps:
            1. Use the `audio_analyze` resource to check current loudness and peak levels
            2. If levels need adjustment, use the `mixer` tool to adjust the master fader
            3. Use the `project` tool with action "bounce" to export
            4. Analyze the bounced file to verify it meets the target specs
            """

        return GetPrompt.Result(
            description: "Mastering workflow targeting \(platform) loudness standards",
            messages: [.user(.text(text: prompt))]
        )
    }

    private static func handleSessionOverviewPrompt(
        cache: StateCache
    ) async throws -> GetPrompt.Result {
        let transport = await cache.getTransport()
        let tracks = await cache.getTracks()
        let mixer = await cache.getMixer()
        let project = await cache.getProject()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let transportJSON = String(data: try encoder.encode(transport), encoding: .utf8) ?? "{}"
        let tracksJSON = String(data: try encoder.encode(tracks), encoding: .utf8) ?? "[]"
        let mixerJSON = String(data: try encoder.encode(mixer), encoding: .utf8) ?? "{}"
        let projectJSON = String(data: try encoder.encode(project), encoding: .utf8) ?? "{}"

        let prompt = """
            Here is the complete state of the current Logic Pro session.

            **Project:**
            \(projectJSON)

            **Transport:**
            \(transportJSON)

            **Tracks (\(tracks.count) total):**
            \(tracksJSON)

            **Mixer:**
            \(mixerJSON)

            Summarize this session: what instruments are present, what's the arrangement \
            status, and what needs attention.
            """

        return GetPrompt.Result(
            description: "Complete session state snapshot",
            messages: [.user(.text(text: prompt))]
        )
    }
}
