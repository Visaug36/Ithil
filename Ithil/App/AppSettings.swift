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
/// calendar math when it changes, so the views never have to wire that up.
///
/// In `-demo` mode the store is a throwaway suite (`LaunchOptions.makeDemoDefaults()`).
@Observable @MainActor
final class AppSettings {
    private let defaults: UserDefaults
    private var storedAppearance: AppearanceChoice
    private var storedDefaultAlert: AlertOffset?
    private var storedFirstWeekday: Int?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedAppearance = AppSettings.readAppearance(from: defaults)
        storedDefaultAlert = AppSettings.readDefaultAlert(from: defaults)
        storedFirstWeekday = AppSettings.readFirstWeekday(from: defaults)
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

    /// Settings in their own throwaway store, for SwiftUI previews.
    static var preview: AppSettings {
        AppSettings(defaults: UserDefaults(suiteName: "io.github.visaug36.Ithil.preview") ?? .standard)
    }

    // MARK: - Storage

    private enum Key {
        static let appearance = "appearance"
        static let defaultAlert = "defaultAlertMinutes"
        static let firstWeekday = "firstWeekday"
    }

    /// Stored for "None", so a missing key can still mean "use the default".
    private static let noAlert = -1

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
}
