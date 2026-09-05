import Foundation

enum BuiltInPluginIdentifiers {
    static let progressSidecar = "com.codexstatus.progress-sidecar"
}

struct BuiltInFeatureDescriptor {
    let name: String
    let summary: String
    let symbolName: String
    let capabilities: [String]
    let privacyDescription: String
    let availability: String
}

enum BuiltInFeatures {
    static let coreStatus = BuiltInFeatureDescriptor(
        name: "Core Status",
        summary: "Detects task state and activity, keeps completion history, and opens the exact Codex task you select.",
        symbolName: "dot.radiowaves.left.and.right",
        capabilities: ["readTaskActivity", "openCodexTasks"],
        privacyDescription: "Reads local Codex task metadata. Prompts, reasoning, commands, paths, and tool output are not displayed or uploaded.",
        availability: "Built in · Always on"
    )

    static let usageMeter = BuiltInFeatureDescriptor(
        name: "Usage Meter",
        summary: "Shows the rate-limit windows available to your signed-in Codex account.",
        symbolName: "chart.donut",
        capabilities: ["readLocalUsage"],
        privacyDescription: "Reads usage data from the local Codex App Server. Nothing is uploaded.",
        availability: "Built in · Default on"
    )

    static let enhancedActivity = BuiltInFeatureDescriptor(
        name: "Enhanced Activity",
        summary: "Improves approval, failure, and live task-state detection with lifecycle hooks.",
        symbolName: "bolt.horizontal.circle",
        capabilities: ["readTaskActivity", "installCodexHooks"],
        privacyDescription: "Adds local Codex hooks that write small status snapshots on this Mac.",
        availability: "Built in · Optional"
    )

    static let macOSNotifications = BuiltInFeatureDescriptor(
        name: "macOS Notifications",
        summary: "Alerts you when a task finishes, needs attention, or stops with an error.",
        symbolName: "bell.badge",
        capabilities: ["postNotifications", "playSounds"],
        privacyDescription: "Uses the macOS notification service. Notification content stays on this Mac.",
        availability: "Built in · Optional"
    )

    static let codexLifecycle = BuiltInFeatureDescriptor(
        name: "Follow Codex Lifecycle",
        summary: "Starts CodexStatus with Codex and closes it after Codex quits.",
        symbolName: "power",
        capabilities: ["installLifecycleWatcher"],
        privacyDescription: "Installs a local LaunchAgent that only checks whether the Codex app is running.",
        availability: "Built in · Optional"
    )

    static let updateChecks = BuiltInFeatureDescriptor(
        name: "CodexStatus Update Checks",
        summary: "Checks GitHub periodically for a newer stable CodexStatus release.",
        symbolName: "arrow.triangle.2.circlepath.circle",
        capabilities: ["accessGitHubReleases"],
        privacyDescription: "Connects only to the public CodexStatus releases endpoint on GitHub. It does not upload task data.",
        availability: "Built in · Optional"
    )
}

/// Keeps Settings usable if the signed plugin package is copied incompletely.
enum BuiltInPluginFallbacks {
    static let progressSidecar = PluginManifest(
        schemaVersion: 1,
        identifier: BuiltInPluginIdentifiers.progressSidecar,
        name: "Progress Sidecar",
        version: "1.0.0",
        minimumHostVersion: "0.2.2",
        author: "CodexStatus",
        summary: "Shows concise progress through a temporary /side-style conversation.",
        symbolName: "sidebar.right",
        kind: .native,
        entryPoint: "progress-sidecar",
        capabilities: ["readTaskActivity", "createEphemeralSideConversation", "useModelQuota"],
        privacyDescription: "Creates an ephemeral, read-only fork of the selected task. The summary stays in CodexStatus and does not enter the source conversation. Each refresh uses account quota."
    )
}
