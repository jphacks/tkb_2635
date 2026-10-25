import simd
import StarCore
import SwiftUI

/// 距離によらず、画面内の各地点名を3Dのピンにつないで表示する。
/// 文字が重なる場所では空いている位置へずらし、線で元のピンを示す。
struct WideCityLabels: View {
    private static let gap: CGFloat = 5
    private static let labelWidth: CGFloat = 138
    private static let rowStep: CGFloat = 22

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
            var placed: [(text: GraphicsContext.ResolvedText, frame: CGRect, pin: CGPoint, selected: Bool)] = []
            for label in labels {
                let selected = label.id == selectedId
                let text = graphics.resolve(Text(label.name)
                    .font(.caption2.weight(selected ? .bold : .medium))
                    .foregroundStyle(.white))
                let measured = text.measure(in: CGSize(width: min(Self.labelWidth, bounds.width) - 14,
                                                       height: .greatestFiniteMagnitude))
                let labelSize = CGSize(width: measured.width + 14, height: measured.height + 8)
                let preferred = CGPoint(x: label.point.x, y: label.point.y - labelSize.height / 2 - Self.gap)
                let frame = Self.place(labelSize, near: preferred, bounds: bounds, occupied: placed.map(\.frame))
                placed.append((text, frame, label.point, selected))
            }
            // 線を先にまとめて描き、文字や背景の上を横切らせない。
            for label in placed {
                var line = Path()
                line.move(to: label.pin)
                line.addLine(to: CGPoint(x: label.frame.midX, y: label.frame.midY))
                graphics.stroke(line, with: .color(.white.opacity(label.selected ? 0.85 : 0.4)), lineWidth: 0.75)
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

    /// 中心に近い地点から場所を確保する。同じ位置の展望台と地上も別々に表示する。
    private var labels: [(id: String, name: String, point: CGPoint, depth: Float)] {
        let eye = camera.eye(scale: WideCityView.scale).eye
        let bounds = CGRect(origin: .zero, size: size)
        return contexts.compactMap { context -> (id: String, name: String, point: CGPoint, depth: Float)? in
            let spot = context.spot
            let p = WideCity.localPosition(latitude: spot.latitude, longitude: spot.longitude)
            let top = SIMD3<Float>(Float(p.east), Float(spot.observerElevation), -Float(p.north)) * WideCityView.scale
            let distance = simd_length(eye - top)
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

    /// 近くの空き位置を探す。密集して収まらない場合も、名前は消さず重なりの少ない位置を使う。
    private static func place(_ size: CGSize, near point: CGPoint, bounds: CGRect, occupied: [CGRect]) -> CGRect {
        let rows = Int(bounds.height / rowStep)
        var best = CGRect.zero
        var bestCost = CGFloat.greatestFiniteMagnitude
        for row in -rows...rows {
            for column in -1...1 {
                let x = min(max(point.x + CGFloat(column) * labelWidth - size.width / 2, bounds.minX),
                            max(bounds.minX, bounds.maxX - size.width))
                let y = min(max(point.y + CGFloat(row) * rowStep - size.height / 2, bounds.minY),
                            max(bounds.minY, bounds.maxY - size.height))
                let rect = CGRect(origin: CGPoint(x: x, y: y), size: size)
                let overlap = occupied.reduce(CGFloat.zero) { total, other in
                    let intersection = rect.insetBy(dx: -2, dy: -2).intersection(other)
                    return total + (intersection.isNull ? 0 : intersection.width * intersection.height)
                }
                let cost = overlap * 10_000 + hypot(rect.midX - point.x, rect.midY - point.y)
                if cost < bestCost { bestCost = cost; best = rect }
            }
        }
        return best
    }
}
