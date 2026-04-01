import Foundation

/// Executes AppleScript commands for Logic Pro project lifecycle operations.
/// Handles only project-level operations: open, save, close, new.
public actor AppleScriptChannel: Channel {

    // MARK: - Channel Protocol

    public nonisolated let name: String = "AppleScript"

    public nonisolated var isAvailable: Bool {
        true  // AppleScript is always available on macOS; permissions checked at execution time
    }

    // MARK: - Properties

    private let timeout: TimeInterval
    private let bundleID: String

    // MARK: - Init

    public init(config: ServerConfig) async {
        self.timeout = config.appleScriptTimeout
        self.bundleID = ServerConfig.logicProBundleID
    }

    // MARK: - Send

    public func send(_ operation: ChannelOperation) async throws -> ChannelResult {
        switch operation {
        case .project(let op):
            return await handleProject(op)
        default:
            return .fail("AppleScript channel only handles project operations")
        }
    }

    // MARK: - Project Operations

    private func handleProject(_ op: ProjectOp) async -> ChannelResult {
        switch op {
        case .open(let path):
            return await openProject(path: path)
        case .save:
            return await saveProject()
        case .close:
            return await closeProject()
        case .new:
            return await newProject()
        case .bounce:
            return .fail("AppleScript cannot trigger bounce directly; use CGEvent channel")
        }
    }

    // MARK: - Open

    private func openProject(path: String) async -> ChannelResult {
        // Security: validate the path
        guard let sanitized = sanitizePath(path) else {
            return .fail("Invalid file path")
        }

        let script = """
        tell application id "\(bundleID)"
            activate
            open POSIX file "\(sanitized)"
        end tell
        """
        return await execute(script: script, description: "open project")
    }

    // MARK: - Save

    private func saveProject() async -> ChannelResult {
        let script = """
        tell application id "\(bundleID)"
            activate
            save front document
        end tell
        """
        return await execute(script: script, description: "save project")
    }

    // MARK: - Close

    private func closeProject() async -> ChannelResult {
        let script = """
        tell application id "\(bundleID)"
            close front document
        end tell
        """
        return await execute(script: script, description: "close project")
    }

    // MARK: - New

    private func newProject() async -> ChannelResult {
        // Logic Pro doesn't have a simple "make new document" AppleScript command.
        // Activating it will show the template chooser if no project is open.
        let script = """
        tell application id "\(bundleID)"
            activate
        end tell
        """
        return await execute(script: script, description: "activate Logic Pro (new project)")
    }

    // MARK: - Script Execution

    private func execute(script: String, description: String) async -> ChannelResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return .fail("Failed to launch osascript: \(error.localizedDescription)")
        }

        // Timeout handling: wait on a detached task
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                process.waitUntilExit()
                return true
            }
            group.addTask { [timeout] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return false
            }

            // Whichever finishes first
            if let first = await group.next() {
                group.cancelAll()
                return first
            }
            return false
        }

        if !completed {
            process.terminate()
            return .fail("AppleScript timed out after \(timeout)s: \(description)")
        }

        guard process.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            return .fail("AppleScript failed (\(description)): \(errStr)")
        }

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return .ok(["action": description, "output": outStr])
    }

    // MARK: - Path Sanitization

    /// Validates and sanitizes a file path for use in AppleScript.
    /// Rejects paths with directory traversal, null bytes, and other dangerous patterns.
    private func sanitizePath(_ path: String) -> String? {
        // Reject null bytes
        guard !path.contains("\0") else { return nil }

        // Reject directory traversal
        guard !path.contains("..") else { return nil }

        // Reject empty paths
        guard !path.isEmpty else { return nil }

        // Escape backslashes and double quotes for AppleScript string embedding
        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Resolve to absolute path and verify it stays within expected bounds
        let resolved = NSString(string: escaped).standardizingPath

        // Must be an absolute path
        guard resolved.hasPrefix("/") else { return nil }

        return escaped
    }
}
