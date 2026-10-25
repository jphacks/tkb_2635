import StarCore
import SwiftUI

/// 試作を確認したシーンの詳細・比較画面で共用する視点切り替え。
struct SkyViewControls: View {
    @Binding var camera: SkyCamera
    let target: HorizontalCoord
    var showsObstructionGuide = false

    var body: some View {
        VStack(spacing: 8) {
            Picker("3Dの視点", selection: $camera.mode) {
                Text("全体を見る").tag(SkyCamera.Mode.overview)
                Text("観測者の目線").tag(SkyCamera.Mode.observer)
            }
            .pickerStyle(.segmented)
            .accessibilityHint("観測者の目線では、その場所に立った高さで空を見回せます")

            if camera.mode == .observer {
                HStack {
                    Text("ドラッグで見回す・ピンチで拡大")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button {
                        faceTarget()
                    } label: {
                        Label("天体の方向へ", systemImage: "scope")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("選んだ天体の現在の方角へ視点を戻します")
                }
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
