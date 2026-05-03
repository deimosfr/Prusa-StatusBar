import SwiftUI

/// Shared test-result tag used by both the printer connection test on the
/// Printer tab and the Buddy Camera test inside `BuddyCameraSection`. Keeps
/// the visual treatment (green check / red octagon) consistent without
/// duplicating the switch.
enum PrinterTestResult: Equatable {
    case success(String)
    case failure(String)
}

struct PrinterTestResultLabel: View {
    let result: PrinterTestResult

    var body: some View {
        switch result {
        case let .success(message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Palette.stateGreen)
                .font(.prusaCaption)
                .lineLimit(2)
        case let .failure(message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(Theme.Palette.stateRed)
                .font(.prusaCaption)
                .lineLimit(2)
        }
    }
}
