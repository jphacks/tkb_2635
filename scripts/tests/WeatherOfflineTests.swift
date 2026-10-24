import Foundation
import Synchronization
import Testing
import StarCore
@testable import WeatherAppModel

final class WeatherProtocol: URLProtocol, @unchecked Sendable {
    enum Response: Sendable { case success, offline, timeout, serverError, partial }
    static let response = Mutex<Response>(.offline)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.response.withLock { $0 }
        let url = request.url!
        #expect(request.timeoutInterval == 15)
        switch response {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        case .timeout:
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        case .partial where Double(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            .first(where: { $0.name == "longitude" })!.value!)! < 139.73:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        default:
            let status = response == .serverError ? 503 : 200
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status,
                httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            let fixture = Bundle.module.url(forResource: "open_meteo_sample", withExtension: "json", subdirectory: "Fixtures")!
            client?.urlProtocol(self, didLoad: try! Data(contentsOf: fixture))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@Suite(.serialized) @MainActor struct WeatherOfflineTests {
    private func model(response: WeatherProtocol.Response) -> AppModel {
        WeatherProtocol.response.withLock { $0 = response }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WeatherProtocol.self]
        let model = AppModel(client: OpenMeteoClient(session: URLSession(configuration: config)))
        model.date = Date(timeIntervalSince1970: 1_792_836_000)
        return model
    }

    @Test func offlineLaunchKeepsSpotsAndPredictions() async {
        let model = model(response: .offline)
        await model.refreshWeather()
        #expect(!model.contexts.isEmpty)
        #expect(!model.isLoadingWeather)
        #expect(model.weatherLoadError?.contains("天気：未取得") == true)
        #expect(model.predictions.count == model.contexts.count)
        #expect(model.predictions.allSatisfy { $0.weatherScore == nil && $0.dataQualityFlags.contains(.weatherMissing) })
        #expect(model.contexts.allSatisfy { model.weather(for: $0.spot) == nil })
    }

    @Test(arguments: [WeatherProtocol.Response.timeout, .serverError])
    func requestFailureFinishesLoading(response: WeatherProtocol.Response) async {
        let model = model(response: response)
        await model.refreshWeather()
        #expect(!model.isLoadingWeather)
        #expect(model.weatherLoadError != nil)
    }

    @Test func partialFailureKeepsSuccessfulGrids() async throws {
        let model = model(response: .partial)
        let fixture = Bundle.module.url(forResource: "open_meteo_sample", withExtension: "json", subdirectory: "Fixtures")!
        let samples = try OpenMeteoClient.decode(Data(contentsOf: fixture), gridId: "", fetchedAt: Date())
        model.date = try #require(samples.first).forecastTime
        await model.refreshWeather()
        #expect(model.weatherLoadError?.contains("一部の地点") == true)
        #expect(!model.isLoadingWeather)
        #expect(model.contexts.contains { model.weather(for: $0.spot) != nil })
        #expect(model.contexts.contains { model.weather(for: $0.spot) == nil })
    }

    @Test func retryRecoversAndLaterFailureClearsOldForecast() async throws {
        let model = model(response: .offline)
        let fixture = Bundle.module.url(forResource: "open_meteo_sample", withExtension: "json", subdirectory: "Fixtures")!
        let samples = try OpenMeteoClient.decode(Data(contentsOf: fixture), gridId: "", fetchedAt: Date())
        model.date = try #require(samples.first).forecastTime
        await model.refreshWeather()
        #expect(model.weatherLoadError != nil)
        WeatherProtocol.response.withLock { $0 = .success }
        await model.refreshWeather()
        #expect(model.weatherLoadError == nil)
        #expect(!model.isLoadingWeather)
        #expect(model.contexts.allSatisfy { model.weather(for: $0.spot) != nil })
        WeatherProtocol.response.withLock { $0 = .offline }
        await model.refreshWeather()
        #expect(model.contexts.allSatisfy { model.weather(for: $0.spot) == nil })
        #expect(model.weatherLoadError != nil)
    }
}
