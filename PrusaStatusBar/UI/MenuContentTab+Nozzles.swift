import SwiftUI

/// Keeps the multi-tool editor out of `MenuContentTab`'s general preference
/// bindings and under SwiftLint's `type_body_length` budget.
extension MenuContentTab {
    var nozzleToolCountBinding: Binding<Int> {
        Binding(
            get: { model.configuredNozzleDiameters.count },
            set: { newCount in
                guard newCount >= 2 else {
                    saveConfiguredNozzleDiameters([])
                    return
                }
                var values = model.configuredNozzleDiameters
                let seed = values.last
                    ?? model.printerInfo?.nozzleDiameter
                    ?? UserPreferences.nozzleDiameterDefault
                if values.count < newCount {
                    values.append(contentsOf: repeatElement(seed, count: newCount - values.count))
                } else {
                    values.removeLast(values.count - newCount)
                }
                saveConfiguredNozzleDiameters(values)
            }
        )
    }

    func nozzleDiameterBinding(at index: Int) -> Binding<Double> {
        Binding(
            get: {
                guard model.configuredNozzleDiameters.indices.contains(index) else {
                    return UserPreferences.nozzleDiameterDefault
                }
                return model.configuredNozzleDiameters[index]
            },
            set: { newValue in
                guard model.configuredNozzleDiameters.indices.contains(index) else { return }
                var values = model.configuredNozzleDiameters
                values[index] = newValue
                saveConfiguredNozzleDiameters(values)
            }
        )
    }

    private func saveConfiguredNozzleDiameters(_ values: [Double]) {
        services.settings.configuredNozzleDiameters = values
        model.configuredNozzleDiameters = services.settings.configuredNozzleDiameters
    }
}
