import StarCore
import SwiftUI

/// 詳細画面の下のシートに入れる情報（判定の理由・比較・観測条件・施設など）。
/// 上から順に、シートを半分まで引き上げたときに見える内容 → 全部引き上げたときの内容。比較画面へのボタンは見出し（SpotSheetHeader）にある。
struct SpotInfoList: View {
    @AppStorage(DirectionNotation.storageKey) private var directionNotation = DirectionNotation.default
    @Environment(AppModel.self) private var model
    let context: SpotContext
    let prediction: Prediction

    var body: some View {
        let spot = context.spot

        List {
            // スコアと見える/隠れるはシートの見出しに出すので、ここは位置と理由だけ
            Section("判定") {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.target.name)：\(directionNotation.text(prediction.azimuth)) 高度\(String(format: "%.1f", prediction.altitude))°")
                    Text("その方位の遮蔽仰角 \(String(format: "%.1f", prediction.obstructionElevation))°")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
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

            RouteSection(spot: spot)

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
        .scrollContentBackground(.hidden)
    }
}
