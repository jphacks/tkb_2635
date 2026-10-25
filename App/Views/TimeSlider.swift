import StarCore
import SwiftUI

/// その夜（18:00〜翌 6:00）の中で、観測時刻を 15 分刻みで動かす
struct TimeSlider: View {
    @AppStorage(TimeNotation.storageKey) private var timeNotation = TimeNotation.default
    @Binding var date: Date
    /// 3D の上に重ねるときの、1行の小さい表示
    var compact = false

    var body: some View {
        let night = ObservingNight(containing: date)
        if compact {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeText(date))
                        .font(.headline.monospacedDigit())
                    Text(night.contains(date) ? "\(Self.dayText(night.start))の夜" : "夜の範囲外")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 56, alignment: .leading)
                slider(night)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("時刻")
                    Spacer()
                    Text(timeText(date))
                        .font(.headline.monospacedDigit())
                }
                slider(night)
                Text(night.contains(date)
                     ? "\(Self.dayText(night.start))の夜。動かすと天体の位置と判定が変わります。"
                     : "選んだ時刻は夜の範囲（18時〜翌6時）の外です。動かすと夜の時刻になります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func slider(_ night: ObservingNight) -> some View {
        Slider(value: Binding(
            get: { Double(night.step(for: date)) },
            set: {
                let newDate = night.date(atStep: Int($0.rounded()))
                guard newDate != date else { return }
                date = newDate
                SoundPlayer.shared.play(.timeTick)
            }
        ), in: 0...Double(night.stepCount), step: 1) {
            Text("観測時刻")
        } minimumValueLabel: {
            Text("18時").font(.caption2)
        } maximumValueLabel: {
            Text("6時").font(.caption2)
        }
        .accessibilityValue(timeText(date))
    }

    private func timeText(_ date: Date) -> String { timeNotation.text(date) }

    private static func dayText(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: TimeZone(identifier: "Asia/Tokyo")!).month(.defaultDigits).day())
    }
}
