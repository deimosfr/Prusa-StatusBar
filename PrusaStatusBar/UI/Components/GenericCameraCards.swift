import SwiftUI

/// Sources card: Stream URL + Still Image URL inputs. Each row renders
/// an inline "Test" button at the trailing edge with its own result
/// chip rendered just below, mirroring the PrusaLink URL row pattern
/// in `URLTestableRow`.
struct GenericCameraSourcesCard: View {
    @Binding var streamURL: String
    @Binding var stillImageURL: String
    let streamValidation: FieldValidationState
    let stillValidation: FieldValidationState
    let isStreamTesting: Bool
    let isStillTesting: Bool
    let streamTestResult: PrinterTestResult?
    let stillTestResult: PrinterTestResult?
    let onTestStream: () -> Void
    let onTestStill: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            GenericCameraURLRow(
                label: L10n.t("printer.generic_camera.stream_url.label"),
                systemImage: "antenna.radiowaves.left.and.right",
                placeholder: "rtsp://192.168.1.50:554/stream1",
                text: $streamURL,
                validation: streamValidation,
                isTesting: isStreamTesting,
                isTestDisabled: !streamValidation.isValid,
                testResult: streamTestResult,
                onTest: onTestStream
            )
            GenericCameraURLRow(
                label: L10n.t("printer.generic_camera.still_url.label"),
                systemImage: "photo",
                placeholder: "https://cam.local/snapshot.jpg",
                text: $stillImageURL,
                validation: stillValidation,
                isTesting: isStillTesting,
                isTestDisabled: !stillValidation.isValid,
                testResult: stillTestResult,
                onTest: onTestStill
            )
        }
    }
}

