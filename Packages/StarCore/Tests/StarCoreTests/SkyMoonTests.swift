import Foundation
import Testing
@testable import StarCore

@Suite struct SkyOrientationTests {
    private func horizontal(_ v: LocalVector) -> HorizontalCoord {
        HorizontalCoord(altitude: asin(v.up) * 180 / .pi, azimuth: Angle.normalize(atan2(v.east, v.north) * 180 / .pi))
    }

    /// 星図を回した向きが、恒星の位置計算（歳差・大気差つき）と 0.6° 以内で合う
    @Test(arguments: ["sirius", "betelgeuse", "capella", "procyon"])
    func matchesStarPositions(id: String) {
        let star = StarCatalog.star(id: id)!
        // 2026-01-15 21:00（東京時間）の渋谷。冬の星座が南の空に高い
        let date = ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z")!
        let sky = SkyOrientation(date: date, latitude: 35.658, longitude: 139.7016)
        let fromMap = horizontal(sky.direction(rightAscension: star.rightAscension * 15, declination: star.declination))
        let computed = Astro.star(star, date: date, latitude: 35.658, longitude: 139.7016)
        #expect(computed.altitude > 15, "高度が低いと大気差で比べにくい")
        #expect(Astro.separation(fromMap, computed) < 0.6, "\(id): \(Astro.separation(fromMap, computed))°")
    }

    @Test func axesStayPerpendicular() {
        let sky = SkyOrientation(date: Date(timeIntervalSince1970: 1_800_000_000), latitude: 35.7, longitude: 139.7)
        #expect(abs(sky.xAxis.dot(sky.yAxis)) < 1e-9)
        #expect(abs(sky.yAxis.dot(sky.zAxis)) < 1e-9)
        #expect(abs(sky.zAxis.dot(sky.zAxis) - 1) < 1e-9)
        // 天の北極は真北の、緯度と同じ高さ
        #expect(abs(asin(sky.zAxis.up) * 180 / .pi - 35.7) < 1e-9)
    }

    @Test func starMapUV() {
        #expect(StarMapProjection.uv(rightAscension: 180, declination: 90) == (0, 0))
        #expect(abs(StarMapProjection.uv(rightAscension: 0, declination: 0).u - 0.5) < 1e-12)
        #expect(abs(StarMapProjection.uv(rightAscension: 90, declination: -90).u - 0.25) < 1e-12)
        #expect(StarMapProjection.uv(rightAscension: 90, declination: -90).v == 1)
    }
}

@Suite struct MoonPhaseTests {
    let southMoon = HorizontalCoord(altitude: 30, azimuth: 180)

    /// 夕方の上弦の月（太陽は西に沈んだあと）は、右（西）側が明るい
    @Test func eveningMoonIsLitOnTheRight() {
        let angle = MoonPhase.brightLimbAngle(moon: southMoon, sun: HorizontalCoord(altitude: -10, azimuth: 270))!
        #expect(angle > 60 && angle < 150, "\(angle)°")
    }

    /// 明け方の下弦の月（太陽は東の地平線の下）は、左（東）側が明るい
    @Test func morningMoonIsLitOnTheLeft() {
        let angle = MoonPhase.brightLimbAngle(moon: southMoon, sun: HorizontalCoord(altitude: -10, azimuth: 90))!
        #expect(angle > 210 && angle < 300, "\(angle)°")
    }

    @Test func sunBelowMoonLightsTheBottom() {
        let angle = MoonPhase.brightLimbAngle(moon: southMoon, sun: HorizontalCoord(altitude: -40, azimuth: 180))!
        #expect(abs(angle - 180) < 1e-6)
    }

    @Test func undefinedWhenMoonAndSunOverlap() {
        #expect(MoonPhase.brightLimbDirection(moon: southMoon, sun: southMoon) == nil)
    }

    @Test func litArea() {
        // 半月: 明るい側（+y）だけ光る
        #expect(MoonPhase.isLit(x: 0, y: 0.5, fraction: 0.5))
        #expect(!MoonPhase.isLit(x: 0, y: -0.5, fraction: 0.5))
        // 満月は全部、新月は（縁を除いて）光らない
        #expect(MoonPhase.isLit(x: 0, y: -0.9, fraction: 1))
        #expect(!MoonPhase.isLit(x: 0, y: 0.9, fraction: 0))
        // 円の外は光らない
        #expect(!MoonPhase.isLit(x: 0.9, y: 0.9, fraction: 1))
    }
}

@Suite struct StarVisibilityTests {
    let contexts = try! SeedData.loadContexts()

    @Test func levels() {
        #expect(StarVisibility.level(darkness: 0.2) == .city)
        #expect(StarVisibility.level(darkness: StarVisibility.suburbanThreshold) == .suburban)
        #expect(StarVisibility.level(darkness: 0.9) == .dark)
    }

    @Test func shibuyaShowsOnlyBrightStars() {
        let spot = contexts.first { $0.id == "shibuya_east_plaza" }!.spot
        let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        let moon = Astro.moon(date: date, latitude: spot.latitude, longitude: spot.longitude)
        #expect(StarVisibility.level(darkness: StarVisibility.skyDarkness(spot: spot, moon: moon)) == .city)
    }

    @Test func opacityFollowsTwilight() {
        #expect(StarVisibility.opacity(sunAltitude: 10) == 0)
        #expect(StarVisibility.opacity(sunAltitude: -30) == 1)
        let mid = StarVisibility.opacity(sunAltitude: -12)
        #expect(mid > 0 && mid < 1)
    }
}
