import StarCore
import SwiftUI

/// 3D の左上の説明（判定・建物データ・出典）
extension Sky3DView {
    var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            if prediction.accessStatus != .open && !compact {
                Label(prediction.accessStatus.label, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Label(prediction.geometricVisibility ? "見える見込み" : (prediction.altitude <= 0 ? "地平線の下" : "遮られる見込み"),
                  systemImage: prediction.geometricVisibility ? "eye" : "eye.slash")
                .foregroundStyle(prediction.geometricVisibility ? .green : .red)
            if !compact {
                Text(context.scene?.name ?? "建物データなし（地平線は暫定値）")
                    .foregroundStyle(.secondary)
            }
            if context.scene.map(CityModelRenderer.hasModel) == true {
                if !compact {
                    Text("建物・地面は昼の実写を暗く表示")
                        .foregroundStyle(.secondary)
                    Text("窓・街灯の明かりはイメージ")
                        .foregroundStyle(.secondary)
                    if context.scene.map(FarGroundRenderer.hasImage) == true {
                        Text("遠くの街明かりは衛星の夜間光をもとにしたイメージ")
                            .foregroundStyle(.secondary)
                    }
                }
                // 地理院タイルは出典の明示が利用の条件。小さい表示でも消さない
                Text(SkyRenderer.credit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if !compact {
                Text("外壁・窓明かりはイメージ")
                    .foregroundStyle(.secondary)
            }
            if !compact && !prediction.geometricVisibility && !prediction.blockedByDirectionMask && prediction.altitude > 0 {
                Label("赤い枠は判定に使った建物の箱", systemImage: "cube")
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.35))
            }
        }
        .font(.caption.bold())
        .padding(8)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
        .padding(8)
    }
}
