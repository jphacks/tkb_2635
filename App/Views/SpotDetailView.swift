import StarCore
import SwiftUI

struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    let context: SpotContext

    var body: some View {
        @Bindable var model = model
        let spot = context.spot
        let prediction = Recommender.evaluate(context, target: model.target, date: model.date,
                                              weather: model.weather(for: spot),
                                              forecastCoverage: model.forecastCoverage(for: spot))

        List {
            Section {
                Sky3DView(context: context, prediction: prediction, date: model.date)
                    .frame(height: 340)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("ドラッグで視点を回転、ピンチで拡大縮小。線の先の球が\(model.target.name)の方向です（緑=見える、赤=遮られる）。")
            }

            Section {
                TimeSlider(date: $model.date)
            } footer: {
                if let message = model.forecastCoverage(for: spot).message {
                    ForecastOutOfRangeNote(message: message)
                }
            }

            if let partner = model.contexts.comparisonPartner(of: context) {
                Section {
                    NavigationLink(value: ComparisonRoute(firstId: context.id, secondId: partner.id)) {
                        Label("\(partner.spot.name)と比べる", systemImage: "rectangle.split.2x1")
                    }
                } footer: {
                    Text("同じ時刻の\(model.target.name)が、目の高さでどう変わるかを並べて見られます。")
                }
            }

            Section("判定") {
                HStack {
                    ScoreBadge(score: prediction.totalScore, tier: prediction.tier)
                    VStack(alignment: .leading) {
                        Text("\(model.target.name)：\(Angle.directionName(prediction.azimuth)) 高度\(String(format: "%.1f", prediction.altitude))°")
                        Text("その方位の遮蔽仰角 \(String(format: "%.1f", prediction.obstructionElevation))°")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                ForEach(prediction.recommendationReasons, id: \.self) { Text($0) }
            }

            RiseSetSection(context: context)

            Section("観測条件") {
                MetricRow(label: "空の開放度 O", value: prediction.openness, detail: context.horizon.isApproximate ? "暫定値" : "建物データから計算")
                if let w = prediction.weatherScore {
                    MetricRow(label: "天気 W", value: w, detail: prediction.cloudCover.map { "雲量 \(Int($0))%" } ?? "")
                } else {
                    LabeledContent("天気 W", value: prediction.dataQualityFlags.contains(.weatherOutOfRange) ? "予報の範囲外" : "未取得")
                }
                MetricRow(label: "暗さ D", value: prediction.darknessScore,
                          detail: spot.localGlareLevel == nil || spot.regionalLightIndex == nil ? "精度不足" : "")
                LabeledContent("月明かりの影響 M", value: model.target == .moon ? "月モードでは減点しない" : String(format: "%.2f", prediction.moonEffect))
                LabeledContent("太陽高度", value: "\(String(format: "%.0f", prediction.sunAltitude))°（\(prediction.skyState.label)）")
                Link("天気データ：Open-Meteo（CC BY 4.0）",
                     destination: URL(string: "https://open-meteo.com/")!)
                    .font(.caption)
            }

            Section {
                LabeledContent("地域の光害（広域）") {
                    if let index = spot.regionalLightIndex {
                        Text(String(format: "%.2f", index)) + Text("  \(spot.regionalLightShortSource)").foregroundStyle(.secondary)
                    } else {
                        Text("未確認").foregroundStyle(.orange)
                    }
                }
                LabeledContent(spot.localGlareLabel) {
                    if let level = spot.localGlareLevel {
                        Text("\(level) / 3")
                    } else {
                        Text("未確認").foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("光害")
            } footer: {
                if spot.regionalLightIndex == nil {
                    Text("地域の光害は未確認です。\(spot.localGlareNote)")
                } else if let source = spot.regionalLightSource {
                    Text("地域の光害は衛星夜間光（\(source)）の年平均から求めた値です。\(spot.localGlareNote)")
                } else {
                    Text("地域の光害は衛星夜間光（VIIRS）を取り込む前の暫定値です。\(spot.localGlareNote)")
                }
            }

            Section("施設・地点") {
                LabeledContent("種類", value: "\(spot.category.label)（\(spot.indoorOutdoor.label)）")
                LabeledContent("目の高さ", value: "標高 \(Int(spot.observerElevation)) m（床 \(Int(spot.floorElevation)) m + \(String(format: "%.1f", spot.eyeHeight)) m）")
                LabeledContent("利用時間", value: spot.accessHoursText(at: model.date))
                LabeledContent("指定日時の入場", value: prediction.accessStatus.label)
                if let note = spot.openingHours.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                ForEach(spot.accessNotices(at: model.date), id: \.message) { notice in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(notice.message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Link("区域制限の公式案内", destination: notice.source)
                    }
                    .font(.callout)
                }
                if let fee = spot.admissionFee { LabeledContent("料金", value: fee) }
                if let reservation = spot.reservationRequired { LabeledContent("予約", value: reservation ? "必要・推奨" : "不要") }
                if let access = spot.accessConditions { Text(access).font(.callout) }
                LabeledContent("天候による閉鎖条件", value: spot.weatherClosureConditions ?? "未確認")
                LabeledContent("撮影機材の制限", value: spot.photographyRestrictions ?? "未確認")
                if let memo = spot.memo { Text(memo).font(.callout).foregroundStyle(.secondary) }
                LabeledContent("最終確認日", value: spot.lastVerifiedAt ?? "未確認")
                if let url = spot.officialWebsite { Link("公式情報を開く", destination: url) }
            }

            if spot.indoorOutdoor != .outdoor || spot.viewingDirectionMask != nil || spot.viewingDirectionNotes != nil {
                Section {
                    LabeledContent("観測できる方角", value: spot.viewingDirectionSummary)
                    LabeledContent("方角の確認", value: spot.hasVerifiedViewingDirections ? "確認済み" : "未確認")
                    LabeledContent("見上げられる高度の上限", value: spot.visibleAltitudeSummary)
                    if let notes = spot.viewingDirectionNotes {
                        Text(notes).font(.callout)
                    }
                } header: {
                    Text("窓・屋根と見える方角")
                } footer: {
                    Text("方位は北0°・東90°・南180°・西270°。範囲が北をまたぐ場合は、開始角度から北を通って終了角度までです。方角が未確認の地点は、見える見込みでも「要確認」とします。")
                }
            }

            if let scene = context.scene {
                Section("建物データ") {
                    LabeledContent("収録建物数", value: "\(scene.buildings.count)棟")
                    Text(scene.source).font(.caption).foregroundStyle(.secondary)
                }
                SurroundingsSection(context: context)
            }

            if !prediction.dataQualityFlags.isEmpty {
                Section("データの注意") {
                    ForEach(prediction.dataQualityFlags, id: \.self) { flag in
                        Label(flag.message, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle(spot.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MetricRow: View {
    let label: String
    let value: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(String(format: "%.2f", value)).monospacedDigit()
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: value)
        }
    }
}
