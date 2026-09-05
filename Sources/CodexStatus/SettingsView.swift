import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var pluginRegistry: PluginRegistry
    @ObservedObject var model: StatusModel
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject var notificationController: StatusNotificationController
    @ObservedObject var lifecycleController: LifecycleController
    @ObservedObject private var viewState: SettingsViewState

    let onOpenDataFolder: () -> Void
    let onRemoveAllIntegrations: () -> Void

    init(
        preferences: AppPreferences,
        pluginRegistry: PluginRegistry,
        model: StatusModel,
        updateChecker: AppUpdateChecker,
        notificationController: StatusNotificationController,
        lifecycleController: LifecycleController,
        onOpenDataFolder: @escaping () -> Void,
        onRemoveAllIntegrations: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.pluginRegistry = pluginRegistry
        self.model = model
        self.updateChecker = updateChecker
        self.notificationController = notificationController
        self.lifecycleController = lifecycleController
        viewState = SettingsViewState()
        self.onOpenDataFolder = onOpenDataFolder
        self.onRemoveAllIntegrations = onRemoveAllIntegrations
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $viewState.selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(Optional(pane))
            }
            .navigationTitle("CodexStatus")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 190)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    paneTitle
                    selectedPane
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 460, idealHeight: 540)
        .alert("Remove CodexStatus integrations?", isPresented: $viewState.isConfirmingIntegrationRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Integrations", role: .destructive) {
                preferences.enhancedActivityEnabled = false
                preferences.followCodexLifecycle = false
                onRemoveAllIntegrations()
            }
        } message: {
            Text("This removes CodexStatus hooks and its background lifecycle helper. Your settings and task data are kept.")
        }
        .alert(item: $viewState.pluginAlert) { alert in
            switch alert {
            case .message(let title, let detail):
                Alert(
                    title: Text(title),
                    message: Text(detail),
                    dismissButton: .default(Text("OK"))
                )
            case .remove(let plugin):
                Alert(
                    title: Text("Remove \(plugin.manifest.name)?"),
                    message: Text("This removes the imported plugin package from CodexStatus."),
                    primaryButton: .destructive(Text("Remove")) {
                        removeImportedPlugin(plugin)
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .sheet(isPresented: $viewState.isShowingPromptLibrary) {
            PromptLibraryEditor(library: model.promptLibrary)
                .preferredColorScheme(preferences.appTheme.colorScheme)
        }
        .preferredColorScheme(preferences.appTheme.colorScheme)
    }

    private var paneTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text((viewState.selectedPane ?? .extensions).title)
                .font(.system(size: 22, weight: .semibold))
            Text((viewState.selectedPane ?? .extensions).subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        switch viewState.selectedPane ?? .extensions {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .extensions:
            extensionsSection
        case .about:
            aboutSection
        }
    }

    private var generalSection: some View {
        SettingsSection(title: "General", symbolName: "gearshape") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mark completed tasks as read")
                    Text("Click is safer; hover matches the original CodexStatus behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Picker("Mark completed tasks as read", selection: $preferences.completionReadMode) {
                    ForEach(CompletionReadMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 132)
            }
        }
    }

    private var appearanceSection: some View {
        SettingsSection(title: "Appearance", symbolName: "paintbrush") {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Theme")
                        Text("Built in · Optional")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text("Use the system appearance or keep CodexStatus light or dark.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Picker("Theme", selection: $preferences.appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
            }

            Divider()

            PreferenceToggle(
                title: "Show project names",
                detail: "Display the project suffix beside each task when available.",
                isOn: $preferences.showProjectNames
            )
            Divider()
            PreferenceToggle(
                title: "Show task count in menu bar",
                detail: "Show a number when multiple tasks share the displayed status.",
                isOn: $preferences.showMenuBarCount
            )
            Divider()
            PreferenceToggle(
                title: "Cycle active status colors",
                detail: "Rotate through active states when several kinds of work need attention.",
                isOn: $preferences.cycleStatusColors
            )
            Divider()
            PreferenceToggle(
                title: "Fold idle tasks",
                detail: "Keep inactive tasks in one expandable row.",
                isOn: $preferences.foldIdleTasks
            )
        }
    }

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection(title: "Built in · Default on", symbolName: "checkmark.seal") {
                Text("Essential status and navigation stay part of the app. They work immediately and do not depend on plugins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                BuiltInFeatureRow(
                    descriptor: BuiltInFeatures.coreStatus,
                    isOn: .constant(true),
                    statusText: model.connectionMessage,
                    allowsToggle: false
                )

                Divider()

                BuiltInFeatureRow(
                    descriptor: BuiltInFeatures.usageMeter,
                    isOn: $preferences.usageEnabled,
                    statusText: model.usageUpdatedAt == nil ? "Waiting for usage data" : "Usage data available"
                )
            }

            SettingsSection(title: "Built in · Optional", symbolName: "switch.2") {
                Text("These features ship with CodexStatus but stay off until you choose them because they add alerts or install local integrations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                BuiltInFeatureRow(
                    descriptor: BuiltInFeatures.enhancedActivity,
                    isOn: $preferences.enhancedActivityEnabled,
                    statusText: model.hooksInstalled ? "Hooks installed" : "Hooks not installed"
                )

                Divider()

                BuiltInFeatureRow(
                    descriptor: BuiltInFeatures.codexLifecycle,
                    isOn: $preferences.followCodexLifecycle,
                    statusText: lifecycleController.statusText
                )

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    BuiltInFeatureRow(
                        descriptor: BuiltInFeatures.macOSNotifications,
                        isOn: $preferences.notificationsEnabled,
                        statusText: notificationController.statusText
                    )

                    if preferences.notificationsEnabled {
                        Divider().padding(.leading, 38)
                        notificationControls
                            .padding(.leading, 38)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    BuiltInFeatureRow(
                        descriptor: BuiltInFeatures.updateChecks,
                        isOn: $preferences.updateChecksEnabled,
                        statusText: updateChecker.state.statusText
                    )

                    if preferences.updateChecksEnabled {
                        HStack(spacing: 10) {
                            Button("Check Now") {
                                updateChecker.checkNow()
                            }
                            .controlSize(.small)
                            .disabled(updateChecker.state.isBusy)

                            updateDownloadControl
                            Spacer()
                        }
                        .padding(.leading, 38)
                    }
                }
            }

            SettingsSection(title: "Plugins", symbolName: "puzzlepiece.extension") {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Independent capabilities can be installed and updated separately. Imported resource packs never execute third-party code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(".codexstatusplugin · schema 1")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 12)
                    Button("Folder") {
                        openPluginsFolder()
                    }
                    Button("Import…") {
                        choosePluginToImport()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    PluginRow(
                        descriptor: manifest(
                            BuiltInPluginIdentifiers.progressSidecar,
                            fallback: BuiltInPluginFallbacks.progressSidecar
                        ),
                        source: .bundled,
                        isOn: $preferences.progressSidecarEnabled,
                        statusText: preferences.progressSidecarEnabled ? preferences.progressRefreshInterval.title : "Off"
                    )

                    if preferences.progressSidecarEnabled {
                        Divider().padding(.leading, 38)
                        progressSidecarControls
                            .padding(.leading, 38)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    PluginRow(
                        descriptor: manifest(
                            BuiltInPluginIdentifiers.promptLibrary,
                            fallback: BuiltInPluginFallbacks.promptLibrary
                        ),
                        source: .bundled,
                        isOn: $preferences.promptLibraryEnabled,
                        statusText: model.promptLibrary.statusText
                    )

                    if preferences.promptLibraryEnabled {
                        HStack(spacing: 9) {
                            Button("Manage Presets…") {
                                viewState.isShowingPromptLibrary = true
                            }
                            .controlSize(.small)
                            if let warning = model.promptLibrary.loadWarnings.first {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(warning)
                            }
                            Spacer()
                        }
                        .padding(.leading, 38)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Imported Resource Packs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if pluginRegistry.importedPlugins.isEmpty {
                        Text("No imported plugins. Resource packs are validated and installed disabled.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(Array(pluginRegistry.importedPlugins.enumerated()), id: \.element.id) { index, plugin in
                            if index > 0 { Divider() }
                            PluginRow(
                                descriptor: plugin.manifest,
                                source: .imported,
                                isOn: importedPluginBinding(plugin.id),
                                statusText: pluginRegistry.isImportedPluginEnabled(plugin.id) ? "Enabled" : "Installed · disabled",
                                onRemove: { viewState.pluginAlert = .remove(plugin) }
                            )
                        }
                    }
                }
            }
        }
    }

    private func manifest(_ identifier: String, fallback: PluginManifest) -> PluginManifest {
        pluginRegistry.plugin(identifier: identifier)?.manifest ?? fallback
    }

    @ViewBuilder
    private var updateDownloadControl: some View {
        switch updateChecker.state {
        case .available(let update, _):
            Button("Download \(update.version)") {
                updateChecker.downloadAvailableUpdate()
            }
            .controlSize(.small)
            .disabled(update.downloadAsset == nil)
        case .downloading(let update):
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Downloading \(update.version)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloaded(let result, _):
            Button("Show \(result.update.version) in Downloads") {
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            }
            .controlSize(.small)
        case .downloadFailed(let update, _):
            Button("Retry \(update.version)") {
                updateChecker.downloadAvailableUpdate()
            }
            .controlSize(.small)
        default:
            EmptyView()
        }
    }

    private func importedPluginBinding(_ identifier: String) -> Binding<Bool> {
        Binding(
            get: { pluginRegistry.isImportedPluginEnabled(identifier) },
            set: { pluginRegistry.setImportedPlugin(identifier, enabled: $0) }
        )
    }

    private func choosePluginToImport() {
        let panel = NSOpenPanel()
        panel.title = "Import CodexStatus Plugin"
        panel.message = "Choose a .codexstatusplugin resource-pack folder. Imported code is not allowed."
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        if let pluginType = UTType(filenameExtension: "codexstatusplugin") {
            panel.allowedContentTypes = [pluginType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let plugin = try pluginRegistry.importPlugin(from: url)
            viewState.pluginAlert = .message(
                title: "Plugin Imported",
                detail: "\(plugin.manifest.name) \(plugin.manifest.version) was installed disabled. Review its capabilities before enabling it."
            )
        } catch {
            viewState.pluginAlert = .message(
                title: "Plugin Was Not Imported",
                detail: error.localizedDescription
            )
        }
    }

    private func openPluginsFolder() {
        do {
            try pluginRegistry.prepareInstalledPluginsDirectory()
            NSWorkspace.shared.open(pluginRegistry.installedPluginsDirectory)
        } catch {
            viewState.pluginAlert = .message(title: "Plugins Folder Unavailable", detail: error.localizedDescription)
        }
    }

    private func removeImportedPlugin(_ plugin: InstalledPlugin) {
        do {
            try pluginRegistry.removePlugin(identifier: plugin.id)
        } catch {
            viewState.pluginAlert = .message(title: "Plugin Was Not Removed", detail: error.localizedDescription)
        }
    }

    private var progressSidecarControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Automatic updates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Automatic updates", selection: $preferences.progressRefreshInterval) {
                    ForEach(ProgressRefreshInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .labelsHidden()
                .frame(width: 132)
            }

            Text("Progress prompt")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(text: $preferences.progressSidecarPrompt)
                .font(.system(size: 11))
                .frame(minHeight: 58, maxHeight: 78)
                .padding(5)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                }

            HStack(alignment: .firstTextBaseline) {
                Text("Manual and automatic updates run in an ephemeral read-only side conversation. They do not change the source task, but each update uses account quota.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Reset Prompt") {
                    preferences.progressSidecarPrompt = AppPreferences.defaultProgressSidecarPrompt
                }
                .controlSize(.small)
            }
        }
    }

    private var notificationControls: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Choose a separate alert and sound for each event. Needs Attention includes approval and input requests; Enhanced Activity improves detection accuracy.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NotificationRuleRow(
                title: "Completed",
                detail: "A task finished successfully",
                status: .done,
                isEnabled: $preferences.notifyOnCompletion,
                sound: $preferences.completionNotificationSound,
                onTest: { notificationController.sendTestNotification(for: .done) }
            )

            Divider()

            NotificationRuleRow(
                title: "Needs Attention",
                detail: "Approval or input is required",
                status: .needsAttention,
                isEnabled: $preferences.notifyOnAttention,
                sound: $preferences.attentionNotificationSound,
                onTest: { notificationController.sendTestNotification(for: .needsAttention) }
            )

            Divider()

            NotificationRuleRow(
                title: "Error",
                detail: "A task failed or stopped unexpectedly",
                status: .error,
                isEnabled: $preferences.notifyOnError,
                sound: $preferences.errorNotificationSound,
                onTest: { notificationController.sendTestNotification(for: .error) }
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Quiet hours", isOn: $preferences.notificationQuietHoursEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                if preferences.notificationQuietHoursEnabled {
                    HStack(spacing: 7) {
                        Text("From").foregroundStyle(.secondary)
                        DatePicker(
                            "Quiet hours start",
                            selection: quietStartBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                        Text("to").foregroundStyle(.secondary)
                        DatePicker(
                            "Quiet hours end",
                            selection: quietEndBinding,
                            displayedComponents: .hourAndMinute
                        )
                        .labelsHidden()
                    }
                    .font(.caption)
                }
            }

            Text("Test buttons ignore quiet hours and event switches.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var quietStartBinding: Binding<Date> {
        timeBinding(for: $preferences.notificationQuietStartMinute)
    }

    private var quietEndBinding: Binding<Date> {
        timeBinding(for: $preferences.notificationQuietEndMinute)
    }

    private func timeBinding(for minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    byAdding: .minute,
                    value: minutes.wrappedValue,
                    to: Calendar.current.startOfDay(for: Date())
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        )
    }

    private var aboutSection: some View {
        SettingsSection(title: "About & Privacy", symbolName: "hand.raised") {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CodexStatus")
                        .fontWeight(.medium)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Link("View on GitHub", destination: Self.repositoryURL)
            }

            Divider()

            Text("CodexStatus runs locally, has no analytics, and does not upload your task or usage data. Enabled extensions list every capability they use above.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Open Data Folder", action: onOpenDataFolder)
                Spacer()
                Button("Remove Installed Integrations…", role: .destructive) {
                    viewState.isConfirmingIntegrationRemoval = true
                }
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "0.3.1"
    }

    private static let repositoryURL = URL(string: "https://github.com/patrick-lim-1008/CodexStatus")!
}

