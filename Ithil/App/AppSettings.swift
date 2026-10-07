import Foundation
import IthilCore
import Observation

/// The Night / Dawn / Match System appearance choice.
enum AppearanceChoice: String, CaseIterable {
    case night, dawn, system
}

/// Preferences that belong to this Mac rather than to a library folder, stored in `UserDefaults`.
///
/// Every property is read once at launch and written through on change. Changing `appearance` applies it
/// to the whole app at once (see `Appearance`). `AppModel` observes `firstWeekday` and rebuilds its
/// calendar math when it changes, so the views never have to wire that up. `QuickAddHotKeyController`
/// observes `quickAddHotKey` and re-registers the global shortcut.
///
/// In `-demo` mode the store is a throwaway suite (`LaunchOptions.makeDemoDefaults()`), and onboarding
/// counts as done.
@Observable @MainActor
final class AppSettings {
    private let defaults: UserDefaults
    private let isDemo: Bool
    private var storedAppearance: AppearanceChoice
    private var storedDefaultAlert: AlertOffset?
    private var storedFirstWeekday: Int?
    private var storedShowsMenuBarExtra: Bool
    private var storedQuickAddHotKey: HotKeyCombo?
    private var storedHasCompletedOnboarding: Bool

    /// `isDemo` defaults to what the launch arguments say; the app passes `options.isDemo` explicitly.
    init(defaults: UserDefaults = .standard, isDemo: Bool = LaunchOptions.current.isDemo) {
        self.defaults = defaults
        self.isDemo = isDemo
        storedAppearance = AppSettings.readAppearance(from: defaults)
        storedDefaultAlert = AppSettings.readDefaultAlert(from: defaults)
        storedFirstWeekday = AppSettings.readFirstWeekday(from: defaults)
        storedShowsMenuBarExtra = defaults.object(forKey: Key.showsMenuBarExtra) as? Bool ?? true
        storedQuickAddHotKey = AppSettings.readQuickAddHotKey(from: defaults)
        storedHasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    /// Default `.night`.
    var appearance: AppearanceChoice {
        get { storedAppearance }
        set {
            guard newValue != storedAppearance else { return }
            storedAppearance = newValue
            defaults.set(newValue.rawValue, forKey: Key.appearance)
            Appearance.apply(newValue)
        }
    }

    /// The alert new events get. Default 10 minutes; nil means "None".
    var defaultAlert: AlertOffset? {
        get { storedDefaultAlert }
        set {
            guard newValue != storedDefaultAlert else { return }
            storedDefaultAlert = newValue
            defaults.set(newValue?.minutesBefore ?? Self.noAlert, forKey: Key.defaultAlert)
        }
    }

    /// nil follows the locale; 1 = Sunday … 7 = Saturday. Other values are treated as nil.
    var firstWeekday: Int? {
        get { storedFirstWeekday }
        set {
            let weekday = newValue.flatMap { (1...7).contains($0) ? $0 : nil }
            guard weekday != storedFirstWeekday else { return }
            storedFirstWeekday = weekday
            if let weekday {
                defaults.set(weekday, forKey: Key.firstWeekday)
            } else {
                defaults.removeObject(forKey: Key.firstWeekday)
            }
        }
    }

    /// `firstWeekday`, or the locale's when it is nil.
    var effectiveFirstWeekday: Int {
        firstWeekday ?? Calendar.autoupdatingCurrent.firstWeekday
    }

    /// Whether the moon menu bar extra is shown. Default true.
    var showsMenuBarExtra: Bool {
        get { storedShowsMenuBarExtra }
        set {
            guard newValue != storedShowsMenuBarExtra else { return }
            storedShowsMenuBarExtra = newValue
            defaults.set(newValue, forKey: Key.showsMenuBarExtra)
        }
    }

    /// The global shortcut that opens Quick Add from any app. Default ⌥Space; nil means off.
    ///
    /// A stored shortcut without ⌘, ⌥ or ⌃ (which would stop that key from typing everywhere) or one that
    /// can't be read counts as the default.
    var quickAddHotKey: HotKeyCombo? {
        get { storedQuickAddHotKey }
        set {
            guard newValue != storedQuickAddHotKey else { return }
            storedQuickAddHotKey = newValue
            guard let newValue else {
                defaults.set(Self.hotKeyOff, forKey: Key.quickAddHotKey)
                return
            }
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.quickAddHotKey)
            }
        }
    }

    /// Whether the first-launch onboarding has been finished (or skipped). Default false; always true in
    /// `-demo`, which never shows onboarding.
    var hasCompletedOnboarding: Bool {
        get { isDemo || storedHasCompletedOnboarding }
        set {
            guard newValue != storedHasCompletedOnboarding else { return }
            storedHasCompletedOnboarding = newValue
            defaults.set(newValue, forKey: Key.hasCompletedOnboarding)
        }
    }

    /// Settings in their own throwaway store, for SwiftUI previews. Like `-demo`, previews skip onboarding.
    static var preview: AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "io.github.visaug36.Ithil.preview") ?? .standard, isDemo: true)
    }

    // MARK: - Storage

    private enum Key {
        static let appearance = "appearance"
        static let defaultAlert = "defaultAlertMinutes"
        static let firstWeekday = "firstWeekday"
        static let showsMenuBarExtra = "showsMenuBarExtra"
        static let quickAddHotKey = "quickAddHotKey"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    /// Stored for "None", so a missing key can still mean "use the default".
    private static let noAlert = -1

    /// Stored for a Quick Add shortcut that was turned off, so a missing key can still mean ⌥Space.
    private static let hotKeyOff = "off"

    private static func readAppearance(from defaults: UserDefaults) -> AppearanceChoice {
        defaults.string(forKey: Key.appearance).flatMap { AppearanceChoice(rawValue: $0) } ?? .night
    }

    private static func readDefaultAlert(from defaults: UserDefaults) -> AlertOffset? {
        guard let minutes = defaults.object(forKey: Key.defaultAlert) as? Int else { return .tenMinutes }
        return minutes == noAlert ? nil : AlertOffset(minutesBefore: minutes)
    }

    private static func readFirstWeekday(from defaults: UserDefaults) -> Int? {
        guard let weekday = defaults.object(forKey: Key.firstWeekday) as? Int else { return nil }
        return (1...7).contains(weekday) ? weekday : nil
    }

    private static func readQuickAddHotKey(from defaults: UserDefaults) -> HotKeyCombo? {
        let stored = defaults.object(forKey: Key.quickAddHotKey)
        if let text = stored as? String, text == hotKeyOff {
            return nil
        }
        guard let data = stored as? Data,
            let combo = try? JSONDecoder().decode(HotKeyCombo.self, from: data),
            combo.hasRequiredModifier
        else { return .optionSpace }
        return combo
    }
}
