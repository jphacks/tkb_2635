import Foundation

public extension Spot {
    /// 屋内は具体的な窓の範囲が必要。確認フラグだけでは全方位を確認済みにしない。
    var hasVerifiedViewingDirections: Bool {
        guard directionMaskVerified else { return false }
        if indoorOutdoor == .indoor {
            guard let ranges = viewingDirectionMask, !ranges.isEmpty else { return false }
        }
        return viewingDirectionMask?.allSatisfy { $0.from.isFinite && $0.to.isFinite } ?? true
    }

    func isBlockedByViewingLimits(azimuth: Double, altitude: Double) -> Bool {
        let outsideWindows = viewingDirectionMask.map { ranges in
            !ranges.contains { $0.contains(azimuth) }
        } ?? false
        let aboveWindow = maxVisibleAltitude.map { altitude > $0 } ?? false
        return outsideWindows || aboveWindow
    }

    var viewingDirectionSummary: String {
        guard let ranges = viewingDirectionMask else {
            return hasVerifiedViewingDirections ? "方角の制限なし" : "未確認"
        }
        guard !ranges.isEmpty else { return "観測できる方角の登録なし" }
        let summary = ranges.map { range in
            if abs(range.to - range.from) >= 360 { return "全方位" }
            return "\(range.from.formatted())°〜\(range.to.formatted())°"
        }.joined(separator: "、")
        return hasVerifiedViewingDirections ? summary : "\(summary)（未確認）"
    }

    var visibleAltitudeSummary: String {
        guard let altitude = maxVisibleAltitude else { return "未確認・未設定" }
        // 高度の確認フラグはまだ無いので、設定値を確認済みとは表示しない。
        return "\(altitude.formatted())°（暫定値）"
    }
}
