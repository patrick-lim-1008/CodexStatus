import AppKit
import SwiftUI

struct StatusPopover: View {
    @ObservedObject var model: StatusModel
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var updateChecker: AppUpdateChecker
    @ObservedObject private var viewState: StatusPopoverViewState
    let onOpenSettings: () -> Void

    init(
        model: StatusModel,
        preferences: AppPreferences,
        updateChecker: AppUpdateChecker,
        onOpenSettings: @escaping () -> Void
    ) {
        self.model = model
        self.preferences = preferences
        self.updateChecker = updateChecker
        viewState = StatusPopoverViewState()
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.tasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(model.prominentTasks) { task in
                        taskEntry(task)
                    }

                    if !model.foldedIdleTasks.isEmpty {
                        idleDisclosure
                        if model.showsIdleTasks {
                            ForEach(model.foldedIdleTasks) { task in
                                taskEntry(task)
                            }
                        }
                    }
                }
                .padding(8)
            }

        }
        .frame(width: 224)
        .background(.regularMaterial)
        .preferredColorScheme(preferences.appTheme.colorScheme)
        .alert(item: $viewState.progressAlert) { alert in
            switch alert {
            case .confirmation(let task):
                Alert(
                    title: Text("Ask the Progress Sidecar?"),
                    message: Text("This creates a temporary side conversation for “\(task.name)”. It will not change the source task, but it uses account quota."),
                    primaryButton: .default(Text("Ask Sidecar")) {
                        preferences.progressSidecarWarningAcknowledged = true
                        sendProgressRequest(for: task)
                    },
                    secondaryButton: .cancel()
                )
            case .failure(let message):
                Alert(
                    title: Text("Progress is unavailable"),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func taskEntry(_ task: AgentTask) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { model.openThread(task.id) } label: {
                    TaskRow(
                        task: task,
                        showsProjectName: preferences.showProjectNames,
                        isProjectHovering: model.hoveredProjectTaskID == task.id,
                        onProjectHoverChanged: { hovering in
                            if hovering {
                                model.hoveredProjectTaskID = task.id
                            } else if model.hoveredProjectTaskID == task.id {
                                model.hoveredProjectTaskID = nil
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                if preferences.progressSidecarEnabled {
                    Button {
                        beginProgressRequest(for: task)
                    } label: {
                        Group {
                            if model.progressSidecar.requestingTaskIDs.contains(task.id) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "sidebar.right")
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 28)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.progressSidecar.requestingTaskIDs.contains(task.id))
                    .help("Ask for progress without interrupting this task")
                }

                if preferences.promptLibraryEnabled, !model.promptLibrary.presets.isEmpty {
                    Menu {
                        ForEach(model.promptLibrary.presets) { preset in
                            Button {
                                copyPrompt(preset, for: task)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(preset.title)
                                    Text(preset.sourceName)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: viewState.copiedPromptTaskID == task.id
                            ? "checkmark"
                            : "text.badge.plus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(viewState.copiedPromptTaskID == task.id ? .green : .secondary)
                            .frame(width: 20, height: 28)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Choose a prompt, copy it, and open this task")
                }
            }
            .contextMenu {
                if preferences.progressSidecarEnabled {
                    if model.progressSidecar.requestingTaskIDs.contains(task.id) {
                        Button("Getting progress…") {}
                            .disabled(true)
                    } else {
                        Button("Ask Progress Sidecar") {
                            beginProgressRequest(for: task)
                        }
                    }
                    if model.progressSidecar.snapshots[task.id] != nil {
                        Button("Hide Progress") {
                            model.progressSidecar.dismissProgress(for: task.id)
                        }
                    }
                } else {
                    Button("Enable Progress Sidecar…", action: onOpenSettings)
                }
                if preferences.promptLibraryEnabled, !model.promptLibrary.presets.isEmpty {
                    Menu("Copy Prompt & Open Task") {
                        ForEach(model.promptLibrary.presets) { preset in
                            Button(preset.title) {
                                copyPrompt(preset, for: task)
                            }
                        }
                    }
                }
            }

            if let snapshot = model.progressSidecar.snapshots[task.id] {
                ProgressSnapshotView(snapshot: snapshot) {
                    model.progressSidecar.dismissProgress(for: task.id)
                }
                .padding(.leading, 25)
                .padding(.trailing, 4)
                .padding(.bottom, 6)
            } else if model.progressSidecar.requestingTaskIDs.contains(task.id) {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("Asking in a temporary side conversation…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, 25)
                .padding(.trailing, 4)
                .padding(.bottom, 7)
            }
        }
        .onHover { hovering in
            if hovering && task.status == .done && preferences.completionReadMode == .hover {
                model.acknowledgeCompletion(for: task.id)
            }
        }
        .zIndex(model.hoveredProjectTaskID == task.id ? 20 : 0)
    }

    private func beginProgressRequest(for task: AgentTask) {
        if preferences.progressSidecarWarningAcknowledged {
            sendProgressRequest(for: task)
        } else {
            viewState.progressAlert = .confirmation(task)
        }
    }

    private func sendProgressRequest(for task: AgentTask) {
        model.progressSidecar.requestProgress(for: task) { result in
            if case .failure(let error) = result {
                viewState.progressAlert = .failure(error.localizedDescription)
            }
        }
    }

    private func copyPrompt(_ preset: PromptPreset, for task: AgentTask) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(preset.composedText, forType: .string)
        viewState.copiedPromptTaskID = task.id
        model.openThread(task.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if viewState.copiedPromptTaskID == task.id {
                viewState.copiedPromptTaskID = nil
            }
        }
    }

    private var idleDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                model.showsIdleTasks.toggle()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: model.showsIdleTasks ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 10)
                Text("\(model.foldedIdleTasks.count) idle \(model.foldedIdleTasks.count == 1 ? "task" : "tasks")")
                    .font(.caption)
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 5) {
            Button { model.openCodex() } label: {
                HStack(spacing: 7) {
                    CodexMarkView(color: model.summaryStatus.color)
                        .frame(width: 16, height: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text("Codex").font(.headline)
                            Circle()
                                .fill(model.isConnected ? Color.green : Color.secondary)
                                .frame(width: 5, height: 5)
                        }
                        Text(summaryText).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Bring Codex to front")
            .layoutPriority(1)

            Button { model.refreshAll() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 13, height: 16)
            }
            .buttonStyle(.plain)
            .help("Refresh activity and usage")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 13, height: 16)
            }
            .buttonStyle(.plain)
            .help("Open CodexStatus Settings")

            updateAction

            Spacer(minLength: 3)
            if preferences.usageEnabled {
                UsageSummaryView(
                    weeklyWindow: model.weeklyUsageWindow,
                    fiveHourWindow: model.fiveHourUsageWindow,
                    singleWindow: model.singleUsageWindow,
                    updatedAt: model.usageUpdatedAt,
                    isHovering: model.isUsageHovering,
                    onHoverChanged: { model.isUsageHovering = $0 }
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .zIndex(10)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text(model.isConnected ? "Start a Codex task to see it here" : "Open Codex to show live tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var summaryText: String {
        guard !model.tasks.isEmpty else {
            return model.isConnected ? "Idle" : "Waiting for Codex"
        }
        let noun = model.summaryCount == 1 ? "task" : "tasks"
        return "\(model.summaryCount) \(noun) · \(model.summaryStatus.title)"
    }

    @ViewBuilder
    private var updateAction: some View {
        switch updateChecker.state {
        case .available(let update, _), .downloadFailed(let update, _):
            Button {
                updateChecker.downloadAvailableUpdate()
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 13, height: 16)
            }
            .buttonStyle(.plain)
            .help("Download CodexStatus \(update.version)")
        case .downloading:
            ProgressView()
                .controlSize(.mini)
                .frame(width: 13, height: 16)
                .help("Downloading CodexStatus update")
        case .downloaded(let result, _):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([result.fileURL])
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 13, height: 16)
            }
            .buttonStyle(.plain)
            .help("Show CodexStatus \(result.update.version) in Downloads")
        default:
            EmptyView()
        }
    }
}

private enum ProgressAlert: Identifiable {
    case confirmation(AgentTask)
    case failure(String)

    var id: String {
        switch self {
        case .confirmation(let task): "confirmation-\(task.id)"
        case .failure(let message): "failure-\(message)"
        }
    }
}

@MainActor
private final class StatusPopoverViewState: ObservableObject {
    @Published var progressAlert: ProgressAlert?
    @Published var copiedPromptTaskID: String?
}

private struct ProgressSnapshotView: View {
    let snapshot: ProgressSnapshot
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                Text(snapshot.updatedAt, style: .relative)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .help("Hide progress")
        }
        .padding(7)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct UsageSummaryView: View {
    let weeklyWindow: UsageWindow?
    let fiveHourWindow: UsageWindow?
    let singleWindow: UsageWindow?
    let updatedAt: Date?
    let isHovering: Bool
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        Group {
            if fiveHourWindow != nil {
                dualUsageSummary
            } else {
                singleUsageSummary
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                onHoverChanged(hovering)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                UsageHoverCard(
                    windows: displayedWindows,
                    updatedText: updatedText
                )
                .offset(y: fiveHourWindow == nil ? 34 : 54)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topTrailing)))
                .allowsHitTesting(false)
            }
        }
        .accessibilityLabel(helpText)
    }

    private var dualUsageSummary: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 4) {
                Text(weeklyResetDate)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                UsageRing(window: weeklyWindow, size: 23)
            }

            VStack(alignment: .trailing, spacing: 2) {
                UsageBar(window: fiveHourWindow)
                    .frame(width: 70)
                HStack(spacing: 3) {
                    Text(fiveHourRemainingText)
                    Text("·")
                    Text(fiveHourResetTime)
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private var singleUsageSummary: some View {
        HStack(spacing: 5) {
            Text(singleResetDate)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            UsageRing(window: singleWindow, size: 28)
        }
    }

    private var weeklyResetDate: String {
        guard let weeklyWindow, weeklyWindow.resetsAt > 0 else { return "Week —" }
        return Date(timeIntervalSince1970: weeklyWindow.resetsAt)
            .formatted(.dateTime.month(.abbreviated).day())
    }

    private var singleResetDate: String {
        guard let singleWindow, singleWindow.resetsAt > 0 else { return "—" }
        return Date(timeIntervalSince1970: singleWindow.resetsAt)
            .formatted(.dateTime.month(.abbreviated).day())
    }

    private var helpText: String {
        (displayedWindows.map(usageDescription) + [updatedText])
            .joined(separator: "\n")
    }

    private var displayedWindows: [UsageWindow] {
        if fiveHourWindow != nil {
            return [weeklyWindow, fiveHourWindow].compactMap { $0 }
        }
        return [singleWindow].compactMap { $0 }
    }

    private var fiveHourRemainingText: String {
        guard let fiveHourWindow else { return "5h —" }
        return "5h \(Int(fiveHourWindow.remainingPercent.rounded()))%"
    }

    private var fiveHourResetTime: String {
        guard let fiveHourWindow, fiveHourWindow.resetsAt > 0 else { return "—" }
        return Date(timeIntervalSince1970: fiveHourWindow.resetsAt)
            .formatted(.dateTime.hour().minute())
    }

    private var updatedText: String {
        guard let updatedAt else { return "Usage refresh time unavailable" }
        return "Updated " + updatedAt.formatted(.dateTime.hour().minute().second())
    }

    private func usageDescription(_ window: UsageWindow?) -> String {
        guard let window else { return "Usage unavailable" }
        let percentage = "\(Int(window.remainingPercent.rounded()))% remaining"
        guard window.resetsAt > 0 else { return "\(window.name) · \(percentage)" }
        let reset = Date(timeIntervalSince1970: window.resetsAt)
            .formatted(.dateTime.year().month().day().hour().minute())
        return "\(window.name) · \(percentage) · resets \(reset)"
    }
}

private struct UsageHoverCard: View {
    let windows: [UsageWindow]
    let updatedText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(windows) { window in
                usageLine(window)
            }
            Text(updatedText)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10))
        .foregroundStyle(.primary)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }

    @ViewBuilder
    private func usageLine(_ window: UsageWindow) -> some View {
        HStack(spacing: 5) {
            Text(window.name).fontWeight(.semibold)
            Text("\(Int(window.remainingPercent.rounded()))% left")
                .foregroundStyle(.secondary)
        }
        if window.resetsAt > 0 {
            Text("Resets " + Date(timeIntervalSince1970: window.resetsAt)
                .formatted(.dateTime.year().month().day().hour().minute()))
                .foregroundStyle(.secondary)
        }
    }
}

