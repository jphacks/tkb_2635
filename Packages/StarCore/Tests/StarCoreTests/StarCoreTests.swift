import Foundation
import Testing
@testable import StarCore

private func utc(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso)!
}

@Suite struct AstroTests {
    /// 参照値は Astronomy Engine（Python 版）で計算した渋谷駅付近の月の位置
    @Test(arguments: [
        ("2026-10-24T12:00:00Z", 57.63, 151.94, 0.963),
        ("2026-10-25T15:00:00Z", 62.59, 219.45, 0.995),
        ("2026-01-01T10:00:00Z", 54.54, 92.27, 0.940),
    ])
    func moonMatchesAstronomyEngine(iso: String, altitude: Double, azimuth: Double, fraction: Double) {
        let moon = Astro.moon(date: utc(iso), latitude: 35.658, longitude: 139.7016)
        let error = Astro.separation(moon.position, HorizontalCoord(altitude: altitude, azimuth: azimuth))
        #expect(error < 0.7, "角度誤差 \(error)°")
        #expect(abs(moon.illuminatedFraction - fraction) < 0.02)
    }

    @Test func sunIsBelowHorizonAtNight() {
        let sun = Astro.sun(date: utc("2026-10-24T12:00:00Z"), latitude: 35.658, longitude: 139.7016)
        #expect(abs(sun.altitude - -49.19) < 1)
        #expect(abs(sun.azimuth - 296.77) < 1.5)
    }

    @Test func polarisStaysNearNorthAtTokyoLatitude() {
        let polaris = StarCatalog.star(id: "polaris")!
        let p = Astro.star(polaris, date: utc("2026-10-24T12:00:00Z"), latitude: 35.658, longitude: 139.7016)
        #expect(abs(p.altitude - 35.7) < 1.5)
        #expect(p.azimuth < 3 || p.azimuth > 357)
    }

    @Test func directionNames() {
        #expect(Angle.directionName(0) == "北")
        #expect(Angle.directionName(135) == "南東")
        #expect(Angle.directionName(350) == "北")
    }
}

@Suite struct GeometryTests {
    let tower = Building(id: "t", name: "塔", x: 0, y: 100, width: 20, depth: 20, height: 100, usage: nil)

    @Test func buildingBlocksOnlyItsDirection() {
        let profile = HorizonProfile.compute(observerEast: 0, observerNorth: 0, eyeElevation: 1.5,
                                             groundElevation: 0, buildings: [tower])
        // 手前の面までの距離 90m、高さ差 98.5m
        #expect(abs(profile.elevation(at: 0) - atan2(98.5, 90) * 180 / .pi) < 0.01)
        #expect(profile.elevation(at: 180) == 0)
        #expect(profile.elevation(at: 90) == 0)
    }

    @Test func higherObserverSeesOverBuilding() {
        let profile = HorizonProfile.compute(observerEast: 0, observerNorth: 0, eyeElevation: 150,
                                             groundElevation: 0, buildings: [tower])
        #expect(profile.samples.allSatisfy { $0 == 0 })
        #expect(profile.openness == 1)
    }

    @Test func opennessOfUniformHorizon() {
        let profile = HorizonProfile.uniform(30, isApproximate: true)
        #expect(abs(profile.openness - 0.5) < 1e-9)
    }

    @Test func azimuthRangeAcrossNorth() {
        let range = AzimuthRange(from: 300, to: 60)
        #expect(range.contains(0))
        #expect(range.contains(330))
        #expect(!range.contains(180))
    }
}

@Suite struct RecommenderTests {
    @Test func scoreFormula() {
        #expect(abs(Recommender.score(openness: 1, weather: 1, darkness: 1) - 100) < 1e-9)
        #expect(abs(Recommender.score(openness: 0.5, weather: 0.5, darkness: 0.2) - 42.5) < 1e-9)
    }

    @Test func unverifiedGlareIsNotTreatedAsZero() {
        let unknown = Recommender.darkness(skyBrightness: 0.5, localGlareLevel: nil, moonEffect: 0)
        let none = Recommender.darkness(skyBrightness: 0.5, localGlareLevel: 0, moonEffect: 0)
        #expect(unknown.assumed)
        #expect(!none.assumed)
        #expect(unknown.value < none.value)
    }

