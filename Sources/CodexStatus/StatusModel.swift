import AppKit
import Combine
import SwiftUI

enum AgentStatus: Int, CaseIterable, Identifiable, Comparable {
    case idle = 0
    case working = 2
    case needsAttention = 3
    case done = 1
    case error = 4

    var id: Self { self }

    var title: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .needsAttention: "Needs Attention"
        case .done: "Done"
        case .error: "Error"
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .idle: .systemGray
        case .working: .systemBlue
        case .needsAttention: .systemOrange
        case .done: .systemGreen
        case .error: .systemRed
        }
    }

    static func < (lhs: AgentStatus, rhs: AgentStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(snapshotValue: String) {
        switch snapshotValue {
        case "working": self = .working
        case "needsAttention": self = .needsAttention
        case "done": self = .done
        case "error": self = .error
        default: self = .idle
        }
    }
}

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var detail: String
    var status: AgentStatus
    var updatedAt: Date
    var isRecentlyCompleted: Bool = false
    var projectName: String? = nil
    var completionAt: Date? = nil
    var activityUpdatedAt: Date? = nil
    var turnStartedAt: Date? = nil
}

private struct CodexSnapshot: Decodable {
    let id: String
    let name: String
    let detail: String
    let status: String
    let updatedAt: Date
}

private struct DiscoveredThread: Decodable {
    let id: String
    let name: String
    let cwd: String
    let updatedAt: Double
    let statusType: String
    let activeFlags: [String]
    let lifecycle: String
    let lifecycleUpdatedAt: Double
    let activity: String
    let activityUpdatedAt: Double
    let turnStartedAt: Double
}

struct UsageWindow: Decodable, Identifiable {
    let name: String
    let remainingPercent: Double
    let resetsAt: Double

    var id: String { name }
}

private struct ScanResult: Decodable {
    let connected: Bool
    let threads: [DiscoveredThread]
    let usageWindows: [UsageWindow]?
}

@MainActor
final class StatusModel: ObservableObject {
    /// Keep a stopped task noticeable, without leaving it as a permanent error.
    private static let stoppedStatusLifetime: TimeInterval = 5 * 60
    /// Avoid flickering on one failed poll, but never leave a stale active task
    /// blue indefinitely after Codex closes or its App Server becomes unavailable.
    private static let discoveryFreshnessLifetime: TimeInterval = 30

    @Published private(set) var tasks: [AgentTask] = []
    @Published private(set) var hooksInstalled = false
    @Published private(set) var appServerConnected = false
    @Published private(set) var connectionMessage = "Checking Codex connection…"
    @Published var showsIdleTasks = false
    @Published var isUsageHovering = false
    @Published var hoveredProjectTaskID: String?
    @Published private(set) var usageWindows: [UsageWindow] = []
    @Published private(set) var usageUpdatedAt: Date?
    let progressSidecar: ProgressSidecarPlugin
    let promptLibrary: PromptLibraryPlugin

    private let installer = CodexIntegrationInstaller()
    private let preferences: AppPreferences
    private var refreshTimer: Timer?
    private var scanTimer: Timer?
    private var scannerProcess: Process?
    private var discoveredTasks: [AgentTask] = []
    private var lastSuccessfulThreadScanAt: Date?
    private var lastUsageScan: Date?
    private var completionLedger: CompletionLedger
    private var preferenceObservers = Set<AnyCancellable>()

