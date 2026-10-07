import SwiftUI

/// The main window's sidebar: mini month, Up next and Subjects, on the starry sidebar background, with the
/// notification permission card pinned to the bottom when it applies.
struct CalendarSidebar: View {
    var body: some View {
        // The card sits below the scroll view rather than over it, so nothing scrolls behind its margins.
        VStack(spacing: 0) {
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
            SidebarNotificationPrompt()
        }
        .starryBackground(.backgroundSidebar)
    }
}

/// The explain-then-ask card, only when an alert is coming up in the next two weeks: while permission
/// hasn't been asked for (until "Not Now"), or while notifications are off.
private struct SidebarNotificationPrompt: View {
    @Environment(NotificationsController.self) private var notifications

    var body: some View {
        if isShown {
            NotificationPermissionView()
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
    }

    private var isShown: Bool {
        switch notifications.authorization {
        case .notDetermined:
            return !notifications.isPromptDismissed && notifications.hasUpcomingAlerts
        case .denied:
            return notifications.hasUpcomingAlerts
        case .unknown, .authorized:
            return false
        }
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
