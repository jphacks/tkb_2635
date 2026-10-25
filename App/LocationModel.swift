import CoreLocation
import Observation
import StarCore

/// 現在地を 1 回だけ取得する。許可されない・取れないときは coordinate が nil のまま。
@MainActor
@Observable
final class LocationModel: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var errorMessage: String?
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        // 地点までの距離が分かればよいので、精度は 100 m 程度で十分
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 使ってよいかを聞く（まだ聞いていないとき）。許可済みならすぐ現在地を取りにいく。
    func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// 現在地から地点までの直線距離 [km]。現在地が無ければ nil。
    func distanceKm(to spot: Spot) -> Double? {
        coordinate.map {
            Distance.greatCircleKm(fromLatitude: $0.latitude, fromLongitude: $0.longitude,
                                   toLatitude: spot.latitude, toLongitude: spot.longitude)
        }
    }
}

// CLLocationManager はメインスレッドで作ったので、通知もメインスレッドに届く
extension LocationModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else if status == .denied || status == .restricted {
                coordinate = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last?.coordinate else { return }
        MainActor.assumeIsolated {
            coordinate = latest
            errorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated { errorMessage = message }
    }
}
