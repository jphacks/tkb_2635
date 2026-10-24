import SwiftUI

@main
struct StarSpotApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SpotListView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task { await model.refreshWeather() }
        }
    }
}
