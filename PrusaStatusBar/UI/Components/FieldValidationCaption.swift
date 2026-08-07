import SwiftUI

/// Per-field syntactic validation state surfaced by `PrinterTab`. Drives
/// the inline caption and gates each row's Test icon.
enum FieldValidationState: Equatable {
    case empty
    case valid
    case invalid(String)

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
}

/// Single-line caption rendered under every Printer-tab text field that has
/// an inline Test icon. Composes a colored validity prefix (green "Valid
/// URL" / red reason) with the always-visible gray connectivity hint, joined
/// by " - ". Empty field collapses to just the hint.
struct FieldValidationCaption: View {
    let state: FieldValidationState
    let validLabel: String
    let hint: String

    init(
        state: FieldValidationState,
        validLabel: String = L10n.t("printer.field.validation.valid"),
        hint: String = L10n.t("printer.field.validation.click_to_test")
    ) {
        self.state = state
        self.validLabel = validLabel
        self.hint = hint
    }

    var body: some View {
        composedLine
            .font(.prusaCaption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var composedLine: Text {
        let hintText = Text(hint).foregroundColor(Theme.Palette.textSecondary)
        switch state {
        case .empty:
            return hintText
        case .valid:
            return Text(validLabel).foregroundColor(Theme.Palette.stateGreen)
                + Text(" - ").foregroundColor(Theme.Palette.textSecondary)
                + hintText
        case let .invalid(message):
            return Text(message).foregroundColor(Theme.Palette.stateRed)
                + Text(" - ").foregroundColor(Theme.Palette.textSecondary)
                + hintText
        }
    }
}
