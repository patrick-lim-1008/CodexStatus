import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        preferences: AppPreferences,
        model: StatusModel,
        onOpenDataFolder: @escaping () -> Void,
        onRemoveAllIntegrations: @escaping () -> Void,
        onSendTestNotification: @escaping (AgentStatus) -> Void
    ) {
        let settingsView = SettingsView(
            preferences: preferences,
            model: model,
            onOpenDataFolder: onOpenDataFolder,
            onRemoveAllIntegrations: onRemoveAllIntegrations,
            onSendTestNotification: onSendTestNotification
        )
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CodexStatus Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 660, height: 460)
        window.setFrameAutosaveName("CodexStatus.SettingsWindow")
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Brings the settings window forward even though CodexStatus has no Dock icon.
    func present() {
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }
}
