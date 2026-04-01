import ApplicationServices
import Foundation

// MARK: - Errors

enum BounceError: Error, LocalizedError, Sendable {
    case logicProNotRunning
    case accessibilityDenied
    case dialogNotFound
    case bounceButtonNotFound
    case bounceTimedOut
    case invalidOutputPath(String)
    case noPIDAvailable

    var errorDescription: String? {
        switch self {
        case .logicProNotRunning:
            return "Logic Pro is not running"
        case .accessibilityDenied:
            return "Accessibility permission not granted"
        case .dialogNotFound:
            return "Bounce dialog not found"
        case .bounceButtonNotFound:
            return "Bounce button not found in dialog"
        case .bounceTimedOut:
            return "Bounce operation timed out"
        case .invalidOutputPath(let reason):
            return "Invalid output path: \(reason)"
        case .noPIDAvailable:
            return "Could not determine Logic Pro PID"
        }
    }
}

// MARK: - Bounce Controller

/// Automates Logic Pro's bounce workflow using CGEvent for keyboard
/// shortcuts and the Accessibility API for dialog interaction.
actor BounceController {

    // MARK: - Configuration

    /// Maximum time to wait for the bounce dialog to appear.
    private let dialogTimeout: TimeInterval = 5.0

    /// Maximum time to wait for the bounce to complete.
    private let bounceTimeout: TimeInterval = 300.0  // 5 minutes

    /// Polling interval when waiting for dialog/completion.
    private let pollInterval: TimeInterval = 0.5

    // MARK: - Bounce Project

    /// Open the bounce dialog, optionally configure output path and format,
    /// click Bounce, and wait for the output file. Returns the path to the
    /// bounced file.
    func bounceProject(
        outputPath: String? = nil,
        format: String = "wav"
    ) async throws -> String {
        // Validate prerequisites
        guard PermissionChecker.isLogicProRunning() else {
            throw BounceError.logicProNotRunning
        }
        guard PermissionChecker.checkAccessibility() else {
            throw BounceError.accessibilityDenied
        }
        guard let pid = PermissionChecker.logicProPID() else {
            throw BounceError.noPIDAvailable
        }

        // Validate output path if provided
        if let outputPath {
            guard !outputPath.contains("..") else {
                throw BounceError.invalidOutputPath("Directory traversal not allowed")
            }
            guard outputPath.hasPrefix("/") || outputPath.hasPrefix("~") else {
                throw BounceError.invalidOutputPath("Path must be absolute")
            }
            let resolvedDir: String
            if outputPath.hasPrefix("~") {
                resolvedDir = NSString(string: outputPath).expandingTildeInPath
            } else {
                resolvedDir = outputPath
            }
            let dirURL = URL(fileURLWithPath: resolvedDir).deletingLastPathComponent()
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir),
                  isDir.boolValue else {
                throw BounceError.invalidOutputPath("Output directory does not exist")
            }
        }

        // Step 1: Send Cmd+B to open the bounce dialog
        try sendBounceShortcut(pid: pid)

        // Step 2: Wait for the bounce dialog to appear
        let appElement = AXUIElementCreateApplication(pid)
        let dialog = try await waitForBounceDialog(app: appElement)

        // Step 3: Configure format if needed (set the format popup)
        if format != "wav" {
            await setFormatInDialog(dialog, format: format)
        }

        // Step 4: Determine the output file location for monitoring
        let monitorDir = resolveOutputDirectory(outputPath: outputPath)
        let existingFiles = filesInDirectory(monitorDir)

        // Step 5: Click the Bounce button
        try clickBounceButton(in: dialog)

        // Step 6: Wait for a new file to appear in the output directory
        let outputFile = try await waitForBounceCompletion(
            directory: monitorDir,
            existingFiles: existingFiles,
            format: format
        )

        return outputFile
    }

    // MARK: - CGEvent: Cmd+B

    private func sendBounceShortcut(pid: pid_t) throws {
        // Key code for 'B' = 11
        let keyCode: CGKeyCode = 11

        guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            throw BounceError.dialogNotFound
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }

    // MARK: - AX: Wait for Bounce Dialog

    private func waitForBounceDialog(app: AXUIElement) async throws -> AXUIElement {
        let deadline = Date().addingTimeInterval(dialogTimeout)

        while Date() < deadline {
            if let dialog = findBounceDialog(in: app) {
                return dialog
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        throw BounceError.dialogNotFound
    }

    private func findBounceDialog(in app: AXUIElement) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsValue)
        guard result == .success, let windows = windowsValue as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
            if let title = titleValue as? String,
               title.localizedCaseInsensitiveContains("bounce") {
                return window
            }

            // Also check the subrole for sheet dialogs
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &roleValue)
            if let subrole = roleValue as? String, subrole == "AXDialog" {
                // Check children for bounce-related content
                if dialogContainsBounceContent(window) {
                    return window
                }
            }
        }

        return nil
    }

    private func dialogContainsBounceContent(_ element: AXUIElement) -> Bool {
        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &childrenValue
        )
        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            return false
        }

        for child in children {
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
            if let title = titleValue as? String,
               title.localizedCaseInsensitiveContains("bounce") {
                return true
            }
            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descValue)
            if let desc = descValue as? String,
               desc.localizedCaseInsensitiveContains("bounce") {
                return true
            }
        }
        return false
    }

    // MARK: - AX: Set Format

    private func setFormatInDialog(_ dialog: AXUIElement, format: String) async {
        // Look for a popup button related to file format
        guard let popup = findElementByRole(
            in: dialog,
            role: kAXPopUpButtonRole as String,
            descriptionContains: "format"
        ) else {
            fputs("[BounceController] Format popup not found, using default\n", stderr)
            return
        }

        // Press the popup to open it and set the value
        let formatValue: CFTypeRef = format as CFTypeRef
        AXUIElementSetAttributeValue(popup, kAXValueAttribute as CFString, formatValue)
    }

    // MARK: - AX: Click Bounce Button

    private func clickBounceButton(in dialog: AXUIElement) throws {
        // Find the Bounce button
        guard let button = findElementByRole(
            in: dialog,
            role: kAXButtonRole as String,
            titleContains: "bounce"
        ) else {
            // Try finding "OK" button as fallback
            guard let okButton = findElementByRole(
                in: dialog,
                role: kAXButtonRole as String,
                titleContains: "ok"
            ) else {
                throw BounceError.bounceButtonNotFound
            }
            AXUIElementPerformAction(okButton, kAXPressAction as CFString)
            return
        }

        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    // MARK: - AX: Element Search

    private func findElementByRole(
        in parent: AXUIElement,
        role: String,
        titleContains: String? = nil,
        descriptionContains: String? = nil
    ) -> AXUIElement? {
        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            parent, kAXChildrenAttribute as CFString, &childrenValue
        )
        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &roleValue)
            let childRole = roleValue as? String ?? ""

            if childRole == role {
                if let search = titleContains {
                    var titleValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleValue)
                    if let title = titleValue as? String,
                       title.localizedCaseInsensitiveContains(search) {
                        return child
                    }
                }
                if let search = descriptionContains {
                    var descValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(child, kAXDescriptionAttribute as CFString, &descValue)
                    if let desc = descValue as? String,
                       desc.localizedCaseInsensitiveContains(search) {
                        return child
                    }
                }
                if titleContains == nil && descriptionContains == nil {
                    return child
                }
            }

            // Recurse into children
            if let found = findElementByRole(
                in: child,
                role: role,
                titleContains: titleContains,
                descriptionContains: descriptionContains
            ) {
                return found
            }
        }

        return nil
    }

    // MARK: - File Monitoring

    private func resolveOutputDirectory(outputPath: String?) -> String {
        if let outputPath {
            if outputPath.hasPrefix("~") {
                let resolved = NSString(string: outputPath).expandingTildeInPath
                return URL(fileURLWithPath: resolved).deletingLastPathComponent().path
            }
            return URL(fileURLWithPath: outputPath).deletingLastPathComponent().path
        }
        // Default: Desktop
        return NSString("~/Desktop").expandingTildeInPath
    }

    private func filesInDirectory(_ path: String) -> Set<String> {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return Set(contents)
    }

    private func waitForBounceCompletion(
        directory: String,
        existingFiles: Set<String>,
        format: String
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(bounceTimeout)
        let expectedExtension = format.lowercased()

        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))

            let currentFiles = filesInDirectory(directory)
            let newFiles = currentFiles.subtracting(existingFiles)

            for newFile in newFiles {
                if newFile.lowercased().hasSuffix(".\(expectedExtension)") {
                    let fullPath = (directory as NSString).appendingPathComponent(newFile)
                    // Verify file is not still being written (size stabilized)
                    if await isFileStable(at: fullPath) {
                        return fullPath
                    }
                }
            }
        }

        throw BounceError.bounceTimedOut
    }

    private func isFileStable(at path: String) async -> Bool {
        guard let attrs1 = try? FileManager.default.attributesOfItem(atPath: path),
              let size1 = attrs1[.size] as? UInt64 else {
            return false
        }

        try? await Task.sleep(for: .seconds(1))

        guard let attrs2 = try? FileManager.default.attributesOfItem(atPath: path),
              let size2 = attrs2[.size] as? UInt64 else {
            return false
        }

        return size1 == size2 && size1 > 0
    }
}
