import Foundation

struct CodexIntegrationInstaller {
    private let fileManager: FileManager
    private let supportDirectoryOverride: URL?
    private let hooksURLOverride: URL?
    private let bundleURL: URL

    init(
        fileManager: FileManager = .default,
        supportDirectory: URL? = nil,
        hooksURL: URL? = nil,
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        self.fileManager = fileManager
        supportDirectoryOverride = supportDirectory
        hooksURLOverride = hooksURL
        self.bundleURL = bundleURL
    }

    var supportDirectory: URL {
        if let supportDirectoryOverride { return supportDirectoryOverride }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexStatus", isDirectory: true)
    }

    var sessionsDirectory: URL {
        supportDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    private var installedHelperURL: URL {
        supportDirectory.appendingPathComponent("CodexStatusHook")
    }

    private var hooksURL: URL {
        if let hooksURLOverride { return hooksURLOverride }
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        return codexHome.appendingPathComponent("hooks.json")
    }

    var isInstalled: Bool {
        guard fileManager.isExecutableFile(atPath: installedHelperURL.path),
              let data = try? Data(contentsOf: hooksURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any]
        else { return false }

        return hooks.values.contains { value in
            guard let groups = value as? [Any] else { return false }
            return groups.contains { value in
                guard let group = value as? [String: Any],
                      let handlers = group["hooks"] as? [Any]
                else { return false }
                return handlers.contains { value in
                    guard let handler = value as? [String: Any] else { return false }
                    return isManagedHandler(handler)
                }
            }
        }
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
                return handlers.contains(where: isManagedHandler)
            }
            if !alreadyPresent {
                groups.append(["hooks": [handler]])
                hooks[event] = groups
            }
        }

        root["description"] = root["description"] ?? "User-level Codex lifecycle hooks."
        root["hooks"] = hooks
        let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try securelyWriteHooks(output)
    }

    func uninstall() throws {
        if fileManager.fileExists(atPath: hooksURL.path) {
            let data = try Data(contentsOf: hooksURL)
            if !data.isEmpty {
                guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                if var hooks = root["hooks"] as? [String: Any] {
                    var didRemoveHandler = false

                    for (event, value) in hooks {
                        guard let groups = value as? [Any] else { continue }
                        var remainingGroups: [Any] = []

                        for value in groups {
                            guard var group = value as? [String: Any],
                                  let handlers = group["hooks"] as? [Any]
                            else {
                                remainingGroups.append(value)
                                continue
                            }

                            let remainingHandlers = handlers.filter { value in
                                guard let handler = value as? [String: Any] else { return true }
                                return !isManagedHandler(handler)
                            }

                            guard remainingHandlers.count != handlers.count else {
                                remainingGroups.append(value)
                                continue
                            }

                            didRemoveHandler = true
                            if !remainingHandlers.isEmpty {
                                group["hooks"] = remainingHandlers
                                remainingGroups.append(group)
                            }
                        }

                        hooks[event] = remainingGroups
                    }

                    if didRemoveHandler {
                        root["hooks"] = hooks
                        let output = try JSONSerialization.data(
                            withJSONObject: root,
                            options: [.prettyPrinted, .sortedKeys]
                        )
                        try securelyWriteHooks(output)
                    }
                }
            }
        }

        if fileManager.fileExists(atPath: installedHelperURL.path) {
            try fileManager.removeItem(at: installedHelperURL)
        }
    }

    private func installHelper() throws {
        let bundled = bundleURL.appendingPathComponent("Contents/Helpers/CodexStatusHook")
        guard fileManager.fileExists(atPath: bundled.path) else { return }

        if fileManager.fileExists(atPath: installedHelperURL.path) {
            try fileManager.removeItem(at: installedHelperURL)
        }
        try fileManager.copyItem(at: bundled, to: installedHelperURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedHelperURL.path)
    }

    private func isManagedHandler(_ handler: [String: Any]) -> Bool {
        guard let command = handler["command"] as? String else { return false }
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = installedHelperURL.path
        return trimmedCommand == path
            || trimmedCommand == "\"\(path)\""
            || trimmedCommand == "'\(path)'"
    }

    private func securelyWriteHooks(_ data: Data) throws {
        let parentDirectory = hooksURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectory, withIntermediateDirectories: true)

        let temporaryURL = parentDirectory
            .appendingPathComponent(".hooks.json.\(UUID().uuidString).tmp")
        guard fileManager.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
            if fileManager.fileExists(atPath: hooksURL.path) {
                _ = try fileManager.replaceItemAt(
                    hooksURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: hooksURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksURL.path)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}
