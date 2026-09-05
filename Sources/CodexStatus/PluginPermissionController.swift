import Combine
import Foundation
import UserNotifications

struct PluginPermissionRequest: Identifiable, Equatable, Sendable {
    let plugin: InstalledPlugin

    var id: String { plugin.id }
}

@MainActor
final class PluginPermissionController: ObservableObject {
    typealias NotificationAuthorizationRequest = @Sendable () async -> Bool

    @Published var pendingRequest: PluginPermissionRequest?
    @Published private(set) var isRequesting = false
    @Published private(set) var failureMessage: String?

    private let ledger: PluginPermissionLedger
    private let requestNotificationAuthorization: NotificationAuthorizationRequest
    private var activation: ((Bool) -> Void)?

    init(
        defaults: UserDefaults = .standard,
        requestNotificationAuthorization: @escaping NotificationAuthorizationRequest = {
            await PluginPermissionController.requestNotifications()
        }
    ) {
        ledger = PluginPermissionLedger(defaults: defaults)
        self.requestNotificationAuthorization = requestNotificationAuthorization
    }

    func isPreflightSatisfied(for manifest: PluginManifest) -> Bool {
        ledger.isGranted(for: manifest)
    }

    func requestEnable(
        _ plugin: InstalledPlugin,
        activate: @escaping (Bool) -> Void
    ) {
        guard !plugin.manifest.permissions.isEmpty else {
            activate(true)
            return
        }
        guard !ledger.isGranted(for: plugin.manifest) else {
            activate(true)
            return
        }
        activation?(false)
        activation = activate
        failureMessage = nil
        pendingRequest = PluginPermissionRequest(plugin: plugin)
    }

    func cancelPendingRequest() {
        guard !isRequesting else { return }
        activation?(false)
        activation = nil
        failureMessage = nil
        pendingRequest = nil
    }

    func approvePendingRequest() {
        guard let request = pendingRequest, !isRequesting else { return }
        isRequesting = true
        failureMessage = nil

        Task {
            let needsNotifications = request.plugin.manifest.permissions.contains {
                PluginPermissionCatalog.requiresSystemAuthorization($0.identifier)
            }
            if needsNotifications, !(await requestNotificationAuthorization()) {
                failureMessage = "macOS notification access was not granted. The plugin remains off; you can allow notifications in System Settings and try again."
                isRequesting = false
                return
            }

            ledger.grant(request.plugin.manifest)
            let completion = activation
            activation = nil
            isRequesting = false
            failureMessage = nil
            pendingRequest = nil
            completion?(true)
        }
    }

    func revoke(_ plugin: InstalledPlugin) {
        ledger.revoke(identifier: plugin.id)
    }

    private nonisolated static func requestNotifications() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) == true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}
