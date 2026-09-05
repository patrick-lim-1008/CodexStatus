import Foundation

@main
struct AppUpdateCheckerLiveSmoke {
    @MainActor
    static func main() async throws {
        let checker = AppUpdateChecker(currentVersion: "0.3.0")
        checker.setEnabled(true)

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            switch checker.state {
            case .upToDate, .available:
                checker.setEnabled(false)
                print("App update network smoke test passed")
                return
            case .failed:
                throw LiveUpdateFailure("The public GitHub releases check failed")
            case .disabled, .idle, .checking:
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        throw LiveUpdateFailure("The public GitHub releases check timed out")
    }
}

private struct LiveUpdateFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
