import Foundation

/// 観測者の位置を動かさずに見回す向きと視野角。方位は北=0°・東=90°、高度は水平=0°。
public struct ObserverViewpoint: Equatable, Sendable {
    public private(set) var azimuth: Double
    public private(set) var altitude: Double
    public private(set) var fieldOfView: Double

    public static let altitudeLimit = 85.0
    public static let defaultFieldOfView = 55.0
    public static let fieldOfViewRange = 25.0...80.0

    public init(target: HorizontalCoord, fieldOfView: Double = Self.defaultFieldOfView) {
        azimuth = target.azimuth.isFinite ? Angle.normalize(target.azimuth) : 0
        altitude = target.altitude.isFinite ? min(Self.altitudeLimit, max(-Self.altitudeLimit, target.altitude)) : 0
        self.fieldOfView = fieldOfView.isFinite
            ? min(Self.fieldOfViewRange.upperBound, max(Self.fieldOfViewRange.lowerBound, fieldOfView))
            : Self.defaultFieldOfView
    }

    public var direction: LocalVector {
        LocalVector(HorizontalCoord(altitude: altitude, azimuth: azimuth))
    }

    public func turned(horizontal: Double, vertical: Double) -> Self {
        guard horizontal.isFinite, vertical.isFinite else { return self }
        return Self(target: HorizontalCoord(altitude: altitude + vertical, azimuth: azimuth + horizontal),
                    fieldOfView: fieldOfView)
    }

    /// 拡大しても観測者の位置・目の高さは変えず、視野角だけを狭める。
    public func zoomed(magnification: Double) -> Self {
        guard magnification.isFinite, magnification > 0 else { return self }
        return Self(target: HorizontalCoord(altitude: altitude, azimuth: azimuth),
                    fieldOfView: fieldOfView / magnification)
    }
}
