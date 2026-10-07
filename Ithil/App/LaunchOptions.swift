import Foundation
import IthilCore
import os

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "LaunchOptions")

/// What the launch arguments ask for.
///
/// - `-demo` loads the design's sample data into a fresh temporary folder, with throwaway settings. The
///   user's own folder, bookmark and settings are never read or written.
/// - `-demoNow 2026-10-06T13:50` (local time) additionally pins the clock, for screenshots. It only takes
///   effect together with `-demo`, so a stray argument can never freeze the clock on real data (backups
///   and `savedAt` stamps depend on it).
struct LaunchOptions: Sendable {
    var isDemo: Bool
    /// The pinned "now" from `-demoNow`, if any.
    var pinnedNow: Date?
    /// The screenshot scene from `-demoAppearance`, `-demoSpan`, `-demoScene` and `-demoWindowSize`.
    var demoScene = DemoScene()

    /// The options of this process.
    static var current: LaunchOptions {
        parse(ProcessInfo.processInfo.arguments, timeZone: .current)
    }

    /// The clock the app runs on: the pinned instant, or the system clock.
    var timeSource: any TimeSource {
        if let pinnedNow {
            return FixedTimeSource(pinnedNow)
        }
        return SystemTimeSource()
    }

    static func parse(_ arguments: [String], timeZone: TimeZone) -> LaunchOptions {
        let isDemo = arguments.contains("-demo")
        var pinnedNow: Date?
        if let flag = arguments.firstIndex(of: "-demoNow") {
            let valueIndex = arguments.index(after: flag)
            let value = valueIndex < arguments.endIndex ? arguments[valueIndex] : ""
            if let date = parseLocalDateTime(value, timeZone: timeZone) {
                pinnedNow = date
            } else {
                logger.error("Ignoring -demoNow: expected yyyy-MM-dd'T'HH:mm, got \(value, privacy: .public)")
            }
        }
        if pinnedNow != nil, !isDemo {
            logger.notice("Ignoring -demoNow without -demo")
            pinnedNow = nil
        }
        var options = LaunchOptions(isDemo: isDemo, pinnedNow: pinnedNow)
        if isDemo {
            options.demoScene = DemoScene.parse(arguments)
        }
        return options
    }

    /// Parses `yyyy-MM-dd'T'HH:mm` as a wall-clock time in `timeZone`. Nil for anything else.
    static func parseLocalDateTime(_ text: String, timeZone: TimeZone) -> Date? {
        let halves = text.split(separator: "T", omittingEmptySubsequences: false)
        guard halves.count == 2, let day = CalendarDate(isoString: String(halves[0])) else { return nil }
        let time = halves[1].split(separator: ":", omittingEmptySubsequences: false)
        guard time.count == 2, time[0].count == 2, time[1].count == 2,
            let hour = Int(time[0]), let minute = Int(time[1]),
            (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        return calendar.date(from: parts)
    }

    /// The settings store for `-demo`: its own suite, emptied at every launch, so demo runs never see
    /// or change the user's settings.
    static func makeDemoDefaults() -> UserDefaults {
        let suiteName = "io.github.visaug36.Ithil.demo"
        // UserDefaults refuses only NSGlobalDomain and the app's own bundle ID as suite names.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("The demo settings suite could not be created")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
