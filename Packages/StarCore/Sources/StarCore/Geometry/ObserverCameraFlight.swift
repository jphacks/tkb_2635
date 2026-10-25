import Foundation

/// 観測者の目を原点にしたカメラ位置 [m] と、見る方向の単位ベクトル。
public struct ObserverCameraPose: Equatable, Sendable {
    public let position: LocalVector
    public let direction: LocalVector

    public init(position: LocalVector, direction: LocalVector) {
        self.position = position
        self.direction = direction
    }
}

/// 街全体から観測位置へ近づき、その場で空を見上げる2段階の移動。
public struct ObserverCameraFlight: Sendable {
    public static let duration = 2.8
    public static let approachFraction = 0.7
    private static let approachDistanceMeters = 8.0
    private static let approachHeightMeters = 2.5
    private static let overviewFocusHeightMeters = 120.0

    private let start: ObserverCameraPose
    private let waypoint: LocalVector
    private let target: HorizontalCoord
    private static let zero = LocalVector(east: 0, north: 0, up: 0)

    public init(start: ObserverCameraPose, target: HorizontalCoord) {
        self.start = start
        self.target = HorizontalCoord(altitude: ObserverViewpoint(target: target).altitude,
                                      azimuth: ObserverViewpoint(target: target).azimuth)
        let horizontal = hypot(start.position.east, start.position.north)
        let east = horizontal > 0 ? start.position.east / horizontal : 0
        let north = horizontal > 0 ? start.position.north / horizontal : -1
        waypoint = LocalVector(east: east * Self.approachDistanceMeters,
                              north: north * Self.approachDistanceMeters, up: Self.approachHeightMeters)
    }

    public static func overviewPose(yaw: Double, pitch: Double, distanceMeters: Double) -> ObserverCameraPose {
        let position = LocalVector(east: sin(yaw) * cos(pitch) * distanceMeters,
                                   north: -cos(yaw) * cos(pitch) * distanceMeters,
                                   up: sin(pitch) * distanceMeters)
        let focus = LocalVector(east: 0, north: 0, up: overviewFocusHeightMeters)
        return ObserverCameraPose(position: position, direction: focus.minus(position).normalized)
    }

    public func pose(progress: Double) -> ObserverCameraPose {
        let progress = progress.isFinite ? min(1, max(0, progress)) : 0
        if progress == 0 { return start }
        if progress < Self.approachFraction {
            let t = Self.ease(progress / Self.approachFraction)
            let position = Self.mix(start.position, waypoint, t)
            let focus = LocalVector(east: 0, north: 0, up: Self.overviewFocusHeightMeters * (1 - t))
            return ObserverCameraPose(position: position, direction: focus.minus(position).normalized)
        }

        let t = Self.ease((progress - Self.approachFraction) / (1 - Self.approachFraction))
        let position = Self.mix(waypoint, Self.zero, t)
        let initialDirection = Self.zero.minus(waypoint).normalized
        let initialAltitude = asin(initialDirection.up) * 180 / .pi
        let initialAzimuth = atan2(initialDirection.east, initialDirection.north) * 180 / .pi
        // 北や南をまたぐときも最短の向きへ回し、途中で反対側へ一周させない。
        let turn = Angle.normalize(target.azimuth - initialAzimuth + 180) - 180
        let direction = LocalVector(HorizontalCoord(altitude: initialAltitude + (target.altitude - initialAltitude) * t,
                                                    azimuth: initialAzimuth + turn * t))
        return ObserverCameraPose(position: position, direction: direction)
    }

    private static func ease(_ value: Double) -> Double { value * value * (3 - 2 * value) }

    private static func mix(_ a: LocalVector, _ b: LocalVector, _ t: Double) -> LocalVector {
        LocalVector(east: a.east + (b.east - a.east) * t,
                    north: a.north + (b.north - a.north) * t, up: a.up + (b.up - a.up) * t)
    }
}
