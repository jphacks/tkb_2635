import StarCore
import SwiftUI

/// ホームのシートの中の条件カード。日時・天体・月の情報と、スコアの注意書きをまとめる
struct HomeConditionsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 14) {
            Text("観測の条件")
                .font(.headline)

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

            HomeScoreNotes()
        }
        .homeCard()
    }
}

/// 予報の範囲外の注意と、スコアの意味の注意書き
struct HomeScoreNotes: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let message = model.forecastOutOfRangeMessage {
                ForecastOutOfRangeNote(message: message)
            }
            Text("スコアは観測条件の目安で、観測できる確率ではありません。")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

/// ホームの上に重ねる見出し。例:「今夜 21:00 の 月▾」。天体の名前のところで天体を選び直せる
struct HomeHeadline: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let day = Self.dayLabel(for: model.date)
        let time = model.date.formatted(Self.timeFormat)

        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Group {
                Text(day)
                Text(time).monospacedDigit()
                Text("の").foregroundStyle(.secondary)
            }
            .font(.headline)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(day) \(time) の")
            .accessibilityAddTraits(.isHeader)
            TargetPicker(target: $model.target)
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(HomeStyle.moonlight)
                .fixedSize()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
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
