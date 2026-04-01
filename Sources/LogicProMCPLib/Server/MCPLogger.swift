import Foundation
import MCP

/// Structured MCP logger that sends log messages to connected clients
/// via the MCP logging notification protocol.
///
/// Respects the minimum log level set by the client through `logging/setLevel`.
/// Falls back to stderr when no MCP server is connected.
public actor MCPLogger {

    // MARK: - Properties

    private var server: Server?
    private var minimumLevel: LogLevel = .info
    private let loggerName: String

    private static let levelOrder: [LogLevel] = [
        .debug, .info, .notice, .warning, .error, .critical, .alert, .emergency,
    ]

    // MARK: - Init

    public init(name: String) {
        self.loggerName = name
    }

    // MARK: - Configuration

    public func attach(to server: Server) {
        self.server = server
    }

    public func setMinimumLevel(_ level: LogLevel) {
        minimumLevel = level
    }

    // MARK: - Logging

    public func debug(_ message: String) async {
        await log(level: .debug, message: message)
    }

    public func info(_ message: String) async {
        await log(level: .info, message: message)
    }

    public func warning(_ message: String) async {
        await log(level: .warning, message: message)
    }

    public func error(_ message: String) async {
        await log(level: .error, message: message)
    }

    public func log(level: LogLevel, message: String) async {
        guard shouldLog(level) else { return }

        if let server {
            do {
                try await server.log(
                    level: level,
                    logger: loggerName,
                    data: .string(message)
                )
            } catch {
                // MCP send failed — fall back to stderr
                stderrLog(level: level, message: message)
            }
        } else {
            stderrLog(level: level, message: message)
        }
    }

    // MARK: - Level Filtering

    private func shouldLog(_ level: LogLevel) -> Bool {
        guard let minIndex = Self.levelOrder.firstIndex(of: minimumLevel),
              let msgIndex = Self.levelOrder.firstIndex(of: level) else {
            return true
        }
        return msgIndex >= minIndex
    }

    // MARK: - Stderr Fallback

    private func stderrLog(level: LogLevel, message: String) {
        fputs("[logic-pro-mcp] [\(level.rawValue)] \(message)\n", stderr)
    }
}
