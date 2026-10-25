import CoreGraphics

/// シーン専用の外観（city-scenes.json の facadeStyles で選ぶ、部品名 facade_4_*・facade_5_*）。
/// 東大本郷の、茶色いスクラッチタイル張りの校舎と安田講堂を、写真を使わずに描く。
/// 1枚の画像が、都市モデルの壁の UV 1周期（窓 8 列 × 8 階、scripts/blender_city_usdz.py の FACADE_TILE_U・V）に当たる。
struct CampusFacade {
    enum Style { case scratchTile, auditorium }
    enum Map { case color, roughness, normal }
    let style: Style

    /// 部品名の種類の番号（facade_<番号>_<模様>）から外観を決める。シーン専用の外観でなければ nil。
    init?(partName: String) {
        if partName.hasPrefix("facade_4_") { style = .scratchTile }
        else if partName.hasPrefix("facade_5_") { style = .auditorium }
        else { return nil }
    }

    private static let pixels = 512
    private static let columns = 8
    private static let rows = 8

    private static let tile = (r: 0.44, g: 0.27, b: 0.18)
    private static let stone = CGColor(red: 0.62, green: 0.56, blue: 0.47, alpha: 1)
    private static let glass = CGColor(red: 0.05, green: 0.07, blue: 0.10, alpha: 1)

    private static func random(_ a: Int, _ b: Int) -> Double {
        var n = UInt32(truncatingIfNeeded: a &* 73_856_093 ^ b &* 19_349_663) &+ 0x9e37_79b9
        n = (n ^ (n >> 16)) &* 0x85eb_ca6b
        n = (n ^ (n >> 13)) &* 0xc2b2_ae35
        return Double(n ^ (n >> 16)) / Double(UInt32.max)
    }

    func image(map: Map) -> CGImage? {
        let size = Self.pixels
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        switch map {
        case .color: drawTiles(context)
        case .roughness:
            context.setFillColor(CGColor(gray: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        case .normal:
            context.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
        let cell = CGFloat(size) / CGFloat(Self.columns)
        for row in 0..<Self.rows {
            if style == .auditorium && row % 2 == 0 { band(context, map: map, y: CGFloat(row) * cell, width: CGFloat(size)) }
            for column in 0..<Self.columns {
                window(context, map: map, origin: CGPoint(x: CGFloat(column) * cell, y: CGFloat(row) * cell), cell: cell)
            }
        }
        return context.makeImage()
    }

    /// タイル1枚（約 0.23m × 0.06m）ごとに明るさを少し変え、目地を暗くする。遠目には茶色の濃淡になる。
    private func drawTiles(_ context: CGContext) {
        let size = Self.pixels
        let tileWidth = 4, tileHeight = 2
        for y in stride(from: 0, to: size, by: tileHeight) {
            let shift = (y / tileHeight) % 2 * tileWidth / 2
            for x in stride(from: -shift, to: size, by: tileWidth) {
                let v = 0.82 + Self.random(x, y) * 0.32
                context.setFillColor(CGColor(red: Self.tile.r * v, green: Self.tile.g * v, blue: Self.tile.b * v, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
            }
            context.setFillColor(CGColor(red: 0.22, green: 0.15, blue: 0.11, alpha: 0.5))
            context.fill(CGRect(x: 0, y: y, width: size, height: 1))
        }
    }

    /// 安田講堂の、階ごとの石の帯（コーニス）。
    private func band(_ context: CGContext, map: Map, y: CGFloat, width: CGFloat) {
        let rect = CGRect(x: 0, y: y + 1, width: width, height: 5)
        switch map {
        case .color: context.setFillColor(Self.stone)
        case .roughness: context.setFillColor(CGColor(gray: 0.75, alpha: 1))
        case .normal: context.setFillColor(CGColor(red: 0.5, green: 0.7, blue: 0.95, alpha: 1))
        }
        context.fill(rect)
    }

    /// 縦長の窓と石の窓台。安田講堂は上をアーチにし、窓を細く高くする。
    private func window(_ context: CGContext, map: Map, origin: CGPoint, cell: CGFloat) {
        let arched = style == .auditorium
        let width = cell * (arched ? 0.34 : 0.42)
        let height = cell * (arched ? 0.66 : 0.58)
        let pane = CGRect(x: origin.x + (cell - width) / 2, y: origin.y + cell * 0.18, width: width, height: height)
        let shape = CGMutablePath()
        if arched {
            let radius = width / 2
            shape.move(to: CGPoint(x: pane.minX, y: pane.minY))
            shape.addLine(to: CGPoint(x: pane.minX, y: pane.maxY - radius))
            shape.addArc(center: CGPoint(x: pane.midX, y: pane.maxY - radius), radius: radius,
                         startAngle: .pi, endAngle: 0, clockwise: true)
            shape.addLine(to: CGPoint(x: pane.maxX, y: pane.minY))
            shape.closeSubpath()
        } else {
            shape.addRect(pane)
        }
        let sill = CGRect(x: pane.minX - 3, y: pane.minY - 4, width: pane.width + 6, height: 4)
        switch map {
        case .color:
            context.setFillColor(Self.stone)
            context.fill(sill)
            // 窓の周りの石の縁取り
            context.setStrokeColor(Self.stone)
            context.setLineWidth(arched ? 3 : 2)
            context.addPath(shape)
            context.strokePath()
            context.setFillColor(Self.glass)
            context.addPath(shape)
            context.fillPath()
            // 窓の桟（縦1本・横1本）
            context.setFillColor(CGColor(red: 0.20, green: 0.17, blue: 0.14, alpha: 1))
            context.fill(CGRect(x: pane.midX - 1, y: pane.minY, width: 2, height: pane.height))
            context.fill(CGRect(x: pane.minX, y: pane.minY + pane.height * 0.45, width: pane.width, height: 2))
        case .roughness:
            context.setFillColor(CGColor(gray: 0.25, alpha: 1))
            context.addPath(shape)
            context.fillPath()
        case .normal:
            // 窓の凹み。左右と上下の縁だけ法線を傾ける（接線空間）。
            context.setFillColor(CGColor(red: 0.32, green: 0.5, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: pane.minX, y: pane.minY, width: 2, height: pane.height))
            context.setFillColor(CGColor(red: 0.68, green: 0.5, blue: 0.95, alpha: 1))
            context.fill(CGRect(x: pane.maxX - 2, y: pane.minY, width: 2, height: pane.height))
            context.setFillColor(CGColor(red: 0.5, green: 0.32, blue: 0.95, alpha: 1))
            context.fill(sill)
        }
    }
}
