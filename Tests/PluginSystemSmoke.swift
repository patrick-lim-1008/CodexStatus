import Foundation

private struct PluginTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct PluginSystemSmoke {
    @MainActor
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexStatusPluginTests-\(UUID().uuidString)", isDirectory: true)
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let installedRoot = root.appendingPathComponent("installed", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        try fileManager.createDirectory(at: bundledRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let suiteName = "CodexStatusPluginTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let bundledManifest = manifest(
            identifier: "com.codexstatus.test-native",
            version: "1.0.0",
            kind: .native,
            entryPoint: "test-native",
            capabilities: ["readTaskActivity"]
        )
        try makePackage(named: "Native", manifest: bundledManifest, in: bundledRoot)

        var registry = PluginRegistry(
            bundledRoot: bundledRoot,
            installedRoot: installedRoot,
            hostVersion: "0.2.2",
            defaults: defaults
        )
        try expect(registry.bundledPlugins.count == 1, "Bundled native plugin should load")

        let importedManifest = manifest(
            identifier: "com.example.prompt-pack",
            version: "1.0.0",
            kind: .resourcePack,
            capabilities: ["providePrompts", "writeClipboard"],
            permissions: [
                PluginPermissionDeclaration(
                    identifier: "writeClipboard",
                    reason: "Copy a selected prompt."
                )
            ]
        )
        let importedSource = try makePackage(named: "Prompts", manifest: importedManifest, in: sourceRoot)
        let imported = try registry.importPlugin(from: importedSource)
        try expect(imported.source == .imported, "Valid resource pack should import")
        try expect(!registry.isImportedPluginEnabled(imported.id), "Imported plugin should default disabled")

        registry.setImportedPlugin(imported.id, enabled: true)
        try expect(
            !registry.isImportedPluginEnabled(imported.id),
            "Registry must reject activation before permission preflight"
        )
        PluginPermissionLedger(defaults: defaults).grant(imported.manifest)
        registry.setImportedPlugin(imported.id, enabled: true)
        registry = PluginRegistry(
            bundledRoot: bundledRoot,
            installedRoot: installedRoot,
            hostVersion: "0.2.2",
            defaults: defaults
        )
        try expect(registry.isImportedPluginEnabled(imported.id), "Enabled state should persist")

        let updatedManifest = manifest(
            identifier: imported.id,
            version: "1.1.0",
            kind: .resourcePack,
            capabilities: ["providePrompts", "writeClipboard"],
            permissions: [
                PluginPermissionDeclaration(
                    identifier: "writeClipboard",
                    reason: "Copy a selected prompt and its constraints."
                )
            ]
        )
        let updatedSource = try makePackage(named: "PromptsUpdated", manifest: updatedManifest, in: sourceRoot)
        let updated = try registry.importPlugin(from: updatedSource)
        try expect(
            !registry.isImportedPluginEnabled(updated.id),
            "A changed permission declaration must disable an updated plugin before it can run"
        )
        try expect(
            registry.permissionBlockedImportedPluginIDs.contains(updated.id),
            "Updated plugins that were enabled should be queued for permission review"
        )

        let older = manifest(
            identifier: imported.id,
            version: "0.9.0",
            kind: .resourcePack,
            capabilities: ["providePrompts"]
        )
        let olderSource = try makePackage(named: "Older", manifest: older, in: sourceRoot)
        try expectRegistryError(.olderVersion) { try registry.importPlugin(from: olderSource) }

        let externalNative = manifest(
            identifier: "com.example.unsafe-native",
            version: "1.0.0",
            kind: .native,
            entryPoint: "payload",
            capabilities: []
        )
        let nativeSource = try makePackage(named: "ExternalNative", manifest: externalNative, in: sourceRoot)
        try expectRegistryError(.externalNativeCodeNotAllowed) { try registry.importPlugin(from: nativeSource) }

        let incompatible = manifest(
            identifier: "com.example.future-pack",
            version: "1.0.0",
            minimumHostVersion: "9.0.0",
            kind: .resourcePack,
            capabilities: []
        )
        let futureSource = try makePackage(named: "Future", manifest: incompatible, in: sourceRoot)
        try expectRegistryError(.incompatibleHost("9.0.0")) { try registry.importPlugin(from: futureSource) }

        let unknownPermission = manifest(
            identifier: "com.example.unknown-permission",
            version: "1.0.0",
            kind: .resourcePack,
            capabilities: ["readEverything"],
            permissions: [
                PluginPermissionDeclaration(identifier: "readEverything", reason: "Read everything.")
            ]
        )
        let unknownSource = try makePackage(named: "UnknownPermission", manifest: unknownPermission, in: sourceRoot)
        try expectRegistryError(.unsupportedPermission("readEverything")) {
            try registry.importPlugin(from: unknownSource)
        }

        let mismatchedPermission = manifest(
            identifier: "com.example.mismatched-permission",
            version: "1.0.0",
            kind: .resourcePack,
            capabilities: ["providePrompts"],
            permissions: [
                PluginPermissionDeclaration(identifier: "writeClipboard", reason: "Copy a selected prompt.")
            ]
        )
        let mismatchSource = try makePackage(named: "MismatchedPermission", manifest: mismatchedPermission, in: sourceRoot)
        try expectRegistryError(.invalidPermissions) { try registry.importPlugin(from: mismatchSource) }

        let legacyJSON = """
        {
          "schemaVersion": 1,
          "identifier": "com.example.legacy-pack",
          "name": "Legacy Pack",
          "version": "1.0.0",
          "minimumHostVersion": "0.2.2",
          "author": "Tests",
          "summary": "No permissions field.",
          "symbolName": "puzzlepiece",
          "kind": "resourcePack",
          "capabilities": ["providePrompts"],
          "privacyDescription": "Test only."
        }
        """
        let legacy = try JSONDecoder().decode(PluginManifest.self, from: Data(legacyJSON.utf8))
        try expect(legacy.permissions.isEmpty, "Legacy manifests should decode with no permissions")

        let executableManifest = manifest(
            identifier: "com.example.executable-pack",
            version: "1.0.0",
            kind: .resourcePack,
            capabilities: []
        )
        let executableSource = try makePackage(named: "Executable", manifest: executableManifest, in: sourceRoot)
        let executableURL = executableSource.appendingPathComponent("payload.sh")
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try expectUnsafePackage { try registry.importPlugin(from: executableSource) }

        let symlinkManifest = manifest(
            identifier: "com.example.symlink-pack",
            version: "1.0.0",
            kind: .resourcePack,
            capabilities: []
        )
        let symlinkSource = try makePackage(named: "Symlink", manifest: symlinkManifest, in: sourceRoot)
        try fileManager.createSymbolicLink(
            at: symlinkSource.appendingPathComponent("outside"),
            withDestinationURL: URL(fileURLWithPath: "/tmp")
        )
        try expectUnsafePackage { try registry.importPlugin(from: symlinkSource) }

        try registry.removePlugin(identifier: imported.id)
        try expect(registry.importedPlugins.isEmpty, "Imported plugin should be removable")
        try expect(!registry.isImportedPluginEnabled(imported.id), "Removal should clear enabled state")

        if let bundledPath = ProcessInfo.processInfo.environment["CODEX_STATUS_VALIDATE_BUNDLED_ROOT"] {
            let appRegistry = PluginRegistry(
                bundledRoot: URL(fileURLWithPath: bundledPath, isDirectory: true),
                installedRoot: root.appendingPathComponent("app-installed", isDirectory: true),
                hostVersion: "0.3.2",
                defaults: defaults
            )
            try expect(
                appRegistry.plugin(identifier: "com.codexstatus.progress-sidecar") != nil,
                "Built app must load the Progress Sidecar manifest"
            )
            try expect(
                appRegistry.plugin(identifier: "com.codexstatus.prompt-library") != nil,
                "Built app must load the Prompt Library manifest"
            )
        }
        print("PluginKit import and security smoke tests passed")
    }

