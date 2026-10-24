import Testing
@testable import StarCore

@Suite struct DistanceTests {
    @Test func shibuyaToKasaiRinkaiPark() {
        // 渋谷駅東口 → 葛西臨海公園（地図上の直線距離 ≈ 14.4 km）
        let km = Distance.greatCircleKm(fromLatitude: 35.6585, fromLongitude: 139.7030,
                                        toLatitude: 35.6430, toLongitude: 139.8610)
        #expect(abs(km - 14.4) < 0.1)
    }

    @Test func tokyoToShinjuku() {
        // 東京駅 → 新宿駅（≈ 6.1 km）
        let km = Distance.greatCircleKm(fromLatitude: 35.6812, fromLongitude: 139.7671,
                                        toLatitude: 35.6896, toLongitude: 139.7006)
        #expect(abs(km - 6.1) < 0.1)
    }

    @Test func samePointIsZeroAndSymmetric() {
        #expect(Distance.greatCircleKm(fromLatitude: 35.68, fromLongitude: 139.77,
                                       toLatitude: 35.68, toLongitude: 139.77) == 0)
        let ab = Distance.greatCircleKm(fromLatitude: 35.6, fromLongitude: 139.7, toLatitude: 35.7, toLongitude: 139.8)
        let ba = Distance.greatCircleKm(fromLatitude: 35.7, fromLongitude: 139.8, toLatitude: 35.6, toLongitude: 139.7)
        #expect(abs(ab - ba) < 1e-9)
    }

    @Test func antipodesIsHalfCircumference() {
        let km = Distance.greatCircleKm(fromLatitude: 0, fromLongitude: 0, toLatitude: 0, toLongitude: 180)
        #expect(abs(km - Distance.earthRadiusKm * .pi) < 1e-6)
    }

    @Test func labels() {
        #expect(Distance.label(km: 0.234) == "230 m")
        #expect(Distance.label(km: 3.24) == "3.2 km")
        #expect(Distance.label(km: 14.4) == "14 km")
    }
}
