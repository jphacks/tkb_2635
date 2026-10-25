import StarCore
import SwiftUI

/// 動きを少なくするか。iOS の「視差効果を減らす」か、アプリの設定のどちらかがオンなら少なくする
struct MotionSetting: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var system
    @AppStorage(MotionPreference.reduceKey) private var user = MotionPreference.reduceDefault

    var isReduced: Bool { system || user }
}
