import Combine
import CryptoKit
import Foundation

struct AppUpdateAsset: Equatable {
    let fileName: String
    let downloadURL: URL
    let size: Int?
    let sha256: String?
}

struct AvailableAppUpdate: Equatable {
    let version: String
    let title: String
    let releaseURL: URL
    let downloadAsset: AppUpdateAsset?
}

struct DownloadedAppUpdate: Equatable {
    let update: AvailableAppUpdate
    let fileURL: URL
}

enum AppUpdateState: Equatable {
    case disabled
    case idle
    case checking
    case upToDate(Date)
    case available(AvailableAppUpdate, Date)
    case downloading(AvailableAppUpdate)
    case downloaded(DownloadedAppUpdate, Date)
    case downloadFailed(AvailableAppUpdate, Date)
    case failed(Date)

    var statusText: String {
        switch self {
        case .disabled: "Off"
        case .idle: "Ready to check"
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .available(let update, _): "Version \(update.version) available"
        case .downloading(let update): "Downloading \(update.version)…"
        case .downloaded(let result, _): "Version \(result.update.version) downloaded"
        case .downloadFailed: "Download failed · try again"
        case .failed: "Could not check · try again"
        }
    }

    var actionableUpdate: AvailableAppUpdate? {
        switch self {
        case .available(let update, _), .downloadFailed(let update, _): update
        default: nil
        }
    }

    var downloadedUpdate: DownloadedAppUpdate? {
        guard case .downloaded(let result, _) = self else { return nil }
        return result
    }

    var isBusy: Bool {
        switch self {
        case .checking, .downloading: true
        default: false
        }
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let size: Int?
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case size
        case digest
    }
}

private struct GitHubReleaseResponse: Decodable {
    let tagName: String
    let name: String?
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

enum AppUpdateDownloadError: LocalizedError {
    case assetUnavailable
    case invalidResponse
    case invalidArchive
    case sizeMismatch
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .assetUnavailable: "This release does not contain a downloadable CodexStatus archive."
        case .invalidResponse: "The update server returned an invalid download response."
        case .invalidArchive: "The downloaded update is not a valid ZIP archive."
        case .sizeMismatch: "The downloaded update size does not match the release metadata."
        case .checksumMismatch: "The downloaded update checksum does not match the GitHub release."
        }
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    static let releasesEndpoint = URL(
        string: "https://api.github.com/repos/patrick-lim-1008/CodexStatus/releases/latest"
    )!
    nonisolated static let maximumDownloadSize = 100 * 1_024 * 1_024

    @Published private(set) var state: AppUpdateState = .disabled

    private let session: URLSession
    private let currentVersion: String
    private let downloadsDirectory: URL
    private let fileManager: FileManager
    private var timer: Timer?
    private var operationTask: Task<Void, Never>?

    init(
        session: URLSession = .shared,
        currentVersion: String = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.0.0",
        downloadsDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.session = session
        self.currentVersion = currentVersion
        self.fileManager = fileManager
        self.downloadsDirectory = downloadsDirectory
            ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        operationTask?.cancel()
        operationTask = nil

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
        guard !state.isBusy else { return }
        state = .checking
        operationTask?.cancel()
        operationTask = Task { [weak self] in
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

    func downloadAvailableUpdate() {
        guard let update = state.actionableUpdate else { return }
        guard let asset = update.downloadAsset else {
            state = .downloadFailed(update, Date())
            return
        }

        state = .downloading(update)
        operationTask?.cancel()
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: asset.downloadURL)
                request.timeoutInterval = 120
                request.setValue("CodexStatus/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (temporaryURL, response) = try await session.download(for: request)
                guard !Task.isCancelled,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else { throw AppUpdateDownloadError.invalidResponse }

                try Self.validateDownloadedArchive(at: temporaryURL, asset: asset)
                try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
                let destination = Self.availableDestination(
                    for: asset.fileName,
                    version: update.version,
                    in: downloadsDirectory,
                    fileManager: fileManager
                )
                try fileManager.moveItem(at: temporaryURL, to: destination)
                guard !Task.isCancelled else {
                    try? fileManager.removeItem(at: destination)
                    return
                }
                state = .downloaded(DownloadedAppUpdate(update: update, fileURL: destination), Date())
            } catch {
                guard !Task.isCancelled else { return }
                state = .downloadFailed(update, Date())
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
        let expectedName = "codexstatus-v\(version).zip"
        let asset = release.assets?.first {
            $0.name.lowercased() == expectedName
        } ?? release.assets?.first {
            $0.name.lowercased().hasSuffix(".zip")
                && $0.name.lowercased().contains("codexstatus")
        }
        return AvailableAppUpdate(
            version: version,
            title: release.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "CodexStatus \(version)",
            releaseURL: release.htmlURL,
            downloadAsset: asset.map {
                AppUpdateAsset(
                    fileName: $0.name,
                    downloadURL: $0.browserDownloadURL,
                    size: $0.size,
                    sha256: normalizedDigest($0.digest)
                )
            }
        )
    }

    nonisolated static func validateDownloadedArchive(
        at url: URL,
        asset: AppUpdateAsset
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= maximumDownloadSize else {
            throw AppUpdateDownloadError.invalidArchive
        }
        if let expectedSize = asset.size, expectedSize > 0, size != expectedSize {
            throw AppUpdateDownloadError.sizeMismatch
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let signature = try handle.read(upToCount: 4) ?? Data()
        guard signature.count >= 2, signature[0] == 0x50, signature[1] == 0x4B else {
            throw AppUpdateDownloadError.invalidArchive
        }
        if let expectedDigest = asset.sha256 {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard actual.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                throw AppUpdateDownloadError.checksumMismatch
            }
        }
    }

    nonisolated private static func availableDestination(
        for proposedName: String,
        version: String,
        in directory: URL,
        fileManager: FileManager
    ) -> URL {
        let lastComponent = URL(fileURLWithPath: proposedName).lastPathComponent
        let safeName = lastComponent.lowercased().hasSuffix(".zip")
            ? lastComponent
            : "CodexStatus-v\(version).zip"
        let base = String(safeName.dropLast(4))
        var candidate = directory.appendingPathComponent(safeName)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(suffix).zip")
            suffix += 1
        }
        return candidate
    }

    nonisolated private static func normalizedDigest(_ value: String?) -> String? {
        guard let value else { return nil }
        let lower = value.lowercased()
        let digest = lower.hasPrefix("sha256:") ? String(lower.dropFirst(7)) : lower
        guard digest.count == 64, digest.allSatisfy({ $0.isHexDigit }) else { return nil }
        return digest
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
