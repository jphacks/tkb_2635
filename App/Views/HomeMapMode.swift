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

    /// ホーム側の 3D が消えてから作る（2 つ同時にあると、シミュレータで全画面の方が真っ暗なままのことがあった）
    @State private var isReady = false
    private static let delay = Duration.milliseconds(400)

    var body: some View {
        Group {
            if isReady {
                WideCityView()
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