@MainActor
private final class SettingsViewState: ObservableObject {
    @Published var selectedPane: SettingsPane? = .extensions
    @Published var isConfirmingIntegrationRemoval = false
    @Published var isShowingPromptLibrary = false
    @Published var pluginAlert: PluginAlert?
}

private enum PluginAlert: Identifiable {
    case message(title: String, detail: String)
    case remove(InstalledPlugin)

    var id: String {
        switch self {
        case .message(let title, let detail): "message-\(title)-\(detail)"
        case .remove(let plugin): "remove-\(plugin.id)"
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case appearance
    case extensions
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .extensions: "Extensions"
        case .about: "About & Privacy"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Choose how CodexStatus behaves on this Mac."
        case .appearance: "Keep the menu bar and task list as compact as you prefer."
        case .extensions: "Add optional capabilities without changing the quiet core experience."
        case .about: "Version, privacy, local data, and integration controls."
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintbrush"
        case .extensions: "puzzlepiece.extension"
        case .about: "hand.raised"
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let symbolName: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
        } label: {
            Label(title, systemImage: symbolName)
                .font(.headline)
        }
    }
}

private struct PreferenceToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

private struct NotificationRuleRow: View {
    let title: String
    let detail: String
    let status: AgentStatus
    @Binding var isEnabled: Bool
    @Binding var sound: NotificationSoundChoice
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)

            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)

            Spacer(minLength: 8)

            Picker("Sound", selection: $sound) {
                ForEach(NotificationSoundChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 122)
            .disabled(!isEnabled)

            Button(action: onTest) {
                Image(systemName: "bell")
            }
            .buttonStyle(.borderless)
            .help("Test \(title) notification")
        }
    }
}

