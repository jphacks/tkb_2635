import MapKit
import StarCore
import SwiftUI

/// 地図で、ピンの色の意味を示す
struct TierLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(RecommendationTier.allTiers, id: \.self) { tier in
                Label {
                    Text(tier.label)
                } icon: {
                    Circle().fill(tier.color).frame(width: 10, height: 10)
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: .capsule)
    }
}

/// 23 区の 2D の地図に、段階の色のピンを並べる
struct SpotMap: View {
    let contexts: [SpotContext]
    let predictions: [Prediction]
    /// ピンを押したときに、その地点の ID を渡す
    let onSelect: (String) -> Void

    @State private var selectedId: String?

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.675, longitude: 139.77),
            span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.22))), selection: $selectedId) {
            ForEach(contexts) { context in
                let tier = predictions.first { $0.spotId == context.id }?.tier ?? .needsCheck
                // 標準のマーカーに任せ、縮尺と混み具合に応じて名前を間引く。
                Marker(context.spot.name, systemImage: tier == .recommended ? "star.fill" : "mappin",
                       coordinate: CLLocationCoordinate2D(latitude: context.spot.latitude, longitude: context.spot.longitude))
                    .tint(tier.color)
                    .tag(context.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .onChange(of: selectedId) { _, id in
            guard let id else { return }
            selectedId = nil
            SoundPlayer.shared.play(.pinTap)
            onSelect(id)
        }
    }
}
