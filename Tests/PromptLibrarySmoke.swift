import Foundation

private struct PromptLibraryTestFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct PromptLibrarySmoke {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexStatusPromptTests-\(UUID().uuidString).codexstatusplugin", isDirectory: true)
        let resources = root.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let preset = PromptPresetPayload(
            id: "safe-review",
            title: "Safe Review",
            prompt: "Review the current changes.",
            constraints: "Do not modify files.\nReport evidence first."
        )
        let pack = PromptPackFile(schemaVersion: 1, presets: [preset])
        try JSONEncoder().encode(pack).write(
            to: resources.appendingPathComponent("prompts.json"),
            options: .atomic
        )

        let loaded = try PromptLibrarySupport.loadPack(at: root)
        try expect(loaded == [preset], "A valid local prompt pack must load")
        try expect(
            loaded[0].composedText == "Review the current changes.\n\nConstraints:\nDo not modify files.\nReport evidence first.",
            "Prompt and constraints must compose without losing line breaks"
        )

        let duplicate = PromptPackFile(schemaVersion: 1, presets: [preset, preset])
        try JSONEncoder().encode(duplicate).write(
            to: resources.appendingPathComponent("prompts.json"),
            options: .atomic
        )
        do {
            _ = try PromptLibrarySupport.loadPack(at: root)
            throw PromptLibraryTestFailure(description: "Duplicate preset identifiers were accepted")
        } catch PromptPackError.duplicateIdentifier("safe-review") {
            // Expected.
        }

        let oversized = PromptPackFile(schemaVersion: 1, presets: [
            PromptPresetPayload(
                id: "too-long",
                title: "Too Long",
                prompt: String(repeating: "x", count: 6_001),
                constraints: ""
            )
        ])
        try JSONEncoder().encode(oversized).write(
            to: resources.appendingPathComponent("prompts.json"),
            options: .atomic
        )
        do {
            _ = try PromptLibrarySupport.loadPack(at: root)
            throw PromptLibraryTestFailure(description: "An oversized prompt was accepted")
        } catch PromptPackError.invalidPreset("too-long") {
            // Expected.
        }

        try testPluginIntegration()

        print("Prompt Library resource-pack smoke tests passed")
    }

    @MainActor
    private static func testPluginIntegration() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("CodexStatusPromptIntegration-\(UUID().uuidString)", isDirectory: true)
        let bundledRoot = root.appendingPathComponent("bundled", isDirectory: true)
        let installedRoot = root.appendingPathComponent("installed", isDirectory: true)
        let importRoot = root.appendingPathComponent("import", isDirectory: true)
        let suiteName = "CodexStatusPromptIntegration-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw PromptLibraryTestFailure(description: "Could not create isolated defaults")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? fileManager.removeItem(at: root)
        }

        try makePromptPackage(
            at: bundledRoot.appendingPathComponent("com.codexstatus.prompt-library.codexstatusplugin"),
            identifier: "com.codexstatus.prompt-library",
            name: "Prompt & Constraint Library",
            preset: PromptPresetPayload(id: "built-in", title: "Built In", prompt: "Built in prompt", constraints: "")
        )
        try makePromptPackage(
            at: importRoot.appendingPathComponent("com.friend.prompts.codexstatusplugin"),
            identifier: "com.friend.prompts",
            name: "Friend Prompts",
            preset: PromptPresetPayload(id: "friend", title: "Friend Preset", prompt: "Friend prompt", constraints: "Be concise.")
        )

        let registry = PluginRegistry(
            bundledRoot: bundledRoot,
            installedRoot: installedRoot,
            hostVersion: "0.3.0",
            defaults: defaults
        )
        let preferences = AppPreferences(
            defaults: defaults,
            existingHooksInstalled: false,
            existingLifecycleInstalled: false
        )
        preferences.promptLibraryEnabled = true
        let library = PromptLibraryPlugin(
            preferences: preferences,
            registry: registry,
            defaults: defaults
        )
        try expect(library.presets.map(\.title) == ["Built In"], "Bundled prompt presets must appear when enabled")

        let custom = PromptPresetPayload(
            id: "mine",
            title: "My Preset",
            prompt: "My prompt",
            constraints: "Keep it local."
        )
        try library.saveCustomPreset(custom)
        try expect(library.presets.contains { $0.title == "My Preset" }, "A custom preset must appear immediately")
        let restored = PromptLibraryPlugin(
            preferences: preferences,
            registry: registry,
            defaults: defaults
        )
        try expect(restored.customPresets == [custom], "Custom presets must survive a restart")

        let importedURL = importRoot.appendingPathComponent("com.friend.prompts.codexstatusplugin")
        _ = try registry.importPlugin(from: importedURL)
        registry.setImportedPlugin("com.friend.prompts", enabled: true)
        library.refresh()
        try expect(library.presets.contains { $0.title == "Friend Preset" }, "Enabled imported prompt packs must feed the picker")
    }

    private static func makePromptPackage(
        at packageURL: URL,
        identifier: String,
        name: String,
        preset: PromptPresetPayload
    ) throws {
        let resources = packageURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let manifest = PluginManifest(
            schemaVersion: 1,
            identifier: identifier,
            name: name,
            version: "1.0.0",
            minimumHostVersion: "0.3.0",
            author: "Test",
            summary: "Test prompt pack",
            symbolName: "text.badge.plus",
            kind: .resourcePack,
            entryPoint: nil,
            capabilities: ["providePrompts"],
            privacyDescription: "Local test prompts."
        )
        try JSONEncoder().encode(manifest).write(
            to: packageURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try JSONEncoder().encode(PromptPackFile(schemaVersion: 1, presets: [preset])).write(
            to: resources.appendingPathComponent("prompts.json"),
            options: .atomic
        )
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        if !condition() { throw PromptLibraryTestFailure(description: message) }
    }
}
