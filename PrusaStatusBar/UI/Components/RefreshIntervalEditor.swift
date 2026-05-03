import SwiftUI

/// Premium-feeling polling-interval picker. Two presentation pieces:
///
/// 1. A `SpoolIntervalSlider`: horizontal track with the Prusa filament-spool
///    icon as the thumb, mapped logarithmically over `bounds`. Drag commits
///    the value continuously.
/// 2. A "Custom" row with a numeric `TextField` and a `seconds` / `minutes`
///    `Picker`. The field commits on submit / focus loss, clamping into
///    `bounds`. Stays available alongside the slider so power users can land
///    on exact values like 47 s or 7 min.
///
/// The component is parametric in bounds so the General tab can reuse it for
/// the connected and the disconnected interval rows.
struct RefreshIntervalEditor: View {
    @Binding var seconds: Int
    let bounds: ClosedRange<Int>

    @State private var customValue: Int = 0
    @State private var customUnit: Unit = .seconds
    @FocusState private var customFieldFocused: Bool

    private enum Unit: String, CaseIterable, Hashable {
        case seconds, minutes

        var multiplier: Int {
            switch self {
            case .seconds: 1
            case .minutes: 60
            }
        }

        var label: String {
            switch self {
            case .seconds: "seconds"
            case .minutes: "minutes"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sml) {
            SpoolIntervalSlider(seconds: $seconds, bounds: bounds)
            customRow
        }
        .onAppear { syncCustomFromSeconds() }
        .onChange(of: seconds) { _, _ in
            // Always sync custom field to the authoritative `seconds` value.
            // Slider drag changes `seconds`, custom typing does not (typing
            // updates `customValue`; commit then writes through to `seconds`),
            // so this never clobbers in-progress edits. A previous focused
            // guard could leave the field stale forever if @FocusState missed
            // a transition (e.g. focus moving to the Picker), making the
            // number stop tracking the slider until the next commit.
            syncCustomFromSeconds()
        }
    }

    private var customRow: some View {
        HStack(spacing: Theme.Spacing.sml) {
            Text(L10n.t("misc.refresh_interval.custom"))
                .font(.prusaCaptionStrong)
                .foregroundStyle(Theme.Palette.textSecondary)

            // Hard-locked numeric field. `.plain` TextField inside a VStack
            // with explicit `.frame(width: 80, height: 24)` is the only
            // setup that doesn't let the chrome widen with longer values.
            // `.roundedBorder` chrome on macOS is content-sized, no amount
            // of `.frame` / `.overlay` wrapping makes it stop at 80 pt.
            // We draw our own border via `.background` + `.overlay` to
            // recover the rounded look. Locale grouping is off so 4-digit
            // values stay the same visual width as 3-digit ones.
            VStack(spacing: 0) {
                TextField("", value: $customValue, format: .number.grouping(.never))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.prusaBody.monospacedDigit())
                    .lineLimit(1)
                    .focused($customFieldFocused)
                    .padding(.horizontal, 6)
                    .onSubmit { commitCustom() }
                    .onChange(of: customFieldFocused) { _, isFocused in
                        if !isFocused { commitCustom() }
                    }
                #if os(macOS)
                    .onExitCommand { commitCustom() }
                #endif
            }
            .frame(width: 80, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Theme.Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: Theme.Hairline.width)
            )
            .clipped()

            Picker("", selection: $customUnit) {
                ForEach(Unit.allCases, id: \.self) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
            .onChange(of: customUnit) { _, _ in commitCustom() }

            Spacer(minLength: 0)

            // Fixed width sized to the longest format ("= 59 min 59 s") so
            // the row layout doesn't shift as the value moves between
            // single-digit seconds and multi-minute totals.
            Text(Self.formatted(seconds: seconds))
                .font(.prusaCaption.monospacedDigit())
                .foregroundStyle(Theme.Palette.textTertiary)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
    }

    // MARK: - Helpers

    private func commit(_ value: Int) {
        let clamped = min(bounds.upperBound, max(bounds.lowerBound, value))
        seconds = clamped
        syncCustomFromSeconds()
    }

    private func commitCustom() {
        let proposed = customValue * customUnit.multiplier
        commit(proposed)
    }

    private func syncCustomFromSeconds() {
        // Choose the unit that produces a clean integer; minutes wins when
        // the value is an exact multiple of 60.
        if seconds >= 60, seconds.isMultiple(of: 60) {
            customUnit = .minutes
            customValue = seconds / 60
        } else {
            customUnit = .seconds
            customValue = seconds
        }
    }

    static func formatted(seconds value: Int) -> String {
        if value < 60 {
            return "= \(value) s"
        }
        let minutes = value / 60
        let remainder = value % 60
        if remainder == 0 {
            return "= \(minutes) min"
        }
        return "= \(minutes) min \(remainder) s"
    }
}

#if DEBUG
    private struct RefreshIntervalEditorPreview: View {
        @State private var connected = 10
        @State private var disconnected = 60

        var body: some View {
            Form {
                Section("Connected") {
                    RefreshIntervalEditor(
                        seconds: $connected,
                        bounds: UserPreferences.refreshIntervalMin ... UserPreferences.refreshIntervalMax
                    )
                }
                Section("Disconnected") {
                    RefreshIntervalEditor(
                        seconds: $disconnected,
                        bounds: UserPreferences.disconnectedRefreshIntervalMin
                            ... UserPreferences.disconnectedRefreshIntervalMax
                    )
                }
            }
            .formStyle(.grouped)
            .frame(width: 480, height: 360)
        }
    }

    #Preview {
        RefreshIntervalEditorPreview()
    }
#endif
