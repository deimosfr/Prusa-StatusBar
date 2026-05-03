import SwiftUI

/// Reusable `.alert` modifier driving a Keychain-storage confirmation prompt.
///
/// The flow:
/// 1. The hosting view stores the desired toggle value in a `Bool?` state
///    (nil = no dialog).
/// 2. `keychainConfirmationAlert` observes that flag and surfaces an `.alert`
///    with direction-specific title / body / buttons.
/// 3. Confirm fires `onConfirm` (which performs the migration); cancel fires
///    `onCancel` (which reverts the local toggle mirror so it snaps back).
extension View {
    func keychainConfirmationAlert(
        pending: Binding<Bool?>,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        modifier(KeychainConfirmationAlert(pending: pending, onConfirm: onConfirm, onCancel: onCancel))
    }
}

private struct KeychainConfirmationAlert: ViewModifier {
    @Binding var pending: Bool?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: presentationBinding,
            presenting: pending
        ) { enabled in
            if enabled {
                Button(L10n.t("printer.keychain.confirm_enable.button")) { onConfirm() }
            } else {
                Button(L10n.t("printer.keychain.confirm_disable.button"), role: .destructive) {
                    onConfirm()
                }
            }
            Button(L10n.t("common.cancel"), role: .cancel) { onCancel() }
        } message: { enabled in
            Text(enabled
                ? L10n.t("printer.keychain.confirm_enable.body")
                : L10n.t("printer.keychain.confirm_disable.body"))
        }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { pending != nil },
            set: { isPresented in
                if !isPresented, pending != nil {
                    onCancel()
                }
            }
        )
    }

    private var title: String {
        switch pending {
        case true?: L10n.t("printer.keychain.confirm_enable.title")
        case false?: L10n.t("printer.keychain.confirm_disable.title")
        case nil: ""
        }
    }
}