    private static func manifest(
        identifier: String,
        version: String,
        minimumHostVersion: String = "0.2.2",
        kind: PluginKind,
        entryPoint: String? = nil,
        capabilities: [String],
        permissions: [PluginPermissionDeclaration] = []
    ) -> PluginManifest {
        PluginManifest(
            schemaVersion: 1,
            identifier: identifier,
            name: identifier,
            version: version,
            minimumHostVersion: minimumHostVersion,
            author: "Tests",
            summary: "Test plugin",
            symbolName: "puzzlepiece",
            kind: kind,
            entryPoint: entryPoint,
            capabilities: capabilities,
            permissions: permissions,
            privacyDescription: "Test data only."
        )
    }

    @discardableResult
    private static func makePackage(
        named name: String,
        manifest: PluginManifest,
        in root: URL
    ) throws -> URL {
        let packageURL = root.appendingPathComponent("\(name).codexstatusplugin", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: packageURL.appendingPathComponent("manifest.json"))
        return packageURL
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw PluginTestFailure(description: message) }
    }

    private static func expectRegistryError(
        _ expected: PluginRegistryError,
        operation: () throws -> Void
    ) throws {
        do {
            try operation()
            throw PluginTestFailure(description: "Expected plugin registry error")
        } catch let error as PluginRegistryError {
            switch (expected, error) {
            case (.olderVersion, .olderVersion),
                 (.externalNativeCodeNotAllowed, .externalNativeCodeNotAllowed),
                 (.incompatibleHost, .incompatibleHost),
                 (.unsupportedPermission, .unsupportedPermission),
                 (.invalidPermissions, .invalidPermissions): return
            default: throw PluginTestFailure(description: "Unexpected registry error: \(error)")
            }
        }
    }

    private static func expectUnsafePackage(operation: () throws -> Void) throws {
        do {
            try operation()
            throw PluginTestFailure(description: "Unsafe plugin package was accepted")
        } catch PluginRegistryError.unsafePackage {
            return
        }
    }

}
