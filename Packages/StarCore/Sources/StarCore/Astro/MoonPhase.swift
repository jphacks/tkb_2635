import Foundation

/// 月の満ち欠けの見え方（4-10）。3D の月の絵を作るのに使う。
public enum MoonPhase {
    /// 月の明るい側が向いている空の方向（月の位置での接線方向の単位ベクトル）。
    /// 太陽の方向から、月の方向の成分を除いたもの。月と太陽が重なる・正反対のときは nil
    public static func brightLimbDirection(moon: HorizontalCoord, sun: HorizontalCoord) -> LocalVector? {
        let m = LocalVector(moon), s = LocalVector(sun)
        let t = s.minus(m.scaled(s.dot(m)))
        guard t.dot(t) > 1e-12 else { return nil }
        return t.normalized
    }

    /// 明るい側の向き [度]。月を見上げたときの「天頂の向き」を 0° とし、右回り（右 = 90°）。
    /// 月が天頂にあるなど、天頂の向きが決まらないときは nil
    public static func brightLimbAngle(moon: HorizontalCoord, sun: HorizontalCoord) -> Double? {
        guard let t = brightLimbDirection(moon: moon, sun: sun) else { return nil }
        let m = LocalVector(moon)
        let zenith = LocalVector(east: 0, north: 0, up: 1)
        let upOnSky = zenith.minus(m.scaled(zenith.dot(m)))
        guard upOnSky.dot(upOnSky) > 1e-12 else { return nil }
        let up = upOnSky.normalized
        // 月の方を向いた人から見た右
        let right = m.cross(up)
        return Angle.normalize(atan2(t.dot(right), t.dot(up)) / Astro.deg)
    }

    /// 月の円の中の点が光っているか。x・y は円の半径を 1 とした位置で、明るい側を +y とする。
    /// fraction は輝面比 0（新月）〜1（満月）。明暗の境目は楕円になる
    public static func isLit(x: Double, y: Double, fraction: Double) -> Bool {
        guard x * x + y * y <= 1 else { return false }
        let c = 1 - 2 * min(max(fraction, 0), 1)
        return y >= c * (1 - x * x).squareRoot()
    }
}
