import Foundation

struct CodexLifecycleInstaller {
    private let fileManager = FileManager.default
    private let label = "com.local.CodexStatusWatcher"

    private var supportDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexStatus", isDirectory: true)
    }

    private var installedWatcherURL: URL {
        supportDirectory.appendingPathComponent("CodexStatusWatcher")
    }

    private var targetPathURL: URL {
        supportDirectory.appendingPathComponent("target-app-path.txt")
    }

    private var launchAgentURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    func install() throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let bundledWatcher = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/CodexStatusWatcher")
        guard fileManager.fileExists(atPath: bundledWatcher.path) else { return }

        var needsRestart = false
        let bundledData = try Data(contentsOf: bundledWatcher)
        let installedData = try? Data(contentsOf: installedWatcherURL)
        if bundledData != installedData {
            if fileManager.fileExists(atPath: installedWatcherURL.path) {
                try fileManager.removeItem(at: installedWatcherURL)
            }
            try fileManager.copyItem(at: bundledWatcher, to: installedWatcherURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedWatcherURL.path)
            needsRestart = true
        }

        let appPath = Bundle.main.bundleURL.path + "\n"
        if (try? String(contentsOf: targetPathURL, encoding: .utf8)) != appPath {
            try appPath.write(to: targetPathURL, atomically: true, encoding: .utf8)
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [installedWatcherURL.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        if (try? Data(contentsOf: launchAgentURL)) != plistData {
            try plistData.write(to: launchAgentURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: launchAgentURL.path)
            needsRestart = true
        }

        if needsRestart {
            bootstrapOrRestartAgent()
        }
    }

    private func bootstrapOrRestartAgent() {
        let domain = "gui/\(getuid())"
        runLaunchctl(["bootstrap", domain, launchAgentURL.path])
        runLaunchctl(["kickstart", "-k", "\(domain)/\(label)"])
    }

    private func runLaunchctl(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
