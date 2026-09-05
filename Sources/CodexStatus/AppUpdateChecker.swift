import Combine
import Foundation

struct AvailableAppUpdate: Equatable {
    let version: String
    let title: String
    let releaseURL: URL
}

enum AppUpdateState: Equatable {
    case disabled
    case idle
    case checking
    case upToDate(Date)
    case available(AvailableAppUpdate, Date)
    case failed(Date)

    var statusText: String {
        switch self {
        case .disabled: "Off"
        case .idle: "Ready to check"
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .available(let update, _): "Version \(update.version) available"
        case .failed: "Could not check · try again"
        }
    }

    var availableUpdate: AvailableAppUpdate? {
        guard case .available(let update, _) = self else { return nil }
        return update
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    static let releasesEndpoint = URL(
        string: "https://api.github.com/repos/patrick-lim-1008/CodexStatus/releases/latest"
    )!

    @Published private(set) var state: AppUpdateState = .disabled

    private let session: URLSession
    private let currentVersion: String
    private var timer: Timer?
    private var checkTask: Task<Void, Never>?

    init(
        session: URLSession = .shared,
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0"
    ) {
        self.session = session
        self.currentVersion = currentVersion
    }

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        checkTask?.cancel()
        checkTask = nil

        guard enabled else {
            state = .disabled
            return
        }

        if state == .disabled { state = .idle }
        checkNow()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNow() }
        }
    }

    func checkNow() {
        guard state != .checking else { return }
        state = .checking
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: Self.releasesEndpoint)
                request.timeoutInterval = 12
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("CodexStatus/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    if !Task.isCancelled { state = .failed(Date()) }
                    return
                }
                let update = try Self.availableUpdate(from: data, currentVersion: currentVersion)
                guard !Task.isCancelled else { return }
                state = update.map { .available($0, Date()) } ?? .upToDate(Date())
            } catch {
                guard !Task.isCancelled else { return }
                state = .failed(Date())
            }
        }
    }

    nonisolated static func availableUpdate(
        from data: Data,
        currentVersion: String
    ) throws -> AvailableAppUpdate? {
        let release = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        guard !release.draft, !release.prerelease else { return nil }
        let version = normalizedVersion(release.tagName)
        guard compareVersions(version, normalizedVersion(currentVersion)) == .orderedDescending else {
            return nil
        }
        return AvailableAppUpdate(
            version: version,
            title: release.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "CodexStatus \(version)",
            releaseURL: release.htmlURL
        )
    }

    nonisolated private static func normalizedVersion(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.first?.lowercased() == "v" ? String(trimmed.dropFirst()) : trimmed
    }

    nonisolated private static func compareVersions(
        _ lhs: String,
        _ rhs: String
    ) -> ComparisonResult {
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

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
