import SwiftUI

/// The main window's sidebar: mini month, Up next and Subjects, on the starry sidebar background.
struct CalendarSidebar: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                MiniMonthView()
                SidebarUpNextSection()
                SidebarSubjectsSection()
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .starryBackground(.backgroundSidebar)
    }
}

/// A sidebar section label ("Up next", "Subjects"): 11 pt semibold in `TextTertiary`.
struct SidebarSectionLabel: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(Typography.caption)
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }
}
