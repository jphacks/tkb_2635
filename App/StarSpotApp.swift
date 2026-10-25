import StarCore
import SwiftUI

@main
struct StarSpotApp: App {
    @State private var model = AppModel()
    @State private var location = LocationModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default
    @State private var selectedTab = AppTab.home
    @AppStorage(OnboardingView.storageKey) private var hasSeenOnboarding = false

    private enum AppTab { case home, settings }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                Tab("ホーム", systemImage: "moon.stars", value: AppTab.home) { SpotListView() }
                Tab("設定", systemImage: "gearshape", value: AppTab.settings) { SettingsView() }
            }
                // ホームは夜空・3D が主役なので常に夜の見た目。設定タブだけ、選んだ明るさに従う
                .preferredColorScheme(selectedTab == .home ? .dark : appearance.colorScheme)
                .sheet(isPresented: Binding(get: { !hasSeenOnboarding }, set: { if !$0 { hasSeenOnboarding = true } })) {
                    OnboardingView()
                }
                .environment(model)
                .environment(location)
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

private extension AppearanceMode {
    /// nil のときは iPhone の設定に従う
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
