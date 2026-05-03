import AppKit
import SwiftUI

/// Modal sheet for picking an SF Symbol used by a custom action button.
/// Layout:
///   - Search field at the top
///   - Recently-used row (when not empty and search is empty)
///   - Category sections with `LazyVGrid` of symbol cells
///   - Footer with Cancel + Use selection buttons
struct SymbolPickerSheet: View {
    /// Currently selected symbol. Reading the binding seeds the initial
    /// selection ring; writing happens only when the user confirms.
    @Binding var selection: String
    /// Recently-used symbols, most-recent-first. Read for display, written
    /// when the user confirms a pick.
    @Binding var recents: [String]
    /// Dismiss callback owned by the presenter; lets the parent close the
    /// sheet without each consumer having to plumb its own state.
    let onClose: () -> Void

    @State private var draft: String
    @State private var query: String = ""
    /// Cached result of `SymbolCatalog.filtered(query:)`. Recomputed only
    /// when the query string changes, so the search field stays smooth on
    /// big catalogs (the filter walks every symbol name).
    @State private var filteredCategories: [SymbolCatalog.Category] = SymbolCatalog.filtered(query: "")
    @FocusState private var searchFocused: Bool

    @Environment(\.brandAccent) private var accent
    @Environment(\.brandCustomHex) private var customHex

    init(
        selection: Binding<String>,
        recents: Binding<[String]>,
        onClose: @escaping () -> Void
    ) {
        _selection = selection
        _recents = recents
        self.onClose = onClose
        _draft = State(initialValue: selection.wrappedValue)
    }

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(40), spacing: 6),
        count: 8
    )

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if query.isEmpty, !recents.isEmpty {
                        section(title: L10n.t("symbol_picker.recent"), symbols: recents)
                    }
                    ForEach(filteredCategories, id: \.id) { category in
                        section(title: category.title, symbols: category.symbols)
                    }
                    if filteredCategories.isEmpty {
                        Text(L10n.t("symbol_picker.empty"))
                            .font(.prusaCaption)
                            .foregroundStyle(Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                }
                .padding(14)
            }
            Divider()
            footer
        }
        .frame(width: 480, height: 520)
        .background(Theme.Palette.surfaceElevated)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, newValue in
            filteredCategories = SymbolCatalog.filtered(query: newValue)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.textTertiary)
            TextField(L10n.t("symbol_picker.search_placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.prusaBody)
                .focused($searchFocused)
                .onSubmit { confirm() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func section(title: String, symbols: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).prusaSectionHeader()
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(symbols, id: \.self) { symbol in
                    SymbolCell(
                        name: symbol,
                        isSelected: symbol == draft,
                        accent: accent,
                        customHex: customHex
                    ) {
                        draft = symbol
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: draft.isEmpty ? "questionmark.square.dashed" : draft)
                    .font(.system(size: 18, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 22, height: 22)
                Text(draft.isEmpty ? L10n.t("symbol_picker.no_selection") : draft)
                    .font(.prusaCaption.monospaced())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(L10n.t("common.cancel")) { onClose() }
                .keyboardShortcut(.cancelAction)
            Button(L10n.t("symbol_picker.use")) { confirm() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func confirm() {
        guard !draft.isEmpty else { return }
        selection = draft
        var updated = recents.filter { $0 != draft }
        updated.insert(draft, at: 0)
        recents = Array(updated.prefix(8))
        onClose()
    }
}

private struct SymbolCell: View {
    let name: String
    let isSelected: Bool
    let accent: Theme.Accent
    let customHex: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
                Image(systemName: name)
                    .font(.system(size: 16, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(foreground)
            }
            .frame(width: 40, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.Palette.brand(accent, customHex: customHex) : .clear,
                        lineWidth: 1.5
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(true)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .onHover { isHovering = $0 }
    }

    private var background: Color {
        if isSelected {
            return Theme.Palette.brandMuted(accent, customHex: customHex)
        }
        if isHovering {
            return Color.gray.opacity(0.12)
        }
        return Color.clear
    }

    private var foreground: Color {
        if isSelected {
            return Theme.Palette.brand(accent, customHex: customHex)
        }
        return Theme.Palette.textPrimary
    }
}

#if DEBUG
    private struct SymbolPickerSheetPreview: View {
        @State private var symbol: String = "bolt"
        @State private var recents: [String] = ["power", "lightbulb.fill"]
        var body: some View {
            SymbolPickerSheet(selection: $symbol, recents: $recents) {}
        }
    }

    #Preview {
        SymbolPickerSheetPreview()
    }
#endif
