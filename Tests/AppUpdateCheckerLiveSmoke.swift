import Foundation

@main
struct AppUpdateCheckerLiveSmoke {
    @MainActor
    static func main() async throws {
        let downloadRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexStatusUpdateDownload-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: downloadRoot) }

        let checker = AppUpdateChecker(
            currentVersion: "0.2.2",
            downloadsDirectory: downloadRoot
        )
        checker.setEnabled(true)

        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            switch checker.state {
            case .available:
                checker.downloadAvailableUpdate()
            case .downloaded(let result, _):
                guard FileManager.default.fileExists(atPath: result.fileURL.path),
                      result.fileURL.pathExtension.lowercased() == "zip"
                else { throw LiveUpdateFailure("The release archive was not saved") }
                checker.setEnabled(false)
                print("App update check and verified download smoke test passed")
                return
            case .downloadFailed:
                throw LiveUpdateFailure("The public GitHub release archive failed validation")
            case .upToDate:
                throw LiveUpdateFailure("The live test baseline must be older than the published release")
            case .failed:
                throw LiveUpdateFailure("The public GitHub releases check failed")
            case .disabled, .idle, .checking, .downloading:
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw LiveUpdateFailure("The public GitHub update download timed out")
    }
}

private struct LiveUpdateFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