/// Authentication card: segmented mode picker + animated reveal of
/// username and password rows when mode is not `.none`.
struct GenericCameraAuthCard: View {
    @Binding var authMode: GenericCameraAuthMode
    @Binding var username: String
    @Binding var password: String
    @Binding var isPasswordVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            ConnectionRow {
                Label(L10n.t("printer.generic_camera.auth_mode.label"), systemImage: "lock.shield")
            } content: {
                Picker("", selection: $authMode) {
                    Text(L10n.t("printer.generic_camera.auth_mode.none")).tag(GenericCameraAuthMode.none)
                    Text(L10n.t("printer.generic_camera.auth_mode.basic")).tag(GenericCameraAuthMode.basic)
                    Text(L10n.t("printer.generic_camera.auth_mode.digest")).tag(GenericCameraAuthMode.digest)
                }
                .pickerStyle(.segmented)
                .frame(width: connectionFieldWidth + connectionTestButtonReservedWidth + Theme.Spacing.sml)
                .labelsHidden()
            }
            if authMode != .none {
                GenericCameraUsernameRow(username: $username)
                GenericCameraPasswordRow(password: $password, isPasswordVisible: $isPasswordVisible)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

/// Stream options card: RTSP transport picker (visible only when stream
/// URL parses as RTSP) and a Stepper for frame rate.
struct GenericCameraStreamOptionsCard: View {
    @Binding var rtspTransport: GenericCameraRTSPTransport
    @Binding var framerate: Int
    let streamIsRTSP: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            if streamIsRTSP {
                ConnectionRow {
                    Label(L10n.t("printer.generic_camera.transport.label"), systemImage: "arrow.left.arrow.right")
                } content: {
                    Picker("", selection: $rtspTransport) {
                        Text("TCP").tag(GenericCameraRTSPTransport.tcp)
                        Text("UDP").tag(GenericCameraRTSPTransport.udp)
                        Text("UDP multicast").tag(GenericCameraRTSPTransport.udpMulticast)
                        Text("HTTP").tag(GenericCameraRTSPTransport.http)
                    }
                    .pickerStyle(.menu)
                    .frame(width: connectionFieldWidth)
                    .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ConnectionRow {
                Label(L10n.t("printer.generic_camera.framerate.label"), systemImage: "speedometer")
            } content: {
                HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                    Stepper(
                        value: $framerate,
                        in: UserPreferences.genericCameraFramerateMin ... UserPreferences.genericCameraFramerateMax
                    ) {
                        Text(String(format: L10n.t("printer.generic_camera.framerate.value"), framerate))
                            .font(.prusaBody)
                            .monospacedDigit()
                    }
                    .frame(width: connectionFieldWidth, alignment: .leading)
                    Color.clear
                        .frame(width: connectionTestButtonReservedWidth, height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Security card: Verify SSL toggle + Content-Type free-text field.
/// Last in the column so power-user knobs do not crowd the common path.
struct GenericCameraSecurityCard: View {
    @Binding var verifySSL: Bool
    @Binding var contentType: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            Toggle(isOn: $verifySSL) {
                Label(L10n.t("printer.generic_camera.verify_ssl.label"), systemImage: "lock.shield.fill")
            }
            ConnectionRow {
                Label(L10n.t("printer.generic_camera.content_type.label"), systemImage: "doc.text")
            } content: {
                HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                    TextField(
                        "",
                        text: $contentType,
                        prompt: Text(UserPreferences.genericCameraContentTypeDefault)
                    )
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(.prusaBody)
                    .lineLimit(1)
                    .frame(width: connectionFieldWidth)
                    Color.clear
                        .frame(width: connectionTestButtonReservedWidth, height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Single labelled URL field with an inline "Test" icon button at the
/// trailing edge, an animated test-result chip rendered beneath, and an
/// inline validation error caption. Used by `GenericCameraSourcesCard`
/// for both the Stream and Still URL rows.
struct GenericCameraURLRow: View {
    let label: String
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let validation: FieldValidationState
    let isTesting: Bool
    let isTestDisabled: Bool
    let testResult: PrinterTestResult?
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ConnectionRow {
                Label(label, systemImage: systemImage)
            } content: {
                HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                    TextField("", text: $text, prompt: Text(placeholder))
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
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                FieldValidationCaption(state: validation)
                    .frame(width: captionWidth, alignment: .leading)
            }
            if let testResult {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    PrinterTestResultLabel(result: testResult)
                }
                .padding(.leading, connectionLabelWidth + Theme.Spacing.med)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: testResult)
        .animation(.easeInOut(duration: 0.15), value: isTesting)
    }
}

/// Username row inside `GenericCameraAuthCard`. Plain TextField with a
/// `.username` content-type hint so password managers do not autofill the
/// field with a saved password by mistake.
struct GenericCameraUsernameRow: View {
    @Binding var username: String

    var body: some View {
        ConnectionRow {
            Label(L10n.t("printer.generic_camera.username.label"), systemImage: "person")
        } content: {
            HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                TextField("", text: $username, prompt: Text(L10n.t("printer.generic_camera.username.placeholder")))
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .font(.prusaBody)
                    .lineLimit(1)
                    .frame(width: connectionFieldWidth)
                Color.clear
                    .frame(width: connectionTestButtonReservedWidth, height: 1)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Password row inside `GenericCameraAuthCard`. SecureField with the
/// reveal-toggle pattern shared with `PrinterApiKeyRow`: ZStack of
/// SecureField and TextField sized to the same width so flipping the
/// visibility never resizes the row.
struct GenericCameraPasswordRow: View {
    @Binding var password: String
    @Binding var isPasswordVisible: Bool

    var body: some View {
        ConnectionRow {
            Label(L10n.t("printer.generic_camera.password.label"), systemImage: "key")
        } content: {
            HStack(alignment: .center, spacing: Theme.Spacing.sml) {
                ZStack {
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .opacity(isPasswordVisible ? 0 : 1)
                        .allowsHitTesting(!isPasswordVisible)
                    TextField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .opacity(isPasswordVisible ? 1 : 0)
                        .allowsHitTesting(isPasswordVisible)
                }
                .font(.prusaBody)
                .frame(width: connectionFieldWidth)
                Button {
                    isPasswordVisible.toggle()
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(width: connectionTestButtonReservedWidth)
                .help(isPasswordVisible
                    ? L10n.t("printer.generic_camera.password.hide")
                    : L10n.t("printer.generic_camera.password.show"))
            }
        }
    }
}
