import Combine
import Foundation

enum PluginKind: String, Codable, Sendable {
    case native
    case resourcePack
}

struct PluginManifest: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let identifier: String
    let name: String
    let version: String
    let minimumHostVersion: String
    let author: String
    let summary: String
    let symbolName: String
    let kind: PluginKind
    let entryPoint: String?
    let capabilities: [String]
    let privacyDescription: String

    var id: String { identifier }
}

enum PluginSource: String, Equatable, Sendable {
    case bundled = "Bundled plugin"
    case imported = "Imported"
}

struct InstalledPlugin: Identifiable, Equatable, Sendable {
    let manifest: PluginManifest
    let source: PluginSource
    let packageURL: URL

    var id: String { manifest.identifier }
}

enum PluginRegistryError: LocalizedError {
    case notPluginPackage
    case missingManifest
    case manifestTooLarge
    case invalidManifest
    case unsupportedSchema(Int)
    case invalidIdentifier
    case invalidVersion
    case incompatibleHost(String)
    case externalNativeCodeNotAllowed
    case bundledIdentifierConflict
    case unsafePackage(String)
    case packageTooLarge
    case olderVersion
    case installFailed
    case notImported

    var errorDescription: String? {
        switch self {
        case .notPluginPackage: "Choose a .codexstatusplugin package."
        case .missingManifest: "The plugin package does not contain manifest.json."
        case .manifestTooLarge: "The plugin manifest is larger than 128 KB."
        case .invalidManifest: "The plugin manifest is incomplete or invalid."
        case .unsupportedSchema(let version): "Plugin schema version \(version) is not supported."
        case .invalidIdentifier: "The plugin identifier must use reverse-domain form, such as com.example.plugin."
        case .invalidVersion: "The plugin version must contain only numeric components."
        case .incompatibleHost(let version): "This plugin requires CodexStatus \(version) or later."
        case .externalNativeCodeNotAllowed: "PluginKit v1 does not execute imported native code. Import a resource-pack plugin instead."
        case .bundledIdentifierConflict: "An imported plugin cannot replace a bundled plugin."
        case .unsafePackage(let item): "The plugin contains an unsafe item: \(item)."
        case .packageTooLarge: "The plugin exceeds the 25 MB or 256-file safety limit."
        case .olderVersion: "The imported plugin is older than the installed version."
        case .installFailed: "CodexStatus could not install this plugin."
        case .notImported: "Only imported plugins can be removed."
        }
    }
}

@MainActor
final class PluginRegistry: ObservableObject {
    static let supportedSchemaVersion = 1
    static let maximumManifestSize = 128 * 1_024
    static let maximumPackageSize = 25 * 1_024 * 1_024
    static let maximumFileCount = 256

    @Published private(set) var plugins: [InstalledPlugin] = []
    @Published private(set) var enabledImportedPluginIDs: Set<String> = []

    private let bundledRoot: URL
    private let installedRoot: URL
    private let defaults: UserDefaults
    private let hostVersion: String
    private let fileManager: FileManager
    private let enabledKey = "plugins.imported.enabledIdentifiers"

