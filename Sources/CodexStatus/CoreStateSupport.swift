import Foundation

enum TaskLifecycleResolution: Equatable {
    case idle
    case working
    case needsAttention
    case completed
    case aborted
}

enum CoreTaskStatePolicy {
    static func resolve(
        statusType: String,
        activeFlags: [String],
        rolloutLifecycle: String
    ) -> TaskLifecycleResolution {
        if rolloutLifecycle == "completed" { return .completed }
        if rolloutLifecycle == "aborted" { return .aborted }
        if statusType == "active" && activeFlags.contains("waitingOnApproval") {
            return .needsAttention
        }
        if statusType == "active" || rolloutLifecycle == "running" {
            return .working
        }
        return .idle
    }

    static func shouldUseHookSignal(
        isAttentionOrError: Bool,
        hookUpdatedAt: Date,
        discoveredUpdatedAt: Date
    ) -> Bool {
        isAttentionOrError && hookUpdatedAt >= discoveredUpdatedAt
    }
}

struct CompletionLedger {
    static let trackingStartedAtKey = "doneTrackingStartedAt.v1"
    static let acknowledgementsKey = "acknowledgedCompletions.v1"
    static let maximumAcknowledgements = 2_048

    private(set) var trackingStartedAt: Double
    private(set) var acknowledgements: [String: Double]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, now: Date = Date()) {
        self.defaults = defaults
        let nowValue = now.timeIntervalSince1970
        let storedStart = (defaults.object(forKey: Self.trackingStartedAtKey) as? NSNumber)?.doubleValue
        if let storedStart,
           storedStart.isFinite,
           storedStart > 0,
           storedStart <= nowValue + 5 * 60 {
            trackingStartedAt = storedStart
        } else {
            trackingStartedAt = nowValue
            defaults.set(nowValue, forKey: Self.trackingStartedAtKey)
        }

        let stored = defaults.dictionary(forKey: Self.acknowledgementsKey) ?? [:]
        acknowledgements = stored.reduce(into: [:]) { result, item in
            guard !item.key.isEmpty,
                  let timestamp = (item.value as? NSNumber)?.doubleValue,
                  timestamp.isFinite,
                  timestamp > 0
            else { return }
            result[item.key] = timestamp
        }
        trimAndPersistIfNeeded()
    }

    func isUnacknowledged(taskID: String, completedAt: Date) -> Bool {
        let timestamp = completedAt.timeIntervalSince1970
        guard !taskID.isEmpty, timestamp.isFinite, timestamp > trackingStartedAt else {
            return false
        }
        return timestamp > (acknowledgements[taskID] ?? 0)
    }

    mutating func acknowledge(taskID: String, completedAt: Date) {
        let timestamp = completedAt.timeIntervalSince1970
        guard !taskID.isEmpty, timestamp.isFinite, timestamp > 0 else { return }
        acknowledgements[taskID] = max(timestamp, acknowledgements[taskID] ?? 0)
        trimAndPersistIfNeeded(force: true)
    }

    private mutating func trimAndPersistIfNeeded(force: Bool = false) {
        let originalCount = acknowledgements.count
        if originalCount > Self.maximumAcknowledgements {
            acknowledgements = Dictionary(
                uniqueKeysWithValues: acknowledgements
                    .sorted { $0.value > $1.value }
                    .prefix(Self.maximumAcknowledgements)
                    .map { ($0.key, $0.value) }
            )
        }
        if force || acknowledgements.count != originalCount {
            defaults.set(acknowledgements, forKey: Self.acknowledgementsKey)
        }
    }
}

enum ProjectIdentity {
    static func displayName(forWorkingDirectory cwd: String) -> String? {
        guard !cwd.isEmpty else { return nil }
        let components = URL(fileURLWithPath: cwd).standardizedFileURL.pathComponents

        // Projectless desktop tasks receive a generated Documents/Codex/YYYY-MM-DD/slug
        // directory. It is workspace plumbing, not a user-facing project.
        if let codexIndex = components.lastIndex(of: "Codex"),
           components.count > codexIndex + 2,
           isDateDirectory(components[codexIndex + 1]) {
            return nil
        }

        // ChatGPT Projects expose an internal g-p-* working directory but not
        // their display name through thread/list. Never leak that internal id.
        if cwd.contains("/.codex/.chatgpt-projects/") {
            return "ChatGPT Project"
        }

        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? nil : name
    }

    private static func isDateDirectory(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts[0].count == 4
            && parts[1].count == 2
            && parts[2].count == 2
            && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}
