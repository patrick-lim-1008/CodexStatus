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
        if CommandLine.arguments.contains("--validate-scanner-shape") {
            try validateScannerShape()
            print("Scanner unavailable-state smoke test passed")
            return
        }
        if CommandLine.arguments.contains("--validate-weekly-only-usage") {
            try validateWeeklyOnlyUsage()
            print("Scanner weekly-only usage smoke test passed")
            return
        }
        if CommandLine.arguments.contains("--validate-rollout-output") {
            try validateRolloutOutput()
            print("Rollout activity privacy smoke test passed")
            return
        }
        if CommandLine.arguments.contains("--validate-progress-output") {
            try validateProgressOutput()
            print("Progress Sidecar helper smoke test passed")
            return
        }

        try testFreshInstallDefaults()
        try testLegacyMigration()
        try testStoredValuesWinOverMigration()
        try testHookRemovalPreservesUnrelatedConfiguration()
        try testCompletionLedgerRecoveryAndPersistence()
        try testProjectIdentityFiltering()
        try testCoreTaskStatePolicy()
        try testUpdateReleaseParsing()
        try testLifecycleInstallerRoundTrip()
        try testQuietHoursPolicy()
        print("AppPreferences smoke tests passed")
    }

    private static func validateScannerOutput() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["connected"] as? Bool == true,
              let threads = root["threads"] as? [[String: Any]],
              threads.first?["id"] as? String == "test-thread",
              let usageWindows = root["usageWindows"] as? [[String: Any]],
              usageWindows.count == 2,
              usageWindows.contains(where: { $0["name"] as? String == "5-hour limit" }),
              usageWindows.contains(where: { $0["name"] as? String == "Weekly limit" })
        else {
            throw TestFailure("Scanner must report connection, tasks, and every named usage window")
        }
    }

    private static func validateScannerShape() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["connected"] is Bool,
              root["threads"] is [Any]
        else {
            throw TestFailure("Scanner must return a structured result even when Codex is unavailable")
        }
        if let usageWindows = root["usageWindows"], !(usageWindows is [Any]) {
            throw TestFailure("usageWindows must be an array when present")
        }
    }

    private static func validateWeeklyOnlyUsage() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["connected"] as? Bool == true,
              let usageWindows = root["usageWindows"] as? [[String: Any]],
              usageWindows.count == 1,
              usageWindows.first?["name"] as? String == "Weekly limit"
        else {
            throw TestFailure("A model-specific 5-hour bucket must not be shown as the general account limit")
        }
    }

    private static func validateRolloutOutput() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["lifecycle"] as? String == "running",
              root["activity"] as? String == "Editing files",
              ((root["turnStartedAt"] as? NSNumber)?.doubleValue ?? 0) > 0
        else {
            throw TestFailure("Rollout parser must return sanitized activity and lifecycle")
        }

        let output = String(decoding: data, as: UTF8.self)
        try expect(!output.contains("PRIVATE"), "Rollout output must not copy private content")
        try expect(!output.contains("SECRET"), "Rollout output must not copy tool arguments")
    }

    private static func validateProgressOutput() throws {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["ok"] as? Bool == true,
              root["code"] as? String == "complete",
              root["summary"] as? String == "Stage: implementation\nCurrent: temporary side conversation is working\nNext: local test"
        else {
            throw TestFailure("Progress Sidecar helper must return the temporary conversation summary")
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
            try expect(preferences.appTheme == .system, "Fresh installs should follow the system theme")
            try expect(!preferences.enhancedActivityEnabled, "Enhanced Activity must be opt-in")
            try expect(!preferences.notificationsEnabled, "Notifications must be opt-in")
            try expect(!preferences.updateChecksEnabled, "Network update checks must be opt-in")
            try expect(preferences.completionNotificationSound == .glass, "Completion should default to Glass")
            try expect(preferences.attentionNotificationSound == .ping, "Attention should default to Ping")
            try expect(preferences.errorNotificationSound == .basso, "Errors should default to Basso")
            try expect(preferences.notifyOnCompletion, "Completion alerts should default on")
            try expect(preferences.notifyOnAttention, "Attention alerts should default on")
            try expect(preferences.notifyOnError, "Error alerts should default on")
            try expect(!preferences.notificationQuietHoursEnabled, "Quiet hours should be opt-in")
            try expect(preferences.notificationQuietStartMinute == 22 * 60, "Quiet hours should start at 22:00")
            try expect(preferences.notificationQuietEndMinute == 8 * 60, "Quiet hours should end at 08:00")
            try expect(!preferences.progressSidecarEnabled, "Progress Sidecar must be opt-in")
            try expect(preferences.progressSidecarPrompt == AppPreferences.defaultProgressSidecarPrompt, "Progress Sidecar should use the safe default prompt")
            try expect(!preferences.progressSidecarWarningAcknowledged, "The quota warning must be shown before first use")
            try expect(preferences.progressRefreshInterval == .manual, "Automatic progress updates must default to off")
            try expect(!preferences.promptLibraryEnabled, "Prompt Library must be opt-in")
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
            first.appTheme = .dark
            first.updateChecksEnabled = true
            first.completionNotificationSound = .pop
            first.attentionNotificationSound = .none
            first.errorNotificationSound = .systemDefault
            first.notifyOnError = false
            first.notificationQuietHoursEnabled = true
            first.notificationQuietStartMinute = 23 * 60 + 30
            first.notificationQuietEndMinute = 7 * 60 + 15
            first.progressSidecarEnabled = true
            first.progressSidecarPrompt = "Stored sidecar prompt"
            first.progressSidecarWarningAcknowledged = true
            first.progressRefreshInterval = .threeMinutes
            first.promptLibraryEnabled = true

            let restored = AppPreferences(
                defaults: defaults,
                existingHooksInstalled: true,
                existingLifecycleInstalled: true
            )
            try expect(!restored.followCodexLifecycle, "Stored lifecycle preference must win")
            try expect(!restored.enhancedActivityEnabled, "Stored extension preference must win")
            try expect(restored.completionReadMode == .click, "Stored read behavior must win")
            try expect(!restored.showMenuBarCount, "Stored appearance preference must win")
            try expect(restored.appTheme == .dark, "Stored theme must survive restart")
            try expect(restored.updateChecksEnabled, "Stored update-check preference must survive restart")
            try expect(restored.completionNotificationSound == .pop, "Stored completion sound must win")
            try expect(restored.attentionNotificationSound == .none, "Stored attention sound must win")
            try expect(restored.errorNotificationSound == .systemDefault, "Stored error sound must win")
            try expect(!restored.notifyOnError, "Stored event selection must win")
            try expect(restored.notificationQuietHoursEnabled, "Stored quiet-hours choice must win")
            try expect(restored.notificationQuietStartMinute == 23 * 60 + 30, "Stored quiet start must win")
            try expect(restored.notificationQuietEndMinute == 7 * 60 + 15, "Stored quiet end must win")
            try expect(restored.progressSidecarEnabled, "Stored Progress Sidecar setting must win")
            try expect(restored.progressSidecarPrompt == "Stored sidecar prompt", "Stored sidecar prompt must win")
            try expect(restored.progressSidecarWarningAcknowledged, "Stored sidecar warning choice must win")
            try expect(restored.progressRefreshInterval == .threeMinutes, "Stored progress interval must win")
            try expect(restored.promptLibraryEnabled, "Stored Prompt Library setting must survive restart")
        }
    }

    private static func testHookRemovalPreservesUnrelatedConfiguration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexStatusTests-\(UUID().uuidString)", isDirectory: true)
        let supportDirectory = root.appendingPathComponent("support", isDirectory: true)
        let hooksURL = root.appendingPathComponent("hooks.json")
        let helperURL = supportDirectory.appendingPathComponent("CodexStatusHook")
        let bundleURL = root.appendingPathComponent("CodexStatus.app", isDirectory: true)
        let bundledHelperURL = bundleURL.appendingPathComponent("Contents/Helpers/CodexStatusHook")
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: bundledHelperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: root) }

        guard fileManager.createFile(
            atPath: bundledHelperURL.path,
            contents: Data("test helper".utf8),
            attributes: [.posixPermissions: 0o755]
        ) else {
            throw TestFailure("Could not create test helper")
        }
        try fileManager.copyItem(at: bundledHelperURL, to: helperURL)

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
            bundleURL: bundleURL
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

        try installer.install()
        try installer.install()
        try expect(installer.isInstalled, "Enhanced Activity installation must be idempotent")

        let installedData = try Data(contentsOf: hooksURL)
        guard let installedRoot = try JSONSerialization.jsonObject(with: installedData) as? [String: Any],
              let installedHooks = installedRoot["hooks"] as? [String: Any]
        else {
            throw TestFailure("Enhanced Activity must write valid hook configuration")
        }
        let managedHandlerCount = installedHooks.values.reduce(into: 0) { count, value in
            guard let groups = value as? [[String: Any]] else { return }
            for group in groups {
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                count += handlers.filter {
                    ($0["command"] as? String)?.contains("CodexStatusHook") == true
                }.count
            }
        }
        try expect(managedHandlerCount == 9, "Enhanced Activity must install one handler per supported lifecycle event")
        try installer.uninstall()
        try expect(!installer.isInstalled, "Enhanced Activity must be removable after reinstall")
    }

    @MainActor
    private static func testCompletionLedgerRecoveryAndPersistence() throws {
        try withCleanDefaults { defaults in
            let now = Date(timeIntervalSince1970: 2_000_000_000)
            defaults.set(Double.infinity, forKey: CompletionLedger.trackingStartedAtKey)
            defaults.set([
                "valid": 2_000_000_010,
                "invalid": Double.nan
            ], forKey: CompletionLedger.acknowledgementsKey)

            var ledger = CompletionLedger(defaults: defaults, now: now)
            try expect(ledger.trackingStartedAt == now.timeIntervalSince1970, "A corrupt tracking timestamp must recover")
            try expect(ledger.acknowledgements["invalid"] == nil, "Invalid acknowledgement timestamps must be discarded")
            try expect(!ledger.isUnacknowledged(taskID: "old", completedAt: now), "Existing completions must not become unread on installation")

            let completion = now.addingTimeInterval(30)
            try expect(ledger.isUnacknowledged(taskID: "new", completedAt: completion), "A new completion must remain unread")
            ledger.acknowledge(taskID: "new", completedAt: completion)
            try expect(!ledger.isUnacknowledged(taskID: "new", completedAt: completion), "Acknowledgement must clear unread state")

            let restored = CompletionLedger(defaults: defaults, now: now.addingTimeInterval(60))
            try expect(!restored.isUnacknowledged(taskID: "new", completedAt: completion), "Acknowledgement must survive restart")
        }
    }

    private static func testProjectIdentityFiltering() throws {
        try expect(
            ProjectIdentity.displayName(forWorkingDirectory: "/Users/test/Projects/CodexStatus") == "CodexStatus",
            "A real working directory must expose its project name"
        )
        try expect(
            ProjectIdentity.displayName(forWorkingDirectory: "/Users/test/Documents/Codex/2026-09-05/generated-chat") == nil,
            "Generated projectless task directories must not be shown as projects"
        )
        try expect(
            ProjectIdentity.displayName(forWorkingDirectory: "/Users/test/.codex/.chatgpt-projects/g-p-secret") == "ChatGPT Project",
            "Internal ChatGPT Project identifiers must not be displayed"
        )
        try expect(
            ProjectIdentity.displayName(forWorkingDirectory: "") == nil,
            "An empty working directory must not create a project label"
        )
    }

    private static func testCoreTaskStatePolicy() throws {
        try expect(
            CoreTaskStatePolicy.resolve(
                statusType: "active",
                activeFlags: [],
                rolloutLifecycle: "completed"
            ) == .completed,
            "A terminal completion must win over a stale active flag"
        )
        try expect(
            CoreTaskStatePolicy.resolve(
                statusType: "active",
                activeFlags: ["waitingOnApproval"],
                rolloutLifecycle: "aborted"
            ) == .aborted,
            "A terminal abort must win over a stale approval flag"
        )
        try expect(
            CoreTaskStatePolicy.resolve(
                statusType: "active",
                activeFlags: ["waitingOnApproval"],
                rolloutLifecycle: "running"
            ) == .needsAttention,
            "A live approval request must remain visible"
        )
        let current = Date(timeIntervalSince1970: 100)
        try expect(
            !CoreTaskStatePolicy.shouldUseHookSignal(
                isAttentionOrError: true,
                hookUpdatedAt: current.addingTimeInterval(-1),
                discoveredUpdatedAt: current
            ),
            "An old Hook alert must not replace newer task state"
        )
        try expect(
            CoreTaskStatePolicy.shouldUseHookSignal(
                isAttentionOrError: true,
                hookUpdatedAt: current,
                discoveredUpdatedAt: current
            ),
            "A current Hook alert must enrich task state"
        )
    }

    private static func testUpdateReleaseParsing() throws {
        let stable = Data(#"""
        {
          "tag_name": "v0.4.0",
          "name": "CodexStatus 0.4",
          "html_url": "https://github.com/patrick-lim-1008/CodexStatus/releases/tag/v0.4.0",
          "draft": false,
          "prerelease": false,
          "assets": [{
            "name": "CodexStatus-v0.4.0.zip",
            "browser_download_url": "https://github.com/patrick-lim-1008/CodexStatus/releases/download/v0.4.0/CodexStatus-v0.4.0.zip",
            "size": 4,
            "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
          }]
        }
        """#.utf8)
        let update = try AppUpdateChecker.availableUpdate(from: stable, currentVersion: "0.3.0")
        try expect(update?.version == "0.4.0", "A newer stable release must be detected")
        try expect(update?.downloadAsset?.fileName == "CodexStatus-v0.4.0.zip", "The matching release archive must be selected")
        try expect(update?.downloadAsset?.sha256 == String(repeating: "a", count: 64), "The GitHub SHA-256 digest must be normalized")
        let current = try AppUpdateChecker.availableUpdate(from: stable, currentVersion: "0.4.0")
        try expect(
            current == nil,
            "The current release must not be reported as an update"
        )

        let prerelease = Data(#"""
        {
          "tag_name": "v0.4.0-beta.1",
          "name": "Preview",
          "html_url": "https://github.com/patrick-lim-1008/CodexStatus/releases/tag/v0.4.0-beta.1",
          "draft": false,
          "prerelease": true
        }
        """#.utf8)
        let ignoredPrerelease = try AppUpdateChecker.availableUpdate(
            from: prerelease,
            currentVersion: "0.3.0"
        )
        try expect(
            ignoredPrerelease == nil,
            "Prereleases must not be offered by stable update checks"
        )

        let archiveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexStatus-update-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: archiveURL)
        try AppUpdateChecker.validateDownloadedArchive(
            at: archiveURL,
            asset: AppUpdateAsset(
                fileName: "CodexStatus-v0.4.0.zip",
                downloadURL: URL(string: "https://example.com/CodexStatus.zip")!,
                size: 4,
                sha256: nil
            )
        )
        do {
            try AppUpdateChecker.validateDownloadedArchive(
                at: archiveURL,
                asset: AppUpdateAsset(
                    fileName: "CodexStatus-v0.4.0.zip",
                    downloadURL: URL(string: "https://example.com/CodexStatus.zip")!,
                    size: 5,
                    sha256: nil
                )
            )
            throw TestFailure("An update with the wrong byte size was accepted")
        } catch AppUpdateDownloadError.sizeMismatch {
            // Expected.
        }
    }

    private static func testLifecycleInstallerRoundTrip() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexStatusLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let launchAgents = root.appendingPathComponent("LaunchAgents", isDirectory: true)
        let bundle = root.appendingPathComponent("CodexStatus.app", isDirectory: true)
        let bundledWatcher = bundle.appendingPathComponent("Contents/Helpers/CodexStatusWatcher")
        try fileManager.createDirectory(
            at: bundledWatcher.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard fileManager.createFile(
            atPath: bundledWatcher.path,
            contents: Data("watcher".utf8),
            attributes: [.posixPermissions: 0o755]
        ) else {
            throw TestFailure("Could not create lifecycle fixture")
        }
        defer { try? fileManager.removeItem(at: root) }

        var launchctlCalls: [[String]] = []
        let installer = CodexLifecycleInstaller(
            fileManager: fileManager,
            supportDirectory: support,
            launchAgentsDirectory: launchAgents,
            bundleURL: bundle,
            serviceUID: 501,
            launchctlRunner: { arguments in
                launchctlCalls.append(arguments)
                return arguments.first == "print" ? 1 : 0
            }
        )

        try installer.install()
        try expect(installer.isInstalled, "Lifecycle watcher must be detected after installation")
        try expect(
            launchctlCalls.contains(where: { $0.first == "bootstrap" }),
            "Lifecycle installation must load its LaunchAgent"
        )
        try installer.install()
        try installer.uninstall()
        try expect(!installer.isInstalled, "Lifecycle watcher must be fully removable")
        try expect(
            launchctlCalls.contains(where: { $0.first == "bootout" }),
            "Lifecycle removal must unload its LaunchAgent"
        )
    }

    private static func testQuietHoursPolicy() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(hour: Int, minute: Int) -> Date {
            calendar.date(from: DateComponents(
                year: 2026,
                month: 9,
                day: 5,
                hour: hour,
                minute: minute
            ))!
        }

        try expect(
            QuietHoursPolicy.isQuiet(
                at: date(hour: 23, minute: 0),
                startMinute: 22 * 60,
                endMinute: 8 * 60,
                calendar: calendar
            ),
            "Overnight quiet hours must include late evening"
        )
        try expect(
            QuietHoursPolicy.isQuiet(
                at: date(hour: 7, minute: 59),
                startMinute: 22 * 60,
                endMinute: 8 * 60,
                calendar: calendar
            ),
            "Overnight quiet hours must include early morning"
        )
        try expect(
            !QuietHoursPolicy.isQuiet(
                at: date(hour: 8, minute: 0),
                startMinute: 22 * 60,
                endMinute: 8 * 60,
                calendar: calendar
            ),
            "Quiet hours must end at the configured boundary"
        )
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
