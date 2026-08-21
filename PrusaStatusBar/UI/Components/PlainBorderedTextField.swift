import AppKit
import SwiftUI

/// Public entry point. Picks between a regular and a secure
/// `NSTextField` based on `isSecure`. Wrapped in a SwiftUI structural
/// `if/else` (with distinct `.id()` per mode) so toggling `isSecure`
/// forces SwiftUI to rebuild the underlying NSView; without that,
/// `NSViewRepresentable.updateNSView` cannot swap an `NSTextField` for
/// an `NSSecureTextField` (or vice versa) and the eye toggle would be
/// a no-op.
struct PlainBorderedTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var monospaced: Bool = true

    var body: some View {
        if isSecure {
            PlainBorderedNSTextField(
                placeholder: placeholder,
                text: $text,
                isSecure: true,
                monospaced: monospaced
            )
            .id("secure")
        } else {
            PlainBorderedNSTextField(
                placeholder: placeholder,
                text: $text,
                isSecure: false,
                monospaced: monospaced
            )
            .id("plain")
        }
    }
}

/// `NSTextField`-backed text input. Wrapped via `NSViewRepresentable`
/// rather than SwiftUI's `TextField` because the SwiftUI version
/// honours the `NSTextField`'s growing `intrinsicContentSize`, which
/// made the field push its row sideways (and clip its own content)
/// whenever the user typed something longer than the visible width.
/// Here we explicitly set:
///
/// - `usesSingleLineMode = true` + scrollable cell so long content
///   scrolls horizontally inside the bezel instead of expanding it,
/// - low horizontal hugging + compression resistance so AppKit never
///   asks SwiftUI for more horizontal space than was offered.
struct PlainBorderedNSTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    let monospaced: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field: NSTextField = isSecure ? NSSecureTextField() : NSTextField()
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = false
        field.font = font
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.alignment = .left
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }

    func updateNSView(_ nsView: NSTextField, context _: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        if nsView.font != font {
            nsView.font = font
        }
    }

    private var font: NSFont {
        let size = NSFont.systemFontSize
        return monospaced
            ? .monospacedSystemFont(ofSize: size, weight: .regular)
            : .systemFont(ofSize: size)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
