import AppKit
import Foundation

let codexBundleIdentifier = "com.openai.codex"
let statusBundleIdentifier = "com.local.CodexStatus"
let targetPathURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/CodexStatus/target-app-path.txt")

func synchronizeApps() {
    let codexIsRunning = !NSRunningApplication
        .runningApplications(withBundleIdentifier: codexBundleIdentifier)
        .isEmpty
    let statusApps = NSRunningApplication
        .runningApplications(withBundleIdentifier: statusBundleIdentifier)

    if codexIsRunning && statusApps.isEmpty {
        guard let path = try? String(contentsOf: targetPathURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path)
        else { return }
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: path),
            configuration: .init()
        )
    } else if !codexIsRunning {
        for app in statusApps { app.terminate() }
    }
}

let workspaceCenter = NSWorkspace.shared.notificationCenter
let launchObserver = workspaceCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification,
    object: nil,
    queue: .main
) { _ in synchronizeApps() }
let terminateObserver = workspaceCenter.addObserver(
    forName: NSWorkspace.didTerminateApplicationNotification,
    object: nil,
    queue: .main
) { _ in synchronizeApps() }

let fallbackTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
    synchronizeApps()
}

synchronizeApps()
RunLoop.main.run()

workspaceCenter.removeObserver(launchObserver)
workspaceCenter.removeObserver(terminateObserver)
fallbackTimer.invalidate()
