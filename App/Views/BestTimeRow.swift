import StarCore
import SwiftUI

/// 「今夜〇時、〇〇がおすすめ」。選んだ天体を、その夜のどの地点・時刻で見るのがよいかを 1 行で出す（7-05）
struct BestTimeRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TimeNotation.storageKey) private var timeNotation = TimeNotation.default
    @State private var best: BestTimeFinder.Best?
    let onSelect: (String) -> Void

    var body: some View {
        let night = ObservingNight(containing: model.date)
        VStack(spacing: 0) {
            if let best, let spot = model.context(id: best.prediction.spotId)?.spot {
                Button {
                    model.date = best.date
                    onSelect(spot.id)
                } label: {
                    Label("\(timeNotation.text(best.date)) に \(spot.name) がおすすめ（\(model.target.name)）",
                          systemImage: "sparkles")
                        .font(.subheadline).foregroundStyle(HomeStyle.moonlight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityHint("押すと、その時刻でこの地点の詳細を開きます")
            }
        }
        // 天体・夜・天気の取得が変わったときだけ探し直す
        .task(id: "\(model.target.id)|\(night.start.timeIntervalSince1970)|\(model.isLoadingWeather)") {
            best = model.bestTime()
        }
    }
}
