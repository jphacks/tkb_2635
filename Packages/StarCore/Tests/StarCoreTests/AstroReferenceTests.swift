import Foundation
import Testing
@testable import StarCore

/// skyfield（JPL DE421）で計算した参照値（scripts/verify_astro.py が生成）と全件で見比べる（3-03）
@Suite struct AstroReferenceTests {
    /// 許容誤差 [度]。根拠と結果は docs/astro/verification.md
    static let moonTolerance = 0.5
    static let moonFractionTolerance = 0.01
    /// 3-03 の完了条件：月の高度・方位の差がそれぞれ 1° 以内。
    /// 方位の差は空の上での距離（方位差 × cos 高度）で測る。真上の近くでは方位の数字そのものが大きく振れるため
    static let moonAltAzTolerance = 1.0
    static let sunTolerance = 0.1
    /// 歳差は補正済み（3-06）。章動・光行差の分（0.01° 程度）が残る
    static let starTolerance = 0.1
    /// 位置を比べるのは、参照値で地平線より上にある件だけ。
    /// 地平線の約 1° 下で大気差の計算を打ち切る位置が実装ごとに少し違い、そこで最大 0.7° の段差が出るため
    /// （地平線より下の天体はアプリでは「見えない」扱いなので、この差は結果に影響しない）
    static let minimumAltitude = 0.0

    struct Fixture: Decodable {
        struct Observer: Decodable { var id: String; var latitude: Double; var longitude: Double }
        struct Position: Decodable { var altitude: Double; var azimuth: Double; var illuminatedFraction: Double? }
        struct Sample: Decodable {
            var observer: String
            var time: Date
            var moon: Position
            var sun: Position
            var stars: [String: Position]
        }
        var observers: [Observer]
        var samples: [Sample]
    }

    /// 誤差の最大・平均を集める
    struct Stats: CustomStringConvertible {
        var unit = "°"
        var max = 0.0, sum = 0.0, count = 0, worst = ""
        mutating func add(_ error: Double, at label: String) {
            if error > max { max = error; worst = label }
            sum += error
            count += 1
        }
        var mean: Double { count == 0 ? 0 : sum / Double(count) }
        var description: String {
            String(format: "最大 %.4f%@（%@）, 平均 %.4f%@, %d 件", max, unit, worst, mean, unit, count)
        }
    }

    static func loadFixture() throws -> Fixture {
        let url = try #require(Bundle.module.url(forResource: "astro_reference", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Fixture.self, from: Data(contentsOf: url))
    }

    static func observers(_ fixture: Fixture) -> [String: Fixture.Observer] {
        Dictionary(uniqueKeysWithValues: fixture.observers.map { ($0.id, $0) })
    }

    static func coord(_ p: Fixture.Position) -> HorizontalCoord {
        HorizontalCoord(altitude: p.altitude, azimuth: p.azimuth)
    }

    @Test func fixtureHasEnoughSamples() throws {
        let fixture = try Self.loadFixture()
        #expect(fixture.samples.count >= 300)
        // 地平線より上の件が少なすぎると、比べた意味がなくなる
        #expect(fixture.samples.filter { $0.moon.altitude >= Self.minimumAltitude }.count >= 100)
    }

    @Test func moonMatchesSkyfield() throws {
        let fixture = try Self.loadFixture()
        let sites = Self.observers(fixture)
        var position = Stats(), altitude = Stats(), azimuth = Stats(), rawAzimuth = Stats(), fraction = Stats(unit: "")
        for s in fixture.samples {
            let site = try #require(sites[s.observer])
            let moon = Astro.moon(date: s.time, latitude: site.latitude, longitude: site.longitude)
            let label = "\(s.observer) \(s.time)"
            if s.moon.altitude >= Self.minimumAltitude {
                position.add(Astro.separation(moon.position, Self.coord(s.moon)), at: label)
                altitude.add(abs(moon.position.altitude - s.moon.altitude), at: label)
                let dAz = Angle.normalize(moon.position.azimuth - s.moon.azimuth + 180) - 180
                rawAzimuth.add(abs(dAz), at: label)
                azimuth.add(abs(dAz) * cos(s.moon.altitude * .pi / 180), at: label)
            }
            let expected = try #require(s.moon.illuminatedFraction)
            fraction.add(abs(moon.illuminatedFraction - expected), at: label)
        }
        print("月の位置: \(position)")
        print("月の高度差: \(altitude)")
        print("月の方位差（空の上での距離）: \(azimuth)")
        print("月の方位差（方位の数字そのもの）: \(rawAzimuth)")
        print("月の輝面比: \(fraction)")
        #expect(position.max <= Self.moonTolerance, "月の位置の誤差 \(position)")
        #expect(altitude.max <= Self.moonAltAzTolerance, "月の高度差 \(altitude)")
        #expect(azimuth.max <= Self.moonAltAzTolerance, "月の方位差 \(azimuth)")
        #expect(fraction.max <= Self.moonFractionTolerance, "月の輝面比の誤差 \(fraction)")
    }

    @Test func sunMatchesSkyfield() throws {
        let fixture = try Self.loadFixture()
        let sites = Self.observers(fixture)
        var stats = Stats()
        for s in fixture.samples {
            let site = try #require(sites[s.observer])
            let sun = Astro.sun(date: s.time, latitude: site.latitude, longitude: site.longitude)
            if s.sun.altitude >= Self.minimumAltitude {
                stats.add(Astro.separation(sun, Self.coord(s.sun)), at: "\(s.observer) \(s.time)")
            }
        }
        print("太陽: \(stats)")
        #expect(stats.max <= Self.sunTolerance, "太陽の誤差 \(stats)")
    }

    @Test func starsMatchSkyfield() throws {
        let fixture = try Self.loadFixture()
        let sites = Self.observers(fixture)
        var perStar: [String: Stats] = [:]
        for s in fixture.samples {
            let site = try #require(sites[s.observer])
            for (id, expected) in s.stars where expected.altitude >= Self.minimumAltitude {
                let star = try #require(StarCatalog.star(id: id))
                let actual = Astro.star(star, date: s.time, latitude: site.latitude, longitude: site.longitude)
                perStar[id, default: Stats()].add(Astro.separation(actual, Self.coord(expected)), at: "\(s.observer) \(s.time)")
            }
        }
        for (id, stats) in perStar.sorted(by: { $0.key < $1.key }) {
            print("恒星 \(id): \(stats)")
            #expect(stats.max <= Self.starTolerance, "恒星 \(id) の誤差 \(stats)")
        }
        #expect(perStar.count == 6)
    }

    /// 北極星は天の北極に近く、歳差の影響が最も大きい。2026-10-24 の値を個別に確かめる
    @Test func polarisMatchesSkyfieldOnDemoDay() throws {
        let fixture = try Self.loadFixture()
        let sites = Self.observers(fixture)
        let polaris = try #require(StarCatalog.star(id: "polaris"))
        let dayEnd = try #require(ISO8601DateFormatter().date(from: "2026-10-25T00:00:00Z"))
        let samples = fixture.samples.filter { $0.time < dayEnd }
        #expect(samples.count == 8)
        for s in samples {
            let site = try #require(sites[s.observer])
            let expected = try #require(s.stars["polaris"])
            let actual = Astro.star(polaris, date: s.time, latitude: site.latitude, longitude: site.longitude)
            let error = Astro.separation(actual, Self.coord(expected))
            #expect(error <= Self.starTolerance, "北極星 \(s.observer) \(s.time): \(error)°")
        }
    }
}
