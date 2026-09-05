import Combine
import Foundation

@MainActor
final class ProgressSidecarPlugin: ObservableObject, NativePluginRuntime {
    let identifier = BuiltInPluginIdentifiers.progressSidecar

    @Published private(set) var requestingTaskIDs: Set<String> = []
    @Published private(set) var snapshots: [String: ProgressSnapshot] = [:]
    @Published private(set) var isRunning = false

    private let preferences: AppPreferences
    private let controller: ProgressSidecarController
    private var lastRequests: [String: Date] = [:]
    private var preferenceObservers = Set<AnyCancellable>()

    init(
        preferences: AppPreferences,
        packageURL: URL,
        controller: ProgressSidecarController? = nil
    ) {
        self.preferences = preferences
        self.controller = controller ?? ProgressSidecarController(
            helperURL: packageURL
                .appendingPathComponent("Helpers", isDirectory: true)
                .appendingPathComponent("CodexStatusProgress")
        )
        preferences.$progressSidecarEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled { self?.start() } else { self?.stop() }
            }
            .store(in: &preferenceObservers)
    }

    func start() {
        isRunning = true
    }

    func stop() {
        isRunning = false
        controller.cancelAll()
        requestingTaskIDs.removeAll()
        snapshots.removeAll()
        lastRequests.removeAll()
    }

    func update(tasks: [AgentTask]) {
        guard isRunning,
              let interval = preferences.progressRefreshInterval.seconds else { return }
        let now = Date()
        for task in tasks where task.status == .working {
            guard !requestingTaskIDs.contains(task.id) else { continue }
            let elapsed = lastRequests[task.id].map { now.timeIntervalSince($0) }
                ?? .greatestFiniteMagnitude
            if elapsed >= interval {
                requestProgress(for: task)
            }
        }
    }

    func canRequestProgress(for task: AgentTask) -> Bool {
        isRunning && !requestingTaskIDs.contains(task.id)
    }

    func requestProgress(
        for task: AgentTask,
        completion: ((Result<ProgressSnapshot, ProgressSidecarFailure>) -> Void)? = nil
    ) {
        guard canRequestProgress(for: task) else { return }
        requestingTaskIDs.insert(task.id)
        lastRequests[task.id] = Date()
        controller.request(threadID: task.id, prompt: preferences.progressSidecarPrompt) { [weak self] result in
            guard let self else { return }
            if case .success(let snapshot) = result {
                snapshots[task.id] = snapshot
            }
            requestingTaskIDs.remove(task.id)
            completion?(result)
        }
    }

    func dismissProgress(for threadID: String) {
        snapshots[threadID] = nil
    }
}
