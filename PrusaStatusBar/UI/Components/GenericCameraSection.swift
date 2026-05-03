import SwiftUI

/// Optional second-camera section shown directly below the Buddy Camera
/// section in the Printer tab. Mirrors HA's "Generic Camera" integration:
/// nine inputs grouped into four cards (Sources, Authentication, Stream
/// options, Security) with animated reveal of conditional fields. The
/// section is gated by an "Enable Generic Camera" toggle that defaults
/// OFF; gating mirrors `BuddyCameraSection` (toggle disabled until the
/// PrusaLink URL is set).
struct GenericCameraSection: View {
    @Binding var enabled: Bool
    @Binding var streamURL: String
    @Binding var stillImageURL: String
    @Binding var rtspTransport: GenericCameraRTSPTransport
    @Binding var authMode: GenericCameraAuthMode
    @Binding var username: String
    @Binding var password: String
    @Binding var framerate: Int
    @Binding var verifySSL: Bool
    @Binding var contentType: String
    @Binding var streamURLError: String?
    @Binding var stillURLError: String?
    let probe: RTSPProbing
    let isPrinterURLSet: Bool

    @State var isPasswordVisible: Bool = false
    @State var isStreamTesting: Bool = false
    @State var isStillTesting: Bool = false
    @State var streamTestResult: PrinterTestResult?
    @State var stillTestResult: PrinterTestResult?

    var body: some View {
        Section {
            enableToggleRow
            if enabled {
                GenericCameraAuthCard(
                    authMode: $authMode,
                    username: $username,
                    password: $password,
                    isPasswordVisible: $isPasswordVisible
                )
                GenericCameraStreamOptionsCard(
                    rtspTransport: $rtspTransport,
                    framerate: $framerate,
                    streamIsRTSP: streamIsRTSP
                )
                GenericCameraSecurityCard(
                    verifySSL: $verifySSL,
                    contentType: $contentType
                )
                GenericCameraSourcesCard(
                    streamURL: $streamURL,
                    stillImageURL: $stillImageURL,
                    streamURLError: streamURLError,
                    stillURLError: stillURLError,
                    isStreamTesting: isStreamTesting,
                    isStillTesting: isStillTesting,
                    streamTestResult: streamTestResult,
                    stillTestResult: stillTestResult,
                    onTestStream: { Task { await runStreamTest() } },
                    onTestStill: { Task { await runStillTest() } }
                )
            }
        } header: {
            Label(L10n.t("printer.generic_camera.header"), systemImage: "video.fill")
        } footer: {
            FormFooterText(L10n.t("printer.generic_camera.footer"))
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: enabled)
        .animation(.easeInOut(duration: 0.2), value: authMode)
        .animation(.easeInOut(duration: 0.2), value: streamIsRTSP)
    }

    private var enableToggleRow: some View {
        Toggle(L10n.t("printer.generic_camera.enable.label"), isOn: $enabled)
            .disabled(!isPrinterURLSet)
            .help(isPrinterURLSet ? "" : L10n.t("printer.camera.enable.requires_url"))
    }

    var streamIsRTSP: Bool {
        let trimmed = streamURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "rtsp" || scheme == "rtsps"
    }
}
