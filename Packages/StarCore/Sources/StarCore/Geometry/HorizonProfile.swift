import Foundation

/// 観測地点から見た、方位ごとの建物・地形の最大仰角 h(A)（仕様書 4.2）
public struct HorizonProfile: Sendable {
    /// samples[i] は方位 i°（0〜359）の最大仰角 [度]
    public let samples: [Double]
    /// 建物データではなく暫定値から作ったプロファイルか
    public let isApproximate: Bool

    public init(samples: [Double], isApproximate: Bool) {
        precondition(samples.count == 360)
        self.samples = samples
        self.isApproximate = isApproximate
    }

    public static func uniform(_ elevation: Double, isApproximate: Bool) -> HorizonProfile {
        HorizonProfile(samples: Array(repeating: elevation, count: 360), isApproximate: isApproximate)
    }

    public func elevation(at azimuth: Double) -> Double {
        samples[Int(Angle.normalize(azimuth).rounded()) % 360]
    }

    /// 空の開放度 O ≈ (1/N) Σ (1 − sin h(A_i))（仕様書 4.4）
    public var openness: Double {
        samples.reduce(0) { $0 + (1 - sin(max(0, $1) * .pi / 180)) } / Double(samples.count)
    }

    /// 建物を直方体として、方位 1° ごとに観測者の目から最も手前で当たる面までの仰角を求める。
    /// 観測者が立っている建物（hostBuildingId）は除外する。地形はシーン内で平坦と見なす。
    public static func compute(spot: Spot, scene: CityScene) -> HorizonProfile {
        let p = scene.localPosition(latitude: spot.latitude, longitude: spot.longitude)
        return compute(observerEast: p.east, observerNorth: p.north, eyeElevation: spot.observerElevation,
                       groundElevation: scene.groundElevation,
                       buildings: scene.buildings.filter { $0.id != spot.hostBuildingId })
    }

    public static func compute(observerEast ox: Double, observerNorth oy: Double, eyeElevation: Double,
                               groundElevation: Double, buildings: [Building]) -> HorizonProfile {
        var samples = Array(repeating: 0.0, count: 360)
        let directions = (0..<360).map { i -> (dx: Double, dy: Double) in
            let a = Double(i) * .pi / 180
            return (sin(a), cos(a))
        }
        // 目より低い建物は空をふさがないので除く。残りも、建物の角が見える方位の範囲だけを調べる
        // （範囲の外の方位の半直線はその建物に当たらないので、結果は全方位を調べたときと同じ）。
        for b in buildings where groundElevation + b.height > eyeElevation {
            let top = groundElevation + b.height
            let minX = b.x - b.width / 2, maxX = b.x + b.width / 2
            let minY = b.y - b.depth / 2, maxY = b.y + b.depth / 2
            for i in azimuthRange(ox: ox, oy: oy, minX: minX, maxX: maxX, minY: minY, maxY: maxY) {
                let index = (i % 360 + 360) % 360
                let (dx, dy) = directions[index]
                guard let distance = rayHit(ox: ox, oy: oy, dx: dx, dy: dy,
                                            minX: minX, maxX: maxX, minY: minY, maxY: maxY)
                else { continue }
                let elevation = atan2(top - eyeElevation, distance) * 180 / .pi
                samples[index] = max(samples[index], elevation)
            }
        }
        return HorizonProfile(samples: samples, isApproximate: false)
    }

    /// 観測者から見て長方形の角がある方位 [度] の範囲（両側に 1° の余裕）。観測者が長方形の中か縁なら全方位。
    static func azimuthRange(ox: Double, oy: Double,
                             minX: Double, maxX: Double, minY: Double, maxY: Double) -> ClosedRange<Int> {
        if ox >= minX - 1, ox <= maxX + 1, oy >= minY - 1, oy <= maxY + 1 { return 0...359 }
        let center = atan2((minX + maxX) / 2 - ox, (minY + maxY) / 2 - oy) * 180 / .pi
        var low = 0.0, high = 0.0
        for (x, y) in [(minX, minY), (minX, maxY), (maxX, minY), (maxX, maxY)] {
            let delta = Angle.normalize(atan2(x - ox, y - oy) * 180 / .pi - center + 180) - 180
            low = min(low, delta)
            high = max(high, delta)
        }
        return Int((center + low).rounded(.down)) - 1...Int((center + high).rounded(.up)) + 1
    }

    /// 2D の半直線と長方形の交差（スラブ法）。観測者の外側で当たったときの距離を返す。
    static func rayHit(ox: Double, oy: Double, dx: Double, dy: Double,
                       minX: Double, maxX: Double, minY: Double, maxY: Double) -> Double? {
        var tMin = -Double.infinity, tMax = Double.infinity
        // 東西・南北の2軸を順に調べる（配列を作らないよう、軸ごとに関数を呼ぶ）
        guard slab(o: ox, d: dx, lo: minX, hi: maxX, tMin: &tMin, tMax: &tMax),
              slab(o: oy, d: dy, lo: minY, hi: maxY, tMin: &tMin, tMax: &tMax),
              tMax >= tMin, tMin > 0.5 else { return nil }
        return tMin
    }

    /// 1軸ぶんのスラブ法。半直線がこの軸の範囲に入らなければ false。
    private static func slab(o: Double, d: Double, lo: Double, hi: Double,
                             tMin: inout Double, tMax: inout Double) -> Bool {
        if abs(d) < 1e-12 { return o >= lo && o <= hi }
        let t1 = (lo - o) / d, t2 = (hi - o) / d
        tMin = max(tMin, min(t1, t2))
        tMax = min(tMax, max(t1, t2))
        return true
    }
}
