import Foundation
import Testing
@testable import StarCore

@Suite struct ObserverViewpointTests {
    @Test(arguments: [0.0, 90.0, 180.0, 270.0])
    func looksTowardCardinalDirection(azimuth: Double) {
        let view = ObserverViewpoint(target: HorizontalCoord(altitude: 0, azimuth: azimuth))
        #expect(abs(view.direction.east - sin(azimuth * .pi / 180)) < 1e-10)
        #expect(abs(view.direction.north - cos(azimuth * .pi / 180)) < 1e-10)
        #expect(abs(view.direction.up) < 1e-10)
    }

    @Test func draggingCrossesNorthAndStopsBeforeVertical() {
        let view = ObserverViewpoint(target: HorizontalCoord(altitude: 20, azimuth: 350))
        let moved = view.turned(horizontal: 30, vertical: 100)
        #expect(moved.azimuth == 20)
        #expect(moved.altitude == ObserverViewpoint.altitudeLimit)
        #expect(view.turned(horizontal: -370, vertical: -200).azimuth == 340)
        #expect(view.turned(horizontal: -370, vertical: -200).altitude == -ObserverViewpoint.altitudeLimit)
        #expect(abs(moved.direction.dot(moved.direction) - 1) < 1e-10)
    }

    @Test func zoomKeepsDirectionAndHasLimits() {
        let view = ObserverViewpoint(target: HorizontalCoord(altitude: 57, azimuth: 155))
        let zoomed = view.zoomed(magnification: 2)
        #expect(zoomed.fieldOfView == 27.5)
        #expect(zoomed.direction == view.direction)
        #expect(view.zoomed(magnification: 100).fieldOfView == 25)
        #expect(view.zoomed(magnification: 0.01).fieldOfView == 80)
        #expect(view.zoomed(magnification: 0) == view)
        #expect(view.turned(horizontal: .nan, vertical: 0) == view)
    }

    @Test func shibuyaDemoHasDifferentObstructionAtTheTwoEyeHeights() throws {
        let contexts = try SeedData.loadContexts()
        let ground = try #require(contexts.first { $0.id == "shibuya_east_plaza" })
        let sky = try #require(contexts.first { $0.id == "shibuya_sky" })
        let date = try #require(ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z"))
        let groundPrediction = Recommender.evaluate(ground, target: .moon, date: date, weather: nil)
        let skyPrediction = Recommender.evaluate(sky, target: .moon, date: date, weather: nil)
        let view = ObserverViewpoint(target: HorizontalCoord(altitude: groundPrediction.altitude,
                                                            azimuth: groundPrediction.azimuth))
        #expect(ground.scene?.observerViewEnabled == true)
        #expect(sky.scene?.observerViewEnabled == true)
        // 床は国土地理院 DEM の 14.8m（2-06）
        #expect(abs(ground.spot.observerElevation - 16.3) < 1e-9)
        #expect(sky.spot.observerElevation == 245.5)
        #expect(!groundPrediction.geometricVisibility)
        #expect(skyPrediction.geometricVisibility)
        #expect(abs(view.direction.up - sin(groundPrediction.altitude * .pi / 180)) < 1e-10)
        // 高さを切り替えても同じ方位・仰角で見比べられる（地点間の月の方向差はごく小さい）。
        #expect(abs(groundPrediction.altitude - skyPrediction.altitude) < 0.01)
        #expect(abs(groundPrediction.azimuth - skyPrediction.azimuth) < 0.01)
    }

    @Test func existingSceneJSONStillDecodesWithoutObserverFlag() throws {
        let json = #"{"id":"old","name":"既存地点","originLatitude":35,"originLongitude":139,"groundElevation":0,"source":"test","buildings":[]}"#
        let scene = try JSONDecoder().decode(CityScene.self, from: Data(json.utf8))
        #expect(scene.observerViewEnabled == nil)
    }
}
