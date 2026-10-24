import CoreGraphics

/// 外観用の配色。実際の外壁材や点灯状況を示すものではない。
struct BuildingFacade {
    enum Style: Int, CaseIterable { case glass, stone, residential, neutral }
    let style: Style
    let variant: Int

    init(usage: String?, id: String) {
        let usage = usage ?? ""
        if usage.contains("住宅") || usage.contains("住居") {
            style = .residential
        } else if usage.contains("業務") || usage.contains("オフィス") {
            style = .glass
        } else if usage.contains("商業") || usage.contains("ホテル") {
            style = .stone
        } else {
            style = .neutral
        }
        // SwiftのhashValueは起動ごとに変わるため、外観には固定ハッシュを使う。
        let hash = id.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        variant = Int(hash % 4)
    }

    init(style: Style, variant: Int) {
        self.style = style
        self.variant = variant
    }

    static let tileColumns = 8
    static let tileRows = 8
    static let columnMeters: Float = 3.2
    static let floorMeters: Float = 3.4

    var wall: CGColor {
        switch style {
        case .glass: CGColor(red: 0.18, green: 0.24, blue: 0.30, alpha: 1)
        case .stone: CGColor(red: 0.40, green: 0.39, blue: 0.36, alpha: 1)
        case .residential: CGColor(red: 0.33, green: 0.32, blue: 0.31, alpha: 1)
        case .neutral: CGColor(red: 0.29, green: 0.32, blue: 0.36, alpha: 1)
        }
    }

    /// 壁と発光を別画像にし、暗い壁全体が発光しないようにする。
    func image(emission: Bool) -> CGImage? {
        let pixels = 256
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: pixels * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(emission ? CGColor(gray: 0, alpha: 1) : wall)
        context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let cell = CGFloat(pixels) / CGFloat(Self.tileColumns)
        for row in 0..<Self.tileRows {
            for column in 0..<Self.tileColumns {
                let random = (UInt32(row * 977 + column * 131 + variant * 7_919) &* 2_654_435_761) ^ UInt32(row * column * 97)
                let lit = random % 100 < 27
                if emission && !lit { continue }
                let warm = CGColor(red: 0.88, green: 0.67, blue: 0.38, alpha: 1)
                let cool = CGColor(red: 0.61, green: 0.70, blue: 0.78, alpha: 1)
                let dark = CGColor(red: 0.09, green: 0.14, blue: 0.20, alpha: 1)
                context.setFillColor(lit ? (random % 7 == 0 ? cool : warm) : dark)
                let inset: CGFloat = style == .glass ? 2.5 : 7
                let rectangle = CGRect(x: CGFloat(column) * cell + inset, y: CGFloat(row) * cell + 7,
                                       width: cell - 2 * inset, height: cell - 12)
                context.fill(rectangle)
                if !emission && style == .glass {
                    context.setFillColor(CGColor(red: 0.25, green: 0.32, blue: 0.39, alpha: 1))
                    context.fill(CGRect(x: rectangle.midX, y: rectangle.minY, width: 1, height: rectangle.height))
                }
            }
        }
        return context.makeImage()
    }
}
