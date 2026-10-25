import Foundation
import Testing
@testable import StarCore

@Suite struct ObserverCameraFlightTests {
    let start = ObserverCameraFlight.overviewPose(yaw: .pi / 5, pitch: 0.35, distanceMeters: 1_000)
    let target = HorizontalCoord(altitude: 57, azimuth: 135)

    @Test func startsAtOriginalOverviewAndEndsAtTheEye() {
        let flight = ObserverCameraFlight(start: start, target: target)
        #expect(flight.pose(progress: 0) == start)
        #expect(flight.pose(progress: -1) == start)
        let end = flight.pose(progress: 1)
        #expect(end.position == LocalVector(east: 0, north: 0, up: 0))
        #expect(abs(end.direction.dot(LocalVector(target)) - 1) < 1e-10)
        #expect(flight.pose(progress: 2) == end)
    }

    @Test func approachesObservationPositionBeforeLookingUp() {
        let flight = ObserverCameraFlight(start: start, target: target)
        let near = flight.pose(progress: ObserverCameraFlight.approachFraction)
        #expect(abs(hypot(near.position.east, near.position.north) - 8) < 1e-9)
        #expect(near.position.up == 2.5)
        #expect(near.direction.up < 0)
        #expect(flight.pose(progress: 0.95).direction.up > 0)
    }

    @Test func stagesJoinWithoutJumping() {
        let flight = ObserverCameraFlight(start: start, target: target)
        let before = flight.pose(progress: ObserverCameraFlight.approachFraction - 0.000001)
        let after = flight.pose(progress: ObserverCameraFlight.approachFraction + 0.000001)
        #expect(before.position.minus(after.position).dot(before.position.minus(after.position)) < 1e-10)
        #expect(before.direction.dot(after.direction) > 0.999999)
    }

    @Test func directionsAreFiniteUnitVectorsThroughoutFlight() {
        for azimuth in [0.0, 90.0, 180.0, 270.0, 359.0] {
            let flight = ObserverCameraFlight(start: start, target: HorizontalCoord(altitude: 85, azimuth: azimuth))
            for step in 0...100 {
                let pose = flight.pose(progress: Double(step) / 100)
                #expect(abs(pose.direction.dot(pose.direction) - 1) < 1e-9)
                #expect(pose.position.up >= 0)
                #expect(pose.position.east.isFinite && pose.position.north.isFinite)
            }
        }
    }

    @Test func movingOnTheSameVerticalAxisHasAStableApproach() {
        let vertical = ObserverCameraPose(position: LocalVector(east: 0, north: 0, up: 500),
                                          direction: LocalVector(east: 0, north: 0, up: -1))
        let flight = ObserverCameraFlight(start: vertical, target: target)
        #expect(flight.pose(progress: .nan) == vertical)
        #expect(flight.pose(progress: 0.7).position.north == -8)
    }
}
