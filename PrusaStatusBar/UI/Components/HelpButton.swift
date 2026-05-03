import SwiftUI

/// Slim variant of `HelpButton` for rows that already carry a fully-resolved
/// help string (e.g. one that interpolates min/max bounds). Renders the same
/// "?" glyph and popover styling but skips the localised-key indirection
/// and the "Learn more" link, since the body is the entire payload.
struct InlineHelpButton: View {
    let text: String

    @State private var isPresented: Bool = false

    init(body: String) {
        text = body
    }

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(L10n.t("common.help.tooltip"))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            Text(text)
                .font(.prusaBody)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Theme.Spacing.med)
                .frame(width: 280, alignment: .leading)
        }
    }
}

/// Classic macOS rounded "?" help button. Tapping it opens a popover with a
/// short localized explanation and a "Learn more" link to an external URL.
/// Sized to nestle inside the Printer-tab field-label column without
/// disturbing baseline alignment.
struct HelpButton: View {
    let bodyKey: String
    let learnMoreURL: URL

    @State private var isPresented: Bool = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(L10n.t("common.help.tooltip"))
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
                Text(L10n.t(bodyKey))
                    .font(.prusaBody)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Link(L10n.t("common.help.learn_more"), destination: learnMoreURL)
                    .font(.prusaCaption)
            }
            .padding(Theme.Spacing.med)
            .frame(width: 280, alignment: .leading)
        }
    }
}