    convenience init(defaults: UserDefaults = .standard) {
        let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let installedRoot = supportRoot
            .appendingPathComponent("CodexStatus", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
        let bundledRoot = Bundle.main.resourceURL?
            .appendingPathComponent("Plugins", isDirectory: true)
            ?? Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/Plugins", isDirectory: true)
        let hostVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.2.2"
        self.init(
            bundledRoot: bundledRoot,
            installedRoot: installedRoot,
            hostVersion: hostVersion,
            defaults: defaults
        )
    }

    init(
        bundledRoot: URL,
        installedRoot: URL,
        hostVersion: String,
        defaults: UserDefaults,
        fileManager: FileManager = .default
    ) {
        self.bundledRoot = bundledRoot
        self.installedRoot = installedRoot
        self.hostVersion = hostVersion
        self.defaults = defaults
        self.fileManager = fileManager
        enabledImportedPluginIDs = Set(defaults.stringArray(forKey: enabledKey) ?? [])
        reload()
    }

    var bundledPlugins: [InstalledPlugin] {
        plugins.filter { $0.source == .bundled }
    }

    var importedPlugins: [InstalledPlugin] {
        plugins.filter { $0.source == .imported }
    }

    var installedPluginsDirectory: URL { installedRoot }

    func prepareInstalledPluginsDirectory() throws {
        try fileManager.createDirectory(at: installedRoot, withIntermediateDirectories: true)
    }

    func plugin(identifier: String) -> InstalledPlugin? {
        plugins.first { $0.id == identifier }
    }

    func isImportedPluginEnabled(_ identifier: String) -> Bool {
        enabledImportedPluginIDs.contains(identifier)
    }

    func setImportedPlugin(_ identifier: String, enabled: Bool) {
        guard importedPlugins.contains(where: { $0.id == identifier }) else { return }
        if enabled {
            enabledImportedPluginIDs.insert(identifier)
        } else {
            enabledImportedPluginIDs.remove(identifier)
        }
        persistEnabledPlugins()
    }

    func reload() {
        let bundled = scan(root: bundledRoot, source: .bundled)
        let imported = scan(root: installedRoot, source: .imported)
            .filter { candidate in !bundled.contains { $0.id == candidate.id } }
        plugins = (bundled + imported).sorted {
            if $0.source != $1.source { return $0.source == .bundled }
            return $0.manifest.name.localizedCaseInsensitiveCompare($1.manifest.name) == .orderedAscending
        }
        enabledImportedPluginIDs.formIntersection(Set(imported.map(\.id)))
        persistEnabledPlugins()
    }

    @discardableResult
    func importPlugin(from sourceURL: URL) throws -> InstalledPlugin {
        let standardizedSource = sourceURL.standardizedFileURL
        guard standardizedSource.pathExtension == "codexstatusplugin" else {
            throw PluginRegistryError.notPluginPackage
        }

        let candidate = try validatePackage(at: standardizedSource, source: .imported)
        guard candidate.manifest.kind == .resourcePack else {
            throw PluginRegistryError.externalNativeCodeNotAllowed
        }
        guard !bundledPlugins.contains(where: { $0.id == candidate.id }) else {
            throw PluginRegistryError.bundledIdentifierConflict
        }
        if let existing = importedPlugins.first(where: { $0.id == candidate.id }),
           Self.compareVersions(candidate.manifest.version, existing.manifest.version) == .orderedAscending {
            throw PluginRegistryError.olderVersion
        }

        try fileManager.createDirectory(at: installedRoot, withIntermediateDirectories: true)
        let stagingURL = installedRoot.appendingPathComponent(".import-\(UUID().uuidString).codexstatusplugin")
        let targetURL = installedRoot.appendingPathComponent("\(candidate.id).codexstatusplugin")
        let backupURL = installedRoot.appendingPathComponent(".backup-\(UUID().uuidString).codexstatusplugin")

        do {
            try fileManager.copyItem(at: standardizedSource, to: stagingURL)
            _ = try validatePackage(at: stagingURL, source: .imported)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.moveItem(at: targetURL, to: backupURL)
            }
            do {
                try fileManager.moveItem(at: stagingURL, to: targetURL)
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
            } catch {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try? fileManager.moveItem(at: backupURL, to: targetURL)
                }
                throw error
            }
        } catch let error as PluginRegistryError {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw PluginRegistryError.installFailed
        }

