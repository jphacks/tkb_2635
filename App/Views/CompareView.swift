import StarCore
import SwiftUI

/// 比較画面へ移るときの行き先（2地点の ID）
struct ComparisonRoute: Hashable {
    let firstId: String
    let secondId: String
}

/// 同じ天体・同じ時刻の見え方を、2地点で並べて比べる画面
struct CompareView: View {
    @Environment(AppModel.self) private var model
    let first: SpotContext
    let second: SpotContext

    var body: some View {
        @Bindable var model = model
        let comparison = SpotComparison.make(first, second, target: model.target, date: model.date,
                                             weather: model.weather(for:),
                                             forecastCoverage: model.forecastCoverage(for:))

        List {
            Section {
                DatePicker("観測日時", selection: $model.date)
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                TimeSlider(date: $model.date)
                TargetPicker(target: $model.target)
            } footer: {
                if let message = model.forecastOutOfRangeMessage {
                    ForecastOutOfRangeNote(message: message)
                }
            }

            Section {
                Text(comparison.summary)
                    .font(.headline)
                HStack(alignment: .top, spacing: 12) {
                    HeightGauge(side: comparison.first, targetName: model.target.name)
                    HeightGauge(side: comparison.second, targetName: model.target.name)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("棒の灰色は、\(model.target.name)の方角で建物がふさぐ高さ（遮蔽仰角）です。印が灰色より上なら見えます。「高さの余裕」は天体の高度からふさぐ高さを引いた値で、マイナスなら隠れます。")
            }

            Section("くらべる") {
                ComparisonTable(first: comparison.first, second: comparison.second)
            }

            Section("地点の詳しい情報") {
                ForEach([comparison.first, comparison.second], id: \.spot.id) { side in
                    NavigationLink(side.spot.name, value: side.spot.id)
                }
            }
        }
        .navigationTitle("高さで比べる")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 天体の高度と、その方角の遮蔽仰角を、0〜90° の縦の棒で表す
private struct HeightGauge: View {
    let side: SpotComparison.Side
    let targetName: String

    private var prediction: Prediction { side.prediction }

    var body: some View {
        VStack(spacing: 8) {
            Text(side.spot.name)
                .font(.subheadline.bold())
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
            Text("目の高さ 標高\(Int(side.spot.observerElevation))m")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let h = geo.size.height
                let y = { (deg: Double) in h * (1 - min(max(deg, 0), 90) / 90) }
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.05, green: 0.07, blue: 0.2))
                    Rectangle()
                        .fill(.gray.opacity(0.7))
                        .frame(height: h - y(prediction.obstructionElevation))
                    if prediction.altitude > 0 {
                        Image(systemName: targetSymbol)
                            .font(.title2)
                            .foregroundStyle(prediction.geometricVisibility ? .yellow : .red)
                            .position(x: geo.size.width / 2, y: y(prediction.altitude))
                    }
                    VStack {
                        Text("真上 90°")
                        Spacer()
                        Text("地平線 0°")
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .clipShape(.rect(cornerRadius: 6))
            }
            .frame(height: 180)
            .accessibilityElement()
            .accessibilityLabel("\(targetName)の高度\(Int(prediction.altitude))度、建物がふさぐ高さ\(Int(prediction.obstructionElevation))度")

            Label(verdict, systemImage: prediction.geometricVisibility ? "eye" : "eye.slash")
                .font(.subheadline.bold())
                .foregroundStyle(prediction.geometricVisibility ? .green : .red)
        }
        .frame(maxWidth: .infinity)
    }

    private var targetSymbol: String {
        prediction.celestialBodyId == ObservationTarget.moon.id ? "moon.fill" : "star.fill"
    }

    private var verdict: String {
        if prediction.altitude <= 0 { return "地平線の下" }
        if prediction.blockedByDirectionMask { return "窓の外で見えない" }
        return prediction.geometricVisibility ? "見える" : "建物に隠れる"
    }
}

/// 2地点の数値を、項目ごとに左右に並べる
private struct ComparisonTable: View {
    let first: SpotComparison.Side
    let second: SpotComparison.Side

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("")
                Text(first.spot.name).font(.caption.bold()).lineLimit(2)
                Text(second.spot.name).font(.caption.bold()).lineLimit(2)
            }
            Divider()
            row("判定") { $0.prediction.tier.label }
            row("天体の方角") { Angle.directionName($0.prediction.azimuth) }
            row("天体の高度") { degrees($0.prediction.altitude) }
            row("建物がふさぐ高さ") { degrees($0.prediction.obstructionElevation) }
            row("高さの余裕") { degrees($0.clearance) }
            row("目の高さ（標高）") { "\(Int($0.spot.observerElevation)) m" }
            row("空の開放度") { String(format: "%.2f", $0.prediction.openness) }
            row("スコア") { "\(Int($0.prediction.totalScore.rounded()))" }
        }
        .font(.subheadline)
    }

    private func row(_ label: String, _ value: (SpotComparison.Side) -> String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).font(.caption)
            Text(value(first)).monospacedDigit()
            Text(value(second)).monospacedDigit()
        }
    }

    private func degrees(_ value: Double) -> String { String(format: "%.1f°", value) }
}
