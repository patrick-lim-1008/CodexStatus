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

enum NotificationSoundChoice: String, CaseIterable, Identifiable, Sendable {
    case none
    case systemDefault
    case glass
    case ping
    case pop
    case basso

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "None"
        case .systemDefault: "System Default"
        case .glass: "Glass"
        case .ping: "Ping"
        case .pop: "Pop"
        case .basso: "Basso"
        }
    }

    var appKitName: String? {
        switch self {
        case .none, .systemDefault: nil
        case .glass: "Glass"
        case .ping: "Ping"
        case .pop: "Pop"
        case .basso: "Basso"
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
        // Kept only as migration inputs from v0.2's single global sound setting.
        static let notificationSoundEnabled = "extensions.notifications.soundEnabled"
        static let notificationSoundChoice = "extensions.notifications.soundChoice"
        static let completionNotificationSound = "extensions.notifications.completionSound"
        static let attentionNotificationSound = "extensions.notifications.attentionSound"
        static let errorNotificationSound = "extensions.notifications.errorSound"
        static let notifyOnCompletion = "extensions.notifications.onCompletion"
        static let notifyOnAttention = "extensions.notifications.onAttention"
        static let notifyOnError = "extensions.notifications.onError"
        static let notificationQuietHoursEnabled = "extensions.notifications.quietHours.enabled"
        static let notificationQuietStartMinute = "extensions.notifications.quietHours.startMinute"
        static let notificationQuietEndMinute = "extensions.notifications.quietHours.endMinute"
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

    @Published var completionNotificationSound: NotificationSoundChoice {
        didSet { defaults.set(completionNotificationSound.rawValue, forKey: Key.completionNotificationSound) }
    }

    @Published var attentionNotificationSound: NotificationSoundChoice {
        didSet { defaults.set(attentionNotificationSound.rawValue, forKey: Key.attentionNotificationSound) }
    }

    @Published var errorNotificationSound: NotificationSoundChoice {
        didSet { defaults.set(errorNotificationSound.rawValue, forKey: Key.errorNotificationSound) }
    }

    @Published var notifyOnCompletion: Bool {
        didSet { defaults.set(notifyOnCompletion, forKey: Key.notifyOnCompletion) }
    }

    @Published var notifyOnAttention: Bool {
        didSet { defaults.set(notifyOnAttention, forKey: Key.notifyOnAttention) }
    }

    @Published var notifyOnError: Bool {
        didSet { defaults.set(notifyOnError, forKey: Key.notifyOnError) }
    }

    @Published var notificationQuietHoursEnabled: Bool {
        didSet { defaults.set(notificationQuietHoursEnabled, forKey: Key.notificationQuietHoursEnabled) }
    }

    @Published var notificationQuietStartMinute: Int {
        didSet { defaults.set(notificationQuietStartMinute, forKey: Key.notificationQuietStartMinute) }
    }

    @Published var notificationQuietEndMinute: Int {
        didSet { defaults.set(notificationQuietEndMinute, forKey: Key.notificationQuietEndMinute) }
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
        let legacySoundEnabled = Self.storedBool(
            in: defaults,
            forKey: Key.notificationSoundEnabled,
            fallback: true
        )
        let legacySoundChoice = defaults.string(forKey: Key.notificationSoundChoice)
            .flatMap(NotificationSoundChoice.init(rawValue:))
        completionNotificationSound = Self.storedSound(
            in: defaults,
            forKey: Key.completionNotificationSound,
            fallback: legacySoundEnabled ? (legacySoundChoice == .systemDefault ? .glass : legacySoundChoice ?? .glass) : .none
        )
        attentionNotificationSound = Self.storedSound(
            in: defaults,
            forKey: Key.attentionNotificationSound,
            fallback: legacySoundEnabled ? (legacySoundChoice == .systemDefault ? .ping : legacySoundChoice ?? .ping) : .none
        )
        errorNotificationSound = Self.storedSound(
            in: defaults,
            forKey: Key.errorNotificationSound,
            fallback: legacySoundEnabled ? (legacySoundChoice == .systemDefault ? .basso : legacySoundChoice ?? .basso) : .none
        )
        notifyOnCompletion = Self.storedBool(
            in: defaults,
            forKey: Key.notifyOnCompletion,
            fallback: true
        )
        notifyOnAttention = Self.storedBool(
            in: defaults,
            forKey: Key.notifyOnAttention,
            fallback: true
        )
        notifyOnError = Self.storedBool(
            in: defaults,
            forKey: Key.notifyOnError,
            fallback: true
        )
        notificationQuietHoursEnabled = Self.storedBool(
            in: defaults,
            forKey: Key.notificationQuietHoursEnabled,
            fallback: false
        )
        notificationQuietStartMinute = Self.storedInt(
            in: defaults,
            forKey: Key.notificationQuietStartMinute,
            fallback: 22 * 60
        )
        notificationQuietEndMinute = Self.storedInt(
            in: defaults,
            forKey: Key.notificationQuietEndMinute,
            fallback: 8 * 60
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

    private static func storedInt(
        in defaults: UserDefaults,
        forKey key: String,
        fallback: Int
    ) -> Int {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return max(0, min(1_439, defaults.integer(forKey: key)))
    }

    private static func storedSound(
        in defaults: UserDefaults,
        forKey key: String,
        fallback: NotificationSoundChoice
    ) -> NotificationSoundChoice {
        defaults.string(forKey: key)
            .flatMap(NotificationSoundChoice.init(rawValue:))
            ?? fallback
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
        defaults.set(completionNotificationSound.rawValue, forKey: Key.completionNotificationSound)
        defaults.set(attentionNotificationSound.rawValue, forKey: Key.attentionNotificationSound)
        defaults.set(errorNotificationSound.rawValue, forKey: Key.errorNotificationSound)
        defaults.set(notifyOnCompletion, forKey: Key.notifyOnCompletion)
        defaults.set(notifyOnAttention, forKey: Key.notifyOnAttention)
        defaults.set(notifyOnError, forKey: Key.notifyOnError)
        defaults.set(notificationQuietHoursEnabled, forKey: Key.notificationQuietHoursEnabled)
        defaults.set(notificationQuietStartMinute, forKey: Key.notificationQuietStartMinute)
        defaults.set(notificationQuietEndMinute, forKey: Key.notificationQuietEndMinute)
    }
}
