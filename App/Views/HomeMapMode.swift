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

    var body: some View {
        WideCityView()
            .ignoresSafeArea()
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