private struct BuiltInFeatureRow: View {
    let descriptor: BuiltInFeatureDescriptor
    @Binding var isOn: Bool
    let statusText: String
    var allowsToggle = true

    var body: some View {
        ExtensionPresentationRow(
            name: descriptor.name,
            summary: descriptor.summary,
            symbolName: descriptor.symbolName,
            badge: descriptor.availability,
            capabilities: descriptor.capabilities,
            privacyDescription: descriptor.privacyDescription,
            isOn: $isOn,
            statusText: statusText,
            allowsToggle: allowsToggle
        )
    }
}

private struct PluginRow: View {
    let descriptor: PluginManifest
    let source: PluginSource
    @Binding var isOn: Bool
    let statusText: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        ExtensionPresentationRow(
            name: descriptor.name,
            summary: descriptor.summary,
            symbolName: descriptor.symbolName,
            badge: source.rawValue,
            capabilities: descriptor.capabilities,
            privacyDescription: descriptor.privacyDescription,
            isOn: $isOn,
            statusText: statusText,
            onRemove: onRemove
        )
    }
}

private struct ExtensionPresentationRow: View {
    let name: String
    let summary: String
    let symbolName: String
    let badge: String
    let capabilities: [String]
    let privacyDescription: String
    @Binding var isOn: Bool
    let statusText: String
    var allowsToggle = true
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .fontWeight(.medium)
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(capabilities.map { PluginCapabilityLabels.title(for: $0) }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 7) {
                if allowsToggle {
                    Toggle(name, isOn: $isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 16, weight: .semibold))
                        .help("Always available")
                }
                if let onRemove {
                    Button("Remove", role: .destructive, action: onRemove)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .help(privacyDescription)
    }
}

