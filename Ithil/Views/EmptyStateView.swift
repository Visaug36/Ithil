import SwiftUI

/// Illustration, New York headline and an SF Pro secondary line, as in the design's empty states.
struct EmptyStateView: View {
    let illustration: ImageResource
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(illustration)
                .accessibilityHidden(true)
                .padding(.bottom, 10)
            Text(title)
                .font(Typography.emptyHeadline)
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(Typography.secondary)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    EmptyStateView(
        illustration: .emptyDay,
        title: "A quiet day.",
        message: "Nothing planned. Press ⌘N to add something."
    )
    .frame(width: 320, height: 280)
    .starryBackground(.backgroundWindow)
}
