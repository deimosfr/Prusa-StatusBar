import SwiftUI

/// Surface treatment for the popover's content blocks: rounded-rect material
/// background with a hairline stroke. Use via `.prusaCard()`.
public struct PrusaCardModifier: ViewModifier {
    public var padding: CGFloat = Theme.Layout.cardPadding

    public func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Theme.Palette.surfaceElevated,
                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
            )
    }
}

public extension View {
    func prusaCard(padding: CGFloat = Theme.Layout.cardPadding) -> some View {
        modifier(PrusaCardModifier(padding: padding))
    }
}
