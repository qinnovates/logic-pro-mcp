import Foundation
import MCP

extension LogicProServer {

    // MARK: - Completion Registration

    func registerCompletions(on server: Server) async {
        let cacheRef = cache

        await server.withMethodHandler(Complete.self) { params in
            let argName = params.argument.name
            let partial = params.argument.value.lowercased()

            switch params.ref {
            case .prompt(let promptRef):
                let values = await LogicProServer.completePromptArgument(
                    promptName: promptRef.name,
                    argumentName: argName,
                    partial: partial,
                    cache: cacheRef
                )
                return Complete.Result(
                    completion: .init(values: values, total: values.count, hasMore: false)
                )

            case .resource:
                let values = LogicProServer.completeResourceURI(partial: partial)
                return Complete.Result(
                    completion: .init(values: values, total: values.count, hasMore: false)
                )
            }
        }
    }

    // MARK: - Prompt Argument Completion

    private static func completePromptArgument(
        promptName: String,
        argumentName: String,
        partial: String,
        cache: StateCache
    ) async -> [String] {
        switch (promptName, argumentName) {
        case ("master-for-platform", "platform"):
            let platforms = ["spotify", "youtube", "apple_music", "cd"]
            return filterCompletions(platforms, matching: partial)

        case (_, "track_index"):
            let tracks = await cache.getTracks()
            let indices = tracks.map { String($0.index) }
            return filterCompletions(indices, matching: partial)

        case (_, "track_name"):
            let tracks = await cache.getTracks()
            let names = tracks.map { $0.name }
            return filterCompletions(names, matching: partial)

        default:
            return []
        }
    }

    // MARK: - Resource URI Completion

    private static func completeResourceURI(partial: String) -> [String] {
        let allURIs = [
            "logicpro://state/transport",
            "logicpro://state/tracks",
            "logicpro://state/mixer",
            "logicpro://state/project",
            "logicpro://system/health",
            "logicpro://midi/ports",
            "logicpro://audio/analysis",
            "logicpro://state/tracks/detail",
            "logicpro://plugins/available",
        ]
        return filterCompletions(allURIs, matching: partial)
    }

    // MARK: - Filter Helper

    private static func filterCompletions(_ candidates: [String], matching partial: String) -> [String] {
        guard !partial.isEmpty else { return candidates }
        return candidates.filter { $0.lowercased().hasPrefix(partial) }
    }
}
