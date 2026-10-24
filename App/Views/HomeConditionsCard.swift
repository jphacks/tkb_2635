import StarCore
import SwiftUI

/// ホームの条件カード。「今夜 21:00 の 月」の見出しと、日時・天体・月の情報をまとめる
struct HomeConditionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            headline

            VStack(spacing: 10) {
                DatePicker("観測日時", selection: $model.date)
                    .environment(\.timeZone, TimeZone(identifier: "Asia/Tokyo")!)
                Divider().overlay(HomeStyle.cardStroke)
                LabeledContent("見たい天体") {
                    TargetPicker(target: $model.target)
                        .labelsHidden()
                }
                Divider().overlay(HomeStyle.cardStroke)
                MoonSummary(moon: model.moon)
            }
            .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                if let message = model.forecastOutOfRangeMessage {
                    ForecastOutOfRangeNote(message: message)
                }
                Text("スコアは観測条件の目安で、観測できる確率ではありません。")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .homeCard()
    }

    /// 例:「今夜 21:00 の 月」
    private var headline: some View {
        let time = model.date.formatted(Self.timeFormat)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Self.dayLabel(for: model.date))
            Text(time).monospacedDigit()
            Text("の").foregroundStyle(.secondary)
            Text(model.target.name).foregroundStyle(HomeStyle.moonlight)
        }
        .font(.title2.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.dayLabel(for: model.date)) \(time) の \(model.target.name)")
        .accessibilityAddTraits(.isHeader)
    }

    private static let timeFormat = Date.FormatStyle(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        .hour(.defaultDigits(amPM: .omitted)).minute(.twoDigits)

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

/// 選んだ日時が天気予報の範囲外のときの注意書き
struct ForecastOutOfRangeNote: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "calendar.badge.exclamationmark")
            .foregroundStyle(.orange)
    }
}

struct MoonSummary: View {
    let moon: MoonInfo

    var body: some View {
        HStack {
            Image(systemName: "moon.fill")
                .foregroundStyle(HomeStyle.moonlight)
            Text("\(moon.phaseName)（輝面 \(Int(moon.illuminatedFraction * 100))%）")
            Spacer()
            Text(moon.position.altitude > 0
                 ? "\(Angle.directionName(moon.position.azimuth)) 高度\(Int(moon.position.altitude))°"
                 : "地平線の下")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
