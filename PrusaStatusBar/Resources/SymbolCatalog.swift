import Foundation

/// Curated SF Symbol catalog surfaced by the symbol picker sheet. macOS
/// has no public API to enumerate the system's symbol set, so we ship a
/// hand-picked list grouped by category. Names are validated lazily at
/// render time via `NSImage(systemSymbolName:)`; unknown names render as
/// a placeholder without crashing.
public enum SymbolCatalog {
    public struct Category: Hashable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let symbols: [String]
    }

    /// Categorized symbols. Order preserved for display.
    public static let categories: [Category] = [
        Category(
            id: "power",
            title: "Power & Control",
            symbols: [
                "power", "power.circle", "power.circle.fill", "powerplug", "powerplug.fill",
                "bolt", "bolt.fill", "bolt.circle", "bolt.circle.fill",
                "bolt.slash", "bolt.slash.fill", "bolt.badge.checkmark",
                "play", "play.fill", "play.circle", "play.circle.fill",
                "pause", "pause.fill", "pause.circle", "pause.circle.fill",
                "stop", "stop.fill", "stop.circle", "stop.circle.fill",
                "arrow.clockwise", "arrow.clockwise.circle", "arrow.counterclockwise",
                "arrow.uturn.backward", "arrow.uturn.forward",
                "switch.2", "togglepower", "personalhotspot"
            ]
        ),
        Category(
            id: "lighting",
            title: "Lighting",
            symbols: [
                "lightbulb", "lightbulb.fill", "lightbulb.slash", "lightbulb.slash.fill",
                "light.beacon.max", "light.beacon.max.fill",
                "lamp.desk", "lamp.desk.fill", "lamp.table", "lamp.table.fill",
                "lamp.floor", "lamp.floor.fill", "lamp.ceiling", "lamp.ceiling.fill",
                "spigot", "spigot.fill", "rays", "sun.max", "sun.max.fill",
                "sun.min", "sunset.fill", "moon", "moon.fill", "moon.stars.fill"
            ]
        ),
        Category(
            id: "climate",
            title: "Climate",
            symbols: [
                "thermometer.low", "thermometer.medium", "thermometer.high",
                "thermometer.sun.fill", "thermometer.snowflake",
                "fan", "fan.fill", "fan.desk.fill", "fan.floor.fill",
                "fan.ceiling.fill", "fan.oscillation",
                "humidifier", "humidifier.fill", "dehumidifier",
                "wind", "wind.snow",
                "snowflake", "drop", "drop.fill", "flame", "flame.fill",
                "air.conditioner.horizontal", "air.conditioner.horizontal.fill",
                "heater.vertical", "heater.vertical.fill"
            ]
        ),
        Category(
            id: "media",
            title: "Media & Audio",
            symbols: [
                "speaker", "speaker.fill", "speaker.wave.1.fill",
                "speaker.wave.2.fill", "speaker.wave.3.fill", "speaker.slash.fill",
                "music.note", "music.note.list", "headphones", "hifispeaker.fill",
                "tv", "tv.fill", "appletv.fill", "play.tv.fill", "videoprojector.fill",
                "camera", "camera.fill", "video", "video.fill",
                "bell", "bell.fill", "bell.slash", "bell.badge"
            ]
        ),
        Category(
            id: "status",
            title: "Status & Alerts",
            symbols: [
                "checkmark", "checkmark.circle", "checkmark.circle.fill",
                "checkmark.seal", "checkmark.seal.fill",
                "xmark", "xmark.circle", "xmark.circle.fill", "xmark.octagon.fill",
                "exclamationmark.triangle", "exclamationmark.triangle.fill",
                "exclamationmark.circle", "exclamationmark.circle.fill",
                "questionmark.circle", "questionmark.circle.fill",
                "info.circle", "info.circle.fill",
                "wifi", "wifi.slash", "wifi.exclamationmark",
                "antenna.radiowaves.left.and.right",
                "network", "network.slash"
            ]
        ),
        Category(
            id: "home",
            title: "Home & Devices",
            symbols: [
                "house", "house.fill", "house.lodge", "house.lodge.fill",
                "building.2", "building.2.fill", "door.left.hand.open",
                "door.left.hand.closed", "door.garage.open", "door.garage.closed",
                "lock", "lock.fill", "lock.open", "lock.open.fill",
                "key", "key.fill",
                "shield", "shield.fill",
                "alarm", "alarm.fill", "timer",
                "sensor", "sensor.fill", "rectangle.connected.to.line.below",
                "cooktop", "cooktop.fill", "oven", "oven.fill",
                "washer", "washer.fill", "dryer", "dryer.fill",
                "refrigerator", "refrigerator.fill",
                "dishwasher", "dishwasher.fill",
                "blinds.horizontal.open", "blinds.horizontal.closed",
                "curtains.open", "curtains.closed",
                "fanblades", "fanblades.fill",
                "videoprojector"
            ]
        ),
        Category(
            id: "vehicle",
            title: "Vehicles & Outdoor",
            symbols: [
                "car", "car.fill", "bolt.car", "bolt.car.fill",
                "ev.charger", "ev.charger.fill",
                "bicycle", "scooter", "tram.fill",
                "leaf", "leaf.fill", "tree", "tree.fill",
                "drop.degreesign", "drop.degreesign.fill",
                "cloud.sun", "cloud.sun.fill", "cloud.rain", "cloud.rain.fill",
                "cloud.bolt", "cloud.bolt.fill",
                "camera.aperture"
            ]
        ),
        Category(
            id: "misc",
            title: "Misc",
            symbols: [
                "star", "star.fill", "heart", "heart.fill",
                "flag", "flag.fill",
                "tag", "tag.fill",
                "bookmark", "bookmark.fill",
                "gear", "gearshape", "gearshape.fill",
                "wrench.adjustable", "wrench.adjustable.fill",
                "hammer", "hammer.fill",
                "screwdriver", "screwdriver.fill",
                "wand.and.stars", "wand.and.rays",
                "sparkles", "rainbow",
                "bubble.left", "bubble.left.fill",
                "paperplane", "paperplane.fill",
                "paperclip",
                "link", "link.circle", "link.circle.fill",
                "arrow.up.right", "arrow.up.right.square",
                "square.and.arrow.up", "square.and.arrow.down",
                "ellipsis", "ellipsis.circle", "ellipsis.circle.fill"
            ]
        )
    ]

    /// Flattened, deduplicated list of every symbol in the catalog.
    /// Order follows category iteration so the first symbol of each
    /// category lands ahead of later categories.
    public static let allSymbols: [String] = {
        var seen: Set<String> = []
        var ordered: [String] = []
        for category in categories {
            for symbol in category.symbols where !seen.contains(symbol) {
                seen.insert(symbol)
                ordered.append(symbol)
            }
        }
        return ordered
    }()

    /// Substring + case-insensitive match across the catalog. Empty
    /// queries return the unfiltered set.
    public static func filtered(query: String) -> [Category] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return categories }
        return categories.compactMap { category in
            let matches = category.symbols.filter { $0.lowercased().contains(trimmed) }
            return matches.isEmpty ? nil : Category(id: category.id, title: category.title, symbols: matches)
        }
    }
}
