import Foundation

/// 3D の夜景で、窓明かりをいつ点けるかの目安（見た目専用で、判定やスコアには使わない）。
/// 窓は消える順に 3 つのグループに分けてある（scripts/night_lights.py と数をそろえる）。
/// 0: 事務所など 22 時に消える、1: 23 時半に消える、2: 住宅など明け方まで残る。
public enum NightLightSchedule {
    public static let windowGroups = 3

    /// 窓が点き始める時刻 [時]
    static let lightsOnHour = 17
    /// グループごとの消える時刻（その日の正午からの分）。22:00・23:30・翌 5:00
    static let lightsOffMinutes = [10 * 60, 11 * 60 + 30, 17 * 60]

    /// group の窓が date（地点の時刻）に点いているか。
    public static func windowsOn(group: Int, at date: Date, calendar: Calendar = .tokyo) -> Bool {
        guard lightsOffMinutes.indices.contains(group) else { return false }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        // 日付をまたいでも比べやすいよう、正午からの分にする
        let minutes = ((parts.hour ?? 0) * 60 + (parts.minute ?? 0) - 12 * 60 + 24 * 60) % (24 * 60)
        return minutes >= (lightsOnHour - 12) * 60 && minutes < lightsOffMinutes[group]
    }
}
