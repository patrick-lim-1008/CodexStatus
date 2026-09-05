import Foundation

struct ProgressSnapshot: Equatable {
    let summary: String
    let updatedAt: Date
}

enum ProgressSidecarFailure: LocalizedError {
    case helperUnavailable
    case invalidPrompt
    case taskUnavailable
    case connectionFailed
    case forkFailed
    case startFailed
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .helperUnavailable:
            "The Progress Sidecar helper is unavailable."
        case .invalidPrompt:
            "The progress prompt must contain between 1 and 2,000 characters."
        case .taskUnavailable:
            "This task could not be loaded by the local Codex service."
        case .connectionFailed:
            "CodexStatus could not connect to the local Codex service."
        case .forkFailed:
            "Codex could not create a temporary side conversation for this task."
        case .startFailed:
            "Codex did not accept the progress request."
        case .emptyResponse:
            "The side conversation finished without a progress summary."
        }
    }
}

@MainActor
final class ProgressSidecarController {
    private struct HelperRequest: Encodable {
        let threadID: String
        let prompt: String
    }

    private struct HelperResult: Decodable {
        let ok: Bool
        let code: String
        let summary: String?
    }

    private var runningHelpers: [UUID: Process] = [:]
    private let helperURL: URL

    init(helperURL: URL) {
        self.helperURL = helperURL
    }

    func cancelAll() {
        for process in runningHelpers.values where process.isRunning {
            process.terminate()
        }
        runningHelpers.removeAll()
    }

    func request(
        threadID: String,
        prompt: String,
        completion: @escaping (Result<ProgressSnapshot, ProgressSidecarFailure>) -> Void
    ) {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty, trimmedPrompt.count <= 2_000 else {
            completion(.failure(.invalidPrompt))
            return
        }

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            completion(.failure(.helperUnavailable))
            return
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let helperID = UUID()
        process.executableURL = helperURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runningHelpers[helperID] = nil
            }
        }

        do {
            let payload = try JSONEncoder().encode(HelperRequest(
                threadID: threadID,
                prompt: trimmedPrompt
            ))
            try process.run()
            runningHelpers[helperID] = process
            try input.fileHandleForWriting.write(contentsOf: payload)
            try input.fileHandleForWriting.close()

            DispatchQueue.global(qos: .userInitiated).async {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let helperResult = try? JSONDecoder().decode(HelperResult.self, from: data)
                Task { @MainActor in
                    guard let helperResult else {
                        completion(.failure(.connectionFailed))
                        return
                    }
                    guard helperResult.ok,
                          let summary = helperResult.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !summary.isEmpty
                    else {
                        completion(.failure(Self.failure(for: helperResult.code)))
                        return
                    }
                    completion(.success(ProgressSnapshot(summary: summary, updatedAt: Date())))
                }
            }
        } catch {
            if process.isRunning { process.terminate() }
            runningHelpers[helperID] = nil
            completion(.failure(.connectionFailed))
        }
    }

    private static func failure(for code: String) -> ProgressSidecarFailure {
        switch code {
        case "invalidRequest": .invalidPrompt
        case "taskUnavailable": .taskUnavailable
        case "forkFailed": .forkFailed
        case "startFailed": .startFailed
        case "emptyResponse": .emptyResponse
        default: .connectionFailed
        }
    }
}
