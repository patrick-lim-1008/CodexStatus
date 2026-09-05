import Combine
import Foundation

enum CompletionReadMode: String, CaseIterable, Identifiable, Sendable {
    case click
    case hover

    var id: Self { self }

    var title: String {
        switch self {
        case .click: "When clicked"
        case .hover: "When hovered"
        }
    }
}

/// The user-facing preferences shared by the menu bar UI and settings window.
///
/// Each value is written as soon as it changes so an accessory app can quit at
/// any time without needing a separate save step.
@MainActor
final class AppPreferences: ObservableObject {
    private enum Key {
        static let followCodexLifecycle = "preferences.followCodexLifecycle"
        static let completionReadMode = "preferences.completionReadMode"
        static let showProjectNames = "preferences.showProjectNames"
        static let showMenuBarCount = "preferences.showMenuBarCount"
        static let cycleStatusColors = "preferences.cycleStatusColors"
        static let foldIdleTasks = "preferences.foldIdleTasks"
        static let usageEnabled = "extensions.usageMeter.enabled"
        static let enhancedActivityEnabled = "extensions.enhancedActivity.enabled"
        static let notificationsEnabled = "extensions.notifications.enabled"
        static let notificationSoundEnabled = "extensions.notifications.soundEnabled"
    }

    private let defaults: UserDefaults

    @Published var followCodexLifecycle: Bool {
        didSet { defaults.set(followCodexLifecycle, forKey: Key.followCodexLifecycle) }
    }

    @Published var completionReadMode: CompletionReadMode {
        didSet { defaults.set(completionReadMode.rawValue, forKey: Key.completionReadMode) }
    }

    @Published var showProjectNames: Bool {
        didSet { defaults.set(showProjectNames, forKey: Key.showProjectNames) }
    }

    @Published var showMenuBarCount: Bool {
        didSet { defaults.set(showMenuBarCount, forKey: Key.showMenuBarCount) }
    }

    @Published var cycleStatusColors: Bool {
        didSet { defaults.set(cycleStatusColors, forKey: Key.cycleStatusColors) }
    }

    @Published var foldIdleTasks: Bool {
        didSet { defaults.set(foldIdleTasks, forKey: Key.foldIdleTasks) }
    }

    @Published var usageEnabled: Bool {
        didSet { defaults.set(usageEnabled, forKey: Key.usageEnabled) }
    }

    @Published var enhancedActivityEnabled: Bool {
        didSet { defaults.set(enhancedActivityEnabled, forKey: Key.enhancedActivityEnabled) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    @Published var notificationSoundEnabled: Bool {
        didSet { defaults.set(notificationSoundEnabled, forKey: Key.notificationSoundEnabled) }
    }

    /// Creates preferences while safely migrating users of the original release.
    ///
    /// Version 0.1 installed both integrations automatically and marked completed
    /// tasks as read on hover. Their presence therefore identifies an existing
    /// installation. A fresh install gets the less intrusive v0.2 defaults.
    init(
        defaults: UserDefaults = .standard,
        existingHooksInstalled: Bool,
        existingLifecycleInstalled: Bool
    ) {
        self.defaults = defaults

        let isExistingInstallation = existingHooksInstalled || existingLifecycleInstalled
        followCodexLifecycle = Self.storedBool(
            in: defaults,
            forKey: Key.followCodexLifecycle,
            fallback: existingLifecycleInstalled
        )
        completionReadMode = defaults.string(forKey: Key.completionReadMode)
            .flatMap(CompletionReadMode.init(rawValue:))
            ?? (isExistingInstallation ? .hover : .click)
        showProjectNames = Self.storedBool(
            in: defaults,
            forKey: Key.showProjectNames,
            fallback: true
        )
        showMenuBarCount = Self.storedBool(
            in: defaults,
            forKey: Key.showMenuBarCount,
            fallback: true
        )
        cycleStatusColors = Self.storedBool(
            in: defaults,
            forKey: Key.cycleStatusColors,
            fallback: true
        )
        foldIdleTasks = Self.storedBool(
            in: defaults,
            forKey: Key.foldIdleTasks,
            fallback: true
        )
        usageEnabled = Self.storedBool(
            in: defaults,
            forKey: Key.usageEnabled,
            fallback: true
        )
        enhancedActivityEnabled = Self.storedBool(
            in: defaults,
            forKey: Key.enhancedActivityEnabled,
            fallback: existingHooksInstalled
        )
        notificationsEnabled = Self.storedBool(
            in: defaults,
            forKey: Key.notificationsEnabled,
            fallback: false
        )
        notificationSoundEnabled = Self.storedBool(
            in: defaults,
            forKey: Key.notificationSoundEnabled,
            fallback: true
        )

        persistInitialValues()
    }

    private static func storedBool(
        in defaults: UserDefaults,
        forKey key: String,
        fallback: Bool
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    /// `didSet` observers do not run during initialization. Persisting once here
    /// makes the migration decision stable even if an integration is later removed.
    private func persistInitialValues() {
        defaults.set(followCodexLifecycle, forKey: Key.followCodexLifecycle)
        defaults.set(completionReadMode.rawValue, forKey: Key.completionReadMode)
        defaults.set(showProjectNames, forKey: Key.showProjectNames)
        defaults.set(showMenuBarCount, forKey: Key.showMenuBarCount)
        defaults.set(cycleStatusColors, forKey: Key.cycleStatusColors)
        defaults.set(foldIdleTasks, forKey: Key.foldIdleTasks)
        defaults.set(usageEnabled, forKey: Key.usageEnabled)
        defaults.set(enhancedActivityEnabled, forKey: Key.enhancedActivityEnabled)
        defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled)
        defaults.set(notificationSoundEnabled, forKey: Key.notificationSoundEnabled)
    }
}
