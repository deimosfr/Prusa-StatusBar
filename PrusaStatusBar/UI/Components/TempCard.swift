import SwiftUI

/// Temperature card: heater name, mini ring gauge (current/target ratio),
/// "current° -> target°" line. When target is zero the ring renders flat.
struct TempCard: View {
    enum Heater {
        case nozzle
        case bed

        @MainActor
        var label: String {
            switch self {
            case .nozzle: L10n.t("dropdown.heater.nozzle")
            case .bed: L10n.t("dropdown.heater.bed")
            }
        }

        var symbol: String {
            switch self {
            case .nozzle: "thermometer.low"
            case .bed: "square.grid.2x2"
            }
        }
    }

    let heater: Heater
    let temperature: Temperature

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.med) {
            ring
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: heater.symbol)
                        .font(.system(size: 10, weight: .light))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.textTertiary)
                    Text(heater.label)
                        .prusaSectionHeader()
                }
                Text(currentString)
                    .font(.prusaMetricSmall.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
                if temperature.target > 0 {
                    Text(String(format: L10n.t("dropdown.metrics.temp.target"), Int(temperature.target.rounded())))
                        .font(.prusaCaption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                } else {
                    Text(L10n.t("dropdown.metrics.temp.no_target"))
                        .font(.prusaCaption)
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .prusaCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(format: L10n.t("a11y.temp"), heater.label))
        .accessibilityValue(accessibilityValue)
    }

    private var currentString: String {
        "\(Int(temperature.current.rounded()))°"
    }

    private var accessibilityValue: String {
        if temperature.target > 0 {
            return "\(Int(temperature.current.rounded())) degrees, target \(Int(temperature.target.rounded()))"
        }
        return "\(Int(temperature.current.rounded())) degrees"
    }

    private var ratio: Double {
        guard temperature.target > 0 else { return 0 }
        return min(1, max(0, temperature.current / temperature.target))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Theme.Palette.hairline, lineWidth: 2)
            Circle()
                .trim(from: 0, to: ratio)
                .stroke(
                    Theme.Palette.brand(accent, customHex: customHex),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.3),
                    value: ratio
                )
        }
        .frame(width: Theme.Layout.tempRingSize, height: Theme.Layout.tempRingSize)
    }
}

#if DEBUG
    #Preview {
        HStack(spacing: 8) {
            TempCard(heater: .nozzle, temperature: Temperature(current: 215, target: 230))
            TempCard(heater: .bed, temperature: Temperature(current: 58, target: 60))
        }
        .padding()
        .frame(width: 360)
    }
#endif
