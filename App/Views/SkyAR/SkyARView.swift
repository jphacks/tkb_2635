import StarCore
import SwiftUI

/// 全画面の AR。背面カメラの映像に、いま空にある月・惑星・恒星・星座を実際の方角に重ねる。
/// 画像認識は使わず、スマホの向きと地点・いまの時刻だけで置く。
struct SkyARView: View {
    let context: SpotContext
    let monitor: DeviceMotionMonitor
    let onClose: () -> Void

    @State private var camera = CameraFeed()
    @State private var snapshot: SkySnapshot?
    /// 空の位置を計算し直す間隔。天体は 1 時間に 15° 動くので、これで十分
    private static let refreshInterval = Duration.seconds(30)

    var body: some View {
        let attitude = monitor.attitude
        ZStack {
            Color(red: 0.02, green: 0.03, blue: 0.10)
            if camera.state == .running {
                CameraPreview(session: camera.runner.session)
            }
            GeometryReader { proxy in
                Canvas { canvas, size in
                    guard let snapshot, let attitude else { return }
                    let projector = CameraProjector(attitude: attitude, width: size.width, height: size.height,
                                                    verticalFieldOfView: camera.verticalFieldOfView)
                    SkyAROverlay.draw(snapshot, projector: projector, in: &canvas, size: size)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            chrome(hasAttitude: attitude != nil)
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .task { await camera.start() }
        .task { await refreshSky() }
        .onDisappear { camera.stop() }
    }

    private func chrome(hasAttitude: Bool) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Button(action: onClose) {
                    Label("戻る", systemImage: "chevron.down")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(context.spot.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            Spacer()
            if let message = statusMessage(hasAttitude: hasAttitude) {
                Text(message)
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 54)
        .padding(.bottom, 34)
    }

    private func statusMessage(hasAttitude: Bool) -> String? {
        if !hasAttitude { return "スマホの向きを読み取れません。星や月の位置を重ねられません" }
        switch camera.state {
        case .denied: return "カメラが許可されていません。設定で許可すると、実際の景色に重なって見えます"
        case .unavailable: return "カメラを使えません。位置だけを表示しています"
        case .idle, .running: return nil
        }
    }

    private func refreshSky() async {
        let lines = Bundle.main.url(forResource: "constellations", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? ConstellationLines.decode($0) } ?? []
        while !Task.isCancelled {
            snapshot = SkySnapshot.make(context: context, date: .now, constellations: lines)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}
