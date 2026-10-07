import AppKit
import IthilCore
import SwiftUI

/// General: appearance (Night, Dawn, Match System), the default alert for new events, the first day of
/// the week, the Quick Add shortcut, launch at login, the menu bar extra, and whether macOS lets Ithil
/// show notifications.
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
            QuickAddShortcutSection()
            StartupSettingsSection()
            NotificationSettingsSection()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundWindow)
        .frame(height: 620)
    }
}

/// "Quick Add shortcut": the recorder and Reset, with a footnote that says what the shortcut does, guides
/// while recording, or warns when another app has the shortcut.
private struct QuickAddShortcutSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var isRecording = false

    private var hotKeys: QuickAddHotKeyController { .shared }

    var body: some View {
        @Bindable var settings = settings
        Section {
            LabeledContent("Quick Add shortcut") {
                HStack(spacing: 8) {
                    HotKeyRecorder(Text("Quick Add shortcut"), combo: $settings.quickAddHotKey) { recording in
                        recordingChanged(recording)
                    }
                    Button("Reset") {
                        settings.quickAddHotKey = .optionSpace
                    }
                    .disabled(isRecording || settings.quickAddHotKey == .optionSpace)
                    .accessibilityLabel(Text("Reset Quick Add Shortcut"))
                    .accessibilityHint(Text("Sets the shortcut back to ⌥Space"))
                }
            }
        } footer: {
            footer
                .font(Typography.eventTime)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var footer: some View {
        if isRecording {
            Text("Press the new keys, with ⌘, ⌥ or ⌃ but not a menu shortcut. Esc cancels; ⌫ turns it off.")
        } else if settings.quickAddHotKey == nil {
            Text("Quick Add has no shortcut. While Ithil is in front, ⌘N still opens it.")
        } else if hotKeys.status == .unavailable {
            Label {
                Text("Another app is using this shortcut. Choose a different one.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            }
            .foregroundStyle(Color.textSecondary)
        } else {
            Text("Opens Quick Add from any app.")
        }
    }

    /// While recording, the global shortcut steps aside so the current one can be typed again.
    private func recordingChanged(_ recording: Bool) {
        isRecording = recording
        if recording {
            hotKeys.suspend()
        } else {
            hotKeys.resume()
        }
    }
}

/// "Launch at login" and "Show in menu bar", as amber switches. Launch at login reads what macOS says
/// whenever Settings appears or Ithil becomes active, because it can also be changed in System Settings.
private struct StartupSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var launchStatus = LaunchAtLogin.Status.off
    @State private var launchesAtLogin = false
    @State private var launchChangeFailed = false

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Launch at login", isOn: $launchesAtLogin)
                .toggleStyle(.switch)
                .tint(Color.accentColor)
                .disabled(model.isDemo)
                .onChange(of: launchesAtLogin) { _, wanted in
                    changeLaunchAtLogin(to: wanted)
                }
                .onAppear {
                    refreshLaunchStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    refreshLaunchStatus()
                }
            if launchStatus == .requiresApproval, !model.isDemo {
                LoginItemApprovalRow()
            }
            Toggle("Show in menu bar", isOn: $settings.showsMenuBarExtra)
                .toggleStyle(.switch)
                .tint(Color.accentColor)
        } footer: {
            footer
                .font(Typography.eventTime)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: Text {
        if model.isDemo {
            return Text("Demo mode never changes your login items.")
        }
        if launchChangeFailed {
            return Text("macOS didn't allow that. Add Ithil in System Settings → General → Login Items.")
        }
        return Text("The moon in the menu bar shows what's next and opens Quick Add.")
    }

    private func refreshLaunchStatus() {
        launchStatus = LaunchAtLogin.status
        launchesAtLogin = launchStatus != .off
    }

    /// Also runs when `refreshLaunchStatus` updates the switch, so it acts only on a real change.
    private func changeLaunchAtLogin(to wanted: Bool) {
        guard !model.isDemo, wanted != (launchStatus != .off) else { return }
        do {
            try LaunchAtLogin.set(wanted)
            launchChangeFailed = false
        } catch {
            launchChangeFailed = true
        }
        refreshLaunchStatus()
    }
}

/// Shown when Ithil is registered to open at login but switched off in System Settings.
private struct LoginItemApprovalRow: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Switched off in System Settings → General → Login Items.")
                Text("Ithil opens at login once you switch it on there.")
            }
            .font(Typography.secondary)
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("Open Login Items…") {
                LaunchAtLogin.openLoginItemsSettings()
            }
            .accessibilityHint(Text("Opens System Settings → General → Login Items"))
        }
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
