import Combine
import Foundation

@MainActor
final class LifecycleController: ObservableObject {
    @Published private(set) var isInstalled: Bool
    @Published private(set) var statusText: String

    private let installer: CodexLifecycleInstaller

    init(installer: CodexLifecycleInstaller = CodexLifecycleInstaller()) {
        self.installer = installer
        isInstalled = installer.isInstalled
        statusText = installer.isInstalled ? "Ready" : "Off"
    }

    func apply(enabled: Bool) {
        do {
            if enabled {
                try installer.install()
            } else {
                try installer.uninstall()
            }
            isInstalled = installer.isInstalled
            statusText = enabled
                ? (isInstalled ? "Ready" : "Watcher unavailable")
                : "Off"
        } catch {
            isInstalled = installer.isInstalled
            statusText = enabled ? "Could not enable" : "Could not disable"
        }
    }
}
