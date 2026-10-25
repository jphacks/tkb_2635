import Foundation

/// 画面上の位置 [pt]。左上が原点
public struct ScreenPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
}

/// 背面カメラの映像に合わせて、空の方向を画面の位置に直す（縦向きの画面）。
/// カメラ映像は画面いっぱいに拡大して映す（高さがそろう）ので、縦方向の画角から焦点距離を決める。
public struct CameraProjector: Sendable {
    public var attitude: DeviceAttitude
    public var width: Double
    public var height: Double
    /// 縦方向の画角 [度]。カメラの `videoFieldOfView`（センサーの長辺）に当たる
    public var verticalFieldOfView: Double

    /// 背面の広角カメラのおよその画角。実機から画角が取れなかったときに使う
    public static let defaultVerticalFieldOfView = 65.0
    /// カメラの真後ろに近い方向は映らないものとして扱う（0 に近いと位置が飛ぶ）
    private static let minimumDepth = 0.05

    public init(attitude: DeviceAttitude, width: Double, height: Double,
                verticalFieldOfView: Double = CameraProjector.defaultVerticalFieldOfView) {
        self.attitude = attitude
        self.width = width
        self.height = height
        self.verticalFieldOfView = verticalFieldOfView
    }

    /// カメラの前にあるときだけ、画面の位置を返す。画面の外でも返す（切り取りは描く側が行う）
    public func project(_ direction: LocalVector) -> ScreenPoint? {
        let v = attitude.deviceVector(of: direction)
        let depth = -v.z
        guard depth > Self.minimumDepth else { return nil }
        let focal = (height / 2) / tan(verticalFieldOfView * .pi / 360)
        return ScreenPoint(x: width / 2 + focal * v.x / depth, y: height / 2 - focal * v.y / depth)
    }
}
