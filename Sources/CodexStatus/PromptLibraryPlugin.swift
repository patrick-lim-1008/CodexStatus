import Combine
import Foundation

@MainActor
final class PromptLibraryPlugin: ObservableObject {
    @Published private(set) var presets: [PromptPreset] = []
    @Published private(set) var customPresets: [PromptPresetPayload] = []
    @Published private(set) var loadWarnings: [String] = []

    private let preferences: AppPreferences
    private let registry: PluginRegistry
    private let defaults: UserDefaults
    private var observers = Set<AnyCancellable>()
    private let customPresetsKey = "plugins.promptLibrary.customPresets"

    init(
        preferences: AppPreferences,
        registry: PluginRegistry,
        defaults: UserDefaults = .standard
    ) {
        self.preferences = preferences
        self.registry = registry
        self.defaults = defaults
        restoreCustomPresets()

        preferences.$promptLibraryEnabled
            .removeDuplicates()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &observers)
        registry.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reload() }
            }
            .store(in: &observers)
        reload()
    }

    var statusText: String {
        guard preferences.promptLibraryEnabled else { return "Off" }
        let count = presets.count
        return "\(count) \(count == 1 ? "preset" : "presets")"
    }

    func saveCustomPreset(_ preset: PromptPresetPayload) throws {
        try Self.validateCustom(preset)
        if let index = customPresets.firstIndex(where: { $0.id == preset.id }) {
            customPresets[index] = preset
        } else {
            guard customPresets.count < 50 else { throw PromptPackError.tooManyPresets }
            customPresets.append(preset)
        }
        customPresets.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        persistCustomPresets()
        reload()
    }

    func removeCustomPreset(id: String) {
        customPresets.removeAll { $0.id == id }
        persistCustomPresets()
        reload()
    }

    func refresh() {
        reload()
    }

    private func restoreCustomPresets() {
        guard let data = defaults.data(forKey: customPresetsKey),
              let decoded = try? JSONDecoder().decode([PromptPresetPayload].self, from: data)
        else { return }
        customPresets = decoded.filter { (try? Self.validateCustom($0)) != nil }
    }

    private func persistCustomPresets() {
        defaults.set(try? JSONEncoder().encode(customPresets), forKey: customPresetsKey)
    }

    private func reload() {
        guard preferences.promptLibraryEnabled else {
            presets = []
            loadWarnings = []
            return
        }

        var loaded: [PromptPreset] = customPresets.map {
            PromptPreset(payload: $0, sourceName: "My Presets", isEditable: true)
        }
        var warnings: [String] = []
        let packages = registry.plugins.filter { plugin in
            guard plugin.manifest.capabilities.contains("providePrompts") else { return false }
            return plugin.source == .bundled || registry.isImportedPluginEnabled(plugin.id)
        }
        for plugin in packages {
            do {
                loaded += try PromptLibrarySupport.loadPack(at: plugin.packageURL).map {
                    PromptPreset(payload: $0, sourceName: plugin.manifest.name, isEditable: false)
                }
            } catch {
                warnings.append("\(plugin.manifest.name): \(error.localizedDescription)")
            }
        }
        presets = loaded.sorted {
            if $0.sourceName != $1.sourceName {
                return $0.sourceName.localizedCaseInsensitiveCompare($1.sourceName) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        loadWarnings = warnings
    }

    private static func validateCustom(_ preset: PromptPresetPayload) throws {
        let title = preset.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let prompt = preset.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !preset.id.isEmpty,
              !title.isEmpty,
              title.count <= 80,
              !prompt.isEmpty,
              prompt.count <= 6_000,
              preset.constraints.count <= 4_000
        else { throw PromptPackError.invalidPreset(preset.id) }
    }
}
