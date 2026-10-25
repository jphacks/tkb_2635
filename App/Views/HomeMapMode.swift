import SwiftUI

/// ホームの背景に出すもの。2D の地図か、23 区の広域 3D か
enum HomeMapMode: String, CaseIterable, Identifiable {
    case map = "地図"
    case city3D = "3D"

    var id: Self { self }
}

/// 23 区の 3D の静止画（3D を真上から撮ったもの）。3D を読み込むまでと、3D を外している間に出す
struct WideCityPreview: View {
    private static let imageName = "WideCityPreview"
    static let background = Color(red: 0.02, green: 0.03, blue: 0.10)

    var body: some View {
        Self.background
            .overlay {
                if let url = Bundle.main.url(forResource: Self.imageName, withExtension: "jpg"),
                   let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
