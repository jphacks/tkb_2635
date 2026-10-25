import StarCore
import SwiftUI

/// AR の星座（ガラス調の線・にじむ星・淡い線画・ガラスの名札）。3D の空と同じ `ConstellationStyle` で描く。
/// 建物などでさえぎられている線・絵・名札は、消さずに薄く描く。
enum SkyARConstellationLayer {
    private typealias Style = ConstellationStyle

    static func draw(_ snapshot: SkySnapshot, projector: CameraProjector, in context: inout GraphicsContext, size: CGSize) {
        let lines = snapshot.constellations.flatMap { $0.polylines.flatMap { segments($0, projector: projector) } }
        let art = snapshot.art.flatMap { $0.strokes.flatMap { segments($0, projector: projector) } }
        SkyARConstellationImageLayer.draw(snapshot, projector: projector, in: &context, size: size)

        // にじみ: ぼかした太い線を 1 枚の層にまとめて描く（線ごとにぼかすより軽い）
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: Style.arGlowBlur))
            for segment in art where !segment.isBlocked {
                layer.stroke(segment.path, with: .color(Style.artColor.opacity(Style.artOpacity)), lineWidth: Style.arGlowWidth)
            }
            for segment in lines where !segment.isBlocked {
                layer.stroke(segment.path, with: .color(Style.lineColor.opacity(Style.lineGlowOpacity)), lineWidth: Style.arGlowWidth)
            }
        }
        for segment in art {
            let opacity = segment.isBlocked ? Style.blockedOpacity * Style.artOpacity : Style.artOpacity
            context.stroke(segment.path, with: .color(Style.artColor.opacity(opacity)), lineWidth: Style.arArtWidth)
        }
        for segment in lines {
            let opacity = segment.isBlocked ? Style.blockedOpacity : Style.lineCoreOpacity
            context.stroke(segment.path, with: .color(Style.lineColor.opacity(opacity)), lineWidth: Style.arLineWidth)
        }
        drawStars(snapshot, projector: projector, in: &context, size: size)
        drawLabels(snapshot, projector: projector, in: &context, size: size)
    }

    private struct Segment {
        let path: Path
        let isBlocked: Bool
    }

    /// 両端が地平線より上にあり、カメラの前にある線分だけ
    private static func segments(_ line: [SkyPoint], projector: CameraProjector) -> [Segment] {
        zip(line, line.dropFirst()).compactMap { a, b in
            guard a.direction.up > 0, b.direction.up > 0,
                  let p = projector.project(a.direction), let q = projector.project(b.direction) else { return nil }
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y))
            path.addLine(to: CGPoint(x: q.x, y: q.y))
            return Segment(path: path, isBlocked: a.isBlocked || b.isBlocked)
        }
    }

    /// 線のつなぎ目の星を、にじむ光の点にする
    private static func drawStars(_ snapshot: SkySnapshot, projector: CameraProjector,
                                  in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -Style.arStarGlowRadius, dy: -Style.arStarGlowRadius)
        // 画像に光る印がある星は、その印をそのまま使う（光を二重にしない）
        var drawn = SkyARConstellationImageLayer.markedPoints(snapshot, projector: projector)
        for point in snapshot.constellations.flatMap({ $0.polylines.joined() }) where point.direction.up > 0 {
            guard let p = projector.project(point.direction) else { continue }
            let center = CGPoint(x: p.x, y: p.y)
            // 同じ星が複数の折れ線に入っているので、重ねて描かない
            guard bounds.contains(center), !drawn.contains(where: { abs($0.x - center.x) < 0.5 && abs($0.y - center.y) < 0.5 })
            else { continue }
            drawn.append(center)
            let opacity = point.isBlocked ? Style.blockedOpacity : Style.starOpacity
            let glow = Style.arStarGlowRadius, core = Style.arStarCoreRadius
            context.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
                         with: .radialGradient(Gradient(colors: [Style.lineColor.opacity(0.55 * opacity), .clear]),
                                               center: center, startRadius: 0, endRadius: glow))
            context.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)),
                         with: .color(.white.opacity(opacity)))
        }
    }

    /// 見ている向きに近い星座だけ、ガラスの名札を出す
    private static func drawLabels(_ snapshot: SkySnapshot, projector: CameraProjector,
                                   in context: inout GraphicsContext, size: CGSize) {
        let candidates = snapshot.constellations.compactMap { c -> ConstellationLabelCandidate? in
            c.label.map { ConstellationLabelCandidate(id: c.id, direction: $0.direction, brightestMagnitude: c.brightestMagnitude) }
        }
        let picked = Set(ConstellationLabelPicker.pick(candidates, viewDirection: projector.attitude.lookDirection,
                                                       maximumAngle: projector.verticalFieldOfView * Style.labelFieldFraction))
        let bounds = CGRect(origin: .zero, size: size)
        for constellation in snapshot.constellations where picked.contains(constellation.id) {
            guard let label = constellation.label, let p = projector.project(label.direction) else { continue }
            let center = CGPoint(x: p.x, y: p.y)
            guard bounds.contains(center) else { continue }
            let text = context.resolve(Text(constellation.name)
                .font(.system(size: Style.labelFontSize, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Style.labelTextColor))
            let textSize = text.measure(in: size)
            let plate = CGRect(x: center.x - textSize.width / 2 - Style.labelPadding.width,
                               y: center.y - textSize.height / 2 - Style.labelPadding.height,
                               width: textSize.width + Style.labelPadding.width * 2,
                               height: textSize.height + Style.labelPadding.height * 2)
            let shape = Capsule().path(in: plate)
            var layer = context
            layer.opacity = label.isBlocked ? Style.blockedLabelOpacity : 1
            layer.fill(shape, with: .color(.white.opacity(Style.labelPlateOpacity)))
            // 上半分の照り返し（ガラスの厚みの感じ）
            layer.fill(shape, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .clear]),
                                                    startPoint: CGPoint(x: plate.midX, y: plate.minY),
                                                    endPoint: CGPoint(x: plate.midX, y: plate.midY)))
            layer.stroke(shape, with: .color(.white.opacity(Style.labelBorderOpacity)), lineWidth: 0.6)
            layer.draw(text, at: center)
        }
    }
}
