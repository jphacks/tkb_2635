import Foundation
import Testing
@testable import StarCore

@Suite struct SurroundingsTests {
    private func building(_ id: String, x: Double = 0, y: Double = 0, usage: String?) -> Building {
        Building(id: id, name: id, x: x, y: y, width: 10, depth: 10, height: 10, usage: usage)
    }

    private func scene(_ buildings: [Building]) -> CityScene {
        CityScene(id: "test", name: "テスト", originLatitude: 35.68, originLongitude: 139.7,
                  groundElevation: 0, source: "テスト用", buildings: buildings)
    }

    /// 用途ごとの棟数を指定して、原点付近に建物を並べる
    private func buildings(_ counts: [(String?, Int)]) -> [Building] {
        counts.flatMap { usage, count in
            (0..<count).map { building("\(usage ?? "nil")_\($0)", x: Double($0), usage: usage) }
        }
    }

    @Test func countsGroupsAndFractions() {
        let summary = Surroundings.summarize(
            scene: scene(buildings([("業務施設", 8), ("商業施設", 5), ("住宅", 4), ("共同住宅", 1), ("文教厚生施設", 2)])),
            east: 0, north: 0)
        #expect(summary.buildingCount == 20)
        #expect(!summary.isInsufficient)
        #expect(summary.shares.map(\.group) == [.commercial, .residential, .publicCultural])
        #expect(summary.shares.map(\.count) == [13, 5, 2])
        #expect(abs(summary.shares[0].fraction - 0.65) < 1e-9)
        #expect(summary.shares.map(\.percent) == [65, 25, 10])
        #expect(summary.headline == "周辺: 商業・業務施設が多い（商業・業務 65%・住宅 25%）")
    }

    @Test func nilAndUnknownUsageAreOtherButNotHeadline() {
        let summary = Surroundings.summarize(
            scene: scene(buildings([(nil, 6), ("不明", 4), ("見たことのない用途", 2), ("住宅", 5), ("運輸倉庫施設", 3)])),
            east: 0, north: 0)
        #expect(LandUseGroup(usage: nil) == .otherOrUnknown)
        #expect(summary.shares.first?.group == .otherOrUnknown)
        #expect(summary.shares.first?.count == 12)
        // その他・不明が最多でも、一言は分かる用途で作る
        #expect(summary.headline == "周辺: 住宅が多い（住宅 25%・工場・倉庫 15%）")
    }

    @Test func allUnknownStillProducesHeadline() {
        let summary = Surroundings.summarize(scene: scene(buildings([(nil, 20)])), east: 0, north: 0)
        #expect(summary.headline == "周辺: 用途不明の建物が多い（その他・不明 100%）")
    }

    @Test func fewerThanMinimumIsInsufficient() {
        let summary = Surroundings.summarize(scene: scene(buildings([("住宅", 19)])), east: 0, north: 0)
        #expect(summary.buildingCount == 19)
        #expect(summary.isInsufficient)
        #expect(summary.headline == "周辺: 建物データ不足")
    }

    @Test func radiusBoundaryIsInclusiveAtExactly300m() {
        let inside = buildings([("住宅", 19)]) + [building("edge", x: 300, usage: "商業施設")]
        let atEdge = Surroundings.summarize(scene: scene(inside), east: 0, north: 0)
        #expect(atEdge.buildingCount == 20)
        #expect(atEdge.shares.contains { $0.group == .commercial })

        let outside = buildings([("住宅", 19)]) + [building("far", y: -300.01, usage: "商業施設")]
        let beyond = Surroundings.summarize(scene: scene(outside), east: 0, north: 0)
        #expect(beyond.buildingCount == 19)
        #expect(beyond.isInsufficient)
    }

    @Test func spotWithoutSceneIsInsufficient() throws {
        let contexts = try SeedData.loadContexts()
        let park = try #require(contexts.first { $0.scene == nil })
        let summary = Surroundings.summarize(park)
        #expect(summary.buildingCount == nil)
        #expect(summary.isInsufficient)
    }

    @Test func realPlateauSceneGivesHeadlineForShibuya() throws {
        let contexts = try SeedData.loadContexts()
        let plaza = try #require(contexts.first { $0.id == "shibuya_east_plaza" })
        let summary = Surroundings.summarize(plaza)
        #expect((summary.buildingCount ?? 0) >= Surroundings.minimumBuildingCount)
        #expect(summary.headline.hasPrefix("周辺: "))
        #expect(summary.headline.contains("が多い（"))
        // 西新宿も PLATEAU から作ったので（2-05）、周辺の用途が出る
        let central = try #require(contexts.first { $0.id == "shinjuku_central_park" })
        #expect(!Surroundings.summarize(central).isInsufficient)
    }
}
