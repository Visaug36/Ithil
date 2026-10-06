import IthilCore
import SwiftUI

/// Phase 1 placeholder window: the real sidebar and calendar views arrive in Phase 2.
struct ContentView: View {
    private let time: any TimeSource = SystemTimeSource()

    var body: some View {
        NavigationSplitView {
            SidebarPlaceholder(today: time.now)
                .navigationSplitViewColumnWidth(Metrics.sidebarWidth)
        } detail: {
            EmptyStateView(
                illustration: .emptyDay,
                title: "A quiet day.",
                message: "Nothing planned. Press ⌘N to add something."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .starryBackground(.backgroundWindow)
        }
    }
}

private struct SidebarPlaceholder: View {
    let today: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(today, format: .dateTime.month(.wide))
                .font(Typography.sidebarMonth)
                .foregroundStyle(Color.textPrimary)
            Text(today, format: .dateTime.weekday(.wide).day())
                .font(Typography.secondary)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .starryBackground(.backgroundSidebar)
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 640)
}
