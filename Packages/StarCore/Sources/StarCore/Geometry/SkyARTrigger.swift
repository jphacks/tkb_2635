import Foundation

/// スマホを空へ向けたときに、AR へ自動で切り替える判定。
/// 一度切り替えたら、カメラが十分下がるまで切り替えない（AR から戻った直後に、また開かないため）。
public struct SkyARTrigger: Sendable {
    /// この仰角 [度] 以上にカメラが向いたら AR を開く
    public static let enterElevation = 50.0
    /// 開いたあと、この仰角 [度] 以下に下がるまでは開かない
    public static let rearmElevation = 20.0

    private var isArmed: Bool

    /// - Parameter isArmed: false なら、一度カメラが `rearmElevation` まで下がるまで開かない（画面を開いた直後に上を向けていても、すぐには開かない）
    public init(isArmed: Bool = true) {
        self.isArmed = isArmed
    }

    /// 最新のカメラの仰角を渡す。AR を開くべきなら true
    public mutating func shouldEnter(lookElevation: Double) -> Bool {
        if isArmed, lookElevation >= Self.enterElevation {
            isArmed = false
            return true
        }
        if !isArmed, lookElevation <= Self.rearmElevation { isArmed = true }
        return false
    }
}
