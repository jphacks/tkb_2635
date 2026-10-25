import Foundation
import Testing
@testable import StarCore

@Suite struct SpotViewingConditionsTests {
    private let date = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!

    private func observatory() throws -> Spot {
        try #require(try SeedData.loadSpots().first { $0.id == "tocho_observatory" })
    }

    @Test func confirmedWindowRangeChangesRecommendation() throws {
        var spot = try observatory()
        spot.maxVisibleAltitude = nil
        spot.directionMaskVerified = true
        let moon = Astro.moon(date: date, latitude: spot.latitude, longitude: spot.longitude).position
        spot.viewingDirectionMask = [AzimuthRange(from: moon.azimuth - 1, to: moon.azimuth + 1)]
        let allowed = Recommender.evaluate(SpotContext(spot: spot, scene: nil), target: .moon, date: date, weather: nil)
        #expect(allowed.geometricVisibility)
        #expect(!allowed.blockedByDirectionMask)
        #expect(!allowed.dataQualityFlags.contains(.directionMaskUnverified))

        spot.viewingDirectionMask = [AzimuthRange(from: moon.azimuth + 10, to: moon.azimuth + 20)]
        let blocked = Recommender.evaluate(SpotContext(spot: spot, scene: nil), target: .moon, date: date, weather: nil)
        #expect(blocked.blockedByDirectionMask)
        #expect(!blocked.geometricVisibility)
        #expect(blocked.tier == .notVisible)
        #expect(blocked.recommendationReasons.contains { $0.contains("窓や屋根") })
    }

    @Test func indoorFlagAloneDoesNotVerifyUnknownWindows() throws {
        var spot = try observatory()
        spot.directionMaskVerified = true
        spot.viewingDirectionMask = nil
        #expect(!spot.hasVerifiedViewingDirections)
        spot.viewingDirectionMask = []
        #expect(!spot.hasVerifiedViewingDirections)
        let prediction = Recommender.evaluate(SpotContext(spot: spot, scene: nil), target: .moon, date: date, weather: nil)
        #expect(prediction.dataQualityFlags.contains(.directionMaskUnverified))
    }

    @Test func windowHeightAndMultipleRanges() throws {
        var spot = try observatory()
        spot.viewingDirectionMask = [AzimuthRange(from: 330, to: 30), AzimuthRange(from: 100, to: 160)]
        spot.maxVisibleAltitude = 35
        #expect(!spot.isBlockedByViewingLimits(azimuth: 350, altitude: 35))
        #expect(!spot.isBlockedByViewingLimits(azimuth: 0, altitude: 20))
        #expect(!spot.isBlockedByViewingLimits(azimuth: 130, altitude: 20))
        #expect(spot.isBlockedByViewingLimits(azimuth: 130, altitude: 35.1))
        #expect(spot.isBlockedByViewingLimits(azimuth: 270, altitude: 20))
    }

    @Test func allAroundAndBoundaryAngles() {
        let full = AzimuthRange(from: 0, to: 360)
        for angle in [0.0, 90, 180, 270, 359.9, -90] { #expect(full.contains(angle)) }
        let north = AzimuthRange(from: 330, to: 30)
        for angle in [330.0, 0, 30, 360, -30] { #expect(north.contains(angle)) }
        #expect(!north.contains(30.1))
        #expect(!north.contains(.nan))
    }

    @Test func tochoRemainsUnverifiedUntilAnglesAreMeasured() throws {
        let spot = try observatory()
        #expect(!spot.directionMaskVerified)
        #expect(spot.viewingDirectionMask == nil)
        #expect(spot.viewingDirectionSummary == "未確認")
        #expect(spot.viewingDirectionNotes?.contains("北東・南東・南西・西") == true)
    }
}
