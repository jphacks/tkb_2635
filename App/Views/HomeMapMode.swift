import StarCore
import SwiftUI

/// ホームの地図の枠に出すもの。2D の地図か、23 区の広域 3D か
enum HomeMapMode: String, CaseIterable, Identifiable {
    case map = "地図"
    case city3D = "3D"

    var id: Self { self }
}

/// 全画面の広域 3D
struct FullScreenWideCity: View {
    @Environment(\.dismiss) private var dismiss
    let contexts: [SpotContext]
    let predictions: [Prediction]
    let onSelect: (String) -> Void

    /// ホーム側の 3D が消えてから作る（2 つ同時にあると、シミュレータで全画面の方が真っ暗なままのことがあった）
    @State private var isReady = false
    private static let delay = Duration.milliseconds(400)

    var body: some View {
        Group {
            if isReady {
                WideCityView(contexts: contexts, predictions: predictions, onSelect: onSelect)
            } else {
                Color(red: 0.02, green: 0.03, blue: 0.10)
            }
        }
            .ignoresSafeArea()
            .task {
                try? await Task.sleep(for: Self.delay)
                isReady = true
            }
            .overlay(alignment: .topTrailing) {
                Button("3D を閉じる", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(HomeStyle.mapButtonFill, in: .circle)
                    .padding()
            }
    }
}

/// ホームのカードに出す 23 区の 3D の静止画（全画面の 3D を真上から撮ったもの）。押すと全画面の 3D を開く
struct WideCityPreview: View {
    private static let imageName = "WideCityPreview"
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Color(red: 0.02, green: 0.03, blue: 0.10)
                .overlay {
                    if let url = Bundle.main.url(forResource: Self.imageName, withExtension: "jpg"),
                       let image = UIImage(contentsOfFile: url.path) {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("押すと 23 区の 3D と地点のピンを開く", systemImage: "cube.transparent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .background(.ultraThinMaterial, in: .capsule)
                        Text(WideCityView.source)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(8)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("東京23区の建物の3Dを全画面で開く")
    }
}