private struct UsageRing: View {
    let window: UsageWindow?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 2.5)
            if let window {
                Circle()
                    .trim(from: 0, to: max(0, min(1, window.remainingPercent / 100)))
                    .stroke(tintColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: size <= 24 ? 7 : 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }

    private var tintColor: Color {
        guard let window else { return .secondary }
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 25 { return .orange }
        return .blue
    }

}

private struct UsageBar: View {
    let window: UsageWindow?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(tintColor)
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 4)
        .accessibilityLabel(window.map { "\($0.name), \(Int($0.remainingPercent.rounded()))% remaining" } ?? "5-hour usage unavailable")
    }

    private var progress: CGFloat {
        CGFloat(max(0, min(1, (window?.remainingPercent ?? 0) / 100)))
    }

    private var tintColor: Color {
        guard let window else { return .secondary.opacity(0.4) }
        if window.remainingPercent <= 10 { return .red }
        if window.remainingPercent <= 25 { return .orange }
        return .blue
    }
}

private struct TaskRow: View {
    let task: AgentTask
    let showsProjectName: Bool
    let isProjectHovering: Bool
    let onProjectHoverChanged: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(task.status.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(task.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if showsProjectName, let projectName = task.projectName {
                        Text(projectName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 116, alignment: .trailing)
                            .layoutPriority(2)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                withAnimation(.easeOut(duration: 0.1)) {
                                    onProjectHoverChanged(hovering)
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if isProjectHovering {
                                    ProjectNameHoverCard(projectName: projectName)
                                        .offset(y: 19)
                                        .transition(.opacity.combined(with: .scale(
                                            scale: 0.97,
                                            anchor: .topTrailing
                                        )))
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                }
                Text(task.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
    }
}

private struct ProjectNameHoverCard: View {
    let projectName: String

    var body: some View {
        Text(projectName)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.primary)
        .frame(maxWidth: 180, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
}
