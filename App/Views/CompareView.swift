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
    /// 地点を切り替えても、3D の向きと距離はそのまま
    @State private var camera = SkyCamera()
    /// 3D に出している地点（false = first）。3D を2つ同時に描くと描画用のメモリが足りなくなるので、1つを切り替える
    @State private var showsSecond = false

    var body: some View {
        @Bindable var model = model
        let comparison = SpotComparison.make(first, second, target: model.target, date: model.date,
                                             weather: model.weather(for:))

        List {
            Section {
                DatePicker("観測日時", selection: $model.date)
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                TimeSlider(date: $model.date)
                TargetPicker(target: $model.target)
            }

            Section {
                Text(comparison.summary)
                    .font(.headline)
            }

            Section {
                HStack(spacing: 8) {
                    SideButton(side: comparison.first, isSelected: !showsSecond) { showsSecond = false }
                    SideButton(side: comparison.second, isSelected: showsSecond) { showsSecond = true }
                }
                let shown = showsSecond ? comparison.second : comparison.first
                Sky3DView(context: showsSecond ? second : first, prediction: shown.prediction, date: model.date,
                          sharedCamera: $camera, compact: true)
                    .frame(height: 300)
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("ボタンで地点を切り替えると、同じ向き・同じ時刻のまま 3D が変わります。線が緑なら見え、赤なら建物に遮られます。")
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

/// 3D に出す地点を選ぶボタン。地点名・目の高さ・判定を出す
private struct SideButton: View {
    let side: SpotComparison.Side
    let isSelected: Bool
    let action: () -> Void

    private var prediction: Prediction { side.prediction }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(side.spot.name)
                    .font(.subheadline.bold())
                    .lineLimit(2, reservesSpace: true)
                Text("目の高さ 標高\(Int(side.spot.observerElevation))m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(verdict, systemImage: prediction.geometricVisibility ? "eye" : "eye.slash")
                    .font(.subheadline.bold())
                    .foregroundStyle(prediction.geometricVisibility ? .green : .red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                        in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
