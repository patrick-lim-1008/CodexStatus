import Foundation

struct CodexLifecycleInstaller {
    private let fileManager: FileManager
    private let label = "com.local.CodexStatusWatcher"
    private let supportDirectoryOverride: URL?
    private let launchAgentsDirectoryOverride: URL?
    private let bundleURL: URL
    private let serviceUID: uid_t
    private let launchctlRunner: (([String]) -> Int32?)?

    init(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil,
        launchAgentsDirectory: URL? = nil,
        bundleURL: URL = Bundle.main.bundleURL,
        serviceUID: uid_t = getuid(),
        launchctlRunner: (([String]) -> Int32?)? = nil
    ) {
        self.fileManager = fileManager
        supportDirectoryOverride = supportDirectory
        launchAgentsDirectoryOverride = launchAgentsDirectory
        self.bundleURL = bundleURL
        self.serviceUID = serviceUID
        self.launchctlRunner = launchctlRunner
    }

    private var supportDirectory: URL {
        if let supportDirectoryOverride { return supportDirectoryOverride }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexStatus", isDirectory: true)
    }

    private var installedWatcherURL: URL {
        supportDirectory.appendingPathComponent("CodexStatusWatcher")
    }

    private var targetPathURL: URL {
        supportDirectory.appendingPathComponent("target-app-path.txt")
    }

    private var launchAgentURL: URL {
        let directory = launchAgentsDirectoryOverride
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        return directory
            .appendingPathComponent("\(label).plist")
    }

    private var serviceTarget: String {
        "gui/\(serviceUID)/\(label)"
    }

    var isInstalled: Bool {
        guard fileManager.isExecutableFile(atPath: installedWatcherURL.path),
              let plistData = try? Data(contentsOf: launchAgentURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: plistData,
                options: [],
                format: nil
              ) as? [String: Any],
              plist["Label"] as? String == label,
              let arguments = plist["ProgramArguments"] as? [String],
              arguments.first == installedWatcherURL.path,
              let targetPath = try? String(contentsOf: targetPathURL, encoding: .utf8),
              !targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        return true
    }

    func install() throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgentURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let bundledWatcher = bundleURL
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
            bootoutAgent()
            bootstrapOrRestartAgent()
        } else if !isAgentLoaded {
            bootstrapOrRestartAgent()
        }
    }

    func uninstall() throws {
        bootoutAgent()

        for url in [launchAgentURL, installedWatcherURL, targetPathURL] {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private func bootstrapOrRestartAgent() {
        let domain = "gui/\(serviceUID)"
        runLaunchctl(["bootstrap", domain, launchAgentURL.path])
        runLaunchctl(["kickstart", "-k", serviceTarget])
    }

    private var isAgentLoaded: Bool {
        runLaunchctl(["print", serviceTarget]) == 0
    }

    private func bootoutAgent() {
        runLaunchctl(["bootout", serviceTarget])
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32? {
        if let launchctlRunner { return launchctlRunner(arguments) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return nil
        }
    }
}
