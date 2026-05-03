import SwiftUI

/// Embeddable view holding the four custom action slot cards. Lives at
/// the bottom of `MenuContentTab` (no longer a standalone Preferences
/// tab). Owns its own auto-save debounce so the parent form does not
/// have to coordinate per-keystroke writes.
struct CustomActionsSection: View {
    @Bindable var model: AppModel
    let services: AppServices

    @State private var draft: [CustomActionSlot: CustomActionConfig] = [:]
    @State private var saveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.med) {
            ForEach(CustomActionSlot.allCases, id: \.self) { slot in
                CustomActionSlotCard(
                    slot: slot,
                    config: bindingFor(slot),
                    runner: services.customActionRunner,
                    recents: recentsBinding,
                    accent: model.accent,
                    customAccentHex: model.customAccentHex
                )
            }
        }
        .onAppear { loadFromModel() }
        .onDisappear {
            saveTask?.cancel()
            persistImmediately()
        }
    }

    private func loadFromModel() {
        var next: [CustomActionSlot: CustomActionConfig] = [:]
        for slot in CustomActionSlot.allCases {
            next[slot] = model.customActions[slot] ?? .default
        }
        draft = next
    }

    private func bindingFor(_ slot: CustomActionSlot) -> Binding<CustomActionConfig> {
        Binding(
            get: { draft[slot] ?? .default },
            set: { newValue in
                draft[slot] = newValue
                scheduleAutoSave()
            }
        )
    }

    private var recentsBinding: Binding<[String]> {
        Binding(
            get: { services.settings.recentSymbols },
            set: { services.settings.recentSymbols = $0 }
        )
    }

    private func scheduleAutoSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            persistImmediately()
        }
    }

    private func persistImmediately() {
        AppModel.saveCustomActions(
            draft,
            to: services.settings,
            secretsStore: services.customActionSecretsStore
        )
        model.customActions = draft
    }
}

/// Visual badge displaying the result of a Test button click. Owned by
/// `CustomActionSlotCard` and presented inline next to the button.
struct CustomActionTestPill: Equatable {
    enum Tone {
        case success, warning, failure

        var foreground: Color {
            switch self {
            case .success: Theme.Palette.stateGreen
            case .warning: Theme.Palette.stateAmber
            case .failure: Theme.Palette.stateRed
            }
        }

        var background: Color {
            foreground.opacity(0.15)
        }
    }

    let text: String
    let tone: Tone
}
