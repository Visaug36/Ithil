import SwiftUI

/// The background of Ithil's floating panels, which sit on top of other windows (the Quick Add panel):
/// `BackgroundRaised` in a rounded shape with a `SeparatorLine` hairline.
///
/// From macOS 26 the panel adopts Liquid Glass at its edge only. The shape gets a `.glassEffect`, and the
/// opaque `BackgroundRaised` fill (with the hairline along its edge) is inset by `glassRimWidth`, so the
/// glass, with its own lit edge, shows as a thin rim around the panel. Every word in the panel still sits on
/// the opaque token color, so the contrast measured in docs/DESIGN.md holds whatever is behind the panel;
/// nothing is ever read over a translucent backdrop. macOS 14 and 15 draw exactly what they drew before.
struct RaisedPanelBackground: ViewModifier {
    let cornerRadius: CGFloat

    /// How much of the glass shows around the opaque fill on macOS 26.
    static let glassRimWidth: CGFloat = 2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            let inner = shape.inset(by: Self.glassRimWidth)
            content
                .background(Color.backgroundRaised, in: inner)
                .overlay {
                    inner.strokeBorder(Color.separatorLine, lineWidth: 1)
                }
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(Color.backgroundRaised, in: shape)
                .overlay {
                    shape.strokeBorder(Color.separatorLine, lineWidth: 1)
                }
                .clipShape(shape)
        }
    }
}

extension View {
    /// Draws the view as one of Ithil's floating panels (see `RaisedPanelBackground`).
    func raisedPanelBackground(cornerRadius: CGFloat) -> some View {
        modifier(RaisedPanelBackground(cornerRadius: cornerRadius))
    }
}
