import SwiftUI

/// Optional "Live" extras card listing printer-reported metrics the user
/// opted into (speed, Z-height, nozzle diameter). Renders nothing when empty.
struct LiveMetricsCard: View {
    struct Row {
        let symbol: String
        let label: String
        let value: String
    }

    let rows: [Row]

    var body: some View {
        if rows.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Rectangle()
                            .fill(Theme.Palette.hairline)
                            .frame(height: Theme.Hairline.width)
                            .padding(.horizontal, Theme.Spacing.med)
                    }
                    rowView(row)
                }
            }
            .prusaCard(padding: 0)
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: Theme.Spacing.sml) {
            Image(systemName: row.symbol)
                .font(.system(size: 12, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 16)
            Text(row.label)
                .font(.prusaBody)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(row.value)
                .font(.prusaBody.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.med)
        .padding(.vertical, 9)
    }
}
