import SwiftUI

struct AboutTab: View {
    @Bindable var model: AppModel
    let services: AppServices

    @State private var isShowingDiagnostics = false

    var body: some View {
        VStack(spacing: Theme.Spacing.lrg) {
            Spacer(minLength: Theme.Spacing.lrg)

            Image("AboutAppIcon")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)

            VStack(spacing: 4) {
                Text("Prusa StatusBar")
                    .font(.system(size: 20, weight: .semibold))
                Text(versionString)
                    .font(.prusaCaption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }

            if let bmcURL = URL(string: "https://buymeacoffee.com/deimosfr") {
                Link(destination: bmcURL) {
                    HStack(spacing: 6) {
                        Text("☕")
                            .font(.system(size: 14))
                        Text(L10n.t("about.coffee_link"))
                            .font(.custom("Cookie", size: 18))
                            .foregroundStyle(Color.black)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.980, green: 0.408, blue: 0.180))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help(L10n.t("about.coffee_help"))
            }

            HStack(spacing: 6) {
                if let repoURL = URL(string: "https://github.com/deimosfr/Prusa-StatusBar") {
                    Link(L10n.t("about.source_link"), destination: repoURL)
                        .font(.prusaCaption)
                }
                Text("·")
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                if let issuesURL = URL(string: "https://github.com/deimosfr/Prusa-StatusBar/issues") {
                    Link(L10n.t("about.issues_link"), destination: issuesURL)
                        .font(.prusaCaption)
                }
            }

            Button {
                isShowingDiagnostics = true
            } label: {
                Label(L10n.t("about.diagnostics.title"), systemImage: "stethoscope")
            }

            Spacer()

            VStack(spacing: 4) {
                Text(L10n.t("about.go2rtc_credit"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                if let vlckitURL = URL(string: "https://code.videolan.org/videolan/VLCKit") {
                    Link("code.videolan.org/videolan/VLCKit", destination: vlckitURL)
                        .font(.prusaCaption)
                }
            }

            VStack(spacing: 4) {
                Text(L10n.t("about.community_notice"))
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .multilineTextAlignment(.center)

                Text("© 2026 Pierre Mavro")
                    .font(.prusaCaption)
                    .foregroundStyle(Theme.Palette.textTertiary)
            }
            .padding(.bottom, Theme.Spacing.lrg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .sheet(isPresented: $isShowingDiagnostics) {
            SupportDiagnosticsSheet(model: model, services: services) {
                isShowingDiagnostics = false
            }
        }
    }

    private var versionString: String {
        let version = AppVersion.shortString ?? "?"
        let build = AppVersion.buildNumber ?? "?"
        return String(format: L10n.t("about.version"), version, build)
    }
}
