import StarCore
import SwiftUI

/// ホームの背景いっぱいに出す、23 区の 3D か 2D の地図。
/// 3D は読み込みに時間がかかるので、読み込むまでと外している間は静止画を出す。
struct HomeBackground: View {
    @Environment(AppModel.self) private var model
    let mode: HomeMapMode
    @Binding var camera: WideCityCamera
    /// false の間は 3D を外す（詳細へ進んでいる間・シートを全開にしている間）
    let isActive: Bool
    /// 下に重なるシートの高さ。地点名・凡例をその上に出す
    let bottomInset: CGFloat
    /// ピンを押したときに、その地点の ID を渡す
    let onSelect: (String) -> Void

    @State private var isCityReady = false

    /// 3D を読み込み終えたあと、描き直させるまでの待ち時間（念のため3回）
    private static let redrawDelays: [Duration] = [.milliseconds(50), .milliseconds(300), .milliseconds(1000)]
    /// 描き直させるために向きを変える量（ラジアン。目には見えない）
    private static let redrawNudge: Float = 0.0001
    /// 凡例とシートの間 [pt]
    private static let legendGap: CGFloat = 8

    var body: some View {
        let predictions = model.predictions

        Group {
            switch mode {
            case .map:
                SpotMap(contexts: model.contexts, predictions: predictions, onSelect: onSelect)
                    .overlay(alignment: .bottom) {
                        TierLegend()
                            .padding(.bottom, bottomInset + Self.legendGap)
                    }
            case .city3D:
                ZStack {
                    WideCityPreview()
                    if isActive {
                        WideCityView(contexts: model.contexts, predictions: predictions, onSelect: onSelect,
                                     camera: $camera, bottomInset: bottomInset) { isCityReady = true }
                            .opacity(isCityReady ? 1 : 0)
                    }
                    if isActive && !isCityReady {
                        ProgressView("街を読み込み中")
                            .tint(.white)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.black.opacity(0.5), in: .rect(cornerRadius: 12))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: isActive) { _, active in
            if !active { isCityReady = false }
        }
        .onChange(of: isCityReady) { _, ready in
            guard ready else { return }
            // 3D を作り直した直後は、何か動くまで真っ暗なことがある。見えないほど少しだけ向きを変えて描かせる
            Task {
                for delay in Self.redrawDelays {
                    try? await Task.sleep(for: delay)
                    camera.yaw += Self.redrawNudge
                }
            }
        }
        .onChange(of: mode) { isCityReady = false }
    }
}
