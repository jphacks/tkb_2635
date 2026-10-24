import Foundation
import Observation
import StarCore

@MainActor
@Observable
final class AppModel {
    let contexts: [SpotContext]
    var date: Date = AppModel.tonight()
    var target: ObservationTarget = .moon
    var isLoadingWeather = false
    var weatherLoadError: String?
    var loadError: String?
    /// 格子 ID ごとの時別予報
    private var forecasts: [String: [Weather]] = [:]
    private let client: OpenMeteoClient

    init(client: OpenMeteoClient = OpenMeteoClient()) {
        self.client = client
        do {
            contexts = try SeedData.loadContexts()
        } catch {
            contexts = []
            loadError = "地点データを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    /// 今夜 21:00（東京時間）。21時を過ぎていれば次の正時。
    static func tonight(now: Date = Date()) -> Date {
        let cal = Calendar.tokyo
        let ninePM = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now)!
        if now < ninePM { return ninePM }
        return cal.nextDate(after: now, matching: DateComponents(minute: 0), matchingPolicy: .nextTime)!
    }

    var predictions: [Prediction] {
        Recommender.rank(contexts.map { Recommender.evaluate($0, target: target, date: date, weather: weather(for: $0.spot)) })
    }

    func context(id: String) -> SpotContext? {
        contexts.first { $0.id == id }
    }

    func weather(for spot: Spot) -> Weather? {
        let grid = OpenMeteoClient.gridId(latitude: spot.latitude, longitude: spot.longitude)
        return forecasts[grid].flatMap { OpenMeteoClient.nearest($0, to: date) }
    }

    var moon: MoonInfo {
        Astro.moon(date: date, latitude: 35.6812, longitude: 139.7671)
    }

    func refreshWeather() async {
        guard !isLoadingWeather else { return }
        isLoadingWeather = true
        weatherLoadError = nil
        defer { isLoadingWeather = false }
        var grids: [String: Spot] = [:]
        for spot in contexts.map(\.spot) {
            grids[OpenMeteoClient.gridId(latitude: spot.latitude, longitude: spot.longitude)] = spot
        }
        var failedCount = 0
        await withTaskGroup(of: (String, [Weather]?).self) { group in
            for (grid, spot) in grids {
                group.addTask { [client] in
                    (grid, try? await client.fetchHourly(latitude: spot.latitude, longitude: spot.longitude))
                }
            }
            for await (grid, samples) in group {
                if let samples, !samples.isEmpty {
                    forecasts[grid] = samples
                } else {
                    // 更新に失敗した地域の古い予報を、最新の天気として使わない。
                    forecasts.removeValue(forKey: grid)
                    failedCount += 1
                }
            }
        }
        if failedCount > 0 {
            weatherLoadError = failedCount == grids.count
                ? "天気：未取得。通信状況を確認し、「天気を更新」で再取得してください。"
                : "一部の地点の天気：未取得。通信状況を確認し、「天気を更新」で再取得してください。"
        }
    }
}
