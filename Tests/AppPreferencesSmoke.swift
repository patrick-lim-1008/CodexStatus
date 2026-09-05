import Foundation

@main
struct AppPreferencesSmoke {
    @MainActor
    static func main() throws {
        if CommandLine.arguments.contains("--validate-scanner-output") {
            try validateScannerOutput()
            print("Scanner output smoke test passed")
            return
        }

        try testFreshInstallDefaults()
        try testLegacyMigration()
        try testStoredValuesWinOverMigration()
        try testHookRemovalPreservesUnrelatedConfiguration()
        print("AppPreferences smoke tests passed")
    }

    private static func validateScannerOutput() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["threads"] is [Any]
        else {
            throw TestFailure("Scanner output must contain a threads array")
        }
        if let usageWindows = root["usageWindows"], !(usageWindows is [Any]) {
            throw TestFailure("usageWindows must be an array when present")
        }
    }

    @MainActor
    private static func testFreshInstallDefaults() throws {
        try withCleanDefaults { defaults in
            let preferences = AppPreferences(
                defaults: defaults,
                existingHooksInstalled: false,
                existingLifecycleInstalled: false
            )
            try expect(!preferences.followCodexLifecycle, "Fresh install must not add a lifecycle helper")
            try expect(preferences.completionReadMode == .click, "Fresh install must use click-to-read")
            try expect(preferences.usageEnabled, "Usage Meter should be enabled by default")
            try expect(!preferences.enhancedActivityEnabled, "Enhanced Activity must be opt-in")
            try expect(!preferences.notificationsEnabled, "Notifications must be opt-in")
            try expect(preferences.completionNotificationSound == .glass, "Completion should default to Glass")
            try expect(preferences.attentionNotificationSound == .ping, "Attention should default to Ping")
            try expect(preferences.errorNotificationSound == .basso, "Errors should default to Basso")
            try expect(preferences.notifyOnCompletion, "Completion alerts should default on")
            try expect(preferences.notifyOnAttention, "Attention alerts should default on")
            try expect(preferences.notifyOnError, "Error alerts should default on")
            try expect(!preferences.notificationQuietHoursEnabled, "Quiet hours should be opt-in")
            try expect(preferences.notificationQuietStartMinute == 22 * 60, "Quiet hours should start at 22:00")
            try expect(preferences.notificationQuietEndMinute == 8 * 60, "Quiet hours should end at 08:00")
        }
    }

    @MainActor
    private static func testLegacyMigration() throws {
        try withCleanDefaults { defaults in
            let preferences = AppPreferences(
                defaults: defaults,
                existingHooksInstalled: true,
                existingLifecycleInstalled: true
            )
            try expect(preferences.followCodexLifecycle, "Existing lifecycle integration must be preserved")
            try expect(preferences.enhancedActivityEnabled, "Existing hooks must be preserved")
            try expect(preferences.completionReadMode == .hover, "Existing hover behavior must be preserved")
        }
    }

    @MainActor
    private static func testStoredValuesWinOverMigration() throws {
        try withCleanDefaults { defaults in
            let first = AppPreferences(
                defaults: defaults,
                existingHooksInstalled: true,
                existingLifecycleInstalled: true
            )
            first.followCodexLifecycle = false
            first.enhancedActivityEnabled = false
            first.completionReadMode = .click
            first.showMenuBarCount = false
            first.completionNotificationSound = .pop
            first.attentionNotificationSound = .none
            first.errorNotificationSound = .systemDefault
            first.notifyOnError = false
            first.notificationQuietHoursEnabled = true
            first.notificationQuietStartMinute = 23 * 60 + 30
            first.notificationQuietEndMinute = 7 * 60 + 15

            let restored = AppPreferences(
                defaults: defaults,
                existingHooksInstalled: true,
                existingLifecycleInstalled: true
            )
            try expect(!restored.followCodexLifecycle, "Stored lifecycle preference must win")
            try expect(!restored.enhancedActivityEnabled, "Stored extension preference must win")
            try expect(restored.completionReadMode == .click, "Stored read behavior must win")
            try expect(!restored.showMenuBarCount, "Stored appearance preference must win")
            try expect(restored.completionNotificationSound == .pop, "Stored completion sound must win")
            try expect(restored.attentionNotificationSound == .none, "Stored attention sound must win")
            try expect(restored.errorNotificationSound == .systemDefault, "Stored error sound must win")
            try expect(!restored.notifyOnError, "Stored event selection must win")
            try expect(restored.notificationQuietHoursEnabled, "Stored quiet-hours choice must win")
            try expect(restored.notificationQuietStartMinute == 23 * 60 + 30, "Stored quiet start must win")
            try expect(restored.notificationQuietEndMinute == 7 * 60 + 15, "Stored quiet end must win")
        }
    }

    private static func testHookRemovalPreservesUnrelatedConfiguration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexStatusTests-\(UUID().uuidString)", isDirectory: true)
        let supportDirectory = root.appendingPathComponent("support", isDirectory: true)
        let hooksURL = root.appendingPathComponent("hooks.json")
        let helperURL = supportDirectory.appendingPathComponent("CodexStatusHook")
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        guard fileManager.createFile(
            atPath: helperURL.path,
            contents: Data("test helper".utf8),
            attributes: [.posixPermissions: 0o755]
        ) else {
            throw TestFailure("Could not create test helper")
        }

        let unrelatedCommand = "/usr/local/bin/my-existing-hook"
        let hooks: [String: Any] = [
            "description": "Keep this description",
            "customField": ["keep": true],
            "hooks": [
                "SessionStart": [[
                    "matcher": "keep matcher",
                    "hooks": [
                        ["type": "command", "command": "\"\(helperURL.path)\""],
                        ["type": "command", "command": unrelatedCommand]
                    ]
                ]],
                "Stop": [[
                    "hooks": [["type": "command", "command": unrelatedCommand]]
                ]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: hooks, options: [.prettyPrinted])
        try data.write(to: hooksURL)

        let installer = CodexIntegrationInstaller(
            supportDirectory: supportDirectory,
            hooksURL: hooksURL,
            bundleURL: root.appendingPathComponent("unused.app")
        )
        try expect(installer.isInstalled, "Test integration should be detected")
        try installer.uninstall()
        try installer.uninstall()
        try expect(!fileManager.fileExists(atPath: helperURL.path), "Managed helper should be removed")

        let resultData = try Data(contentsOf: hooksURL)
        guard let result = try JSONSerialization.jsonObject(with: resultData) as? [String: Any],
              result["description"] as? String == "Keep this description",
              let customField = result["customField"] as? [String: Any],
              customField["keep"] as? Bool == true,
              let resultHooks = result["hooks"] as? [String: Any],
              let sessionGroups = resultHooks["SessionStart"] as? [[String: Any]],
              let sessionGroup = sessionGroups.first,
              sessionGroup["matcher"] as? String == "keep matcher",
              let remainingHandlers = sessionGroup["hooks"] as? [[String: Any]],
              remainingHandlers.count == 1,
              remainingHandlers.first?["command"] as? String == unrelatedCommand,
              let stopGroups = resultHooks["Stop"] as? [[String: Any]],
              !stopGroups.isEmpty
        else {
            throw TestFailure("Unrelated hook configuration was not preserved")
        }
    }

    @MainActor
    private static func withCleanDefaults(
        _ body: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "CodexStatus.Tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestFailure("Could not create isolated preferences")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }
}

private struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
