import SwiftUI

/// Type scale from docs/DESIGN.md: New York (serif) semibold for titles, SF Pro for everything else.
/// Times always use tabular numerals; apply `.monospacedDigit()` where they're shown.
enum Typography {
    static var monthTitle: Font { .system(size: 26, weight: .semibold, design: .serif) }
    static var detailTitle: Font { .system(size: 22, weight: .semibold, design: .serif) }
    static var dayHeader: Font { .system(size: 20, weight: .semibold, design: .serif) }
    static var emptyHeadline: Font { .system(size: 20, weight: .semibold, design: .serif) }
    static var sidebarMonth: Font { .system(size: 18, weight: .semibold, design: .serif) }

    static var body: Font { .system(size: 13) }
    static var secondary: Font { .system(size: 12.5) }
    static var caption: Font { .system(size: 11, weight: .semibold) }
    static var eventTitle: Font { .system(size: 12, weight: .semibold) }
    static var eventTime: Font { .system(size: 11) }
}
