import Foundation

struct PromptPresetPayload: Codable, Equatable, Identifiable {
    let id: String
    var title: String
    var prompt: String
    var constraints: String

    var composedText: String {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanConstraints = constraints.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanConstraints.isEmpty else { return cleanPrompt }
        return "\(cleanPrompt)\n\nConstraints:\n\(cleanConstraints)"
    }
}

struct PromptPackFile: Codable, Equatable {
    let schemaVersion: Int
    let presets: [PromptPresetPayload]
}

struct PromptPreset: Identifiable, Equatable {
    let payload: PromptPresetPayload
    let sourceName: String
    let isEditable: Bool

    var id: String { "\(sourceName)::\(payload.id)" }
    var title: String { payload.title }
    var composedText: String { payload.composedText }
}

enum PromptPackError: LocalizedError, Equatable {
    case missingFile
    case fileTooLarge
    case invalidFormat
    case unsupportedSchema(Int)
    case tooManyPresets
    case invalidPreset(String)
    case duplicateIdentifier(String)

    var errorDescription: String? {
        switch self {
        case .missingFile: "The plugin does not contain Resources/prompts.json."
        case .fileTooLarge: "The prompt pack is larger than 512 KB."
        case .invalidFormat: "The prompt pack is not valid JSON."
        case .unsupportedSchema(let version): "Prompt-pack schema \(version) is not supported."
        case .tooManyPresets: "A prompt pack can contain at most 100 presets."
        case .invalidPreset(let identifier): "Prompt preset \(identifier) is incomplete or too long."
        case .duplicateIdentifier(let identifier): "Prompt preset identifier \(identifier) is duplicated."
        }
    }
}

enum PromptLibrarySupport {
    static let maximumFileSize = 512 * 1_024
    static let maximumPresetCount = 100

    static func loadPack(at packageURL: URL) throws -> [PromptPresetPayload] {
        let url = packageURL
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("prompts.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PromptPackError.missingFile
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maximumFileSize else { throw PromptPackError.fileTooLarge }
        guard let data = try? Data(contentsOf: url),
              let pack = try? JSONDecoder().decode(PromptPackFile.self, from: data)
        else { throw PromptPackError.invalidFormat }
        guard pack.schemaVersion == 1 else {
            throw PromptPackError.unsupportedSchema(pack.schemaVersion)
        }
        guard pack.presets.count <= maximumPresetCount else { throw PromptPackError.tooManyPresets }

        var identifiers = Set<String>()
        for preset in pack.presets {
            let identifier = preset.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = preset.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = preset.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty,
                  identifier.count <= 100,
                  identifier.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }),
                  !title.isEmpty,
                  title.count <= 80,
                  !prompt.isEmpty,
                  prompt.count <= 6_000,
                  preset.constraints.count <= 4_000
            else { throw PromptPackError.invalidPreset(preset.id) }
            guard identifiers.insert(identifier).inserted else {
                throw PromptPackError.duplicateIdentifier(identifier)
            }
        }
        return pack.presets
    }
}
