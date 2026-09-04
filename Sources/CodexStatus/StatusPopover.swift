import AppKit
import SwiftUI

struct StatusPopover: View {
    @ObservedObject var model: StatusModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if model.tasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 2) {
                    ForEach(model.prominentTasks) { task in
                        taskButton(task)
                    }

                    if !model.foldedIdleTasks.isEmpty {
                        idleDisclosure
                        if model.showsIdleTasks {
                            ForEach(model.foldedIdleTasks) { task in
                                taskButton(task)
                            }
                        }
                    }
                }
                .padding(8)
            }

        }
        .frame(width: 224)
        .background(.regularMaterial)
    }

    private func taskButton(_ task: AgentTask) -> some View {
        Button { model.openThread(task.id) } label: {
            TaskRow(
                task: task,
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
        .onHover { hovering in
            if hovering && task.status == .done {
                model.acknowledgeCompletion(for: task.id)
            }
        }
        .zIndex(model.hoveredProjectTaskID == task.id ? 20 : 0)
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
                                .fill(model.hooksInstalled ? Color.green : Color.secondary)
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

            Spacer(minLength: 4)
            UsageSummaryView(
                weeklyWindow: model.weeklyUsageWindow,
                fiveHourWindow: model.fiveHourUsageWindow,
                singleWindow: model.singleUsageWindow,
                updatedAt: model.usageUpdatedAt,
                isHovering: model.isUsageHovering,
                onHoverChanged: { model.isUsageHovering = $0 }
            )
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
            Text(model.hooksInstalled ? "Start a Codex task to see it here" : "Connect Codex to show live tasks")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var summaryText: String {
        guard !model.tasks.isEmpty else { return "Idle" }
        let noun = model.summaryCount == 1 ? "task" : "tasks"
        return "\(model.summaryCount) \(noun) · \(model.summaryStatus.title)"
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
                    if let projectName = task.projectName {
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
