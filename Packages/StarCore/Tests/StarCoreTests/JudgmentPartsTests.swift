import Foundation
import Testing
@testable import StarCore

/// 4-13: 遮蔽判定を LOD2 の形から作った部分の箱で行い、実形状の 3D と食い違わないこと
@Suite struct JudgmentPartsTests {
    private func shibuya(_ spotId: String) throws -> SpotContext {
        try #require(try SeedData.loadContexts().first { $0.id == spotId })
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    @Test func partDecodesFromCompactArrayAndRoundTrips() throws {
        let json = #"{"id":"b","name":"b","x":0,"y":0,"width":10,"depth":10,"height":50,"parts":[[1,2,3,4,50]]}"#
        let building = try JSONDecoder().decode(Building.self, from: Data(json.utf8))
        #expect(building.judgmentParts == [BuildingPart(x: 1, y: 2, width: 3, depth: 4, height: 50)])
        let again = try JSONDecoder().decode(Building.self, from: JSONEncoder().encode(building))
        #expect(again.parts == building.parts)
        let malformed = #"{"id":"b","name":"b","x":0,"y":0,"width":10,"depth":10,"height":50,"parts":[[1,2,3,4]]}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Building.self, from: Data(malformed.utf8)) }
    }

    @Test func buildingWithoutPartsUsesItsWholeBox() {
        let b = Building(id: "b", name: "b", x: 5, y: 6, width: 7, depth: 8, height: 9, usage: nil)
        #expect(b.judgmentParts == [BuildingPart(x: 5, y: 6, width: 7, depth: 8, height: 9)])
    }

    /// 斜めの塔は外接直方体だと基壇の上まで高い壁になる。部分の箱なら塔の脇を通る方位は空く
    @Test func slantedTowerLeavesTheGapOpen() {
        // 斜めに並ぶ 3 つの高い部分（x = -5〜15）と、その東の低い基壇（x = 15〜25）
        let parts = [BuildingPart(x: 0, y: 40, width: 10, depth: 10, height: 100),
                     BuildingPart(x: 5, y: 50, width: 10, depth: 10, height: 100),
                     BuildingPart(x: 10, y: 60, width: 10, depth: 10, height: 100),
                     BuildingPart(x: 20, y: 40, width: 10, depth: 10, height: 5)]
        var tower = Building(id: "t", name: "塔", x: 10, y: 50, width: 30, depth: 30, height: 100, usage: nil)
        let boxOnly = HorizonProfile.compute(observerEast: 20, observerNorth: 0, eyeElevation: 1.5,
                                             groundElevation: 0, buildings: [tower])
        tower.parts = parts
        let withParts = HorizonProfile.compute(observerEast: 20, observerNorth: 0, eyeElevation: 1.5,
                                               groundElevation: 0, buildings: [tower])
        // 真北（基壇の上）は、外接直方体では塔の高さで隠れるが、部分の箱では基壇だけ（目より少し高い）
        #expect(boxOnly.samples[0] > 60)
        #expect(withParts.samples[0] < 10)
    }

    /// 方位ごとの遮蔽仰角の回帰（渋谷駅東口 地上）。PLATEAU から作り直したら、Blender で 3D から測った値と比べて更新する
    @Test(arguments: [(63, 21.337), (105, 31.596), (127, 9.768), (152, 64.631), (300, 81.572)])
    func groundHorizonAtRepresentativeAzimuths(azimuth: Int, expected: Double) throws {
        let ground = try shibuya("shibuya_east_plaza")
        #expect(abs(ground.horizon.samples[azimuth] - expected) < 0.01, "方位 \(azimuth)°: \(ground.horizon.samples[azimuth])")
    }

    /// b-1 で見つかったずれ（10/25 21:00 の地上は、計算では隠れるが 3D では見える）が解消し、計算も「見える」になる
    @Test func groundMoonAt2026_10_25_2100IsVisibleLikeThe3D() throws {
        let p = Recommender.evaluate(try shibuya("shibuya_east_plaza"), target: .moon,
                                     date: date("2026-10-25T12:00:00Z"), weather: nil)
        #expect(abs(p.azimuth - 127.4) < 0.5)
        #expect(p.obstructionElevation < 15)
        #expect(p.geometricVisibility)
    }

    /// デモに使える時刻（4-03 の条件）。地上は隠れ、SHIBUYA SKY は見える
    @Test(arguments: ["2026-10-24T12:00:00Z", "2026-10-29T11:00:00Z", "2026-10-30T12:00:00Z"])
    func demoTimesStillSeparateGroundAndSky(time: String) throws {
        let g = Recommender.evaluate(try shibuya("shibuya_east_plaza"), target: .moon, date: date(time), weather: nil)
        let s = Recommender.evaluate(try shibuya("shibuya_sky"), target: .moon, date: date(time), weather: nil)
        #expect(g.altitude > 0)
        #expect(!g.geometricVisibility)
        #expect(s.geometricVisibility)
    }
}
