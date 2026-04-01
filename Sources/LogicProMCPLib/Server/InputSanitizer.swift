import Foundation

/// Validates and sanitizes user-supplied strings before they reach channel
/// implementations where they may be interpolated into AppleScript, shell
/// arguments, or AX attribute queries.
public enum InputSanitizer {

    /// Maximum allowed length for name-type inputs (plugin names, presets, params).
    /// AU plugin names rarely exceed 64 characters; 256 provides headroom.
    private static let maxNameLength = 256

    /// Sanitize a user-supplied name (plugin name, preset name, parameter name)
    /// for safe use in AppleScript string interpolation and AX queries.
    ///
    /// Rejects null bytes and excessively long strings. Escapes backslashes
    /// and double quotes to prevent AppleScript injection.
    ///
    /// Returns nil if the input is invalid and should be rejected.
    public static func sanitizeName(_ name: String) -> String? {
        guard !name.isEmpty else { return nil }
        guard !name.contains("\0") else { return nil }
        guard name.count <= maxNameLength else { return nil }

        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return escaped
    }

    /// Validate and sanitize a file path. Rejects traversal, null bytes,
    /// and non-absolute paths.
    public static func sanitizePath(_ path: String) -> String? {
        guard !path.isEmpty else { return nil }
        guard !path.contains("\0") else { return nil }
        guard !path.contains("..") else { return nil }
        guard path.hasPrefix("/") else { return nil }

        let escaped = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let resolved = NSString(string: escaped).standardizingPath
        guard resolved.hasPrefix("/") else { return nil }

        return escaped
    }
}
