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
                Section {
                    NavigationLink("出典とライセンス") { CreditsView() }
                } header: {
                    Text("データの出典")
                } footer: {
                    Text("建物（PLATEAU）・天気（Open-Meteo）・星図（NASA・ESA/Gaia）など、使っているデータの提供元と利用条件です。")
                }
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

/// 設定の「出典とライセンス」。データ・素材の出典はここにまとめ、ふだんの画面には出さない
struct CreditsView: View {
    var body: some View {
        List {
            ForEach(DataCredit.all) { credit in
                Section(credit.purpose) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(credit.name).font(.subheadline.bold())
                        Text(credit.provider)
                        Text(credit.licenseText)
                            .foregroundStyle(credit.license == nil ? .orange : .secondary)
                        if let note = credit.note {
                            Text(note).foregroundStyle(.secondary)
                        }
                    }
                    .font(.footnote)
                    if let url = credit.url {
                        Link("提供元のページを開く", destination: url).font(.footnote)
                    }
                }
            }
            Section {
                Text("星座の絵は Astera チームが画像生成 AI で作った簡略な絵で、実際の星座絵や星図ではありません。効果音もチームで合成したものです。施設の営業時間などは、各地点の「公式情報を開く」から確かめられます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("そのほか")
            }
        }
        .navigationTitle("出典とライセンス")
        .navigationBarTitleDisplayMode(.inline)
    }
}
