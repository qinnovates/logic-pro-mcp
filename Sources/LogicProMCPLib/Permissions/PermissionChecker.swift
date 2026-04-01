import ApplicationServices
import AppKit
import Foundation

/// Static helpers that verify the macOS permissions and
/// application state required for the MCP server to function.
public struct PermissionChecker: Sendable {

    // MARK: - Accessibility

    /// Returns `true` if this process is trusted for Accessibility API access.
    public static func checkAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Automation (AppleScript)

    /// Attempts a trivial AppleScript against Logic Pro to verify
    /// Automation permission has been granted.
    /// Returns `true` on success, `false` on failure or timeout.
    public static func checkAutomation() -> Bool {
        let src = """
        tell application id "\(ServerConfig.logicProBundleID)"
            return name
        end tell
        """
        guard let script = NSAppleScript(source: src) else { return false }
        var errorInfo: NSDictionary?
        _ = script.executeAndReturnError(&errorInfo)
        return errorInfo == nil
    }

    // MARK: - Logic Pro Running

    /// Returns `true` if Logic Pro is currently running.
    public static func isLogicProRunning() -> Bool {
        logicProApp() != nil
    }

    /// Returns the PID of Logic Pro, or `nil` if not running.
    public static func logicProPID() -> pid_t? {
        logicProApp()?.processIdentifier
    }

    // MARK: - Aggregate

    /// Returns all permission/status checks with human-readable labels.
    public static func allPermissions() -> [(String, Bool)] {
        [
            ("Accessibility (AX)", checkAccessibility()),
            ("Logic Pro Running", isLogicProRunning()),
            ("Automation (AppleScript)", checkAutomation()),
        ]
    }

    /// Prints formatted diagnostic information to stderr.
    public static func printDiagnostics() {
        let checks = allPermissions()
        let maxLen = checks.map(\.0.count).max() ?? 0

        fputs("\n  Logic Pro MCP — Permission Diagnostics\n", stderr)
        fputs("  \(String(repeating: "-", count: 42))\n", stderr)

        for (label, ok) in checks {
            let padded = label.padding(toLength: maxLen, withPad: " ", startingAt: 0)
            let icon = ok ? "OK" : "FAIL"
            fputs("  \(padded)  [\(icon)]\n", stderr)
        }

        fputs("\n", stderr)

        if !checkAccessibility() {
            fputs("  To grant Accessibility access:\n", stderr)
            fputs("  System Settings > Privacy & Security > Accessibility\n", stderr)
            fputs("  Add this executable or your terminal app.\n\n", stderr)
        }

        if !isLogicProRunning() {
            fputs("  Logic Pro is not running. Start it and try again.\n\n", stderr)
        }
    }

    // MARK: - Private

    private static func logicProApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: ServerConfig.logicProBundleID
        ).first
    }
}
