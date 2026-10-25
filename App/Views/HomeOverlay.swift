import StarCore
import SwiftUI

/// ホームの上に重ねる、日時・天体・表示の切り替え（詳細画面の時刻スライダーと同じ大きさ）
struct HomeOverlay: View {
    @Environment(AppModel.self) private var model
    @Binding var mode: HomeMapMode

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HomeHeadline()
                Spacer(minLength: 8)
                Picker("表示", selection: $mode) {
                    ForEach(HomeMapMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            TimeSlider(date: $model.date, compact: true)
            Group {
                if let message = model.forecastOutOfRangeMessage {
                    ForecastOutOfRangeNote(message: message)
                }
                if let error = model.weatherLoadError {
                    Label(error, systemImage: "cloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

/// ホームの上に重ねる見出し。例:「今夜 21:00 の 月▾」。天体の名前のところで天体を選び直せる
struct HomeHeadline: View {
    @AppStorage(TimeNotation.storageKey) private var timeNotation = TimeNotation.default
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let day = Self.dayLabel(for: model.date)
        let time = timeNotation.text(model.date)
        let name = model.selectedCabinTarget?.name ?? model.target.name

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Group {
                Text(day)
                Text(time).monospacedDigit()
                Text("の").foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(day) \(time) の")
            .accessibilityAddTraits(.isHeader)
            // 星座を選んだときも星座名を見せたいので、Picker の表示ではなく自分で名前を出す
            Menu {
                TargetPicker(target: $model.target)
                    .pickerStyle(.inline)
            } label: {
                HStack(spacing: 2) {
                    Text(name).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(HomeStyle.moonlight)
            }
            .accessibilityLabel("見たい天体、\(name)")
        }
        .font(.headline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    /// この時刻より前の翌日の時刻は、夜の続きとして「今夜」と呼ぶ
    private static let nightEndHour = 5

    /// 今日（と翌朝 5 時まで）なら「今夜」、明日なら「明日」、それ以外は「10/26(月)」
    private static func dayLabel(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.tokyo
        if calendar.isDate(date, inSameDayAs: now) { return "今夜" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return calendar.component(.hour, from: date) < nightEndHour ? "今夜" : "明日"
        }
        var style = Date.FormatStyle(timeZone: calendar.timeZone).month(.defaultDigits).day().weekday(.abbreviated)
        style.locale = Locale(identifier: "ja_JP")
        return date.formatted(style)
    }
}
