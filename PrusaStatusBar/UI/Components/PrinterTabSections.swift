import SwiftUI

/// Width reserved for the leading icon-and-label column in every Connection
/// row. Hand-tuned to fit the longest currently-shipped localized label
/// (Czech "Zobrazované jméno") with icon, so all rows line up against the
/// trailing fields while leaving the fields enough room (the UUID needs 36
/// chars).
let connectionLabelWidth: CGFloat = 160

/// Trailing slot reserved on every "field + inline action" row so all
/// `TextField`s end at the same trailing X. Display-name row reserves
/// this width as an invisible spacer in lieu of a button.
let connectionTestButtonReservedWidth: CGFloat = 28

/// Fixed width on every Connection-section `TextField`. Prevents the
/// `.roundedBorder` field from growing leftwards with content under
/// trailing alignment. Sized for the 520pt Preferences window.
let connectionFieldWidth: CGFloat = 240

/// Body-key + external URL pair for the inline help popover shown in the
/// label column of a Printer-tab row. Nil means no `?` button is rendered
/// (e.g. the fallback URL row reuses the primary URL guidance).
struct PrinterHelpInfo {
    let bodyKey: String
    let learnMoreURL: URL
}

/// Hard-coded Prusa help-article URLs surfaced through the Printer-tab
/// help popovers. Not localized: article slugs are stable and the
/// help.prusa3d.com pages auto-detect language.
enum PrinterHelpLinks {
    private static let articleBase = "https://help.prusa3d.com/article/"

    // swiftlint:disable force_unwrapping
    // String literals are static and well-formed URLs; force-unwrap is safe.
    static let url = URL(string: articleBase + "prusa-connect-and-prusalink-explained_302608")!
    static let apiKey = URL(
        string: articleBase + "prusalink-troubleshooting_304411#original-prusa-i3-mk3-s-mk25-s"
    )!
    static let camera = URL(string: articleBase + "buddy3d-camera_821264")!
    static let uuid = URL(string: "https://help.prusa3d.com/fr/product/prusa-connect")!
    // swiftlint:enable force_unwrapping
}

/// Renders the standard Printer-tab label cell: an SF-symbol-prefixed
/// `Label` followed by an optional inline `?` help button at the trailing
/// edge. Used by every row that participates in the connection grid so
/// the `?` lines up with the rest of the column.
struct ConnectionLabelCell: View {
    let title: String
    let systemImage: String
    let helpInfo: PrinterHelpInfo?

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Label(title, systemImage: systemImage)
            if let helpInfo {
                HelpButton(bodyKey: helpInfo.bodyKey, learnMoreURL: helpInfo.learnMoreURL)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Vertically centers a labeled row by laying it out as an explicit
/// HStack. The default `LabeledContent` style baseline-aligns the label
/// to the field's first text baseline, which on the Printer tab leaves
/// the label visibly higher than the rounded-border field. An explicit
/// `.center` HStack and a fixed-width label column gives a stable,
/// premium-looking grid.
struct ConnectionRow<Label: View, Content: View>: View {
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.med) {
            label()
                .lineLimit(1)
                .frame(width: connectionLabelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

struct PrinterURLRow: View {
    @Binding var url: String
    @Binding var fallbackURL: String
    @Binding var isFallbackExpanded: Bool
    let isPrimaryTesting: Bool
    let isFallbackTesting: Bool
    let isPrimaryTestDisabled: Bool
    let isFallbackTestDisabled: Bool
    let primaryTestResult: PrinterTestResult?
    let fallbackTestResult: PrinterTestResult?
    let onTestPrimary: () -> Void
    let onTestFallback: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            URLTestableRow(
                label: L10n.t("printer.field.url"),
                systemImage: "cable.connector",
                placeholder: "http://core-one.local",
                url: $url,
                isTesting: isPrimaryTesting,
                isTestDisabled: isPrimaryTestDisabled,
                result: primaryTestResult,
                onTest: onTestPrimary,
                helpInfo: PrinterHelpInfo(
                    bodyKey: "printer.help.url.body",
                    learnMoreURL: PrinterHelpLinks.url
                )
            )
            Button {
                isFallbackExpanded.toggle()
            } label: {
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(isFallbackExpanded ? 90 : 0))
                    Text(
                        fallbackURL.isEmpty
                            ? L10n.t("printer.field.fallback_url.add")
                            : L10n.t("printer.field.fallback_url.label")
                    )
                    .font(.prusaCaption)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.Palette.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: isFallbackExpanded)
            if isFallbackExpanded {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    URLTestableRow(
                        label: L10n.t("printer.field.fallback_url"),
                        systemImage: "wifi",
                        placeholder: "http://printer.vpn",
                        url: $fallbackURL,
                        isTesting: isFallbackTesting,
                        isTestDisabled: isFallbackTestDisabled,
                        result: fallbackTestResult,
                        onTest: onTestFallback,
                        helpInfo: nil
                    )
                    Text(L10n.t("printer.fallback_url.footer"))
                        .font(.prusaCaption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.asymmetric(
                    insertion: .opacity.animation(.easeInOut(duration: 0.2)),
                    removal: .identity
                ))
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: isFallbackExpanded)
    }
}

/// Single URL row with an inline "Test" icon button at the trailing edge
/// and an animated result chip rendered just below the field. The chip
/// is owned by the row so each URL has its own self-contained
/// "type → test → see result" loop without touching the bottom Save row.
private struct URLTestableRow: View {
    let label: String
    let systemImage: String
    let placeholder: String
    @Binding var url: String
    let isTesting: Bool
    let isTestDisabled: Bool
    let result: PrinterTestResult?
    let onTest: () -> Void
    let helpInfo: PrinterHelpInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ConnectionRow {
                ConnectionLabelCell(title: label, systemImage: systemImage, helpInfo: helpInfo)
            } content: {
                HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                    TextField("", text: $url, prompt: Text(placeholder))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textContentType(.URL)
                        .font(.prusaBody)
                        .lineLimit(1)
                        .frame(width: connectionFieldWidth)
                    Button(action: onTest) {
                        Group {
                            if isTesting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                        }
                        .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(width: connectionTestButtonReservedWidth)
                    .disabled(isTestDisabled || isTesting)
                    .help(L10n.t("printer.url.test_help"))
                }
            }
            if let result {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PrinterTestResultLabel(result: result)
                }
                .padding(.leading, connectionLabelWidth + Theme.Spacing.med)
                .transition(
                    .opacity.combined(with: .move(edge: .top))
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: result)
        .animation(.easeInOut(duration: 0.15), value: isTesting)
    }
}

struct PrinterApiKeyRow: View {
    @Binding var apiKey: String
    @Binding var isApiKeyVisible: Bool

