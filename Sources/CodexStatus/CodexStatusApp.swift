import AppKit
import Combine
import SwiftUI

@main
struct CodexStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private static let activationNotification = Notification.Name("com.local.CodexStatus.activate")
    private let instanceGuard: SingleInstanceGuard
    private let preferences: AppPreferences
    private let pluginRegistry: PluginRegistry
    private let pluginPermissions: PluginPermissionController
    private let model: StatusModel
    private let updateChecker: AppUpdateChecker
    private let lifecycleController: LifecycleController
    private lazy var statusItem = NSStatusBar.system.statusItem(withLength: 34)
    private let popover = NSPopover()
    private var modelObserver: AnyCancellable?
    private var preferenceObservers = Set<AnyCancellable>()
    private var taskObserver: AnyCancellable?
    private var statusCycleTimer: Timer?
    private var statusCycleIndex = 0
    private var startupPermissionPlugin: InstalledPlugin?

    private lazy var notificationController = StatusNotificationController { [weak self] threadID in
        self?.model.openThread(threadID)
    }

    private lazy var settingsWindowController = SettingsWindowController(
        preferences: preferences,
        pluginRegistry: pluginRegistry,
        pluginPermissions: pluginPermissions,
        model: model,
        updateChecker: updateChecker,
        notificationController: notificationController,
        lifecycleController: lifecycleController,
        onOpenDataFolder: { [weak self] in self?.openDataFolder() },
        onRemoveAllIntegrations: { [weak self] in self?.removeAllIntegrations() }
    )

    override init() {
        let instanceGuard = SingleInstanceGuard()
        self.instanceGuard = instanceGuard
        _ = instanceGuard.acquire()
        let existingHooksInstalled = CodexIntegrationInstaller().isInstalled
        let existingLifecycleInstalled = CodexLifecycleInstaller().isInstalled
        let preferences = AppPreferences(
            existingHooksInstalled: existingHooksInstalled,
            existingLifecycleInstalled: existingLifecycleInstalled
        )
        self.preferences = preferences
        let pluginRegistry = PluginRegistry()
        self.pluginRegistry = pluginRegistry
        let pluginPermissions = PluginPermissionController()
        self.pluginPermissions = pluginPermissions

        var startupPermissionPlugin: InstalledPlugin?
        if preferences.progressSidecarEnabled,
           let plugin = pluginRegistry.plugin(identifier: BuiltInPluginIdentifiers.progressSidecar),
           !pluginPermissions.isPreflightSatisfied(for: plugin.manifest) {
            preferences.progressSidecarEnabled = false
            startupPermissionPlugin = plugin
        }
        if preferences.promptLibraryEnabled,
           let plugin = pluginRegistry.plugin(identifier: BuiltInPluginIdentifiers.promptLibrary),
           !pluginPermissions.isPreflightSatisfied(for: plugin.manifest) {
            preferences.promptLibraryEnabled = false
            startupPermissionPlugin = startupPermissionPlugin ?? plugin
        }
        for plugin in pluginRegistry.importedPlugins
        where pluginRegistry.permissionBlockedImportedPluginIDs.contains(plugin.id) {
            startupPermissionPlugin = startupPermissionPlugin ?? plugin
        }
        self.startupPermissionPlugin = startupPermissionPlugin
        updateChecker = AppUpdateChecker()
        lifecycleController = LifecycleController()
        model = StatusModel(preferences: preferences, pluginRegistry: pluginRegistry)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard instanceGuard.ownsLock else {
            requestActivationOfExistingInstance()
            NSApplication.shared.terminate(nil)
            return
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleActivationRequest(_:)),
            name: Self.activationNotification,
            object: nil
        )

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 224, height: 125)
        popover.contentViewController = NSHostingController(rootView: StatusPopover(
            model: model,
            preferences: preferences,
            updateChecker: updateChecker,
            onOpenSettings: { [weak self] in self?.openSettings() }
        ))

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly

        updateStatusItem()
        modelObserver = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusItem()
            }
        }
        observePreferences()
        taskObserver = model.$tasks.sink { [weak self] tasks in
            self?.notificationController.process(tasks: tasks)
        }
        statusCycleTimer = Timer.scheduledTimer(withTimeInterval: 1.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceStatusCycle()
            }
        }

        if CommandLine.arguments.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openSettings()
            }
        }
        if let plugin = startupPermissionPlugin {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                self.openSettings()
                self.pluginPermissions.requestEnable(plugin) { [weak self] approved in
                    self?.setPlugin(plugin, enabled: approved)
                }
                self.startupPermissionPlugin = nil
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        statusCycleTimer?.invalidate()
        updateChecker.setEnabled(false)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "codexstatus" && $0.host == "settings" }) {
            openSettings()
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if NSApplication.shared.currentEvent?.type == .rightMouseUp {
            showContextMenu(relativeTo: button)
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.showsIdleTasks = false
            updatePopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func requestActivationOfExistingInstance() {
        let wantsSettings = CommandLine.arguments.contains("--settings")
        DistributedNotificationCenter.default().postNotificationName(
            Self.activationNotification,
            object: nil,
            userInfo: ["settings": wantsSettings],
            deliverImmediately: true
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.local.CodexStatus"
        )
        .first { $0.processIdentifier != ownPID }?
        .activate(options: [.activateIgnoringOtherApps])
    }

    @objc private func handleActivationRequest(_ notification: Notification) {
        if notification.userInfo?["settings"] as? Bool == true {
            openSettings()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.showsIdleTasks = false
        updatePopoverSize()
    }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        updatePopoverSize()
        let status = displayedStatus
        let reservesCountSlot = MenuBarLayoutPolicy.reservesCountSlot(
            showCounts: preferences.showMenuBarCount,
            displayedStatusCounts: statusesDisplayedInCycle.map { cycleStatus in
                guard cycleStatus != .idle else { return 0 }
                return model.tasks.filter { $0.status == cycleStatus }.count
            }
        )
        let count = preferences.showMenuBarCount
            ? model.tasks.filter { $0.status == status }.count
            : 0
        statusItem.length = reservesCountSlot ? 34 : 22
        button.image = statusImage(
            status: status,
            count: count,
            reservesCountSlot: reservesCountSlot
        )
        button.toolTip = model.summaryAccessibilityLabel
        button.setAccessibilityLabel(model.summaryAccessibilityLabel)
    }

    private var displayedStatus: AgentStatus {
        let statuses = statusesDisplayedInCycle
        return statuses[statusCycleIndex % statuses.count]
    }

    private var statusesDisplayedInCycle: [AgentStatus] {
        guard preferences.cycleStatusColors else { return [model.summaryStatus] }
        let activeStatuses = model.activeStatuses
        return activeStatuses.isEmpty ? [.idle] : activeStatuses
    }

    private func advanceStatusCycle() {
        guard preferences.cycleStatusColors else {
            statusCycleIndex = 0
            return
        }
        let activeStatuses = model.activeStatuses
        guard activeStatuses.count > 1 else {
            statusCycleIndex = 0
            return
        }
        statusCycleIndex = (statusCycleIndex + 1) % activeStatuses.count
        updateStatusItem()
    }

    private func updatePopoverSize() {
        let height: CGFloat
        if model.tasks.isEmpty {
            height = 116
        } else {
            let taskRowCount = model.prominentTasks.count
                + (model.showsIdleTasks ? model.foldedIdleTasks.count : 0)
            let disclosureCount = model.foldedIdleTasks.isEmpty ? 0 : 1
            let visibleItemCount = taskRowCount + disclosureCount
            let interRowSpacing = max(0, visibleItemCount - 1) * 2
            height = min(
                520,
                64
                    + CGFloat(taskRowCount * 44)
                    + CGFloat(disclosureCount * 30)
                    + CGFloat(interRowSpacing)
                    + CGFloat(model.visibleProgressSummaryCount * 72)
                    + CGFloat(model.visibleProgressLoadingCount * 24)
            )
        }
        popover.contentSize = NSSize(width: 224, height: height)
    }

    private func observePreferences() {
        preferences.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateStatusItem()
                    self?.applyNotificationPreferences()
                }
            }
            .store(in: &preferenceObservers)

        preferences.$followCodexLifecycle
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.lifecycleController.apply(enabled: enabled)
            }
            .store(in: &preferenceObservers)

        preferences.$updateChecksEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.updateChecker.setEnabled(enabled)
            }
            .store(in: &preferenceObservers)

        applyNotificationPreferences()
    }

    private func applyNotificationPreferences() {
        notificationController.configure(NotificationConfiguration(
            enabled: preferences.notificationsEnabled,
            completionSound: preferences.completionNotificationSound,
            attentionSound: preferences.attentionNotificationSound,
            errorSound: preferences.errorNotificationSound,
            notifyOnCompletion: preferences.notifyOnCompletion,
            notifyOnAttention: preferences.notifyOnAttention,
            notifyOnError: preferences.notifyOnError,
            quietHoursEnabled: preferences.notificationQuietHoursEnabled,
            quietStartMinute: preferences.notificationQuietStartMinute,
            quietEndMinute: preferences.notificationQuietEndMinute
        ))
    }

    private func showContextMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(
            title: "Refresh",
            action: #selector(refreshFromMenu),
            keyEquivalent: ""
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 2),
            in: button
        )
    }

    @objc private func refreshFromMenu() {
        model.refreshAll()
    }

    @objc private func openSettings() {
        if popover.isShown {
            popover.performClose(nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindowController.present()
        }
    }

    private func openDataFolder() {
        let folder = CodexIntegrationInstaller().supportDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func removeAllIntegrations() {
        preferences.enhancedActivityEnabled = false
        preferences.followCodexLifecycle = false
        model.removeIntegration()
        lifecycleController.apply(enabled: false)
    }

    private func setPlugin(_ plugin: InstalledPlugin, enabled: Bool) {
        switch plugin.id {
        case BuiltInPluginIdentifiers.progressSidecar:
            preferences.progressSidecarEnabled = enabled
        case BuiltInPluginIdentifiers.promptLibrary:
            preferences.promptLibraryEnabled = enabled
        default:
            pluginRegistry.setImportedPlugin(plugin.id, enabled: enabled)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func statusImage(
        status: AgentStatus,
        count: Int,
        reservesCountSlot: Bool
    ) -> NSImage {
        let countText = status != .idle && count > 1 ? "\(count)" : ""
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let textWidth = countText.isEmpty ? 0 : ceil((countText as NSString).size(withAttributes: attributes).width)
        // Reserve the count slot for the entire color cycle whenever any state
        // needs it. This keeps the mark fixed while cycling, yet returns to a
        // compact status item when no displayed state can show a number.
        let size = NSSize(width: reservesCountSlot ? 34 : 22, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let markX: CGFloat = reservesCountSlot ? 18.5 : 3.5
            self.drawCodexMark(in: NSRect(x: markX, y: 1.5, width: 15, height: 15), color: status.nsColor)

            if !countText.isEmpty {
                let textSize = (countText as NSString).size(withAttributes: attributes)
                let textRect = NSRect(
                    x: 14 - textWidth,
                    y: floor((rect.height - textSize.height) / 2),
                    width: textWidth,
                    height: textSize.height
                )
                (countText as NSString).draw(in: textRect, withAttributes: attributes)
            }
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = model.summaryAccessibilityLabel
        return image
    }

    private func drawCodexMark(in rect: NSRect, color: NSColor) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let orbit = rect.width * 0.225
        let lobeRadius = rect.width * 0.225

        color.setFill()
        NSBezierPath(
            ovalIn: NSRect(
                x: center.x - rect.width * 0.29,
                y: center.y - rect.height * 0.29,
                width: rect.width * 0.58,
                height: rect.height * 0.58
            )
        ).fill()

        for index in 0..<6 {
            let angle = Double(index) * .pi / 3
            let lobeCenter = NSPoint(
                x: center.x + CGFloat(cos(angle)) * orbit,
                y: center.y + CGFloat(sin(angle)) * orbit
            )
            NSBezierPath(
                ovalIn: NSRect(
                    x: lobeCenter.x - lobeRadius,
                    y: lobeCenter.y - lobeRadius,
                    width: lobeRadius * 2,
                    height: lobeRadius * 2
                )
            ).fill()
        }

        NSColor.white.withAlphaComponent(0.94).setStroke()
        let prompt = NSBezierPath()
        prompt.lineWidth = 1.25
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.move(to: NSPoint(x: rect.minX + 4.2, y: rect.minY + 4.7))
        prompt.line(to: NSPoint(x: rect.minX + 6.3, y: rect.midY))
        prompt.line(to: NSPoint(x: rect.minX + 4.2, y: rect.maxY - 4.7))
        prompt.stroke()

        let underscore = NSBezierPath()
        underscore.lineWidth = 1.25
        underscore.lineCapStyle = .round
        underscore.move(to: NSPoint(x: rect.minX + 8.1, y: rect.minY + 4.7))
        underscore.line(to: NSPoint(x: rect.minX + 11.0, y: rect.minY + 4.7))
        underscore.stroke()
    }
}
