import simd
import StarCore
import SwiftUI

/// 全体表示では地点名を隠し、拡大すると近くのピンに名前を表示する。
/// 名前が重なる地点は間引き、地図を移動・拡大すると表示対象が切り替わる。
struct WideCityLabels: View {
    private static let gap: CGFloat = 5
    private static let labelWidth: CGFloat = 138
    /// 1単位=100m。全体表示から十分に拡大したら名前を出す。
    private static let revealDistance: Float = 120
    private static let nearbyDistanceRatio: Float = 1.6

    let contexts: [SpotContext]
    let camera: WideCityCamera
    let size: CGSize
    let selectedId: String?
    var bottomInset: CGFloat = 0
    var topInset: CGFloat = 0

    var body: some View {
        Canvas { graphics, size in
            let top = max(6, topInset + 6)
            let bounds = CGRect(x: 6, y: top, width: max(0, size.width - 12),
                                height: max(0, size.height - bottomInset - top - 6))
            guard bounds.width > 0, bounds.height > 0 else { return }
            var placed: [(text: GraphicsContext.ResolvedText, frame: CGRect, selected: Bool)] = []
            for label in labels {
                let selected = label.id == selectedId
                let text = graphics.resolve(Text(label.name)
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .foregroundStyle(.white))
                let measured = text.measure(in: CGSize(width: min(Self.labelWidth, bounds.width) - 14,
                                                       height: .greatestFiniteMagnitude))
                let labelSize = CGSize(width: measured.width + 14, height: measured.height + 8)
                let preferred = CGPoint(x: label.point.x, y: label.point.y - labelSize.height / 2 - Self.gap)
                guard let frame = Self.place(labelSize, near: preferred, bounds: bounds,
                                             occupied: placed.map(\.frame)) else { continue }
                placed.append((text, frame, selected))
            }
            for label in placed.reversed() {
                let background = Path(roundedRect: label.frame, cornerRadius: 7)
                graphics.fill(background, with: .color(.black.opacity(label.selected ? 0.9 : 0.8)))
                if label.selected {
                    graphics.stroke(background, with: .color(.cyan.opacity(0.8)), lineWidth: 1)
                }
                graphics.draw(label.text, in: label.frame.insetBy(dx: 7, dy: 4))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 中心に近い地点を優先し、遠景の地点は名前を出さない。
    private var labels: [(id: String, name: String, point: CGPoint, depth: Float)] {
        guard camera.distance <= Self.revealDistance else { return [] }
        let eye = camera.eye(scale: WideCityView.scale).eye
        let bounds = CGRect(origin: .zero, size: size)
        return contexts.compactMap { context -> (id: String, name: String, point: CGPoint, depth: Float)? in
            let spot = context.spot
            let p = WideCity.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            let top = SIMD3<Float>(Float(p.east), Float(spot.observerElevation), -Float(p.north)) * WideCityView.scale
            let distance = simd_length(eye - top)
            guard distance <= camera.distance * Self.nearbyDistanceRatio else { return nil }
            let head = WideCityPins.headSize(distance: distance, selected: context.id == selectedId)
            guard let point = camera.project(top + [0, head * WideCityPins.headTopHeight, 0],
                                             scale: WideCityView.scale, in: size),
                  bounds.contains(point) else { return nil }
            return (context.id, spot.name, point, distance)
        }
        .sorted {
            if ($0.id == selectedId) != ($1.id == selectedId) { return $0.id == selectedId }
            return $0.depth == $1.depth ? $0.id < $1.id : $0.depth < $1.depth
        }
    }

    /// ピンのすぐ上・左右だけを使う。入らない名前は、遠くへ動かさず表示を控える。
    private static func place(_ size: CGSize, near point: CGPoint, bounds: CGRect, occupied: [CGRect]) -> CGRect? {
        let offsets: [CGFloat] = [0, size.width / 2 + gap, -size.width / 2 - gap]
        for offset in offsets {
            let rect = CGRect(x: point.x + offset - size.width / 2,
                              y: point.y - size.height / 2, width: size.width, height: size.height)
            guard bounds.contains(rect),
                  !occupied.contains(where: { $0.intersects(rect.insetBy(dx: -3, dy: -3)) }) else { continue }
            return rect
        }
        return nil
    }
}
