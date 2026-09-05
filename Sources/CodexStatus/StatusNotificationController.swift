@preconcurrency import UserNotifications

@MainActor
final class StatusNotificationController: NSObject {
    typealias OpenThreadAction = @MainActor (String) -> Void

    private enum AuthorizationState {
        case unknown
        case requesting
        case allowed
        case denied
    }

    private struct EventKey: Hashable {
        let threadID: String
        let status: AgentStatus
        let updatedAt: Date

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.threadID == rhs.threadID
                && lhs.status == rhs.status
                && lhs.updatedAt == rhs.updatedAt
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(threadID)
            hasher.combine(status.rawValue)
            hasher.combine(updatedAt)
        }
    }

    private struct NotificationEvent {
        let key: EventKey
        let taskName: String
        let detail: String
    }

    private nonisolated static let threadIDUserInfoKey = "CodexStatus.threadID"
    private nonisolated static let soundEnabledUserInfoKey = "CodexStatus.soundEnabled"
    private static let requestIdentifierPrefix = "CodexStatus.task."
    private static let retainedEventLimit = 256

    private let center: UNUserNotificationCenter
    private let openThread: OpenThreadAction

    private var isEnabled = false
    private var isSoundEnabled = true
    private var authorizationState = AuthorizationState.unknown
    private var authorizationGeneration = 0
    private var observedStatuses: [String: AgentStatus]?
    private var pendingEvents: [NotificationEvent] = []
    private var notifiedEventKeys: Set<EventKey> = []
    private var notifiedEventOrder: [EventKey] = []
    private var ownedRequestIdentifiers: [String] = []

    init(
        center: UNUserNotificationCenter = .current(),
        openThread: @escaping OpenThreadAction
    ) {
        self.center = center
        self.openThread = openThread
        super.init()
    }

    func setEnabled(_ enabled: Bool, soundEnabled: Bool) {
        let wasEnabled = isEnabled
        let shouldRequestSoundPermission = enabled && soundEnabled && !isSoundEnabled
        isEnabled = enabled
        isSoundEnabled = soundEnabled

        guard enabled else {
            guard wasEnabled else { return }
            authorizationGeneration &+= 1
            authorizationState = .unknown
            observedStatuses = nil
            pendingEvents.removeAll(keepingCapacity: false)
            center.removePendingNotificationRequests(withIdentifiers: ownedRequestIdentifiers)
            ownedRequestIdentifiers.removeAll(keepingCapacity: false)
            if center.delegate === self {
                center.delegate = nil
            }
            return
        }

        center.delegate = self
        if !wasEnabled {
            observedStatuses = nil
            requestAuthorization()
        } else if shouldRequestSoundPermission {
            requestAuthorization()
        }
    }

    func process(tasks: [AgentTask]) {
        guard isEnabled else { return }

        var newestTasks: [String: AgentTask] = [:]
        for task in tasks {
            guard let current = newestTasks[task.id] else {
                newestTasks[task.id] = task
                continue
            }
            if task.updatedAt > current.updatedAt
                || (task.updatedAt == current.updatedAt && task.status > current.status) {
                newestTasks[task.id] = task
            }
        }

        let currentStatuses = newestTasks.mapValues(\.status)
        guard let previousStatuses = observedStatuses else {
            observedStatuses = currentStatuses
            return
        }

        observedStatuses = currentStatuses
        for task in newestTasks.values.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            guard Self.isNotifiable(task.status),
                  let previousStatus = previousStatuses[task.id],
                  previousStatus != task.status
            else { continue }

            let event = NotificationEvent(
                key: EventKey(
                    threadID: task.id,
                    status: task.status,
                    updatedAt: task.updatedAt
                ),
                taskName: task.name,
                detail: task.detail
            )
            guard remember(event.key) else { continue }
            enqueueOrDeliver(event)
        }
    }

    private static func isNotifiable(_ status: AgentStatus) -> Bool {
        status == .done || status == .needsAttention || status == .error
    }

    private func requestAuthorization() {
        authorizationGeneration &+= 1
        let generation = authorizationGeneration
        authorizationState = .requesting

        var options: UNAuthorizationOptions = [.alert]
        if isSoundEnabled {
            options.insert(.sound)
        }
        center.requestAuthorization(options: options) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isEnabled,
                      self.authorizationGeneration == generation
                else { return }

                self.authorizationState = granted ? .allowed : .denied
                if granted {
                    let events = self.pendingEvents
                    self.pendingEvents.removeAll(keepingCapacity: false)
                    for event in events {
                        self.deliver(event)
                    }
                } else {
                    self.pendingEvents.removeAll(keepingCapacity: false)
                }
            }
        }
    }

    private func enqueueOrDeliver(_ event: NotificationEvent) {
        switch authorizationState {
        case .allowed:
            deliver(event)
        case .unknown, .requesting:
            pendingEvents.append(event)
        case .denied:
            break
        }
    }

    private func deliver(_ event: NotificationEvent) {
        guard isEnabled else { return }

        let content = UNMutableNotificationContent()
        switch event.key.status {
        case .done:
            content.title = "Codex task completed"
        case .needsAttention:
            content.title = "Codex needs your attention"
        case .error:
            content.title = "Codex task stopped"
        case .idle, .working:
            return
        }
        content.subtitle = event.taskName
        content.body = event.detail
        content.threadIdentifier = event.key.threadID
        content.userInfo = [
            Self.threadIDUserInfoKey: event.key.threadID,
            Self.soundEnabledUserInfoKey: isSoundEnabled
        ]
        if isSoundEnabled {
            content.sound = .default
        }

        let timestamp = Int64((event.key.updatedAt.timeIntervalSince1970 * 1_000).rounded())
        let identifier = Self.requestIdentifierPrefix
            + event.key.threadID
            + ".\(event.key.status.rawValue).\(timestamp)"
        ownedRequestIdentifiers.append(identifier)
        if ownedRequestIdentifiers.count > Self.retainedEventLimit {
            ownedRequestIdentifiers.removeFirst(
                ownedRequestIdentifiers.count - Self.retainedEventLimit
            )
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func remember(_ eventKey: EventKey) -> Bool {
        guard notifiedEventKeys.insert(eventKey).inserted else { return false }
        notifiedEventOrder.append(eventKey)
        if notifiedEventOrder.count > Self.retainedEventLimit {
            let staleKeys = notifiedEventOrder.prefix(
                notifiedEventOrder.count - Self.retainedEventLimit
            )
            for key in staleKeys {
                notifiedEventKeys.remove(key)
            }
            notifiedEventOrder.removeFirst(
                notifiedEventOrder.count - Self.retainedEventLimit
            )
        }
        return true
    }
}

extension StatusNotificationController: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.userInfo[Self.soundEnabledUserInfoKey] as? Bool == true {
            options.insert(.sound)
        }
        completionHandler(options)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isDefaultAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let threadID = response.notification.request.content
            .userInfo[Self.threadIDUserInfoKey] as? String
        completionHandler()

        guard isDefaultAction, let threadID else { return }
        Task { @MainActor [weak self] in
            self?.openThread(threadID)
        }
    }
}
