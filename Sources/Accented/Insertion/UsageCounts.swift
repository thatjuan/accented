import Foundation

/// MRU tallies keyed by the variant's lowercase glyph. Persisted as
/// `settings.usageCounts` (JSON) so `SettingsStore` (#8) can take over the same key.
enum UsageCounts {
    static let defaultsKey = "settings.usageCounts"

    static func load(from defaults: UserDefaults = .standard) -> [String: Int] {
        guard let data = defaults.data(forKey: defaultsKey),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return map
    }

    static func bump(_ glyph: String, in defaults: UserDefaults = .standard) {
        let key = glyph.lowercased()
        guard !key.isEmpty else { return }
        var map = load(from: defaults)
        map[key, default: 0] += 1
        if let data = try? JSONEncoder().encode(map) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
