import Foundation
import Observation
import StarCore

@MainActor
@Observable
final class AppModel {
    let contexts: [SpotContext]
    var date: Date = AppModel.tonight()
    var target: ObservationTarget = .moon
    /// 星座と代表星を区別するための表示用ID。観測計算は従来のtargetを使う。
    var selectedCabinTargetID: String?
    var isLoadingWeather = false
    var weatherLoadError: String?
    var loadError: String?
    /// 格子 ID ごとの時別予報。新しいうちは取り直さない。
    private var forecasts = WeatherCache()
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

    /// 予報を書き換えた回数。予想の覚え（predictionCache）が古くなったかを見分ける
    private var forecastRevision = 0
    /// 最後に計算した予想。全地点の天体位置と遮蔽の計算は重く、ホームの 3D を動かすたびに画面が描き直されるので、
    /// 天体・日時・予報が変わったときだけ計算し直す
    @ObservationIgnored private var predictionCache: (key: PredictionKey, value: [Prediction])?

    var predictions: [Prediction] {
        let key = PredictionKey(target: target, date: date, forecastRevision: forecastRevision)
        if let cache = predictionCache, cache.key == key { return cache.value }
        let value = Recommender.rank(contexts.map {
            Recommender.evaluate($0, target: target, date: date, weather: weather(for: $0.spot),
                                 forecastCoverage: forecastCoverage(for: $0.spot))
        })
        predictionCache = (key, value)
        return value
    }

    func context(id: String) -> SpotContext? {
        contexts.first { $0.id == id }
    }

    func weather(for spot: Spot) -> Weather? {
        let grid = OpenMeteoClient.gridId(latitude: spot.latitude, longitude: spot.longitude)
        return forecasts.samples(for: grid).flatMap { OpenMeteoClient.nearest($0, to: date) }
    }

    func forecastCoverage(for spot: Spot) -> ForecastCoverage {
        let grid = OpenMeteoClient.gridId(latitude: spot.latitude, longitude: spot.longitude)
        return OpenMeteoClient.coverage(of: forecasts.samples(for: grid) ?? [], at: date)
    }

    /// 選んだ日時が予報の範囲外のときに出す文。範囲内なら nil。
    var forecastOutOfRangeMessage: String? {
        contexts.lazy.compactMap { self.forecastCoverage(for: $0.spot).message }.first
    }

    var moon: MoonInfo {
        Astro.moon(date: date, latitude: 35.6812, longitude: 139.7671)
    }

    /// 天気を取得する。取得してから間もない地域は通信せず、覚えている予報を使う。
    func refreshWeather() async {
        guard !isLoadingWeather else { return }
        var grids: [String: Spot] = [:]
        for spot in contexts.map(\.spot) {
            grids[OpenMeteoClient.gridId(latitude: spot.latitude, longitude: spot.longitude)] = spot
        }
        let totalCount = grids.count
        let stale = forecasts.gridsToFetch(grids.keys)
        grids = grids.filter { stale.contains($0.key) }
        guard !grids.isEmpty else { return }
        isLoadingWeather = true
        weatherLoadError = nil
        defer { isLoadingWeather = false }
        var failedCount = 0
        await withTaskGroup(of: (String, [Weather]?).self) { group in
            for (grid, spot) in grids {
                group.addTask { [client] in
                    (grid, try? await client.fetchHourly(latitude: spot.latitude, longitude: spot.longitude))
                }
            }
            for await (grid, samples) in group {
                if let samples, !samples.isEmpty {
                    forecasts.store(samples, for: grid)
                } else {
                    // 更新に失敗した地域の古い予報を、最新の天気として使わない。
                    forecasts.remove(grid)
                    failedCount += 1
                }
                forecastRevision += 1
            }
        }
        if failedCount > 0 {
            weatherLoadError = failedCount == totalCount
                ? "天気：未取得。通信状況を確認し、「天気を更新」で再取得してください。"
                : "一部の地点の天気：未取得。通信状況を確認し、「天気を更新」で再取得してください。"
        }
    }
}

/// 予想を計算し直すかを決める入力
private struct PredictionKey: Equatable {
    let target: ObservationTarget
    let date: Date
    let forecastRevision: Int
}
