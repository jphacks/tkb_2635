import StarCore
import SwiftUI

/// 全画面の AR。背面カメラの映像に、いま空にある月・惑星・恒星・星座を実際の方角に重ねる。
/// 画像認識は使わず、スマホの向きと地点・いまの時刻だけで置く。
struct SkyARView: View {
    let context: SpotContext
    let monitor: DeviceMotionMonitor
    var observationDate: Date? = nil
    var locationLabel: String? = nil
    var isDemo = false
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
        .task(id: observationDate) { await refreshSky() }
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
                Text(locationLabel ?? context.spot.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
            }
            if let observationDate {
                Text(observationDate.formatted(Date.FormatStyle(
                    date: .abbreviated, time: .shortened, locale: Locale(identifier: "ja_JP"),
                    timeZone: Calendar.tokyo.timeZone)))
                    .font(.caption.bold()).padding(8)
                    .background(.regularMaterial, in: .capsule)
            }
            Spacer()
            if isDemo {
                Text("デモ位置・選択時刻の空です。カメラ映像は、いま撮影している場所です。")
                    .font(.footnote.bold()).padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
            }
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
        switch camera.state {
        case .denied: return "カメラが許可されていません。設定で許可すると、実際の景色に重なって見えます"
        case .unavailable: return "この端末ではカメラを使えません。戻ると3Dの空を確認できます"
        case .idle, .running:
            return hasAttitude ? nil : "スマホの向きを読み取れません。星や月の位置を重ねられません"
        }
    }

    private func refreshSky() async {
        let lines = ConstellationData.lines, art = ConstellationData.art, images = ConstellationData.images
        while !Task.isCancelled {
            snapshot = SkySnapshot.make(context: context, date: observationDate ?? .now,
                                        constellations: lines, art: art, images: images)
            try? await Task.sleep(for: Self.refreshInterval)
        }
    }
}
