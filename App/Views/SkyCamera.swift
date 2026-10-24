import Foundation

/// 3D を見る向きと距離。比較画面では地点を切り替えても同じ向きのまま見せるため、外で持つ。
struct SkyCamera: Equatable {
    var yaw: Float = .pi / 5
    var pitch: Float = 0.35
    var distance: Float = 10
}
