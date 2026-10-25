import Foundation

/// スマホの姿勢（CoreMotion の `xTrueNorthZVertical`）。AR でカメラが向いている方向と、天体が画面のどこに映るかを求める。
///
/// 基準座標は x=真北・y=西・z=真上。端末の座標は x=画面の右・y=画面の上・z=画面から手前。
/// 行列は「基準座標のベクトル → 端末座標のベクトル」（CoreMotion の `rotationMatrix` と同じ向き）。
/// 実機で向きが逆に見えたときは、この型の中だけを直す。
public struct DeviceAttitude: Sendable, Equatable {
    /// 行ごとに並べた 3×3（m11, m12, m13, m21, ...）
    private let m: [Double]

    public init(m11: Double, m12: Double, m13: Double,
                m21: Double, m22: Double, m23: Double,
                m31: Double, m32: Double, m33: Double) {
        m = [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    }

    /// 地平の向き（東・北・天頂）を、端末の座標に直す
    func deviceVector(of direction: LocalVector) -> (x: Double, y: Double, z: Double) {
        let n = direction.north, w = -direction.east, u = direction.up
        return (m[0] * n + m[1] * w + m[2] * u,
                m[3] * n + m[4] * w + m[5] * u,
                m[6] * n + m[7] * w + m[8] * u)
    }

    /// 背面カメラが向いている方向（端末の -z 軸）
    public var lookDirection: LocalVector {
        LocalVector(east: m[7], north: -m[6], up: -m[8])
    }

    /// 背面カメラの仰角 [度]。水平が 0、真上が 90、真下が -90
    public var lookElevation: Double {
        asin(max(-1, min(1, lookDirection.up))) * 180 / .pi
    }
}
