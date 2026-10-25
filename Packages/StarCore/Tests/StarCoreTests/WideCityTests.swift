import Testing
@testable import StarCore

@Suite struct WideCityTests {
    @Test func originIsZero() {
        let p = WideCity.localPosition(latitude: WideCity.originLatitude, longitude: WideCity.originLongitude)
        #expect(p.east == 0 && p.north == 0)
    }

    @Test func matchesShinjukuScene() {
        // 西新宿シーンの原点は、渋谷の原点から西に約 895m、北に約 3,494m（o-5 で都庁の位置が重なることを確かめた値）
        let p = WideCity.localPosition(latitude: 35.6896, longitude: 139.6917)
        #expect(abs(p.east - -895.4) < 1)
        #expect(abs(p.north - 3_494.1) < 1)
    }

    @Test func wardCodeFromFileName() {
        #expect(WideCity.wardCode(fromBoxFile: "Wide_13104") == "13104")
        #expect(WideCity.wardCode(fromBoxFile: "Wide2_13104") == nil)
        #expect(WideCity.wardCode(fromBoxFile: "Wide_") == nil)
        #expect(WideCity.wardCode(fromBoxFile: "City_shinjuku") == nil)
    }

    private let wards = [
        WideCity.WardBounds(code: "a", minEast: 0, maxEast: 100, minNorth: 0, maxNorth: 100),
        WideCity.WardBounds(code: "b", minEast: 100, maxEast: 200, minNorth: 0, maxNorth: 100),
        WideCity.WardBounds(code: "c", minEast: 300, maxEast: 400, minNorth: 0, maxNorth: 100),
        WideCity.WardBounds(code: "d", minEast: 0, maxEast: 100, minNorth: 1_000, maxNorth: 1_100),
    ]

    @Test func distanceIsZeroInside() {
        #expect(wards[0].distance(east: 50, north: 50) == 0)
        #expect(wards[0].distance(east: 103, north: 104) == 5)
    }

    @Test func nearestWardsInOrderAndLimited() {
        #expect(WideCity.nearestWards(wards, east: 50, north: 50, limit: 3, maxDistance: 10_000) == ["a", "b", "c"])
        #expect(WideCity.nearestWards(wards, east: 350, north: 50, limit: 2, maxDistance: 10_000) == ["c", "b"])
    }

    @Test func farWardsAreLeftOut() {
        #expect(WideCity.nearestWards(wards, east: 50, north: 50, limit: 3, maxDistance: 150) == ["a", "b"])
        #expect(WideCity.nearestWards(wards, east: 50, north: 50, limit: 0, maxDistance: 150).isEmpty)
    }
}