        reload()
        guard let installed = importedPlugins.first(where: { $0.id == candidate.id }) else {
            throw PluginRegistryError.installFailed
        }
        return installed
    }

    func removePlugin(identifier: String) throws {
        guard let plugin = importedPlugins.first(where: { $0.id == identifier }) else {
            throw PluginRegistryError.notImported
        }
        do {
            try fileManager.removeItem(at: plugin.packageURL)
            enabledImportedPluginIDs.remove(identifier)
            reload()
        } catch {
            throw PluginRegistryError.installFailed
        }
    }

    private func scan(root: URL, source: PluginSource) -> [InstalledPlugin] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == "codexstatusplugin" else { return nil }
            return try? validatePackage(at: url, source: source)
        }
    }

    private func validatePackage(at packageURL: URL, source: PluginSource) throws -> InstalledPlugin {
        let values = try? packageURL.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { throw PluginRegistryError.notPluginPackage }
        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PluginRegistryError.missingManifest
        }
        let manifestAttributes = try? fileManager.attributesOfItem(atPath: manifestURL.path)
        let manifestSize = (manifestAttributes?[.size] as? NSNumber)?.intValue ?? 0
        guard manifestSize > 0, manifestSize <= Self.maximumManifestSize else {
            throw PluginRegistryError.manifestTooLarge
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            throw PluginRegistryError.invalidManifest
        }

        try validate(manifest: manifest, source: source)
        try validatePackageContents(
            at: packageURL,
            allowsExecutables: source == .bundled && manifest.kind == .native
        )
        return InstalledPlugin(manifest: manifest, source: source, packageURL: packageURL)
    }

    private func validate(manifest: PluginManifest, source: PluginSource) throws {
        guard manifest.schemaVersion == Self.supportedSchemaVersion else {
            throw PluginRegistryError.unsupportedSchema(manifest.schemaVersion)
        }
        let identifierPattern = #"^[A-Za-z0-9][A-Za-z0-9-]*(\.[A-Za-z0-9][A-Za-z0-9-]*){2,}$"#
        guard manifest.identifier.range(of: identifierPattern, options: .regularExpression) != nil,
              manifest.identifier.count <= 160 else {
            throw PluginRegistryError.invalidIdentifier
        }
        guard Self.isValidVersion(manifest.version), Self.isValidVersion(manifest.minimumHostVersion) else {
            throw PluginRegistryError.invalidVersion
        }
        guard Self.compareVersions(manifest.minimumHostVersion, hostVersion) != .orderedDescending else {
            throw PluginRegistryError.incompatibleHost(manifest.minimumHostVersion)
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manifest.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 80,
              manifest.summary.count <= 280,
              manifest.privacyDescription.count <= 500,
              manifest.capabilities.count <= 24 else {
            throw PluginRegistryError.invalidManifest
        }
        if source == .imported, manifest.kind == .native {
            throw PluginRegistryError.externalNativeCodeNotAllowed
        }
        if manifest.kind == .native,
           manifest.entryPoint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw PluginRegistryError.invalidManifest
        }
    }

    private func validatePackageContents(at packageURL: URL, allowsExecutables: Bool) throws {
        guard let enumerator = fileManager.enumerator(
            at: packageURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { throw PluginRegistryError.invalidManifest }

        var fileCount = 0
        var totalSize = 0
        for case let itemURL as URL in enumerator {
            let values = try itemURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            let relativeName = itemURL.path.replacingOccurrences(of: packageURL.path + "/", with: "")
            if values.isSymbolicLink == true {
                throw PluginRegistryError.unsafePackage(relativeName)
            }
            guard values.isRegularFile == true else { continue }
            fileCount += 1
            totalSize += values.fileSize ?? 0
            let attributes = try fileManager.attributesOfItem(atPath: itemURL.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            if !allowsExecutables, permissions & 0o111 != 0 {
                throw PluginRegistryError.unsafePackage(relativeName)
            }
            if fileCount > Self.maximumFileCount || totalSize > Self.maximumPackageSize {
                throw PluginRegistryError.packageTooLarge
            }
        }
    }

    private func persistEnabledPlugins() {
        defaults.set(enabledImportedPluginIDs.sorted(), forKey: enabledKey)
    }

    private static func isValidVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.count <= 4 && parts.allSatisfy { !$0.isEmpty && Int($0) != nil }
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }
}

enum PluginCapabilityLabels {
    private static let labels: [String: String] = [
        "readLocalUsage": "Reads local usage limits",
        "readTaskActivity": "Reads local task activity",
        "openCodexTasks": "Opens selected Codex tasks",
        "installCodexHooks": "Adds Codex lifecycle hooks",
        "postNotifications": "Posts macOS notifications",
        "playSounds": "Plays notification sounds",
        "installLifecycleWatcher": "Adds a local lifecycle watcher",
        "accessGitHubReleases": "Checks public GitHub releases",
        "createEphemeralSideConversation": "Creates temporary side conversations",
        "useModelQuota": "Uses Codex model quota",
        "providePrompts": "Provides prompt presets",
        "provideThemes": "Provides appearance themes",
        "providePetAssets": "Provides pet artwork"
    ]

    static func title(for capability: String) -> String {
        labels[capability] ?? capability
    }
}

@MainActor
protocol NativePluginRuntime: AnyObject {
    var identifier: String { get }
    var isRunning: Bool { get }
    func start()
    func stop()
}