    var body: some View {
        ConnectionRow {
            ConnectionLabelCell(
                title: L10n.t("printer.field.api_key"),
                systemImage: "key.fill",
                helpInfo: PrinterHelpInfo(
                    bodyKey: "printer.help.api_key.body",
                    learnMoreURL: PrinterHelpLinks.apiKey
                )
            )
        } content: {
            HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                // SecureField is always laid out and drives the row's
                // measured width. TextField overlays it only when visible,
                // matching the SecureField frame exactly so toggling never
                // resizes the box; we just swap which control the user sees.
                // SecureField/TextField with .roundedBorder size to their
                // intrinsic content (character count x glyph width), and
                // .frame(maxWidth: .infinity) alone is not enough to force
                // them to fill. A non-trivial minWidth pushes both controls
                // past the per-content intrinsic so toggling visibility
                // never changes the rendered box width.
                ZStack {
                    SecureField("", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .opacity(isApiKeyVisible ? 0 : 1)
                        .allowsHitTesting(!isApiKeyVisible)
                    TextField("", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .opacity(isApiKeyVisible ? 1 : 0)
                        .allowsHitTesting(isApiKeyVisible)
                }
                .font(.prusaBody)
                .frame(width: connectionFieldWidth)
                Button {
                    isApiKeyVisible.toggle()
                } label: {
                    Image(systemName: isApiKeyVisible ? "eye.slash" : "eye")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: connectionTestButtonReservedWidth)
                .help(isApiKeyVisible ? L10n.t("printer.api_key.hide") : L10n.t("printer.api_key.show"))
            }
        }
    }
}

/// Optional display-name override row. The placeholder mirrors the live
/// API-reported printer name so the user can see the value that will be
/// used if they leave the field blank. Empty input is normalised to nil
/// at save time by `UserPreferences.printerNameOverride`.
struct PrinterDisplayNameRow: View {
    @Binding var nameOverride: String
    let placeholder: String

    var body: some View {
        ConnectionRow {
            Label(L10n.t("printer.field.display_name"), systemImage: "tag")
        } content: {
            HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                TextField("", text: $nameOverride, prompt: Text(placeholder))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(.prusaBody)
                    .lineLimit(1)
                    .frame(width: connectionFieldWidth)
                    .onChange(of: nameOverride) { _, newValue in
                        let cap = AppModel.printerDisplayNameMaxLength
                        if newValue.count > cap {
                            nameOverride = String(newValue.prefix(cap))
                        }
                    }
                // Invisible spacer mirrors the URL row's trailing "Test"
                // button slot so the Display-name field aligns with it.
                Color.clear
                    .frame(width: connectionTestButtonReservedWidth, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// PrusaConnect UUID input row + inline validation error. Bare rows (not a
/// `Section`) so the caller can place it inside an existing Form Section
/// and pair it with sibling controls (e.g. the Show-PrusaLink-button toggle
/// in the Menu Content tab).
struct PrusaConnectUUIDRow: View {
    @Binding var prusaConnectUUID: String
    let uuidError: String?

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.med) {
            HStack(spacing: Theme.Spacing.xxs) {
                Label(L10n.t("printer.connect_uuid.field_label"), systemImage: "globe")
                    .lineLimit(1)
                HelpButton(
                    bodyKey: "content.web_links.uuid.help",
                    learnMoreURL: PrinterHelpLinks.uuid
                )
            }
            Spacer(minLength: 0)
            TextField(
                "",
                text: $prusaConnectUUID,
                prompt: Text("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx")
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
            .font(.prusaBody)
            .frame(width: 320)
        }
        if let uuidError {
            Text(uuidError)
                .font(.prusaCaption)
                .foregroundStyle(Theme.Palette.stateRed)
        }
    }
}

/// Top "Security" section: a single Toggle bound to
/// `useKeychainForApiKey`, plus the consequence caption. The migration is
/// the parent's responsibility (see `PrinterTab.applyKeychainToggle`).
struct PrinterSecuritySection: View {
    @Binding var useKeychain: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Section {
            Toggle(L10n.t("printer.keychain.label"), isOn: $useKeychain)
                .onChange(of: useKeychain) { _, newValue in onChange(newValue) }
        } header: {
            Text(L10n.t("printer.security.header"))
        } footer: {
            FormFooterText(L10n.t("printer.security.footer"))
        }
    }
}