    @Test func openingHoursAcrossMidnight() {
        let hours = OpeningHours(alwaysOpen: false, open: "18:00", close: "02:00")
        #expect(hours.isOpen(at: utc("2026-10-24T14:00:00Z")))  // 23:00 JST
        #expect(!hours.isOpen(at: utc("2026-10-24T03:00:00Z")))  // 12:00 JST
    }

    /// 仕様書 4.3 / 第10章のデモ: 同じ時刻の月が、渋谷の地上では建物に隠れ、SHIBUYA SKY では見える
    @Test func groundVersusObservatoryInShibuya() throws {
        let contexts = try SeedData.loadContexts()
        let ground = try #require(contexts.first { $0.id == "shibuya_east_plaza" })
        let sky = try #require(contexts.first { $0.id == "shibuya_sky" })
        let date = utc("2026-10-24T12:00:00Z")  // 21:00 JST

        let g = Recommender.evaluate(ground, target: .moon, date: date, weather: nil)
        let s = Recommender.evaluate(sky, target: .moon, date: date, weather: nil)
        #expect(g.altitude > 0)
        #expect(!g.geometricVisibility)
        #expect(s.geometricVisibility)
        #expect(s.openness > g.openness)
        #expect(g.dataQualityFlags.contains(.weatherMissing))
        #expect(s.tier == .needsCheck)
    }

    @Test func regionalLightWithoutSourceIsProvisional() throws {
        let context = try #require(try SeedData.loadContexts().first { $0.id == "shibuya_east_plaza" })
        var spot = context.spot
        let date = utc("2026-10-24T12:00:00Z")

        spot.regionalLightSource = nil
        let provisional = Recommender.evaluate(SpotContext(spot: spot, scene: context.scene), target: .moon, date: date, weather: nil)
        #expect(provisional.dataQualityFlags.contains(.regionalLightProvisional))
        #expect(spot.regionalLightShortSource == "暫定値")

        spot.regionalLightSource = "VIIRS VNL v2.2 2023 annual average_masked（EOG, Colorado School of Mines）"
        spot.regionalLightMeasuredAt = "2023"
        let measured = Recommender.evaluate(SpotContext(spot: spot, scene: context.scene), target: .moon, date: date, weather: nil)
        #expect(!measured.dataQualityFlags.contains(.regionalLightProvisional))
        #expect(spot.regionalLightShortSource == "VIIRS 2023")
    }

    @Test func closedFacilityIsUnavailable() throws {
        let gyoen = try #require(try SeedData.loadContexts().first { $0.id == "shinjuku_gyoen" })
        let p = Recommender.evaluate(gyoen, target: .moon, date: utc("2026-10-24T12:00:00Z"), weather: nil)
        #expect(p.tier == .unavailable)
    }

    @Test func seedDataCoversAllCategories() throws {
        let categories = Set(try SeedData.loadSpots().map(\.category))
        #expect(categories == Set(SpotCategory.allCases))
    }
}

@Suite struct WeatherTests {
    @Test func decodesOpenMeteoFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "open_meteo_sample", withExtension: "json", subdirectory: "Fixtures"))
        let samples = try OpenMeteoClient.decode(Data(contentsOf: url), gridId: "test", fetchedAt: Date())
        #expect(samples.count == 24)
        #expect(samples.allSatisfy { $0.cloudCover != nil })
        let first = try #require(samples.first)
        #expect(OpenMeteoClient.nearest(samples, to: first.forecastTime.addingTimeInterval(1_800))?.forecastTime == first.forecastTime)
        #expect(OpenMeteoClient.nearest(samples, to: first.forecastTime.addingTimeInterval(-86_400)) == nil)
    }

    @Test func rainLowersWeatherScore() {
        func weather(cloud: Double, rain: Double) -> Weather {
            Weather(gridId: "", modelName: "", forecastTime: Date(), fetchedAt: Date(),
                    cloudCover: cloud, precipitation: rain, wind: nil, visibility: nil, missingStatus: .ok)
        }
        #expect(Recommender.weatherScore(weather(cloud: 0, rain: 0)) == 1)
        #expect(Recommender.weatherScore(weather(cloud: 0, rain: 1))! < 0.3)
    }
}
