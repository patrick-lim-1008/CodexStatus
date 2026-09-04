import Foundation

struct CodexIntegrationInstaller {
    private let fileManager = FileManager.default

    var supportDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexStatus", isDirectory: true)
    }

    var sessionsDirectory: URL {
        supportDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    private var installedHelperURL: URL {
        supportDirectory.appendingPathComponent("CodexStatusHook")
    }

    private var hooksURL: URL {
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return codexHome.appendingPathComponent("hooks.json")
    }

    var isInstalled: Bool {
        guard fileManager.isExecutableFile(atPath: installedHelperURL.path),
              let data = try? Data(contentsOf: hooksURL),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        return text.contains("CodexStatusHook")
    }

    func prepareSupportDirectory() {
        try? fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try? installHelper()
    }

    func install() throws {
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try installHelper()

        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: hooksURL), !data.isEmpty {
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            root = existing
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let command = "\"\(installedHelperURL.path)\""
        let handler: [String: Any] = ["type": "command", "command": command, "timeout": 2]
        let events = [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse",
            "PermissionRequest", "PostToolUse", "SubagentStart", "SubagentStop", "Stop"
        ]

        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            let alreadyPresent = groups.contains { group in
                let handlers = group["hooks"] as? [[String: Any]] ?? []
                return handlers.contains { ($0["command"] as? String)?.contains("CodexStatusHook") == true }
            }
            if !alreadyPresent {
                groups.append(["hooks": [handler]])
                hooks[event] = groups
            }
        }

        root["description"] = root["description"] ?? "User-level Codex lifecycle hooks."
        root["hooks"] = hooks
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try fileManager.createDirectory(at: hooksURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try output.write(to: hooksURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksURL.path)
    }

    private func installHelper() throws {
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CodexStatusHook")
        guard fileManager.fileExists(atPath: bundled.path) else { return }

        if fileManager.fileExists(atPath: installedHelperURL.path) {
            try fileManager.removeItem(at: installedHelperURL)
        }
        try fileManager.copyItem(at: bundled, to: installedHelperURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedHelperURL.path)
    }
}
