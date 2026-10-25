import CoreLocation
import StarCore
import SwiftUI

/// 設定タブ。選んだ内容は @AppStorage で端末に覚えておく（キーは StarCore の各型にまとめてある）
struct SettingsView: View {
    @Environment(LocationModel.self) private var location
    @Environment(\.openURL) private var openURL
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.default
    @AppStorage(TimeNotation.storageKey) private var timeNotation = TimeNotation.default
    @AppStorage(DirectionNotation.storageKey) private var directionNotation = DirectionNotation.default
    @AppStorage(MotionPreference.reduceKey) private var reduceMotion = MotionPreference.reduceDefault
    @AppStorage(SoundPlayer.enabledKey) private var soundEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section("外観") {
                    Picker("画面の明るさ", selection: $appearance) {
                        ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
                Section("表示") {
                    Picker("時刻", selection: $timeNotation) {
                        ForEach(TimeNotation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("方位", selection: $directionNotation) {
                        ForEach(DirectionNotation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("動きを少なくする", isOn: $reduceMotion)
                }
                Section {
                    Toggle("効果音", isOn: $soundEnabled)
                } header: {
                    Text("音")
                } footer: {
                    Text("消音スイッチがオンのときは、ここがオンでも鳴りません。")
                }
                Section {
                    LabeledContent("現在地", value: locationStatus)
                    Button("iOS の設定を開く") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                } header: {
                    Text("位置情報と通知")
                } footer: {
                    Text("現在地は、近い地点を並べるためだけに使い、外には送りません。このアプリは通知を送りません。")
                }
                Section("データの出典") {
                    Text("天気: Open-Meteo（CC BY 4.0）")
                    Text(SkyRenderer.credit.replacingOccurrences(of: "出典: ", with: ""))
                    Text(WideCityView.source.replacingOccurrences(of: "出典: ", with: ""))
                    Link("Open-Meteo を開く", destination: URL(string: "https://open-meteo.com/")!)
                }
                .font(.footnote)
            }
            .navigationTitle("設定")
        }
    }

    private var locationStatus: String {
        switch location.authorization {
        case .authorizedWhenInUse, .authorizedAlways: "許可されている"
        case .denied, .restricted: "許可されていない"
        default: "まだ選んでいない"
        }
    }
}
