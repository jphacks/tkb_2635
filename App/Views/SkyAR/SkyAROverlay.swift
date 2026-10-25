import StarCore
import SwiftUI

/// AR の映像の上に、月・惑星・恒星・星座線・方角を描く。画面の位置は StarCore の `CameraProjector` が決める。
/// 建物などでさえぎられている天体・線は、消さずに薄く描く。
enum SkyAROverlay {
    private static let blockedOpacity = 0.28
    private static let lineOpacity = 0.6
    private static let lineColor = Color(red: 0.75, green: 0.9, blue: 1)
    /// この等級より明るい恒星だけ名前を出す（出しすぎると画面が埋まる）
    private static let labeledStarMagnitude = 1.5
    /// 画面の外へこれだけはみ出した位置までは描く（点の大きさ分）
    private static let margin: CGFloat = 40
    private static let planetColors: [String: Color] = [
        "mercury": Color(white: 0.8), "venus": Color(red: 1, green: 0.96, blue: 0.8),
        "mars": Color(red: 1, green: 0.5, blue: 0.4), "jupiter": Color(red: 0.95, green: 0.82, blue: 0.62),
        "saturn": Color(red: 0.93, green: 0.82, blue: 0.5),
    ]
    private static let compass: [(label: String, azimuth: Double)] = [("北", 0), ("東", 90), ("南", 180), ("西", 270)]

    static func draw(_ snapshot: SkySnapshot, projector: CameraProjector, in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -margin, dy: -margin)
        func screen(_ direction: LocalVector) -> CGPoint? {
            guard let p = projector.project(direction) else { return nil }
            let point = CGPoint(x: p.x, y: p.y)
            return bounds.contains(point) ? point : nil
        }

        drawHorizon(projector: projector, in: &context, size: size)
        for constellation in snapshot.constellations {
            for line in constellation.polylines { drawLine(line, projector: projector, in: &context) }
            if let label = constellation.label, label.direction.up > 0, let point = screen(label.direction) {
                context.opacity = label.isBlocked ? blockedOpacity : 0.8
                context.draw(Text(constellation.name).font(.caption2).foregroundStyle(lineColor), at: point)
            }
        }
        for object in snapshot.objects where object.isAboveHorizon {
            guard let point = screen(object.direction) else { continue }
            context.opacity = object.isBlocked ? blockedOpacity : 1
            draw(object, at: point, in: &context)
        }
        context.opacity = 1
    }

    private static func draw(_ object: SkyObject, at point: CGPoint, in context: inout GraphicsContext) {
        let (radius, color) = switch object.kind {
        case .moon: (CGFloat(15), Color(red: 1, green: 0.97, blue: 0.82))
        case .planet: (CGFloat(7), planetColors[object.id] ?? .white)
        case .star: (CGFloat(max(1.5, 4 - (object.magnitude ?? 4))), Color.white)
        }
        let dot = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        if object.kind != .star {
            context.fill(Path(ellipseIn: dot.insetBy(dx: -radius * 0.6, dy: -radius * 0.6)), with: .color(color.opacity(0.25)))
        }
        context.fill(Path(ellipseIn: dot), with: .color(color))
        let isLabeled = object.kind != .star || (object.magnitude ?? 9) <= labeledStarMagnitude
        if isLabeled {
            context.draw(Text(object.name).font(.caption).bold().foregroundStyle(.white),
                         at: CGPoint(x: point.x, y: point.y + radius + 10))
        }
    }

    /// 星座の折れ線。両端が地平線より上にある線分だけ描く。さえぎられている側は薄くする
    private static func drawLine(_ line: [SkyPoint], projector: CameraProjector, in context: inout GraphicsContext) {
        for (a, b) in zip(line, line.dropFirst()) {
            guard a.direction.up > 0, b.direction.up > 0,
                  let p = projector.project(a.direction), let q = projector.project(b.direction) else { continue }
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y))
            path.addLine(to: CGPoint(x: q.x, y: q.y))
            context.opacity = (a.isBlocked || b.isBlocked) ? blockedOpacity * 0.6 : lineOpacity
            context.stroke(path, with: .color(lineColor), lineWidth: 1)
        }
    }

    /// 地平線（高度 0°）と東西南北。向きの手がかりにする
    private static func drawHorizon(projector: CameraProjector, in context: inout GraphicsContext, size: CGSize) {
        var path = Path()
        var previous: CGPoint?
        for azimuth in stride(from: 0.0, through: 360.0, by: 3) {
            let vector = LocalVector(HorizontalCoord(altitude: 0, azimuth: azimuth))
            guard let p = projector.project(vector) else { previous = nil; continue }
            let point = CGPoint(x: p.x, y: p.y)
            if let previous, abs(previous.x - point.x) < size.width { path.addLine(to: point) } else { path.move(to: point) }
            previous = point
        }
        context.opacity = 0.35
        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        context.opacity = 1
        for item in compass {
            guard let p = projector.project(LocalVector(HorizontalCoord(altitude: 0, azimuth: item.azimuth))) else { continue }
            context.draw(Text(item.label).font(.subheadline.bold()).foregroundStyle(.white.opacity(0.85)),
                         at: CGPoint(x: p.x, y: p.y + 14))
        }
    }
}
