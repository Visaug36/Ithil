import IthilCore
import SwiftUI

/// General: appearance (Night, Dawn, Match System), the default alert for new events, the first day of
/// the week, and whether macOS lets Ithil show notifications.
struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Appearance") {
                AppearanceChooser(selection: $settings.appearance)
            }
            Section {
                DefaultAlertPicker(alert: $settings.defaultAlert)
                FirstWeekdayPicker(weekday: $settings.firstWeekday)
            } footer: {
                Text("New events start with this alert. Quick Add gives it only to events with a time.")
                    .font(Typography.eventTime)
                    .foregroundStyle(Color.textTertiary)
            }
            NotificationSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundWindow)
        .frame(height: 450)
    }
}

/// "Notifications": what macOS allows, with the button that fits, and a footnote that explains (before
/// asking) or says where to change it.
private struct NotificationSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(NotificationsController.self) private var notifications
    @State private var isRequesting = false

    var body: some View {
        Section {
            LabeledContent("Notifications") {
                HStack(spacing: 10) {
                    status
                        .foregroundStyle(Color.textSecondary)
                    action
                }
            }
            .task {
                // The user may have changed it in System Settings since.
                await notifications.refreshAuthorization()
            }
        } footer: {
            footer
                .font(Typography.eventTime)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: Text {
        if model.isDemo { return Text("Off in demo mode") }
        switch notifications.authorization {
        case .unknown: return Text("Checking…")
        case .notDetermined: return Text("Not turned on")
        case .denied: return Text("Off")
        case .authorized: return Text("On")
        }
    }

    @ViewBuilder private var action: some View {
        if !model.isDemo {
            switch notifications.authorization {
            case .notDetermined:
                Button("Turn On…") {
                    requestPermission()
                }
                .disabled(isRequesting)
                .accessibilityHint(Text("Asks macOS to let Ithil show alerts"))
            case .denied:
                Button("Open System Settings") {
                    notifications.openSystemSettings()
                }
            case .authorized:
                Button("Notification Settings…") {
                    notifications.openSystemSettings()
                }
                .accessibilityHint(Text("Opens Ithil in System Settings → Notifications"))
            case .unknown:
                EmptyView()
            }
        }
    }

    private var footer: Text {
        if model.isDemo {
            return Text("Demo mode never schedules notifications, so your real alerts stay as they are.")
        }
        switch notifications.authorization {
        case .notDetermined, .unknown:
            return Text(NotificationPermissionView.explanation)
        case .denied:
            return Text("Turn them on in System Settings → Notifications → Ithil.")
        case .authorized:
            return Text("Alerts arrive even when Ithil is closed. Their style and sound are set in System Settings.")
        }
    }

    private func requestPermission() {
        guard !isRequesting else { return }
        isRequesting = true
        Task {
            await notifications.requestAuthorization()
            isRequesting = false
        }
    }
}

/// The alert new events get: the presets, then None.
private struct DefaultAlertPicker: View {
    @Binding var alert: AlertOffset?

    var body: some View {
        Picker("Default alert", selection: $alert) {
            ForEach(AlertChoices.offered(including: alert), id: \.self) { offset in
                Text(EventFormatting.alert(offset))
                    .tag(AlertOffset?.some(offset))
            }
            Divider()
            Text(EventFormatting.alert(nil))
                .tag(AlertOffset?.none)
        }
    }
}

/// "System Default (Monday)", then the seven weekdays from the locale's first one.
private struct FirstWeekdayPicker: View {
    @Binding var weekday: Int?

    var body: some View {
        let systemDefault = Self.weekdayName(Calendar.autoupdatingCurrent.firstWeekday)
        Picker("First day of week", selection: $weekday) {
            Text("System Default (\(systemDefault))")
                .tag(Int?.none)
            Divider()
            ForEach(Self.weekdaysInLocaleOrder, id: \.self) { day in
                Text(Self.weekdayName(day))
                    .tag(Int?.some(day))
            }
        }
    }

    /// The seven Gregorian weekdays (1 = Sunday … 7 = Saturday), starting from the locale's first day.
    private static var weekdaysInLocaleOrder: [Int] {
        let first = Calendar.autoupdatingCurrent.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// "Monday", in the user's language.
    private static func weekdayName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .autoupdatingCurrent
        let symbols = calendar.standaloneWeekdaySymbols
        guard symbols.indices.contains(weekday - 1) else { return "" }
        return symbols[weekday - 1]
    }
}

/// Three thumbnail cards: Night, Dawn and Match System (split diagonally). The selected one has the amber
/// ring and a bold label.
private struct AppearanceChooser: View {
    @Binding var selection: AppearanceChoice

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                AppearanceCard(choice: choice, isSelected: selection == choice) {
                    selection = choice
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

private struct AppearanceCard: View {
    let choice: AppearanceChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearanceThumbnailCard(choice: choice)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: Metrics.Glow.selectionRing)
                                .padding(-3)
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 6)
                        }
                    }
                title
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.textPrimary : Color.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(traits)
    }

    private var title: Text {
        switch choice {
        case .night: return Text("Night")
        case .dawn: return Text("Dawn")
        case .system: return Text("Match System")
        }
    }

    private var traits: AccessibilityTraits {
        isSelected ? [.isSelected] : []
    }
}

/// A miniature Ithil window in Night, Dawn, or both split along the diagonal.
private struct AppearanceThumbnailCard: View {
    let choice: AppearanceChoice

    var body: some View {
        ZStack {
            switch choice {
            case .night:
                AppearanceThumbnail()
                    .environment(\.colorScheme, .dark)
            case .dawn:
                AppearanceThumbnail()
                    .environment(\.colorScheme, .light)
            case .system:
                AppearanceThumbnail()
                    .environment(\.colorScheme, .dark)
                AppearanceThumbnail()
                    .environment(\.colorScheme, .light)
                    .clipShape(LowerTrailingTriangle())
            }
        }
        .frame(width: 112, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.separatorLine, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// The window drawn with the theme's own tokens, so the environment's color scheme picks Night or Dawn:
/// sidebar with subject dots, hour lines, a few event blocks and the amber now line.
private struct AppearanceThumbnail: View {
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            grid
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Capsule()
                .fill(Color.textPrimary.opacity(0.55))
                .frame(width: 16, height: 3)
                .padding(.bottom, 2)
            dot(.subjectClay)
            dot(.subjectTeal)
            dot(.subjectIris)
            dot(.subjectFern)
        }
        .padding(7)
        .frame(width: 32)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.backgroundSidebar)
    }

    private var grid: some View {
        ZStack(alignment: .topLeading) {
            Color.backgroundWindow
            VStack(spacing: 11) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.separatorLine)
                        .frame(height: 1)
                }
            }
            .padding(.top, 6)
            HStack(alignment: .top, spacing: 4) {
                block(.subjectClay, height: 20)
                    .padding(.top, 14)
                block(.subjectTeal, height: 28)
                    .padding(.top, 6)
                block(.subjectIris, height: 16)
                    .padding(.top, 30)
                block(.subjectFern, height: 22)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 6)
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 1)
                .padding(.top, 42)
        }
    }

    private func dot(_ color: ColorResource) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(color))
                .frame(width: 4, height: 4)
            Capsule()
                .fill(Color.textSecondary.opacity(0.5))
                .frame(width: 10, height: 2)
        }
    }

    private func block(_ color: ColorResource, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color(color).opacity(0.3))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(color))
                    .frame(width: 1.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .frame(height: height)
    }
}

/// The lower-right half of a rectangle, cut along the diagonal from top right to bottom left.
private struct LowerTrailingTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
