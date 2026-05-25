import SwiftUI

/// Carries the rendered `DropdownView` content height up the view tree so
/// the detached-window path can re-fit its `NSWindow` when the height
/// changes (issue #19). A single `GeometryReader` writes it, so `reduce`
/// just keeps the latest non-zero value. Mirrors `CameraTileHeightPreference`.
private struct DropdownContentHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

/// Measures the modified view's height and invokes `onChange` whenever it
/// changes. A VStack of fixed-size children overflows (rather than clips)
/// when its host window is too short, so the measured height is the true
/// intrinsic content height -- exactly what the detached window needs to
/// re-fit against.
private struct DropdownContentHeightReporter: ViewModifier {
    let onChange: @MainActor () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DropdownContentHeightPreference.self,
                        value: proxy.size.height
                    )
                }
            }
            .onPreferenceChange(DropdownContentHeightPreference.self) { _ in
                // Fire on the next main-actor tick so the re-fit runs after
                // the current SwiftUI update completes (no re-entrant
                // setFrame).
                Task { @MainActor in onChange() }
            }
    }
}

extension View {
    /// Reports this view's rendered height, invoking `onChange` on every
    /// height change. See `DropdownContentHeightReporter`.
    func reportingContentHeight(onChange: @escaping @MainActor () -> Void) -> some View {
        modifier(DropdownContentHeightReporter(onChange: onChange))
    }
}
