import Foundation

public enum MissingStatus: String, Codable, Sendable {
    case ok, partial, missing
}

/// 時別の気象予報（仕様書 7.2）
public struct Weather: Codable, Sendable {
    public var gridId: String
    public var modelName: String
    public var forecastTime: Date
    public var fetchedAt: Date
    /// 雲量 [%]
    public var cloudCover: Double?
    /// 降水量 [mm]
    public var precipitation: Double?
    /// 風速 [km/h]
    public var wind: Double?
    /// 視程 [m]
    public var visibility: Double?
    public var missingStatus: MissingStatus
}

/// Open-Meteo Forecast API（キー不要、CC BY 4.0）
public struct OpenMeteoClient: Sendable {
    public var session: URLSession

    /// 取得する予報の日数（今日を含む）。Open-Meteo の上限は 16 日。
    public static let forecastDays = 16
    /// 予報の時刻と指定時刻のずれをどこまで許すか
    static let matchTolerance: TimeInterval = 90 * 60

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// 0.05° 単位の格子 ID。近い地点は同じ予報を共有する。
    public static func gridId(latitude: Double, longitude: Double) -> String {
        String(format: "%.2f,%.2f", (latitude * 20).rounded() / 20, (longitude * 20).rounded() / 20)
    }

    public func fetchHourly(latitude: Double, longitude: Double) async throws -> [Weather] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "cloud_cover,precipitation,wind_speed_10m,visibility"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: String(Self.forecastDays)),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.decode(data, gridId: Self.gridId(latitude: latitude, longitude: longitude), fetchedAt: Date())
    }

    public static func decode(_ data: Data, gridId: String, fetchedAt: Date) throws -> [Weather] {
        let body = try JSONDecoder().decode(Response.self, from: data)
        let h = body.hourly
        return h.time.indices.map { i in
            let values = [h.cloud_cover?[safe: i], h.precipitation?[safe: i],
                          h.wind_speed_10m?[safe: i], h.visibility?[safe: i]].map { $0 ?? nil }
            let present = values.compactMap { $0 }.count
            let status: MissingStatus = values[0] == nil ? .missing : (present == values.count ? .ok : .partial)
            return Weather(gridId: gridId, modelName: "open-meteo best_match",
                           forecastTime: Date(timeIntervalSince1970: h.time[i]), fetchedAt: fetchedAt,
                           cloudCover: values[0], precipitation: values[1], wind: values[2], visibility: values[3],
                           missingStatus: status)
        }
    }

    /// 指定時刻から 90 分以内で最も近い予報
    public static func nearest(_ samples: [Weather], to date: Date) -> Weather? {
        samples
            .filter { abs($0.forecastTime.timeIntervalSince(date)) <= matchTolerance }
            .min { abs($0.forecastTime.timeIntervalSince(date)) < abs($1.forecastTime.timeIntervalSince(date)) }
    }

    private struct Response: Decodable {
        struct Hourly: Decodable {
            var time: [Double]
            var cloud_cover: [Double?]?
            var precipitation: [Double?]?
            var wind_speed_10m: [Double?]?
            var visibility: [Double?]?
        }
        var hourly: Hourly
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
