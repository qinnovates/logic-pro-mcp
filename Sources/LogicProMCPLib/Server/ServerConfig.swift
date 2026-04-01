import Foundation

/// Centralized configuration for the Logic Pro MCP server.
/// All values load from environment variables with sensible defaults.
public actor ServerConfig {

    // MARK: - MIDI

    public let midiInputPortName: String
    public let midiOutputPortName: String

    // MARK: - OSC

    public let oscHost: String
    public let oscPort: UInt16

    // MARK: - Accessibility Polling Intervals (seconds)

    public let axActiveInterval: TimeInterval
    public let axLightInterval: TimeInterval
    public let axIdleInterval: TimeInterval

    // MARK: - State Cache

    public let stateCacheTTL: TimeInterval

    // MARK: - AppleScript

    public let appleScriptTimeout: TimeInterval

    // MARK: - CGEvent

    public let cgEventKeyRepeatDelay: TimeInterval

    // MARK: - Verify-After-Write

    public let verifyAfterWriteEnabled: Bool
    public let verifyAfterWriteDelay: TimeInterval

    // MARK: - Circuit Breaker

    public let circuitBreakerFailureThreshold: Int
    public let circuitBreakerResetTimeout: TimeInterval

    // MARK: - Paths

    public let keybindingsFilePath: String

    // MARK: - Logic Pro

    public static let logicProBundleID = "com.apple.logic10"

    // MARK: - Server Identity

    public static let serverName = "logic-pro-mcp"
    public static let serverVersion = "0.1.0"

    // MARK: - Init

    public init() {
        self.midiInputPortName = Self.env("LPM_MIDI_IN", default: "Logic Pro MCP In")
        self.midiOutputPortName = Self.env("LPM_MIDI_OUT", default: "Logic Pro MCP Out")

        self.oscHost = Self.env("LPM_OSC_HOST", default: "127.0.0.1")
        self.oscPort = UInt16(Self.env("LPM_OSC_PORT", default: "8000")) ?? 8000

        self.axActiveInterval = Self.envDouble("LPM_AX_ACTIVE_MS", default: 100) / 1000.0
        self.axLightInterval = Self.envDouble("LPM_AX_LIGHT_MS", default: 500) / 1000.0
        self.axIdleInterval = Self.envDouble("LPM_AX_IDLE_MS", default: 2000) / 1000.0

        self.stateCacheTTL = Self.envDouble("LPM_CACHE_TTL_MS", default: 1000) / 1000.0

        self.appleScriptTimeout = Self.envDouble("LPM_APPLESCRIPT_TIMEOUT_MS", default: 5000) / 1000.0

        self.cgEventKeyRepeatDelay = Self.envDouble("LPM_KEY_REPEAT_DELAY_MS", default: 50) / 1000.0

        self.verifyAfterWriteEnabled = Self.envBool("LPM_VERIFY_AFTER_WRITE", default: true)
        self.verifyAfterWriteDelay = Self.envDouble("LPM_VERIFY_DELAY_MS", default: 100) / 1000.0

        self.circuitBreakerFailureThreshold = Int(Self.env("LPM_CB_FAILURE_THRESHOLD", default: "3")) ?? 3
        self.circuitBreakerResetTimeout = Self.envDouble("LPM_CB_RESET_TIMEOUT_S", default: 30)

        let defaultKeybindingsPath = NSString("~/.config/logic-pro-mcp/keybindings.json")
            .expandingTildeInPath
        self.keybindingsFilePath = Self.env("LPM_KEYBINDINGS_PATH", default: defaultKeybindingsPath)
    }

    // MARK: - Environment Helpers

    private static func env(_ key: String, default fallback: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? fallback
    }

    private static func envDouble(_ key: String, default fallback: Double) -> Double {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = Double(raw) else {
            return fallback
        }
        return value
    }

    private static func envBool(_ key: String, default fallback: Bool) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key] else {
            return fallback
        }
        switch raw.lowercased() {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return fallback
        }
    }
}
