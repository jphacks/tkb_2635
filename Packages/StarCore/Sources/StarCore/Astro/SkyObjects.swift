import Foundation

public enum SkyObjectKind: Sendable {
    case moon, planet, star
}

/// AR に出す天体 1 つ
public struct SkyObject: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: SkyObjectKind
    public let position: HorizontalCoord
    /// 恒星の等級。月・惑星は nil
    public let magnitude: Double?
    /// 建物などでさえぎられている（地平線より上だが、見えない向き）
    public let isBlocked: Bool

    public var direction: LocalVector { LocalVector(position) }
    public var isAboveHorizon: Bool { position.altitude > 0 }
}

/// ある地点・時刻の、月・惑星・恒星・星座線の空での位置（AR 用）。
/// 位置の計算は 3D の空と同じもの（`Astro`・`PlanetCatalog`・`SkyOrientation`）を使う。
public struct SkySnapshot: Sendable {
    public let objects: [SkyObject]
    public let constellations: [PlacedConstellation]
    /// 星座の姿の線画（`ConstellationArt`）
    public let art: [PlacedConstellationArt]

    /// - Parameters:
    ///   - constellations: `ConstellationLines.decode` で読んだ星座線。無ければ線は出ない
    ///   - art: `ConstellationArt.decode` で読んだ星座の線画。無ければ絵は出ない
    public static func make(context: SpotContext, date: Date, constellations: [ConstellationLines] = [],
                            art: [ConstellationArt] = []) -> SkySnapshot {
        let lat = context.spot.latitude, lon = context.spot.longitude
        func object(id: String, name: String, kind: SkyObjectKind, position: HorizontalCoord, magnitude: Double? = nil) -> SkyObject {
            SkyObject(id: id, name: name, kind: kind, position: position, magnitude: magnitude,
                      isBlocked: context.blocksSky(altitude: position.altitude, azimuth: position.azimuth))
        }
        var objects = [object(id: "moon", name: "月", kind: .moon, position: Astro.moon(date: date, latitude: lat, longitude: lon).position)]
        for planet in PlanetCatalog.planets {
            objects.append(object(id: planet.id, name: planet.name, kind: .planet,
                                  position: Astro.planet(planet, date: date, latitude: lat, longitude: lon)))
        }
        for star in StarCatalog.stars {
            objects.append(object(id: star.id, name: star.name, kind: .star,
                                  position: Astro.star(star, date: date, latitude: lat, longitude: lon), magnitude: star.magnitude))
        }
        let orientation = SkyOrientation(date: date, latitude: lat, longitude: lon)
        return SkySnapshot(objects: objects,
                           constellations: constellations.map { $0.placed(orientation: orientation, context: context) },
                           art: art.map { $0.placed(orientation: orientation, context: context) })
    }
}
