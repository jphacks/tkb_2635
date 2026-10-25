import Foundation

/// 星座名を出す候補 1 つ
public struct ConstellationLabelCandidate: Sendable, Equatable {
    public let id: String
    /// 名前を置く向き（地平の向き）
    public let direction: LocalVector
    /// 線の星のうち最も明るい星の等級（`ConstellationLines.brightestCatalogMagnitude`）。無ければ nil
    public let brightestMagnitude: Double?

    public init(id: String, direction: LocalVector, brightestMagnitude: Double?) {
        self.id = id
        self.direction = direction
        self.brightestMagnitude = brightestMagnitude
    }
}

/// 画面が星座名で埋まらないよう、出す名前を間引く。3D の空と AR で同じ決まりを使う。
/// 見ている向きに近い星座から順に、明るい星を含む星座を優先して選び、近すぎる名前は出さない。
public enum ConstellationLabelPicker {
    /// 一度に出す名前の最大数
    public static let maximumCount = 6
    /// 名前どうしの最小の間隔 [度]
    public static let minimumSeparation = 14.0
    /// これより低い（地平線に近い）星座には名前を出さない [度]
    public static let minimumAltitude = 3.0
    /// 明るい星を含む星座を、見ている向きにこれだけ近いものとして扱う [度]
    public static let brightBonus = 12.0
    /// 「明るい星」とみなす等級
    public static let brightMagnitude = 1.5

    /// - Parameters:
    ///   - viewDirection: 見ている向き（画面の中心）
    ///   - maximumAngle: 画面の中心からこの角度 [度] より外の星座は選ばない
    /// - Returns: 名前を出す星座の id（優先の高い順）
    public static func pick(_ candidates: [ConstellationLabelCandidate], viewDirection: LocalVector,
                            maximumAngle: Double) -> [String] {
        let view = viewDirection.normalized
        let minimumUp = sin(minimumAltitude * Astro.deg)
        let scored = candidates.compactMap { candidate -> (ConstellationLabelCandidate, Double)? in
            let direction = candidate.direction.normalized
            guard direction.up >= minimumUp else { return nil }
            let angle = angleBetween(direction, view)
            guard angle <= maximumAngle else { return nil }
            let isBright = (candidate.brightestMagnitude ?? .infinity) <= brightMagnitude
            return (candidate, angle - (isBright ? brightBonus : 0))
        }
        .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }

        var chosen: [ConstellationLabelCandidate] = []
        for (candidate, _) in scored where chosen.count < maximumCount {
            let direction = candidate.direction.normalized
            guard chosen.allSatisfy({ angleBetween($0.direction.normalized, direction) >= minimumSeparation }) else { continue }
            chosen.append(candidate)
        }
        return chosen.map(\.id)
    }

    /// 見ている向きがこれより低い（街や地面を見ている）ときは、空の方へ持ち上げて選ぶ [度]
    public static let minimumViewAltitude = 20.0

    /// 街を見下ろしているときも空の星座名が出るよう、見ている向きを空へ持ち上げる。
    /// 持ち上げた分だけ、選ぶ範囲を広げる（画面の上の方に見えている空を含めるため）
    public static func liftedView(_ view: LocalVector, maximumAngle: Double) -> (direction: LocalVector, maximumAngle: Double) {
        let v = view.normalized
        let altitude = asin(max(-1, min(1, v.up))) / Astro.deg
        guard altitude < minimumViewAltitude else { return (v, maximumAngle) }
        let azimuth = atan2(v.east, v.north) / Astro.deg
        return (LocalVector(HorizontalCoord(altitude: minimumViewAltitude, azimuth: azimuth)),
                maximumAngle + minimumViewAltitude - altitude)
    }

    static func angleBetween(_ a: LocalVector, _ b: LocalVector) -> Double {
        acos(max(-1, min(1, a.dot(b)))) / Astro.deg
    }
}
