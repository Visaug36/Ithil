import IthilCore
import SwiftUI

/// The main window once a library is open: sidebar, toolbar, search, and the calendar for the current
/// span (or search results while the search field has text).
///
/// - The sidebar collapses when Month opens, as in the design, and comes back as it was when the user
///   leaves Month.
/// - Choosing a search result shows the event in the calendar but keeps the query in the field; editing
///   the query or pressing Return in the field brings the results back, and clearing it ends the search.
struct CalendarWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// The sidebar's visibility before Month collapsed it, restored when leaving Month.
    @State private var visibilityBeforeMonth: NavigationSplitViewVisibility? = nil
    /// Set after choosing a search result, so the calendar is on screen while the query stays in the field.
    @State private var searchResultsDismissed = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CalendarSidebar()
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarWidth, ideal: Metrics.sidebarWidth, max: Metrics.sidebarWidth)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.backgroundWindow)
                .navigationTitle(EventFormatting.monthAndYear(model.selectedDate))
                .toolbar {
                    CalendarToolbar()
                }
                .modifier(CalendarToolbarBackground())
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search"))
        .onSubmit(of: .search) {
            searchResultsDismissed = false
        }
        .onChange(of: model.searchText) {
            searchResultsDismissed = false
        }
        .onChange(of: model.span) { oldSpan, newSpan in
            spanChanged(from: oldSpan, to: newSpan)
        }
        .onAppear {
            if model.span == .month {
                columnVisibility = .detailOnly
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if showsSearchResults {
            SearchResultsView {
                searchResultsDismissed = true
            }
        } else {
            switch model.span {
            case .day, .week:
                DayWeekView(days: model.visibleDays)
            case .month:
                MonthView(month: model.selectedDate)
            }
        }
    }

    private var showsSearchResults: Bool {
        guard !searchResultsDismissed else { return false }
        return !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func spanChanged(from oldSpan: CalendarSpan, to newSpan: CalendarSpan) {
        if newSpan == .month, oldSpan != .month {
            visibilityBeforeMonth = columnVisibility
            setColumnVisibility(.detailOnly)
        } else if oldSpan == .month, newSpan != .month {
            setColumnVisibility(visibilityBeforeMonth ?? .all)
            visibilityBeforeMonth = nil
        }
    }

    private func setColumnVisibility(_ visibility: NavigationSplitViewVisibility) {
        guard columnVisibility != visibility else { return }
        let animation: Animation? = reduceMotion ? nil : .default
        withAnimation(animation) {
            columnVisibility = visibility
        }
    }
}

/// Paints the window toolbar in `BackgroundWindow` before macOS 26; from macOS 26 the system's Liquid Glass
/// toolbar is left alone.
private struct CalendarToolbarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .toolbarBackground(Color.backgroundWindow, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        }
    }
}
