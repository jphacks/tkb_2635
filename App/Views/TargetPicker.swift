import StarCore
import SwiftUI

/// 見たい天体を選ぶ。一覧と比較画面で同じ選択肢を使う。
struct TargetPicker: View {
    @Binding var target: ObservationTarget

    var body: some View {
        Picker("見たい天体", selection: $target) {
            Text("月").tag(ObservationTarget.moon)
            Section("惑星") {
                ForEach(PlanetCatalog.planets) { planet in
                    Text(planet.name).tag(ObservationTarget.planet(planet))
                }
            }
            Section("恒星") {
                ForEach(StarCatalog.stars) { star in
                    Text(star.name).tag(ObservationTarget.star(star))
                }
            }
        }
    }
}
