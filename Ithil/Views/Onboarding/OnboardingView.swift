import SwiftUI

/// First-launch onboarding: three short pages on the starry window background, each with the app icon
/// and a New York headline, and step dots along the bottom.
///
/// 1. **Welcome**: what Ithil is, in one line and three points.
/// 2. **Choose folder**: the same actions as `ChooseFolderView` (`ChooseFolderActions`). Choosing a folder
///    opens the library, so `MainView` moves on by itself: the library state leaves `.needsFolder`.
/// 3. **Notifications**: `NotificationPermissionView`, then "Continue" (or "Skip"). Finishing sets
///    `AppSettings.hasCompletedOnboarding` and calls `onFinish`.
///
/// `MainView` shows steps 1–2 while the state is `.needsFolder` and step 3 once it is `.ready`, until
/// onboarding is done. `-demo` never shows it. With Reduce Motion on, pages cross-fade instead of sliding.
struct OnboardingView: View {
    /// The pages, in order.
    enum Step: Int, CaseIterable, Hashable, Sendable {
        case welcome
        case chooseFolder
        case notifications

        /// 1-based, for "Step 2 of 3".
        var number: Int {
            rawValue + 1
        }
    }

    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step
    @State private var isGoingBack = false
    private let onFinish: () -> Void

    /// - Parameters:
    ///   - startAt: the first page shown. `.welcome` starts at `.chooseFolder` instead once the welcome
    ///     page was passed in this run of the app, so a folder that couldn't be used (the state goes from
    ///     `.loading` back to `.needsFolder`, which makes a new `OnboardingView`) doesn't start over.
    ///   - onFinish: called after the last page, once `hasCompletedOnboarding` is set.
    init(startAt: Step, onFinish: @escaping () -> Void = {}) {
        let first = startAt == .welcome && OnboardingMemory.hasPassedWelcome ? Step.chooseFolder : startAt
        _step = State(initialValue: first)
        self.onFinish = onFinish
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                ZStack {
                    page
                        .id(step)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OnboardingFooter(step: step, onBack: backAction)
        }
        .starryBackground(.backgroundWindow)
        .toolbarBackground(.hidden, for: .windowToolbar)
    }

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            WelcomeStep {
                OnboardingMemory.hasPassedWelcome = true
                go(to: .chooseFolder)
            }
        case .chooseFolder:
            ChooseFolderStep()
        case .notifications:
            NotificationsStep {
                finish()
            }
        }
    }

    /// "Back" on the folder page only: the welcome page has nothing before it, and once a folder is chosen
    /// the calendar is open.
    private var backAction: (() -> Void)? {
        guard step == .chooseFolder else { return nil }
        return {
            go(to: .welcome)
        }
    }

    /// Slides in from the side it comes from, over a fade of the page it replaces; only a cross-fade with
    /// Reduce Motion on. (The removal is a plain fade, so it never depends on the direction.)
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let insertion = AnyTransition.offset(x: isGoingBack ? -40 : 40).combined(with: .opacity)
        return .asymmetric(insertion: insertion, removal: .opacity)
    }

    private func go(to newStep: Step) {
        isGoingBack = newStep.rawValue < step.rawValue
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.15) : .easeOut(duration: 0.25)
        withAnimation(animation) {
            step = newStep
        }
    }

    private func finish() {
        settings.hasCompletedOnboarding = true
        onFinish()
    }
}

/// Remembers, for this run of the app, that the welcome page was passed. See `OnboardingView.init`.
@MainActor
private enum OnboardingMemory {
    static var hasPassedWelcome = false
}

/// The step dots, centered, with "Back" on the leading side where going back makes sense. (Back comes first
/// so VoiceOver reads it first, as it appears.)
private struct OnboardingFooter: View {
    let step: OnboardingView.Step
    let onBack: (() -> Void)?

    var body: some View {
        ZStack {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .font(Typography.body)
                .foregroundStyle(Color.accentText)
                .accessibilityHint(Text("Goes back to the welcome page"))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            OnboardingStepDots(current: step)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }
}

/// Three small dots, the current one amber. VoiceOver reads "Step 2 of 3".
private struct OnboardingStepDots: View {
    let current: OnboardingView.Step
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingView.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(step == current ? Color.accentColor : inactiveColor)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(current.number) of \(OnboardingView.Step.allCases.count)"))
    }

    private var inactiveColor: Color {
        contrast == .increased ? Color.textSecondary : Color.textTertiary.opacity(0.55)
    }
}

#Preview("Welcome") {
    OnboardingView(startAt: .welcome)
        .environment(AppModel.preview)
        .environment(AppSettings.preview)
        .environment(NotificationsController.preview)
        .frame(width: 900, height: 620)
}

#Preview("Notifications") {
    OnboardingView(startAt: .notifications)
        .environment(AppModel.preview)
        .environment(AppSettings.preview)
        .environment(NotificationsController.preview)
        .frame(width: 900, height: 620)
}
