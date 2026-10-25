import simd
import StarCore
import SwiftUI

/// 広域 3D のピンの上に出す地点名。3D の点を画面の位置に直して SwiftUI の文字を重ねるので、いつも正面を向く。
/// 遠くから見ているときは文字が重なるので、選んでいる（見ている中心に一番近い）地点だけに出す。
/// RealityView の attachments は iOS 26 からなので、iOS 18 でも動くこの形にしている。
struct WideCityLabels: View {
    /// カメラの距離（1 単位 = 100m）がこれより近いと、画面に入っているピン全部に地点名を出す
    static let showAllDistance: Float = 60
    /// 頭の上と文字の間 [pt]
    private static let gap: CGFloat = 4
    /// 画面の外のピンを数えないための、画面の縁からのはみ出しの許し [pt]
    private static let margin: CGFloat = 40

    let contexts: [SpotContext]
    let predictions: [Prediction]
    let camera: WideCityCamera
    let size: CGSize
    let selectedId: String?

    var body: some View {
        ZStack {
            ForEach(labels, id: \.id) { label in
                // 大きさ 0 の点をピンの頭の上に置き、文字の下端の中央をその点に合わせる
                Color.clear
                    .frame(width: 0, height: 0)
                    .overlay(alignment: .bottom) {
                        WideCityLabel(name: label.name, selected: label.id == selectedId)
                            .padding(.bottom, Self.gap)
                    }
                    .position(label.point)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 出す地点名と、画面上の位置。遠い順に並べ、近いピンの名前を上に重ねる
    private var labels: [(id: String, name: String, point: CGPoint, depth: Float)] {
        let showsAll = camera.distance < Self.showAllDistance
        let eye = camera.eye(scale: WideCityView.scale).eye
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -Self.margin, dy: -Self.margin)
        return contexts.compactMap { context -> (id: String, name: String, point: CGPoint, depth: Float)? in
            guard showsAll || context.id == selectedId else { return nil }
            let spot = context.spot
            let p = WideCity.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            let top = SIMD3<Float>(Float(p.east), Float(spot.observerElevation), -Float(p.north)) * WideCityView.scale
            let distance = simd_length(eye - top)
            // ピンの描画（WideCityPins.headSize）と同じ大きさで、頭のいちばん上の位置を求める
            let head = WideCityPins.headSize(distance: distance, selected: context.id == selectedId)
            guard let point = camera.project(top + [0, head * WideCityPins.headTopHeight, 0],
                                             scale: WideCityView.scale, in: size),
                  bounds.contains(point) else { return nil }
            return (context.id, spot.name, point, distance)
        }
        .sorted { $0.depth > $1.depth }
    }
}

/// 白い小さめの文字に、半透明の黒い背景
private struct WideCityLabel: View {
    let name: String
    let selected: Bool

    var body: some View {
        Text(name)
            .font(.caption2.weight(selected ? .bold : .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: .capsule)
            .fixedSize()
    }
}
