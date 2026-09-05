import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var model: StatusModel
    @ObservedObject private var viewState: SettingsViewState

    let onOpenDataFolder: () -> Void
    let onRemoveAllIntegrations: () -> Void
    let onSendTestNotification: (AgentStatus) -> Void

    init(
        preferences: AppPreferences,
        model: StatusModel,
        onOpenDataFolder: @escaping () -> Void,
        onRemoveAllIntegrations: @escaping () -> Void,
        onSendTestNotification: @escaping (AgentStatus) -> Void
    ) {
        self.preferences = preferences
        self.model = model
        viewState = SettingsViewState()
        self.onOpenDataFolder = onOpenDataFolder
        self.onRemoveAllIntegrations = onRemoveAllIntegrations
        self.onSendTestNotification = onSendTestNotification
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
            PreferenceToggle(
                title: "Follow Codex lifecycle",
                detail: "Open CodexStatus when Codex starts and close it when Codex quits.",
                isOn: $preferences.followCodexLifecycle
            )

            Divider()

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
        SettingsSection(title: "Extensions", symbolName: "puzzlepiece.extension") {
            ExtensionRow(
                descriptor: BuiltInExtensions.usageMeter,
                isOn: $preferences.usageEnabled,
                statusText: model.usageUpdatedAt == nil ? "Waiting for usage data" : "Usage data available"
            )

            Divider()

            ExtensionRow(
                descriptor: BuiltInExtensions.enhancedActivity,
                isOn: $preferences.enhancedActivityEnabled,
                statusText: model.hooksInstalled ? "Hooks installed" : "Hooks not installed"
            )

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ExtensionRow(
                    descriptor: BuiltInExtensions.macOSNotifications,
                    isOn: $preferences.notificationsEnabled,
                    statusText: preferences.notificationsEnabled ? "Enabled" : "Off"
                )

                if preferences.notificationsEnabled {
                    Divider().padding(.leading, 38)
                    notificationControls
                        .padding(.leading, 38)
                }
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
                onTest: { onSendTestNotification(.done) }
            )

            Divider()

            NotificationRuleRow(
                title: "Needs Attention",
                detail: "Approval or input is required",
                status: .needsAttention,
                isEnabled: $preferences.notifyOnAttention,
                sound: $preferences.attentionNotificationSound,
                onTest: { onSendTestNotification(.needsAttention) }
            )

            Divider()

            NotificationRuleRow(
                title: "Error",
                detail: "A task failed or stopped unexpectedly",
                status: .error,
                isEnabled: $preferences.notifyOnError,
                sound: $preferences.errorNotificationSound,
                onTest: { onSendTestNotification(.error) }
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
        return version ?? "0.2.1"
    }

    private static let repositoryURL = URL(string: "https://github.com/patrick-lim-1008/CodexStatus")!
}

@MainActor
private final class SettingsViewState: ObservableObject {
    @Published var selectedPane: SettingsPane? = .extensions
    @Published var isConfirmingIntegrationRemoval = false
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

private struct ExtensionRow: View {
    let descriptor: BuiltInExtensionDescriptor
    @Binding var isOn: Bool
    let statusText: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: descriptor.symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(descriptor.name)
                        .fontWeight(.medium)
                    Text("Built-in")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(descriptor.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(descriptor.capabilities.map(\.title).joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
            }

            Spacer(minLength: 12)

            Toggle(descriptor.name, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .help(descriptor.privacySummary)
    }
}
