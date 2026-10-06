import SwiftUI

/// The static star-field tile. Stars appear only in the sidebar, title areas and empty states,
/// never behind the calendar grid, and they never animate.
struct StarField: View {
    var body: some View {
        Image(.starField)
            .resizable(resizingMode: .tile)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Fills the background with `color` and lays the star field over it.
    func starryBackground(_ color: Color) -> some View {
        background {
            ZStack {
                color
                StarField()
            }
            .ignoresSafeArea()
        }
    }
}
