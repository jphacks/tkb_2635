import Foundation
import Testing
@testable import StarCore

private func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

/// 渋谷駅東口
private let latitude = 35.658
private let longitude = 139.702816
/// skyfield と比べるときの角距離の許容差 [度]
private let referenceTolerance = 0.3
/// 東京の緯度。恒星が昇るかの判定に使う
private let tokyoLatitude = 35.7
/// 選べる恒星に求める、南中時の最低高度 [度]
private let minimumTransitAltitude = 10.0

private struct Reference {
    var planet: String
    var time: String
    var altitude: Double
    var azimuth: Double
}

/// scripts/planet_reference.py（skyfield 1.55・DE421）で計算した見かけの高度・方位（大気差込み）
private let references: [Reference] = [
    Reference(planet: "mercury", time: "2026-10-24T12:00:00Z", altitude: -39.959, azimuth: 271.652),
    Reference(planet: "venus", time: "2026-10-24T12:00:00Z", altitude: -55.396, azimuth: 292.395),
    Reference(planet: "mars", time: "2026-10-24T12:00:00Z", altitude: -27.135, azimuth: 37.795),
    Reference(planet: "jupiter", time: "2026-10-24T12:00:00Z", altitude: -33.955, azimuth: 31.658),
    Reference(planet: "saturn", time: "2026-10-24T12:00:00Z", altitude: 52.114, azimuth: 150.801),
    Reference(planet: "mercury", time: "2026-11-15T09:30:00Z", altitude: -33.102, azimuth: 280.549),
    Reference(planet: "venus", time: "2026-11-15T09:30:00Z", altitude: -42.709, azimuth: 291.525),
    Reference(planet: "mars", time: "2026-11-15T09:30:00Z", altitude: -38.914, azimuth: 10.281),
    Reference(planet: "jupiter", time: "2026-11-15T09:30:00Z", altitude: -40.099, azimuth: 10.650),
    Reference(planet: "saturn", time: "2026-11-15T09:30:00Z", altitude: 44.228, azimuth: 132.043),
]

@Suite struct PlanetTests {
    @Test(arguments: references.indices)
    func matchesSkyfield(_ index: Int) throws {
        let ref = references[index]
        let planet = try #require(PlanetCatalog.planet(id: ref.planet))
        let position = Astro.planet(planet, date: utc(ref.time), latitude: latitude, longitude: longitude)
        let expected = HorizontalCoord(altitude: ref.altitude, azimuth: ref.azimuth)
        let error = Astro.separation(position, expected)
        #expect(error < referenceTolerance, "\(planet.name) \(ref.time): 差 \(error)°")
    }

    @Test func catalogHasFiveNakedEyePlanets() {
        #expect(PlanetCatalog.planets.map(\.id) == ["mercury", "venus", "mars", "jupiter", "saturn"])
        #expect(PlanetCatalog.planets.map(\.name) == ["水星", "金星", "火星", "木星", "土星"])
    }

    /// 惑星も出・南中・入りを出せる（2026-10-24 の夜の土星は夕方に南中して夜半前に沈む）
    @Test func riseSetWorksForPlanets() throws {
        let saturn = try #require(PlanetCatalog.planet(id: "saturn"))
        let times = RiseSet.times(for: .planet(saturn), date: utc("2026-10-24T12:00:00Z"),
                                  latitude: latitude, longitude: longitude)
        #expect(times.visibility == .crosses)
        #expect(times.set != nil)
        #expect(ObservationTarget.planet(saturn).id == "saturn")
        #expect(ObservationTarget.planet(saturn).name == "土星")
    }
}

@Suite struct StarCatalogTests {
    /// 東京で南中高度が 10° 以上 ⇔ 赤緯 > 緯度 − 80°（= −44.3°）
    @Test func everyStarRisesHighEnoughInTokyo() {
        let minimumDeclination = tokyoLatitude - (90 - minimumTransitAltitude)
        for star in StarCatalog.stars {
            #expect(star.declination > minimumDeclination, "\(star.name) は東京で高度 10° まで昇らない")
        }
    }

    @Test func starsAreSortedByMagnitudeWithUniqueIDs() {
        let magnitudes = StarCatalog.stars.map(\.magnitude)
        #expect(magnitudes == magnitudes.sorted())
        #expect(Set(StarCatalog.stars.map(\.id)).count == StarCatalog.stars.count)
    }

    @Test func includesAddedStars() {
        for id in ["alnilam", "dubhe", "shaula", "adhara", "algieba"] {
            #expect(StarCatalog.star(id: id) != nil)
        }
        #expect(StarCatalog.stars.count == 52)
    }
}
