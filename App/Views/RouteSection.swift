import MapKit
import StarCore
import SwiftUI

/// 詳細シートの「経路」。現在地からの距離と、Apple マップで経路を開くボタン。
/// 徒歩のときは、取れれば経路の線を小さな地図に描く（MKDirections は公共交通の線を返さない）。
struct RouteSection: View {
    @Environment(LocationModel.self) private var location
    let spot: Spot
    @State private var mode: TransportMode = .transit
    @State private var walkingRoute: MKRoute?

    private static let mapHeight: CGFloat = 180

    var body: some View {
        Section {
            if let km = location.distanceKm(to: spot) {
                LabeledContent("現在地から（直線）", value: Distance.label(km: km))
            } else {
                Label("現在地が取れません。設定で位置情報を許可すると距離と経路が出ます", systemImage: "location.slash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Picker("移動手段", selection: $mode) {
                ForEach(TransportMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if mode == .walking, let route = walkingRoute, let here = location.coordinate {
                RouteMap(route: route, from: here, to: spot)
                    .frame(height: Self.mapHeight)
                    .listRowInsets(EdgeInsets())
                LabeledContent("徒歩", value: "\(Distance.label(km: route.distance / 1000))・約\(Int((route.expectedTravelTime / 60).rounded()))分")
            }
            Button("経路を Apple マップで開く", systemImage: "map") {
                destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: mode.launchOption])
            }
        } header: {
            Text("経路")
        } footer: {
            Text("距離は現在地からの直線距離です。経路と所要時間は Apple マップで確かめてください。")
        }
        .task(id: RouteKey(mode: mode, here: location.coordinate)) {
            await loadWalkingRoute()
        }
    }

    private var destination: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.coordinate))
        item.name = spot.name
        return item
    }

    /// 徒歩の経路を取りにいく。取れなければ線は描かず、ボタンだけを出す。
    private func loadWalkingRoute() async {
        guard mode == .walking, let here = location.coordinate else {
            walkingRoute = nil
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: here))
        request.destination = destination
        request.transportType = .walking
        walkingRoute = try? await MKDirections(request: request).calculate().routes.first
    }
}

/// 現在地から地点までの徒歩の線を描く小さな地図
private struct RouteMap: View {
    let route: MKRoute
    let from: CLLocationCoordinate2D
    let to: Spot

    var body: some View {
        Map(initialPosition: .rect(route.polyline.boundingMapRect.insetBy(
            dx: -route.polyline.boundingMapRect.width * 0.15, dy: -route.polyline.boundingMapRect.height * 0.15))) {
            MapPolyline(route.polyline).stroke(.blue, lineWidth: 4)
            Marker("現在地", systemImage: "location.fill", coordinate: from).tint(.blue)
            Marker(to.name, systemImage: "star.fill", coordinate: to.coordinate).tint(.green)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .allowsHitTesting(false)
    }
}

private struct RouteKey: Equatable {
    let mode: TransportMode
    let latitude: Double?
    let longitude: Double?

    init(mode: TransportMode, here: CLLocationCoordinate2D?) {
        self.mode = mode
        latitude = here?.latitude
        longitude = here?.longitude
    }
}

private enum TransportMode: CaseIterable {
    case transit, walking

    var label: String {
        switch self {
        case .transit: "公共交通"
        case .walking: "徒歩"
        }
    }

    var launchOption: String {
        switch self {
        case .transit: MKLaunchOptionsDirectionsModeTransit
        case .walking: MKLaunchOptionsDirectionsModeWalking
        }
    }
}

private extension Spot {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
