import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private static let sidebarItemIdentifier = NSToolbarItem.Identifier(
        "com.local.CodexStatus.settings.toggleSidebar"
    )

    private let sidebarController: SettingsSidebarController
    private weak var sidebarToolbarItem: NSToolbarItem?

    init(
        preferences: AppPreferences,
        pluginRegistry: PluginRegistry,
        pluginPermissions: PluginPermissionController,
        model: StatusModel,
        updateChecker: AppUpdateChecker,
        notificationController: StatusNotificationController,
        lifecycleController: LifecycleController,
        onOpenDataFolder: @escaping () -> Void,
        onRemoveAllIntegrations: @escaping () -> Void
    ) {
        let sidebarController = SettingsSidebarController()
        self.sidebarController = sidebarController
        let settingsView = SettingsView(
            preferences: preferences,
            pluginRegistry: pluginRegistry,
            pluginPermissions: pluginPermissions,
            model: model,
            updateChecker: updateChecker,
            notificationController: notificationController,
            lifecycleController: lifecycleController,
            sidebarController: sidebarController,
            onOpenDataFolder: onOpenDataFolder,
            onRemoveAllIntegrations: onRemoveAllIntegrations
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
        Self.configureWindowChrome(window)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 660, height: 460)
        window.setFrameAutosaveName("CodexStatus.SettingsWindow")
        window.center()

        super.init(window: window)
        window.delegate = self
        configureToolbar(for: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// Brings the settings window forward even though CodexStatus has no Dock icon.
    func present() {
        if let window {
            Self.configureWindowChrome(window)
        }
        showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    private static func configureWindowChrome(_ window: NSWindow) {
        window.styleMask.remove(.fullSizeContentView)
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .line
        window.toolbarStyle = .unified
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.tabbingMode = .disallowed
    }

    private func configureToolbar(for window: NSWindow) {
        let toolbar = NSToolbar(identifier: "CodexStatus.SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .small
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = true
        window.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarItemIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarItemIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == Self.sidebarItemIdentifier else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Toggle Sidebar"
        item.paletteLabel = "Toggle Sidebar"
        item.toolTip = sidebarController.isVisible ? "Hide sidebar" : "Show sidebar"
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle sidebar")
        item.target = self
        item.action = #selector(toggleSidebar)
        item.isNavigational = true
        item.visibilityPriority = .high
        sidebarToolbarItem = item
        return item
    }

    @objc private func toggleSidebar() {
        sidebarController.toggle()
        sidebarToolbarItem?.toolTip = sidebarController.isVisible ? "Hide sidebar" : "Show sidebar"
    }
}
