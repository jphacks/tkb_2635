import CoreGraphics

/// 実物の外壁写真ではなく、窓枠・ガラス・室内を分けた外観表現。
struct BuildingFacade {
    enum Style: Int, CaseIterable { case glass, stone, residential, neutral }
    enum Map: CaseIterable { case color, emission, roughness, normal }
    let style: Style
    let variant: Int

    init(usage: String?, id: String) {
        let usage = usage ?? ""
        if usage.contains("住宅") || usage.contains("住居") { style = .residential }
        else if usage.contains("業務") || usage.contains("オフィス") { style = .glass }
        else if usage.contains("商業") || usage.contains("ホテル") { style = .stone }
        else { style = .neutral }
        let hash = id.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        variant = Int(hash % 4)
    }

    init(style: Style, variant: Int) {
        self.style = style
        self.variant = variant
    }

    static let tileColumns = 8
    static let tileRows = 8
    // 参考例の窓ベイ・階高（約2.5〜4m）をもとに、遠景でも細かな点になりにくくする。
    static let columnMeters: Float = 3.6
    static let floorMeters: Float = 3.9

    var wall: CGColor {
        switch style {
        case .glass: CGColor(red: 0.075, green: 0.13, blue: 0.19, alpha: 1)
        case .stone: CGColor(red: 0.28, green: 0.27, blue: 0.25, alpha: 1)
        case .residential: CGColor(red: 0.23, green: 0.22, blue: 0.21, alpha: 1)
        case .neutral: CGColor(red: 0.17, green: 0.21, blue: 0.26, alpha: 1)
        }
    }

    private func random(_ column: Int, _ row: Int) -> UInt32 {
        var n = UInt32(column + row * 31 + variant * 7_919) &+ 0x9e3779b9
        n = (n ^ (n >> 16)) &* 0x85ebca6b
        n = (n ^ (n >> 13)) &* 0xc2b2ae35
        return n ^ (n >> 16)
    }

    func image(map: Map) -> CGImage? {
        let pixels = 256
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let background: CGColor
        switch map {
        case .color: background = wall
        case .emission: background = CGColor(gray: 0, alpha: 1)
        case .roughness: background = CGColor(gray: 0.82, alpha: 1)
        case .normal: background = CGColor(red: 0.5, green: 0.5, blue: 1, alpha: 1)
        }
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let cell = CGFloat(pixels) / CGFloat(Self.tileColumns)
        for row in 0..<Self.tileRows {
            // 階の帯（スパンドレル）。壁全面の白飛びを避け、階の構造を見せる。
            if map == .color {
                context.setFillColor(CGColor(red: 0.055, green: 0.075, blue: 0.10, alpha: 1))
                context.fill(CGRect(x: 0, y: CGFloat(row) * cell, width: CGFloat(pixels), height: 4))
            }
            for column in 0..<Self.tileColumns {
                let n = random(column, row)
                let lit = n % 100 < 24
                let inset: CGFloat = style == .glass ? 2 : 6
                let pane = CGRect(x: CGFloat(column) * cell + inset, y: CGFloat(row) * cell + 5,
                                  width: cell - 2 * inset, height: cell - 8)
                let warm = CGColor(red: 0.68, green: 0.47, blue: 0.23, alpha: 1)
                let cool = CGColor(red: 0.35, green: 0.46, blue: 0.57, alpha: 1)
                switch map {
                case .color, .emission:
                    if map == .emission && !lit { continue }
                    let glass = CGColor(red: 0.045, green: 0.085, blue: 0.14, alpha: 1)
                    context.setFillColor(lit ? (n % 9 == 0 ? cool : warm) : glass)
                    context.fill(pane)
                    // 窓内の天井・床・ブラインド。発光マップにも同じ遮りを使う。
                    context.setFillColor(map == .emission ? CGColor(gray: 0, alpha: 1) : wall)
                    context.fill(CGRect(x: pane.minX, y: pane.maxY - 3, width: pane.width, height: 3))
                    context.fill(CGRect(x: pane.midX, y: pane.minY, width: 1.5, height: pane.height))
                    if n % 3 == 0 {
                        context.fill(CGRect(x: pane.minX, y: pane.midY, width: pane.width, height: 2))
                    }
                    if map == .color {
                        context.setFillColor(CGColor(gray: 0, alpha: 0.26))
                        context.fill(CGRect(x: pane.minX, y: pane.minY, width: 2, height: pane.height))
                    }
                case .roughness:
                    context.setFillColor(CGColor(gray: style == .glass ? 0.27 : 0.42, alpha: 1))
                    context.fill(pane)
                case .normal:
                    // 接線空間の凹み。RGBを法線の方向として用い、色テクスチャとは分ける。
                    context.setFillColor(CGColor(red: 0.32, green: 0.5, blue: 0.966, alpha: 1))
                    context.fill(CGRect(x: pane.minX, y: pane.minY, width: 2, height: pane.height))
                    context.setFillColor(CGColor(red: 0.68, green: 0.5, blue: 0.966, alpha: 1))
                    context.fill(CGRect(x: pane.maxX - 2, y: pane.minY, width: 2, height: pane.height))
                    context.setFillColor(CGColor(red: 0.5, green: 0.68, blue: 0.966, alpha: 1))
                    context.fill(CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: 2))
                    context.setFillColor(CGColor(red: 0.5, green: 0.32, blue: 0.966, alpha: 1))
                    context.fill(CGRect(x: pane.minX, y: pane.maxY - 2, width: pane.width, height: 2))
                }
            }
        }
        return context.makeImage()
    }
}
