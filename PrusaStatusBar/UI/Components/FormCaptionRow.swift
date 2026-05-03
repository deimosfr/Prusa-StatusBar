import SwiftUI

/// Plain secondary caption used as a `Section { } footer:` slot inside a
/// SwiftUI `Form`. Forces full-width left-aligned layout so help text
/// does not get clipped by the default centered-narrow-column footer
/// layout SwiftUI applies in some configurations.
struct FormFooterText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.prusaCaption)
            .foregroundStyle(Theme.Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
