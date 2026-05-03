import SwiftUI

/// "Notifications are off" hint shown beneath the Connection section when
/// the user has disabled them in the General tab. Kept here so the parent
/// view stays slim.
struct PrinterNotificationHintSection: View {
    var body: some View {
        Section {
            Label {
                Text(L10n.t("printer.notification_hint"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            } icon: {
                Image(systemName: "bell.slash")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.Palette.stateAmber)
            }
        }
    }
}
