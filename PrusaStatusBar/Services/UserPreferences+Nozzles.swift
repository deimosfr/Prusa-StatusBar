import Foundation

extension UserPreferences {
    /// Manual per-tool diameters for multi-tool printers. An empty array keeps
    /// the existing automatic behavior and displays `/api/v1/info`'s single
    /// `nozzle_diameter` value. PrusaLink currently exposes only Tool 1, so
    /// multi-tool configurations are explicit user input.
    public var configuredNozzleDiameters: [Double] {
        get {
            guard let stored = defaultsAccess.array(forKey: UserPreferencesKey.configuredNozzleDiameters) else {
                return []
            }
            let values = stored.compactMap { ($0 as? NSNumber)?.doubleValue }
                .filter(\.isFinite)
                .prefix(Self.nozzleToolCountMax)
                .map(Self.clampedNozzleDiameter)
            return values.count >= 2 ? values : []
        }
        set {
            let values = newValue.filter(\.isFinite)
                .prefix(Self.nozzleToolCountMax)
                .map(Self.clampedNozzleDiameter)
            if values.count >= 2 {
                defaultsAccess.set(values, forKey: UserPreferencesKey.configuredNozzleDiameters)
            } else {
                defaultsAccess.removeObject(forKey: UserPreferencesKey.configuredNozzleDiameters)
            }
        }
    }

    private static func clampedNozzleDiameter(_ value: Double) -> Double {
        max(nozzleDiameterMin, min(nozzleDiameterMax, value))
    }
}
