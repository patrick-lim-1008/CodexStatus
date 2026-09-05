import AppKit
import Foundation
@preconcurrency import UserNotifications

struct NotificationConfiguration: Equatable {
    var enabled: Bool
    var completionSound: NotificationSoundChoice
    var attentionSound: NotificationSoundChoice
    var errorSound: NotificationSoundChoice
    var notifyOnCompletion: Bool
    var notifyOnAttention: Bool
    var notifyOnError: Bool
    var quietHoursEnabled: Bool
    var quietStartMinute: Int
    var quietEndMinute: Int

    func allows(_ status: AgentStatus) -> Bool {
        switch status {
        case .done: notifyOnCompletion
        case .needsAttention: notifyOnAttention
        case .error: notifyOnError
        case .idle, .working: false
        }
    }

    func sound(for status: AgentStatus) -> NotificationSoundChoice {
        switch status {
        case .done: completionSound
        case .needsAttention: attentionSound
        case .error: errorSound
        case .idle, .working: .none
        }
    }

    var hasAnySound: Bool {
        [completionSound, attentionSound, errorSound].contains { $0 != .none }
    }

    func isQuiet(at date: Date, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = max(0, min(1_439, quietStartMinute))
        let end = max(0, min(1_439, quietEndMinute))
        if start == end { return true }
        if start < end { return minute >= start && minute < end }
        return minute >= start || minute < end
    }
}

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

    private var configuration = NotificationConfiguration(
        enabled: false,
        completionSound: .glass,
        attentionSound: .ping,
        errorSound: .basso,
        notifyOnCompletion: true,
        notifyOnAttention: true,
        notifyOnError: true,
        quietHoursEnabled: false,
        quietStartMinute: 22 * 60,
        quietEndMinute: 8 * 60
    )
    private var authorizationState = AuthorizationState.unknown
    private var authorizationGeneration = 0
    private var observedStatuses: [String: AgentStatus]?
    private var pendingEvents: [NotificationEvent] = []
    private var notifiedEventKeys: Set<EventKey> = []
    private var notifiedEventOrder: [EventKey] = []
    private var ownedRequestIdentifiers: [String] = []
    private var pendingTestNotification = false
    private var pendingTestStatus: AgentStatus = .done

    init(
        center: UNUserNotificationCenter = .current(),
        openThread: @escaping OpenThreadAction
    ) {
        self.center = center
        self.openThread = openThread
        super.init()
    }

    func configure(_ newConfiguration: NotificationConfiguration) {
        let wasEnabled = configuration.enabled
        let shouldRequestSoundPermission = newConfiguration.enabled
            && newConfiguration.hasAnySound
            && !configuration.hasAnySound
        configuration = newConfiguration

        guard newConfiguration.enabled else {
            guard wasEnabled else { return }
            authorizationGeneration &+= 1
            authorizationState = .unknown
            observedStatuses = nil
            pendingEvents.removeAll(keepingCapacity: false)
            pendingTestNotification = false
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
        guard configuration.enabled else { return }

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
            guard configuration.allows(task.status),
                  let previousStatus = previousStatuses[task.id],
                  previousStatus != task.status
            else { continue }

            guard !configuration.isQuiet(at: Date()) else { continue }

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

    func sendTestNotification(for status: AgentStatus) {
        guard configuration.enabled else { return }
        switch authorizationState {
        case .allowed:
            deliverTestNotification(for: status)
        case .unknown:
            pendingTestNotification = true
            pendingTestStatus = status
            requestAuthorization()
        case .requesting:
            pendingTestNotification = true
            pendingTestStatus = status
        case .denied:
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
            )
        }
    }

    private func requestAuthorization() {
        authorizationGeneration &+= 1
        let generation = authorizationGeneration
        authorizationState = .requesting

        var options: UNAuthorizationOptions = [.alert]
        if configuration.hasAnySound {
            options.insert(.sound)
        }
        center.requestAuthorization(options: options) { [weak self] granted, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.configuration.enabled,
                      self.authorizationGeneration == generation
                else { return }

                self.authorizationState = granted ? .allowed : .denied
                if granted {
                    let events = self.pendingEvents
                    self.pendingEvents.removeAll(keepingCapacity: false)
                    for event in events {
                        self.deliver(event)
                    }
                    if self.pendingTestNotification {
                        self.pendingTestNotification = false
                        self.deliverTestNotification(for: self.pendingTestStatus)
                    }
                } else {
                    self.pendingEvents.removeAll(keepingCapacity: false)
                    self.pendingTestNotification = false
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
        guard configuration.enabled,
              configuration.allows(event.key.status),
              !configuration.isQuiet(at: Date())
        else { return }

        let content = UNMutableNotificationContent()
        switch event.key.status {
        case .done:
            content.title = "Codex task completed"
        case .needsAttention:
            content.title = "Codex needs approval or input"
        case .error:
            content.title = "Codex task failed"
        case .idle, .working:
            return
        }
        content.subtitle = event.taskName
        content.body = event.detail
        content.threadIdentifier = event.key.threadID
        content.userInfo = [
            Self.threadIDUserInfoKey: event.key.threadID,
            Self.soundEnabledUserInfoKey: usesNotificationCenterSound(for: event.key.status)
        ]
        applySound(to: content, choice: configuration.sound(for: event.key.status))

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

    private func deliverTestNotification(for status: AgentStatus) {
        guard configuration.enabled else { return }
        let content = UNMutableNotificationContent()
        switch status {
        case .done:
            content.title = "Test · Codex task completed"
            content.body = "A finished task will use this notification and sound."
        case .needsAttention:
            content.title = "Test · Codex needs approval or input"
            content.body = "An authorization or input request will use this alert."
        case .error:
            content.title = "Test · Codex task failed"
            content.body = "A failed or aborted task will use this alert."
        case .idle, .working:
            return
        }
        content.userInfo = [
            Self.soundEnabledUserInfoKey: usesNotificationCenterSound(for: status)
        ]
        applySound(to: content, choice: configuration.sound(for: status))

        let identifier = Self.requestIdentifierPrefix + "test.\(UUID().uuidString)"
        ownedRequestIdentifiers.append(identifier)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    private func usesNotificationCenterSound(for status: AgentStatus) -> Bool {
        configuration.sound(for: status) == .systemDefault
    }

    private func applySound(
        to content: UNMutableNotificationContent,
        choice: NotificationSoundChoice
    ) {
        guard choice != .none else { return }
        if let soundName = choice.appKitName {
            NSSound(named: NSSound.Name(soundName))?.play()
        } else {
            content.sound = .default
        }
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
