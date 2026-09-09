import Foundation

struct CodexIntegrationInstaller {
    private let fileManager: FileManager
    private let supportDirectoryOverride: URL?
    private let hooksURLOverride: URL?
    private let bundleURL: URL
    private let shouldManageHookTrust: Bool

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
        shouldManageHookTrust = supportDirectory == nil && hooksURL == nil
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
        if shouldManageHookTrust {
            try CodexHookTrustManager(
                hooksURL: hooksURL,
                helperURL: installedHelperURL
            ).trustOwnedHooks()
        }
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

struct CodexHookTrustManager {
    private enum TrustError: LocalizedError {
        case codexNotFound
        case serverUnavailable
        case hooksNotDiscovered
        case trustRejected

        var errorDescription: String? {
            switch self {
            case .codexNotFound:
                "Codex is not installed."
            case .serverUnavailable:
                "Codex did not respond while verifying Enhanced Activity."
            case .hooksNotDiscovered:
                "Codex could not find the Enhanced Activity hooks."
            case .trustRejected:
                "Codex did not accept the Enhanced Activity hook trust record."
            }
        }
    }

    private let hooksURL: URL
    private let helperURL: URL

    init(hooksURL: URL, helperURL: URL) {
        self.hooksURL = hooksURL.standardizedFileURL
        self.helperURL = helperURL.standardizedFileURL
    }

    func trustOwnedHooks() throws {
        guard let codexURL = codexExecutableURL() else {
            throw TrustError.codexNotFound
        }

        let server = Process()
        let input = Pipe()
        let output = Pipe()
        server.executableURL = codexURL
        server.arguments = ["app-server", "--listen", "stdio://"]
        server.standardInput = input
        server.standardOutput = output
        server.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var buffer = Data()
        var resultError: Error?
        var didFinish = false

        func finish(_ error: Error? = nil) {
            guard !didFinish else { return }
            didFinish = true
            resultError = error
            semaphore.signal()
        }

        func send(_ message: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: message)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data("\n".utf8))
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            lock.lock()
            defer { lock.unlock() }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let messageID = (message["id"] as? NSNumber)?.intValue
                else { continue }

                do {
                    switch messageID {
                    case 0:
                        try send(["method": "initialized", "params": [:]])
                        try send([
                            "method": "hooks/list",
                            "id": 1,
                            "params": ["cwds": [FileManager.default.homeDirectoryForCurrentUser.path]]
                        ])
                    case 1:
                        guard message["error"] == nil,
                              let response = message["result"] as? [String: Any]
                        else {
                            finish(TrustError.serverUnavailable)
                            continue
                        }
                        let ownedHooks = Self.ownedHooks(
                            in: response,
                            hooksURL: hooksURL,
                            helperURL: helperURL
                        )
                        guard !ownedHooks.isEmpty else {
                            finish(TrustError.hooksNotDiscovered)
                            continue
                        }
                        let updates = Self.trustUpdates(for: ownedHooks)
                        guard !updates.isEmpty else {
                            finish()
                            continue
                        }
                        try send([
                            "method": "config/batchWrite",
                            "id": 2,
                            "params": [
                                "edits": [[
                                    "keyPath": "hooks.state",
                                    "value": updates,
                                    "mergeStrategy": "upsert"
                                ]],
                                "reloadUserConfig": true
                            ]
                        ])
                    case 2:
                        guard message["error"] == nil,
                              let response = message["result"] as? [String: Any],
                              ["ok", "okOverridden"].contains(response["status"] as? String ?? "")
                        else {
                            finish(TrustError.trustRejected)
                            continue
                        }
                        try send([
                            "method": "hooks/list",
                            "id": 3,
                            "params": ["cwds": [FileManager.default.homeDirectoryForCurrentUser.path]]
                        ])
                    case 3:
                        guard message["error"] == nil,
                              let response = message["result"] as? [String: Any]
                        else {
                            finish(TrustError.serverUnavailable)
                            continue
                        }
                        let ownedHooks = Self.ownedHooks(
                            in: response,
                            hooksURL: hooksURL,
                            helperURL: helperURL
                        )
                        let allTrusted = !ownedHooks.isEmpty && ownedHooks.allSatisfy {
                            ["trusted", "managed"].contains($0["trustStatus"] as? String ?? "")
                        }
                        finish(allTrusted ? nil : TrustError.trustRejected)
                    default:
                        break
                    }
                } catch {
                    finish(error)
                }
            }
        }

        do {
            try server.run()
            try send([
                "method": "initialize",
                "id": 0,
                "params": [
                    "clientInfo": [
                        "name": "codex_status",
                        "title": "CodexStatus",
                        "version": "0.3.2"
                    ]
                ]
            ])
            if semaphore.wait(timeout: .now() + 8) == .timedOut {
                resultError = TrustError.serverUnavailable
            }
        } catch {
            resultError = error
        }

        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if server.isRunning { server.terminate() }
        if let resultError { throw resultError }
    }

    private func codexExecutableURL() -> URL? {
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map { URL(fileURLWithPath: $0) }
    }

    static func ownedHooks(
        in response: [String: Any],
        hooksURL: URL,
        helperURL: URL
    ) -> [[String: Any]] {
        let expectedSource = hooksURL.standardizedFileURL.path
        let expectedCommand = helperURL.standardizedFileURL.path
        let entries = response["data"] as? [[String: Any]] ?? []
        return entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.filter { hook in
            guard let sourcePath = hook["sourcePath"] as? String,
                  URL(fileURLWithPath: sourcePath).standardizedFileURL.path == expectedSource,
                  let command = hook["command"] as? String
            else { return false }
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed == expectedCommand
                || trimmed == "\"\(expectedCommand)\""
                || trimmed == "'\(expectedCommand)'"
        }
    }

    static func trustUpdates(for hooks: [[String: Any]]) -> [String: Any] {
        hooks.reduce(into: [:]) { updates, hook in
            guard ["untrusted", "modified"].contains(hook["trustStatus"] as? String ?? ""),
                  let key = hook["key"] as? String,
                  !key.isEmpty,
                  let currentHash = hook["currentHash"] as? String,
                  !currentHash.isEmpty
            else { return }
            updates[key] = ["trusted_hash": currentHash]
        }
    }
}
