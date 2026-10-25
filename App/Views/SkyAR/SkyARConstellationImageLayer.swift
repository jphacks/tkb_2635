import StarCore
import SwiftUI

/// AR の星座の姿の画像（PNG）。StarCore が空に置いた網目の三角形ごとに、画像の同じ三角形を切り抜いて貼る。
/// 建物などでさえぎられている部分は、線と同じく薄くする。
enum SkyARConstellationImageLayer {
    private typealias Style = ConstellationStyle

    static func draw(_ snapshot: SkySnapshot, projector: CameraProjector, in context: inout GraphicsContext, size: CGSize) {
        let screen = CGRect(origin: .zero, size: size)
        for placed in snapshot.images {
            guard let uiImage = ConstellationImageAssets.image(named: placed.image) else { continue }
            let image = context.resolve(Image(uiImage: uiImage))
            let n = placed.divisions
            let imageRect = CGRect(x: 0, y: 0, width: placed.width, height: placed.height)
            for row in 0..<n {
                for column in 0..<n {
                    let corners = [(row, column), (row, column + 1), (row + 1, column), (row + 1, column + 1)]
                    for triangle in [[0, 1, 2], [1, 3, 2]] {
                        let cells = triangle.map { corners[$0] }
                        let points = cells.map { placed.grid[$0.0][$0.1] }
                        // 地平線より下だけの三角形と、カメラの後ろにかかる三角形は描かない
                        guard points.contains(where: { $0.direction.up > 0 }) else { continue }
                        let projected = points.compactMap { projector.project($0.direction) }
                        guard projected.count == 3 else { continue }
                        let screenPoints = projected.map { CGPoint(x: $0.x, y: $0.y) }
                        var path = Path()
                        path.addLines(screenPoints)
                        path.closeSubpath()
                        guard path.boundingRect.intersects(screen) else { continue }
                        let pixels = cells.map { (placed.width * Double($0.1) / Double(n), placed.height * Double($0.0) / Double(n)) }
                        guard let map = TriangleAffine(from: pixels, to: projected.map { ($0.x, $0.y) }) else { continue }
                        var layer = context
                        layer.opacity = Style.imageOpacity * (points.contains(where: \.isBlocked) ? Style.blockedOpacity : 1)
                        layer.clip(to: path)
                        layer.concatenate(CGAffineTransform(a: map.a, b: map.b, c: map.c, d: map.d, tx: map.tx, ty: map.ty))
                        layer.draw(image, in: imageRect)
                    }
                }
            }
        }
    }

    /// 画像に光る印が描き込まれている星の、画面の位置（アプリの星の光を重ねないために使う）
    static func markedPoints(_ snapshot: SkySnapshot, projector: CameraProjector) -> [CGPoint] {
        snapshot.images.flatMap(\.markedStars).compactMap { point in
            guard point.direction.up > 0, let p = projector.project(point.direction) else { return nil }
            return CGPoint(x: p.x, y: p.y)
        }
    }
}
