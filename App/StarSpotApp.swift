import SwiftUI

@main
struct StarSpotApp: App {
    @State private var model = AppModel()
    @State private var location = LocationModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SpotListView()
                .environment(model)
                .environment(location)
                .preferredColorScheme(.dark)
                .task { await model.refreshWeather() }
                .task { location.start() }
                .task { await SoundPlayer.shared.startUp() }
                // アプリに戻ったとき、古くなった地域の天気だけを取り直し、止まっていた BGM を流し直す
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await model.refreshWeather() }
                        SoundPlayer.shared.updateMusic()
                    }
                }
        }
    }
}
