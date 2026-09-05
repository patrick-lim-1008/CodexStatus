import Foundation

private struct PluginPermissionTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct PluginPermissionSmoke {
    @MainActor
    static func main() async throws {
        let suiteName = "CodexStatusPermissionTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manifest = makeManifest(reason: "Post a completion alert.")
        let package = InstalledPlugin(
            manifest: manifest,
            source: .imported,
            packageURL: FileManager.default.temporaryDirectory
        )
        let ledger = PluginPermissionLedger(defaults: defaults)
        try expect(!ledger.isGranted(for: manifest), "Declared permissions must require preflight")
        ledger.grant(manifest, at: Date(timeIntervalSince1970: 1))
        try expect(ledger.isGranted(for: manifest), "Approval should persist")
        try expect(
            PluginPermissionLedger(defaults: defaults).isGranted(for: manifest),
            "Approval should survive controller recreation"
        )
        try expect(
            !ledger.isGranted(for: makeManifest(reason: "Post alerts and sounds.")),
            "Changing a permission declaration must invalidate approval"
        )

        ledger.revoke(identifier: manifest.identifier)
        let denied = PluginPermissionController(
            defaults: defaults,
            requestNotificationAuthorization: { false }
        )
        var deniedActivation: Bool?
        denied.requestEnable(package) { deniedActivation = $0 }
        try expect(denied.pendingRequest?.id == package.id, "Enable should open preflight")
        denied.approvePendingRequest()
        await waitUntilIdle(denied)
        try expect(deniedActivation == nil, "Denied system permission must not activate the plugin")
        try expect(denied.pendingRequest != nil, "Denied preflight should remain visible")
        try expect(denied.failureMessage != nil, "Denied preflight should explain the failure")
        denied.cancelPendingRequest()
        try expect(deniedActivation == false, "Cancel should explicitly keep the plugin disabled")

        let allowed = PluginPermissionController(
            defaults: defaults,
            requestNotificationAuthorization: { true }
        )
        var allowedActivation = false
        allowed.requestEnable(package) { allowedActivation = $0 }
        allowed.approvePendingRequest()
        await waitUntilIdle(allowed)
        try expect(allowedActivation, "Successful preflight should activate the plugin")
        try expect(allowed.pendingRequest == nil, "Successful preflight should close")
        try expect(allowed.isPreflightSatisfied(for: manifest), "Successful preflight should persist")

        var immediateActivation = false
        allowed.requestEnable(package) { immediateActivation = $0 }
        try expect(immediateActivation, "Unchanged permissions should not prompt twice")
        try expect(allowed.pendingRequest == nil, "Unchanged permissions should stay seamless")

        print("Plugin permission preflight smoke tests passed")
    }

    @MainActor
    private static func waitUntilIdle(_ controller: PluginPermissionController) async {
        for _ in 0..<100 where controller.isRequesting {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func makeManifest(reason: String) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1,
            identifier: "com.example.notification-pack",
            name: "Notification Pack",
            version: "1.0.0",
            minimumHostVersion: "0.3.2",
            author: "Tests",
            summary: "Tests notification preflight.",
            symbolName: "bell",
            kind: .resourcePack,
            entryPoint: nil,
            capabilities: ["postNotifications"],
            permissions: [
                PluginPermissionDeclaration(identifier: "postNotifications", reason: reason)
            ],
            privacyDescription: "Test only."
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw PluginPermissionTestFailure(description: message) }
    }
}
