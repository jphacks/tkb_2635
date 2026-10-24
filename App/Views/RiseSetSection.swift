import StarCore
import SwiftUI

/// 選んでいる天体の、その夜の出・南中・入り
struct RiseSetSection: View {
    @Environment(AppModel.self) private var model
    let context: SpotContext

    var body: some View {
        let spot = context.spot
        let times = RiseSet.times(for: model.target, date: model.date,
                                  latitude: spot.latitude, longitude: spot.longitude)

        Section {
            switch times.visibility {
            case .alwaysUp:
                LabeledContent("出・入り", value: "沈まない")
            case .neverUp:
                LabeledContent("出・入り", value: "この夜は昇らない")
            case .crosses:
                EmptyView()
            }
            ForEach(times.events, id: \.date) { event in
                LabeledContent(event.kind.label) {
                    HStack {
                        if event.kind == .transit, let altitude = times.transitAltitude {
                            Text("高度\(String(format: "%.0f", altitude))°").foregroundStyle(.secondary)
                        }
                        Text(Self.timeText(event.date, nightStart: times.nightStart)).monospacedDigit()
                    }
                }
            }
        } header: {
            Text("\(model.target.name)の出・南中・入り")
        } footer: {
            Text("\(Self.dayText(times.nightStart)) 12:00 から翌日 12:00 までの、東京時間の時刻です。天体の中心が地平線（大気の屈折込み）を通る時刻で、建物による遮蔽は考えていません。")
        }
    }

    private static func timeText(_ date: Date, nightStart: Date) -> String {
        let c = Calendar.tokyo.dateComponents([.hour, .minute, .day], from: date)
        let nextDay = Calendar.tokyo.component(.day, from: nightStart) != c.day
        return (nextDay ? "翌" : "") + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func dayText(_ date: Date) -> String {
        let c = Calendar.tokyo.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)"
    }
}
