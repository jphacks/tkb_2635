import Foundation
import Testing
@testable import StarCore

@Suite struct CurrentObservationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func locationQualityRejectsStaleAndInaccurateReadings() throws {
        try fix().validate(now: now)
        for accuracy in [-1.0, 25.1, .infinity, .nan] {
            #expect(throws: ObservationLocationError.self) { try fix(accuracy: accuracy).validate(now: now) }
        }
        for age in [-61.0, 61.0, .infinity] {
            #expect(throws: ObservationLocationError.self) { try fix(age: age).validate(now: now) }
        }
        #expect(throws: ObservationLocationError.self) { try fix(latitude: .nan).validate(now: now) }
        #expect(throws: ObservationLocationError.self) { try fix(latitude: 91).validate(now: now) }
    }

    @Test func elevationInterpolatesAndDoesNotInventMissingValues() {
        let grid = ObservationElevationGrid(minEast: 0, minNorth: 0, step: 10,
                                            columns: 2, rows: 2, values: [0, 10, 20, 30])
        #expect(grid.elevation(east: 5, north: 5) == 15)
        #expect(grid.elevation(east: 10, north: 10) == 30)
        #expect(grid.elevation(east: -0.01, north: 5) == nil)
        #expect(grid.elevation(east: .nan, north: 5) == nil)
        let missing = ObservationElevationGrid(minEast: 0, minNorth: 0, step: 10,
                                               columns: 2, rows: 2, values: [0, nil, 20, 30])
        #expect(missing.elevation(east: 5, north: 5) == nil)
        #expect(missing.elevation(east: 0, north: 0) == 0)
        let malformed = ObservationElevationGrid(minEast: 0, minNorth: 0, step: 0,
                                                 columns: 2, rows: 2, values: [])
        #expect(malformed.elevation(east: 0, north: 0) == nil)
    }

    @Test func movingObserverChangesObstructionWithoutMovingTheCity() throws {
        let region = region()
        let scene = try scene()
        let first = try region.context(at: fix(), scene: scene, now: now)
        let moved = try region.context(at: fix(east: 30), scene: scene, now: now)
        #expect(first.spot.longitude != moved.spot.longitude)
        #expect(first.scene?.buildings.first?.x == moved.scene?.buildings.first?.x)
        #expect(moved.horizon.elevation(at: 90) > first.horizon.elevation(at: 90) + 15)
        #expect(first.spot.floorElevation == 15)
        #expect(first.spot.observerElevation == 16.5)
        #expect(first.spot.hostBuildingId == nil)
        #expect(first.spot.lastVerifiedAt == nil)
        #expect(first.spot.localGlareLevel == nil)
        #expect(first.spot.regionalLightIndex == nil)
        #expect(!first.spot.directionMaskVerified)
    }

    @Test func rejectsOutOfRangeAndIndoorPositions() throws {
        let region = region()
        let scene = try scene()
        #expect(!region.contains(latitude: .nan, longitude: 139))
        #expect(throws: ObservationLocationError.outsideRegion) {
            try region.context(at: fix(east: 250), scene: scene, now: now)
        }
        #expect(throws: ObservationLocationError.insideBuilding) {
            try region.context(at: fix(east: 50), scene: scene, now: now)
        }
        var other = scene
        other.id = "other"
        #expect(throws: ObservationLocationError.missingScene) {
            try region.context(at: fix(), scene: other, now: now)
        }
    }

    @Test func slopeChangesEyeElevationAndTerrainAlsoObstructsTheSky() throws {
        let rising = ObservationElevationGrid(minEast: -4_000, minNorth: -4_000, step: 8_000,
                                              columns: 2, rows: 2, values: [0, 800, 0, 800])
        let angles = try #require(rising.horizon(east: 0, north: 0, eyeElevation: 401.5))
        #expect(angles[90] > 5)
        #expect(angles[270] == 0)
        let empty = ObservationElevationGrid(minEast: -4_000, minNorth: -4_000, step: 8_000,
                                             columns: 2, rows: 2, values: [nil, nil, nil, nil])
        #expect(empty.horizon(east: 0, north: 0, eyeElevation: 0) == nil)
    }

    @Test func bundledShibuyaSampleUsesItsOwnCoordinatesAndGround() throws {
        let regions = try ObservationRegion.loadBundled()
        let region = try #require(regions.first)
        let scenes = try SeedData.loadScenes()
        let scene = try #require(scenes.first { $0.id == region.sceneId })
        let sample = ObservationLocationFix(latitude: region.sampleLatitude, longitude: region.sampleLongitude,
                                             horizontalAccuracy: 0, timestamp: now)
        let context = try region.context(at: sample, scene: scene, now: now)
        #expect(context.spot.latitude == sample.latitude)
        #expect(context.spot.longitude == sample.longitude)
        #expect(context.horizon.samples.allSatisfy { $0.isFinite })
        #expect(context.spot.floorElevationSource != nil)
        #expect(context.scene?.observerViewEnabled == true)
        #expect(!region.contains(latitude: 35.6812, longitude: 139.7671))
        let second = try region.context(at: sample, scene: scene, now: now)
        #expect(context.horizon.samples == second.horizon.samples)
    }

    private func fix(east: Double = 0, accuracy: Double = 5, age: Double = 0, latitude: Double = 35.658) -> ObservationLocationFix {
        ObservationLocationFix(latitude: latitude,
                               longitude: 139.7016 + east / (111_320 * cos(35.658 * .pi / 180)),
                               horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(-age))
    }

    private func region() -> ObservationRegion {
        let grid = ObservationElevationGrid(minEast: -4_000, minNorth: -4_000, step: 8_000,
                                            columns: 2, rows: 2, values: [15, 15, 15, 15])
        return ObservationRegion(id: "test", name: "試験地域", sceneId: "test",
                                 latitude: 35.658, longitude: 139.7016,
                                 selectionRadius: 200, buildingRadius: 500, elevationSource: "fixture",
                                 elevationSourceURL: URL(string: "https://example.com")!, generatedAt: "2026-10-25",
                                 surface: grid, terrain: grid, sampleLatitude: 35.658, sampleLongitude: 139.7016)
    }

    private func scene() throws -> CityScene {
        let json = #"{"id":"test","name":"試験地域","originLatitude":35.658,"originLongitude":139.7016,"groundElevation":15,"source":"fixture","observerViewEnabled":true,"buildings":[{"id":"tower","name":"試験の建物","x":50,"y":0,"width":10,"depth":10,"height":30}]}"#
        return try JSONDecoder().decode(CityScene.self, from: Data(json.utf8))
    }
}
