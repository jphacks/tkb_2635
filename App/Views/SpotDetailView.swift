import StarCore
import SwiftUI

struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    let context: SpotContext

    var body: some View {
        let spot = context.spot
        let prediction = Recommender.evaluate(context, target: model.target, date: model.date,
                                              weather: model.weather(for: spot))

        List {
            Section {
                Sky3DView(context: context, prediction: prediction, date: model.date)
                    .frame(height: 340)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("ドラッグで視点を回転、ピンチで拡大縮小。線の先の球が\(model.target.name)の方向です（緑=見える、赤=遮られる）。")
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

            Section("観測条件") {
                MetricRow(label: "空の開放度 O", value: prediction.openness, detail: context.horizon.isApproximate ? "暫定値" : "建物データから計算")
                if let w = prediction.weatherScore {
                    MetricRow(label: "天気 W", value: w, detail: prediction.cloudCover.map { "雲量 \(Int($0))%" } ?? "")
                } else {
                    LabeledContent("天気 W", value: "未取得")
                }
                MetricRow(label: "暗さ D", value: prediction.darknessScore,
                          detail: spot.localGlareLevel == nil ? "精度不足" : "")
                LabeledContent("月明かりの影響 M", value: model.target == .moon ? "月モードでは減点しない" : String(format: "%.2f", prediction.moonEffect))
            }

            Section {
                LabeledContent("地域の光害（広域）") {
                    Text(String(format: "%.2f", spot.regionalLightIndex)) + Text("  暫定値").foregroundStyle(.secondary)
                }
                LabeledContent("近傍照明（現地確認）") {
                    if let level = spot.localGlareLevel {
                        Text("\(level) / 3")
                    } else {
                        Text("未確認").foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("光害")
            } footer: {
                Text("地域の光害は衛星夜間光（VIIRS）を取り込む前の暫定値です。近傍照明は現地確認の段階評価で、照度の測定値ではありません。")
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
                if let memo = spot.memo { Text(memo).font(.callout).foregroundStyle(.secondary) }
                LabeledContent("最終確認日", value: spot.lastVerifiedAt ?? "未確認")
                if let url = spot.officialWebsite { Link("公式情報を開く", destination: url) }
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
