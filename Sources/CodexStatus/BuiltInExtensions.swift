import Foundation

enum BuiltInExtensionID: String, CaseIterable, Identifiable, Sendable {
    case usageMeter
    case enhancedActivity
    case macOSNotifications

    var id: Self { self }
}

enum BuiltInExtensionCapability: String, CaseIterable, Identifiable, Sendable {
    case readLocalUsage
    case readTaskActivity
    case installCodexHooks
    case postNotifications
    case playSounds

    var id: Self { self }

    var title: String {
        switch self {
        case .readLocalUsage: "Reads local usage limits"
        case .readTaskActivity: "Reads local task activity"
        case .installCodexHooks: "Adds Codex lifecycle hooks"
        case .postNotifications: "Posts macOS notifications"
        case .playSounds: "Plays notification sounds"
        }
    }
}

struct BuiltInExtensionDescriptor: Identifiable, Sendable {
    let id: BuiltInExtensionID
    let name: String
    let summary: String
    let symbolName: String
    let version: String
    let author: String
    let capabilities: [BuiltInExtensionCapability]
    let privacySummary: String
    let defaultEnabled: Bool
}

enum BuiltInExtensions {
    static let usageMeter = BuiltInExtensionDescriptor(
        id: .usageMeter,
        name: "Usage Meter",
        summary: "Shows the rate-limit windows available to your signed-in Codex account.",
        symbolName: "chart.donut",
        version: "1.0",
        author: "CodexStatus",
        capabilities: [.readLocalUsage],
        privacySummary: "Reads usage data from the local Codex App Server. Nothing is uploaded.",
        defaultEnabled: true
    )

    static let enhancedActivity = BuiltInExtensionDescriptor(
        id: .enhancedActivity,
        name: "Enhanced Activity",
        summary: "Improves approval, failure, and live task-state detection with lifecycle hooks.",
        symbolName: "bolt.horizontal.circle",
        version: "1.0",
        author: "CodexStatus",
        capabilities: [.readTaskActivity, .installCodexHooks],
        privacySummary: "Adds local Codex hooks that write small status snapshots on this Mac.",
        defaultEnabled: false
    )

    static let macOSNotifications = BuiltInExtensionDescriptor(
        id: .macOSNotifications,
        name: "macOS Notifications",
        summary: "Alerts you when a task finishes, needs attention, or stops with an error.",
        symbolName: "bell.badge",
        version: "1.0",
        author: "CodexStatus",
        capabilities: [.postNotifications, .playSounds],
        privacySummary: "Uses the macOS notification service. Notification content stays on this Mac.",
        defaultEnabled: false
    )

    static let all: [BuiltInExtensionDescriptor] = [
        usageMeter,
        enhancedActivity,
        macOSNotifications
    ]

    static func descriptor(for id: BuiltInExtensionID) -> BuiltInExtensionDescriptor {
        switch id {
        case .usageMeter: usageMeter
        case .enhancedActivity: enhancedActivity
        case .macOSNotifications: macOSNotifications
        }
    }
}
