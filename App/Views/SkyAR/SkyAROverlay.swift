import StarCore
import SwiftUI

/// AR の映像の上に、月・惑星・恒星・星座線・方角を描く。画面の位置は StarCore の `CameraProjector` が決める。
/// 建物などでさえぎられている天体・線は、消さずに薄く描く。
enum SkyAROverlay {
    private static let blockedOpacity = 0.28
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
        SkyARConstellationLayer.draw(snapshot, projector: projector, in: &context, size: size)
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
