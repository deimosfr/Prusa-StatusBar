import AppKit
import SwiftUI

/// Compact brand-accent picker: a row of small colored circles for the three
/// Prusa presets, followed by a circular swatch that opens the system color
/// panel for an arbitrary user chosen accent color. The active swatch gets a
/// thin selection ring; hovering reveals the accent's name as a tooltip.
struct AccentSwatchPicker: View {
    @Binding var selection: Theme.Accent
    @Binding var customHex: String

    private let dotSize: CGFloat = 16

    private var presetCases: [Theme.Accent] {
        Theme.Accent.allCases.filter { $0 != .custom }
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(presetCases, id: \.self) { accent in
                AccentDot(
                    accent: accent,
                    isSelected: accent == selection,
                    size: dotSize
                ) {
                    selection = accent
                }
            }
            CustomAccentPickerDot(
                customHex: $customHex,
                isSelected: selection == .custom,
                size: dotSize,
                onPicked: { selection = .custom }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("a11y.brand_accent"))
        .accessibilityValue(selection.displayName)
    }
}

private struct AccentDot: View {
    let accent: Theme.Accent
    let isSelected: Bool
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Theme.Palette.brand(accent))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                )
                .padding(3)
                .background(
                    Circle()
                        .strokeBorder(
                            isSelected ? Theme.Palette.brand(accent) : Color.clear,
                            lineWidth: 1.5
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .help(accent.displayName)
        .accessibilityLabel(accent.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Custom-color slot rendered after the preset dots. Renders as a circular
/// swatch matching the preset dots; tapping opens the shared `NSColorPanel`
/// so the user can pick any sRGB color. Selecting a new color writes its
/// `#RRGGBB` representation to `customHex` and flips the active accent to
/// `.custom` via `onPicked`. The native `ColorPicker` view is avoided here
/// because its underlying `NSColorWell` enforces a wide pill geometry that
/// breaks the visual rhythm with the round preset swatches.
private struct CustomAccentPickerDot: View {
    @Binding var customHex: String
    let isSelected: Bool
    let size: CGFloat
    let onPicked: () -> Void

    @StateObject private var panelBridge = ColorPanelBridge()

    private var displayColor: Color {
        Color(hex: customHex) ?? Theme.Palette.brand(.orange)
    }

    var body: some View {
        Button(action: openPanel) {
            ZStack {
                Circle()
                    .fill(Self.rainbowGradient)
                    .frame(width: size, height: size)
                Circle()
                    .fill(displayColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5)
                    )
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
            )
            .padding(3)
            .background(
                Circle()
                    .strokeBorder(
                        isSelected ? displayColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(true)
        .help(Theme.Accent.custom.displayName)
        .accessibilityLabel(Theme.Accent.custom.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private static let rainbowGradient = AngularGradient(
        gradient: Gradient(colors: [
            .red, .orange, .yellow, .green, .blue, .purple, .pink, .red
        ]),
        center: .center
    )

    private func openPanel() {
        panelBridge.onChange = { hex in
            guard hex != customHex else { return }
            customHex = hex
            onPicked()
        }
        panelBridge.present(initialHex: customHex)
    }
}

/// Bridges `NSColorPanel` color changes back into the SwiftUI binding. The
/// panel is a shared singleton so we set ourselves as its target while the
/// picker is in use, then drop the target when the panel closes to avoid
/// reacting to other components' color edits.
@MainActor
private final class ColorPanelBridge: NSObject, ObservableObject, NSWindowDelegate {
    var onChange: ((String) -> Void)?
    private var isAttached = false

    func present(initialHex: String) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        if let initial = Color(hex: initialHex) {
            panel.color = NSColor(initial)
        }
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.delegate = self
        isAttached = true
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        let nsColor = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let red = Int((nsColor.redComponent * 255).rounded())
        let green = Int((nsColor.greenComponent * 255).rounded())
        let blue = Int((nsColor.blueComponent * 255).rounded())
        let hex = String(format: "#%02X%02X%02X", red, green, blue)
        onChange?(hex)
    }

    nonisolated func windowWillClose(_: Notification) {
        Task { @MainActor in
            guard isAttached else { return }
            let panel = NSColorPanel.shared
            panel.setTarget(nil)
            panel.setAction(nil)
            panel.delegate = nil
            isAttached = false
        }
    }
}

#if DEBUG
    private struct AccentSwatchPickerPreview: View {
        @State private var accent: Theme.Accent = .orange
        @State private var customHex: String = UserPreferences.customAccentHexDefault
        var body: some View {
            AccentSwatchPicker(selection: $accent, customHex: $customHex)
                .padding()
                .frame(width: 320)
        }
    }

    #Preview {
        AccentSwatchPickerPreview()
    }
#endif
