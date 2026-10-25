import StarCore
import SwiftUI

/// 試作を確認したシーンの詳細・比較画面で共用する視点切り替え。
struct SkyViewControls: View {
    @Binding var camera: SkyCamera
    let target: HorizontalCoord
    var showsObstructionGuide = false
    var entryIsBuilding = false

    var body: some View {
        VStack(spacing: 8) {
            switch camera.mode {
            case .overview:
                Label(entryIsBuilding ? "淡く光る建物をタップして展望台の目線へ" : "青い観測位置をタップして地上の目線へ",
                      systemImage: "hand.tap")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .entering:
                HStack {
                    ProgressView("観測位置へ移動中")
                        .font(.caption)
                    Spacer()
                    Button("戻る") { camera.mode = .overview }
                        .font(.caption.bold())
                }
            case .observer:
                HStack {
                    Button {
                        camera.mode = .overview
                    } label: {
                        Label("街全体へ戻る", systemImage: "square.3.layers.3d")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    Spacer(minLength: 8)
                    Button {
                        faceTarget()
                    } label: {
                        Label("天体の方向へ", systemImage: "scope")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("選んだ天体の現在の方角へ視点を戻します")
                }
                Text("ドラッグで見回す・ピンチで拡大")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsObstructionGuide {
                    Text("赤枠は判定用の箱です。実際の建物の形とは異なります。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .onChange(of: camera.mode) { _, mode in
            if mode == .observer { faceTarget() }
        }
    }

    private func faceTarget() {
        camera.observer = ObserverViewpoint(target: target, fieldOfView: camera.observer.fieldOfView)
    }
}