    init(preferences: AppPreferences, pluginRegistry: PluginRegistry) {
        self.preferences = preferences
        let sidecarPackageURL = pluginRegistry.plugin(
            identifier: BuiltInPluginIdentifiers.progressSidecar
        )?.packageURL ?? Bundle.main.resourceURL?
            .appendingPathComponent("Plugins/com.codexstatus.progress-sidecar.codexstatusplugin", isDirectory: true)
            ?? Bundle.main.bundleURL
        progressSidecar = ProgressSidecarPlugin(
            preferences: preferences,
            packageURL: sidecarPackageURL
        )
        promptLibrary = PromptLibraryPlugin(
            preferences: preferences,
            registry: pluginRegistry
        )
        completionLedger = CompletionLedger()

        progressSidecar.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &preferenceObservers)
        promptLibrary.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &preferenceObservers)

        applyEnhancedActivityPreference(preferences.enhancedActivityEnabled)
        hooksInstalled = installer.isInstalled
        observePreferences()
        refresh()
        scanExistingThreads()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scanExistingThreads() }
        }
    }

    var summaryStatus: AgentStatus {
        tasks.map(\.status).max() ?? .idle
    }

    var isConnected: Bool {
        appServerConnected || hooksInstalled
    }

    var summaryCount: Int {
        tasks.filter { $0.status == summaryStatus }.count
    }

    var activeStatuses: [AgentStatus] {
        AgentStatus.allCases
            .sorted(by: >)
            .filter { status in
                status != .idle && tasks.contains { $0.status == status }
            }
    }

    var summaryAccessibilityLabel: String {
        guard !tasks.isEmpty else { return "Codex idle" }
        let noun = summaryCount == 1 ? "task" : "tasks"
        return "Codex, \(summaryCount) \(noun) \(summaryStatus.title.lowercased())"
    }

    var prominentTasks: [AgentTask] {
        guard preferences.foldIdleTasks else { return tasks }
        return tasks.filter { $0.status != .idle || $0.isRecentlyCompleted }
    }

    var foldedIdleTasks: [AgentTask] {
        guard preferences.foldIdleTasks else { return [] }
        return tasks.filter { $0.status == .idle && !$0.isRecentlyCompleted }
    }

    var visibleTaskRowCount: Int {
        prominentTasks.count + (foldedIdleTasks.isEmpty ? 0 : (showsIdleTasks ? foldedIdleTasks.count : 1))
    }

    var visibleProgressSummaryCount: Int {
        visibleTasks.filter { progressSidecar.snapshots[$0.id] != nil }.count
    }

    var visibleProgressLoadingCount: Int {
        visibleTasks.filter {
            progressSidecar.requestingTaskIDs.contains($0.id)
                && progressSidecar.snapshots[$0.id] == nil
        }.count
    }

    private var visibleTasks: [AgentTask] {
        showsIdleTasks ? prominentTasks + foldedIdleTasks : prominentTasks
    }

    var weeklyUsageWindow: UsageWindow? {
        usageWindows.first { $0.name.localizedCaseInsensitiveContains("weekly") }
    }

    var fiveHourUsageWindow: UsageWindow? {
        usageWindows.first {
            $0.name.localizedCaseInsensitiveContains("5-hour")
                || $0.name.localizedCaseInsensitiveContains("5 hour")
        }
    }

    var singleUsageWindow: UsageWindow? {
        usageWindows.min { $0.remainingPercent < $1.remainingPercent }
    }

    func refresh() {
        hooksInstalled = installer.isInstalled
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let now = Date()
        let urls: [URL]
        if preferences.enhancedActivityEnabled {
            urls = (try? FileManager.default.contentsOfDirectory(
                at: installer.sessionsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
        } else {
            urls = []
        }

        let hookTasks = urls.compactMap { url -> AgentTask? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let snapshot = try? decoder.decode(CodexSnapshot.self, from: data)
            else { return nil }

            let age = now.timeIntervalSince(snapshot.updatedAt)
            guard age < 12 * 60 * 60 else { return nil }

            var status = AgentStatus(snapshotValue: snapshot.status)
            var detail = snapshot.detail
            var isRecentlyCompleted = false
            var completionAt: Date?
            if status == .done {
                completionAt = snapshot.updatedAt
                isRecentlyCompleted = true
                if !isUnacknowledgedCompletion(taskID: snapshot.id, completedAt: snapshot.updatedAt) {
                    status = .idle
                    detail = "Completed · viewed"
                    isRecentlyCompleted = true
                }
            } else if status == .working && age > 2 * 60 * 60 {
                status = .idle
                detail = "No recent activity"
            } else if status == .error && age > Self.stoppedStatusLifetime {
                status = .idle
                detail = "Stopped earlier"
            }
            if status == .idle && age > 30 * 60 { return nil }

            return AgentTask(
                id: snapshot.id,
                name: snapshot.name,
                detail: detail,
                status: status,
                updatedAt: snapshot.updatedAt,
                isRecentlyCompleted: isRecentlyCompleted,
                completionAt: completionAt,
                activityUpdatedAt: snapshot.updatedAt
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        .prefix(6)
        .map { $0 }

        // The desktop app can briefly return duplicate rows while its thread list
        // is updating. Keep the newest row instead of using the trapping
        // Dictionary initializer, which would crash the menu-bar process.
        var merged: [String: AgentTask] = [:]
        let discoveryIsFresh = appServerConnected
            || lastSuccessfulThreadScanAt.map {
                now.timeIntervalSince($0) < Self.discoveryFreshnessLifetime
            } == true
        for originalTask in discoveredTasks {
            var task = originalTask
            if !discoveryIsFresh,
               task.status == .working || task.status == .needsAttention {
                task.status = .idle
                task.detail = "Status unavailable"
                task.isRecentlyCompleted = false
            }
            guard let existing = merged[task.id], existing.updatedAt >= task.updatedAt else {
                merged[task.id] = task
                continue
            }
        }
        for task in hookTasks {
            guard let discovered = merged[task.id] else {
                merged[task.id] = task
                continue
            }
            // The rollout lifecycle is authoritative for Working/Done/Idle. Hooks
            // provide richer approval and failure signals only when that signal is
            // at least as new as the App Server row. This prevents an old Stopped
            // hook from replacing a later successful or running turn.
            let isFreshHookSignal = CoreTaskStatePolicy.shouldUseHookSignal(
                isAttentionOrError: task.status == .needsAttention || task.status == .error,
                hookUpdatedAt: task.updatedAt,
                discoveredUpdatedAt: discovered.updatedAt
            )
            if isFreshHookSignal {
                var enrichedTask = task
                enrichedTask.projectName = discovered.projectName
                enrichedTask.turnStartedAt = discovered.turnStartedAt
                merged[task.id] = enrichedTask
            }
        }
        tasks = merged.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(6)
            .map { $0 }
        progressSidecar.update(tasks: tasks)

        if appServerConnected, hooksInstalled {
            connectionMessage = tasks.isEmpty ? "Connected · waiting for a task" : "Live Codex activity"
        } else if appServerConnected {
            connectionMessage = tasks.isEmpty ? "Connected · waiting for a task" : "Codex activity"
        } else if hooksInstalled {
            connectionMessage = "Enhanced Activity ready"
        } else if lastSuccessfulThreadScanAt != nil {
            connectionMessage = "Codex unavailable · showing last known tasks"
        } else {
            connectionMessage = "Waiting for Codex"
        }
    }

    func refreshAll() {
        lastUsageScan = nil
        refresh()
        scanExistingThreads()
    }

    func installIntegration() {
        preferences.enhancedActivityEnabled = true
        do {
            try installer.install()
            connectionMessage = "Connected · approve hooks in Codex if prompted"
            refresh()
        } catch {
            connectionMessage = "Could not connect: \(error.localizedDescription)"
        }
    }

    func removeIntegration() {
        preferences.enhancedActivityEnabled = false
        do {
            try installer.uninstall()
            hooksInstalled = false
            connectionMessage = appServerConnected ? "Connected to Codex" : "Waiting for Codex"
            refresh()
        } catch {
            connectionMessage = "Could not remove integration: \(error.localizedDescription)"
        }
    }

    func openCodex() {
        let bundleIdentifier = "com.openai.codex"
        if let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first {
            runningApp.activate(options: [.activateAllWindows])
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    func openThread(_ threadID: String) {
        acknowledgeCompletion(for: threadID)
        guard let url = URL(string: "codex://threads/\(threadID)") else {
            openCodex()
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func scanExistingThreads() {
        guard scannerProcess == nil else { return }
        let scannerURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/CodexStatusThreadScanner")
        guard FileManager.default.isExecutableFile(atPath: scannerURL.path) else { return }

        let process = Process()
        let output = Pipe()
        process.executableURL = scannerURL
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let shouldLoadUsage = preferences.usageEnabled
            && (lastUsageScan.map { Date().timeIntervalSince($0) >= 60 } ?? true)
        if shouldLoadUsage {
            var environment = ProcessInfo.processInfo.environment
            environment["CODEX_STATUS_INCLUDE_USAGE"] = "1"
            process.environment = environment
            lastUsageScan = Date()
        }
        scannerProcess = process

        process.terminationHandler = { [weak self] _ in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = try? JSONDecoder().decode(ScanResult.self, from: data)
            Task { @MainActor in
                guard let self else { return }
                guard let result else {
                    self.appServerConnected = false
                    self.scannerProcess = nil
                    self.refresh()
                    return
                }
                self.appServerConnected = result.connected
                if result.connected {
                    self.lastSuccessfulThreadScanAt = Date()
                    self.discoveredTasks = self.mapDiscoveredThreads(result.threads)
                }
                if result.connected,
                   self.preferences.usageEnabled,
                   let windows = result.usageWindows {
                    self.usageWindows = windows
                    self.usageUpdatedAt = Date()
                }
                self.scannerProcess = nil
                self.refresh()
            }
        }

        do {
            try process.run()
        } catch {
            scannerProcess = nil
        }
    }

    private func observePreferences() {
        preferences.$enhancedActivityEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.applyEnhancedActivityPreference(enabled)
                self?.refresh()
            }
            .store(in: &preferenceObservers)

        preferences.$usageEnabled
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    self.lastUsageScan = nil
                    self.scanExistingThreads()
                } else {
                    self.usageWindows = []
                    self.usageUpdatedAt = nil
                }
            }
            .store(in: &preferenceObservers)
    }

    private func applyEnhancedActivityPreference(_ enabled: Bool) {
        do {
            if enabled {
                try installer.install()
            } else {
                try installer.uninstall()
            }
            hooksInstalled = installer.isInstalled
        } catch {
            hooksInstalled = installer.isInstalled
            connectionMessage = enabled
                ? "Could not enable Enhanced Activity: \(error.localizedDescription)"
                : "Could not disable Enhanced Activity: \(error.localizedDescription)"
        }
    }

    private func mapDiscoveredThreads(_ rows: [DiscoveredThread]) -> [AgentTask] {
        let now = Date()
        return rows.map { row in
            let updatedAt = Date(timeIntervalSince1970: row.updatedAt)
            let age = max(0, now.timeIntervalSince(updatedAt))
            let status: AgentStatus
            let detail: String
            let isRecentlyCompleted: Bool
            let completionAt: Date?
            let resolvedState = CoreTaskStatePolicy.resolve(
                statusType: row.statusType,
                activeFlags: row.activeFlags,
                rolloutLifecycle: row.lifecycle
            )

            // Terminal rollout events win over a briefly stale App Server active
            // flag. Without this ordering, a completed or aborted turn can appear
            // blue until the next server refresh.
            if resolvedState == .completed {
                let completedAt = Date(timeIntervalSince1970: row.lifecycleUpdatedAt)
                completionAt = completedAt
                if isUnacknowledgedCompletion(taskID: row.id, completedAt: completedAt) {
                    status = .done
                    detail = preferences.completionReadMode == .hover
                        ? "Completed · unread (hover to mark read)"
                        : "Completed · unread"
                    isRecentlyCompleted = true
                } else {
                    status = .idle
                    detail = "Completed · viewed"
                    isRecentlyCompleted = true
                }
            } else if resolvedState == .aborted {
                let stoppedAt = Date(timeIntervalSince1970: row.lifecycleUpdatedAt)
                let stoppedAge = row.lifecycleUpdatedAt > 0
                    ? max(0, now.timeIntervalSince(stoppedAt))
                    : age
                if stoppedAge <= Self.stoppedStatusLifetime {
                    status = .error
                    detail = "Stopped before completion"
                } else {
                    status = .idle
                    detail = "Stopped earlier"
                }
                isRecentlyCompleted = false
                completionAt = nil
            } else if resolvedState == .needsAttention {
                status = .needsAttention
                detail = "Waiting for approval"
                isRecentlyCompleted = false
                completionAt = nil
            } else if resolvedState == .working {
                status = .working
                detail = row.activity == "Activity unavailable"
                    ? "Thinking or working"
                    : row.activity
                isRecentlyCompleted = false
                completionAt = nil
            } else {
                status = .idle
                detail = relativeUpdateText(age)
                isRecentlyCompleted = false
                completionAt = nil
            }

            let folderName = URL(fileURLWithPath: row.cwd).lastPathComponent
            let projectName = ProjectIdentity.displayName(forWorkingDirectory: row.cwd)
            let displayName = row.name.isEmpty
                ? (folderName.isEmpty ? "Codex Task" : folderName)
                : row.name
            return AgentTask(
                id: row.id,
                name: displayName,
                detail: detail,
                status: status,
                updatedAt: updatedAt,
                isRecentlyCompleted: isRecentlyCompleted,
                projectName: projectName,
                completionAt: completionAt,
                activityUpdatedAt: row.activityUpdatedAt > 0
                    ? Date(timeIntervalSince1970: row.activityUpdatedAt)
                    : updatedAt,
                turnStartedAt: row.turnStartedAt > 0
                    ? Date(timeIntervalSince1970: row.turnStartedAt)
                    : nil
            )
        }
    }

    private func isUnacknowledgedCompletion(taskID: String, completedAt: Date) -> Bool {
        completionLedger.isUnacknowledged(taskID: taskID, completedAt: completedAt)
    }

    func acknowledgeCompletion(for threadID: String) {
        guard let task = tasks.first(where: { $0.id == threadID }),
              task.status == .done,
              let completedAt = task.completionAt
        else { return }

        completionLedger.acknowledge(taskID: threadID, completedAt: completedAt)

        if let index = discoveredTasks.firstIndex(where: { $0.id == threadID }) {
            discoveredTasks[index].status = .idle
            discoveredTasks[index].detail = "Completed · viewed"
            discoveredTasks[index].isRecentlyCompleted = true
        }
        refresh()
    }

    private func relativeUpdateText(_ age: TimeInterval) -> String {
        if age < 60 { return "Updated just now" }
        if age < 60 * 60 { return "Updated \(Int(age / 60))m ago" }
        if age < 24 * 60 * 60 { return "Updated \(Int(age / 3600))h ago" }
        return "Updated \(Int(age / 86400))d ago"
    }
}