private struct PromptLibraryEditor: View {
    @ObservedObject var library: PromptLibraryPlugin
    @ObservedObject private var editorState: PromptLibraryEditorState
    @Environment(\.dismiss) private var dismiss

    init(library: PromptLibraryPlugin) {
        self.library = library
        editorState = PromptLibraryEditorState()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Prompt & Constraint Library")
                        .font(.headline)
                    Text("Choose a preset from a task row; CodexStatus copies it and opens that task.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 8) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(library.presets) { preset in
                                Button {
                                    load(preset)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(preset.title)
                                            .font(.system(size: 12, weight: .medium))
                                            .lineLimit(1)
                                        Text(preset.sourceName)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        editorState.selectedPresetID == preset.id ? Color.accentColor.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                    Button {
                        beginNewPreset()
                    } label: {
                        Label("New Preset", systemImage: "plus")
                    }
                    .controlSize(.small)
                    .padding(.bottom, 10)
                }
                .frame(width: 190)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    TextField("Preset name", text: $editorState.title)
                        .textFieldStyle(.roundedBorder)

                    Text("Prompt")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editorState.prompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 105)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        }

                    Text("Constraints")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $editorState.constraints)
                        .font(.system(size: 12))
                        .frame(minHeight: 85)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        }

                    if let validationMessage = editorState.validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HStack {
                        if let editingCustomID = editorState.editingCustomID {
                            Button("Delete", role: .destructive) {
                                library.removeCustomPreset(id: editingCustomID)
                                beginNewPreset()
                            }
                        }
                        Spacer()
                        Button(editorState.editingCustomID == nil ? "Save as My Preset" : "Save") {
                            save()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(editorState.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || editorState.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 650, height: 470)
        .onAppear {
            if let first = library.presets.first { load(first) } else { beginNewPreset() }
        }
    }

    private func load(_ preset: PromptPreset) {
        editorState.selectedPresetID = preset.id
        editorState.editingCustomID = preset.isEditable ? preset.payload.id : nil
        editorState.draftID = preset.isEditable ? preset.payload.id : UUID().uuidString
        editorState.title = preset.payload.title
        editorState.prompt = preset.payload.prompt
        editorState.constraints = preset.payload.constraints
        editorState.validationMessage = nil
    }

    private func beginNewPreset() {
        editorState.selectedPresetID = nil
        editorState.editingCustomID = nil
        editorState.draftID = UUID().uuidString
        editorState.title = ""
        editorState.prompt = ""
        editorState.constraints = ""
        editorState.validationMessage = nil
    }

    private func save() {
        let preset = PromptPresetPayload(
            id: editorState.editingCustomID ?? editorState.draftID,
            title: editorState.title.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: editorState.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            constraints: editorState.constraints.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try library.saveCustomPreset(preset)
            editorState.editingCustomID = preset.id
            editorState.selectedPresetID = "My Presets::\(preset.id)"
            editorState.validationMessage = nil
        } catch {
            editorState.validationMessage = error.localizedDescription
        }
    }
}

@MainActor
private final class PromptLibraryEditorState: ObservableObject {
    @Published var selectedPresetID: String?
    @Published var editingCustomID: String?
    @Published var draftID = UUID().uuidString
    @Published var title = ""
    @Published var prompt = ""
    @Published var constraints = ""
    @Published var validationMessage: String?
}
