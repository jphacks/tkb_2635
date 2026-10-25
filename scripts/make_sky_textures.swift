// 4-10・4-12 月と星空の画像を作る。
//
// 使い方:
//   swift scripts/make_sky_textures.swift <原本のフォルダ> App/Resources/Sky
//
// 原本（リポジトリの外に置く）:
//   lroc_color_poles_4k.tif  NASA SVS「CGI Moon Kit」 https://svs.gsfc.nasa.gov/4720（4096×2048、約 13 MB）
//   starmap_2020_4k.exr  NASA SVS「Deep Star Maps 2020」 https://svs.gsfc.nasa.gov/4851
//
// 出力:
//   moon_disk.png  月の表側を正射図法で円に切り出したもの（1024×1024、円の外は透明。大きく見せても細部が出るように 4k の地図から作る）
//   stars_city.png / stars_suburban.png / stars_dark.png
//                  星図を、見える一番暗い星の等級ごとに黒を持ち上げたもの（4096×2048）
//
// 環境に numpy・PIL が無くても動くよう、macOS の ImageIO で読み書きする（Python ではなく Swift）。
import CoreGraphics
import simd
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// magnitude は見える一番暗い星の等級（StarVisibility.Level.limitingMagnitude と合わせる。目安の値）。
/// sky は空そのものの明るさ（直線の値）。街の光で明るい空ほど灰色がかった紺にする（見た目の目安）
/// magnitude が nil の段階は星を消さない（星図の全部。天の川も残る）
let levels: [(name: String, magnitude: Double?, sky: SIMD3<Float>)] = [
    ("stars_city", 2.5, SIMD3(0.012, 0.013, 0.024)),
    ("stars_suburban", 4.0, SIMD3(0.005, 0.006, 0.012)),
    ("stars_dark", nil, SIMD3(0.0012, 0.0015, 0.003)),
]
/// 等級と光の量の関係を測るための星（J2000 の赤経・赤緯 [度]、視等級）。オリオン座とおうし座の、まわりに明るい星や星雲の無いもの。
/// プレアデス星団（星が混み合う）・オリオン大星雲のそば・天の北極の近く（画像が横に伸びる）の星は、光の量が正しく測れないので使わない
let referenceStars: [(name: String, ra: Double, dec: Double, magnitude: Double)] = [
    ("リゲル", 78.634, -8.202, 0.13), ("ベテルギウス", 88.793, 7.407, 0.42),
    ("アルデバラン", 68.980, 16.509, 0.86), ("ベラトリックス", 81.283, 6.350, 1.64),
    ("アルニラム", 84.053, -1.202, 1.69), ("アルニタク", 85.190, -1.943, 1.77),
    ("ミンタカ", 83.002, -0.299, 2.23), ("エータ・オリオニス", 81.119, -2.397, 3.36),
    ("32 オリオニス", 82.696, 5.948, 4.20),
]
/// 星を丸く広げる半径 [画素]。1 画素の星を拡大すると四角く見えるので、周りへ明るさを落としながら広げる
let starRadius = 2
let starSigma: Float = 0.75
let moonSize = 1024

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// 画像を、1画素あたり RGBA の Float（直線の明るさ）で読む。
/// EXR は 16 bit の浮動小数点のまま画素を読む（描き直すと 1.0 より明るい値が切れるため）
func loadFloat(_ url: URL) -> (pixels: [Float], width: Int, height: Int) {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldAllowFloat: true] as CFDictionary)
    else { fail("読めません: \(url.path)") }
    let width = image.width, height = image.height
    var pixels = [Float](repeating: 0, count: width * height * 4)
    if image.bitmapInfo.contains(.floatComponents), image.bitsPerComponent == 16,
       let data = image.dataProvider?.data as Data? {
        let channels = image.bitsPerPixel / 16
        data.withUnsafeBytes { raw in
            for y in 0..<height {
                let row = raw.baseAddress!.advanced(by: y * image.bytesPerRow).assumingMemoryBound(to: Float16.self)
                for x in 0..<width {
                    for c in 0..<min(channels, 3) { pixels[(y * width + x) * 4 + c] = Float(row[x * channels + c]) }
                    pixels[(y * width + x) * 4 + 3] = 1
                }
            }
        }
        return (pixels, width, height)
    }
    let space = CGColorSpace(name: CGColorSpace.linearSRGB)!
    let info = CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 32,
                                bytesPerRow: width * 16, space: space, bitmapInfo: info)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return (pixels, width, height)
}

/// 8 bit の RGBA を書く（sRGB）
func save(_ bytes: [UInt8], width: Int, height: Int, to url: URL, type: UTType, alpha: Bool) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = (alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast).rawValue
    var copy = bytes
    let image = copy.withUnsafeMutableBytes { buffer in
        CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space, bitmapInfo: info)!.makeImage()!
    }
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { fail("書けません: \(url.path)") }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { fail("書けません: \(url.path)") }
    print("書きました:", url.lastPathComponent, width, "x", height)
}

func srgb(_ linear: Float) -> UInt8 {
    let v = max(0, min(1, linear))
    let s = v <= 0.003_130_8 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    return UInt8((s * 255).rounded())
}

/// 月の表側（経度 0° が中心）を、正面から見た円にする
func makeMoon(_ source: URL, _ output: URL) {
    let map = loadFloat(source)
    var bytes = [UInt8](repeating: 0, count: moonSize * moonSize * 4)
    for py in 0..<moonSize {
        for px in 0..<moonSize {
            let x = (Double(px) + 0.5) / Double(moonSize) * 2 - 1
            let y = 1 - (Double(py) + 0.5) / Double(moonSize) * 2
            let r2 = x * x + y * y
            guard r2 <= 1 else { continue }
            let z = (1 - r2).squareRoot()
            let lat = asin(y), lon = atan2(x, z)
            // 正距円筒: 中央が経度 0°、上が北
            let u = Int(((0.5 + lon / (2 * .pi)) * Double(map.width)).rounded(.down)) % map.width
            let v = min(map.height - 1, Int(((0.5 - lat / .pi) * Double(map.height)).rounded(.down)))
            let i = (v * map.width + u) * 4, o = (py * moonSize + px) * 4
            // 縁は 1 画素ぶんだけ透明に近づけて、ぎざぎざを目立たなくする
            let edge = Float(min(1, (1 - r2.squareRoot()) * Double(moonSize) / 2))
            for c in 0..<3 { bytes[o + c] = UInt8(Float(srgb(map.pixels[i + c])) * edge) }
            bytes[o + 3] = UInt8(255 * edge)
        }
    }
    save(bytes, width: moonSize, height: moonSize, to: output.appending(path: "moon_disk.png"), type: .png, alpha: true)
}

/// 一辺 2r+1 画素の正方形の輝度の合計（横に足してから縦に足す）
func boxSum(_ luminance: [Float], width: Int, height: Int, radius: Int) -> [Float] {
    var rows = [Float](repeating: 0, count: luminance.count)
    for y in 0..<height {
        for x in 0..<width {
            var sum: Float = 0
            for dx in -radius...radius { sum += luminance[y * width + (x + dx + width) % width] }
            rows[y * width + x] = sum
        }
    }
    var result = [Float](repeating: 0, count: luminance.count)
    for y in 0..<height {
        for x in 0..<width {
            var sum: Float = 0
            for dy in -radius...radius { sum += rows[min(max(y + dy, 0), height - 1) * width + x] }
            result[y * width + x] = sum
        }
    }
    return result
}

/// 星の光の量: 9×9 画素の輝度の合計から、周り（17×17 の外側の輪）の明るさを引いたもの。
/// 元の星図は明るい星の中心が 1.0 で飽和しているので中心の値では比べられず、
/// また天の川の中では背景の光も足されるので、周りの明るさを引く
func flux(_ luminance: [Float], width: Int, height: Int) -> [Float] {
    let inner = boxSum(luminance, width: width, height: height, radius: 4)
    let outer = boxSum(luminance, width: width, height: height, radius: 8)
    let innerCount: Float = 81, ringCount: Float = 289 - 81
    return zip(inner, outer).map { i, o in max(0, i - innerCount * (o - i) / ringCount) }
}

/// 周りより明るい点（星の中心）の、光の量の一覧（星の数を数えるのに使う）
func peakFluxes(_ luminance: [Float], _ flux: [Float], width: Int, height: Int) -> [Float] {
    var result: [Float] = []
    for y in 1..<(height - 1) {
        for x in 0..<width {
            let v = luminance[y * width + x]
            guard v > 0 else { continue }
            var isPeak = true
            for dy in -1...1 where isPeak {
                for dx in -1...1 where !(dx == 0 && dy == 0) {
                    if luminance[(y + dy) * width + (x + dx + width) % width] > v { isPeak = false; break }
                }
            }
            if isPeak { result.append(flux[y * width + x]) }
        }
    }
    return result
}

/// 赤経・赤緯の近く（半径 3 画素）で一番大きい光の量
func fluxAt(ra: Double, dec: Double, _ flux: [Float], width: Int, height: Int) -> Float {
    let offset = (180 - ra).truncatingRemainder(dividingBy: 360)
    let cx = Int(((offset < 0 ? offset + 360 : offset) / 360 * Double(width)).rounded(.down))
    let cy = Int(((90 - dec) / 180 * Double(height)).rounded(.down))
    var best: Float = 0
    for dy in -3...3 {
        for dx in -3...3 {
            let y = min(max(cy + dy, 0), height - 1)
            best = max(best, flux[y * width + (cx + dx + width) % width])
        }
    }
    return best
}

/// 等級 → 光の量の境目。基準の星の log(光の量) を等級の直線で近づけ、指定の等級での値を返す
func cutFlux(magnitude: Double, _ samples: [(magnitude: Double, flux: Float)]) -> Float {
    let points = samples.filter { $0.flux > 0 }.map { ($0.magnitude, log10(Double($0.flux))) }
    let n = Double(points.count)
    let mx = points.map(\.0).reduce(0, +) / n, my = points.map(\.1).reduce(0, +) / n
    let slope = points.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +) / points.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
    print("傾き（1 等級あたり log10）:", slope)
    return Float(pow(10, my + slope * (magnitude - mx)))
}

func makeStars(_ source: URL, _ output: URL) {
    let map = loadFloat(source)
    let n = map.width * map.height
    var luminance = [Float](repeating: 0, count: n)
    for i in 0..<n {
        luminance[i] = 0.2126 * map.pixels[i * 4] + 0.7152 * map.pixels[i * 4 + 1] + 0.0722 * map.pixels[i * 4 + 2]
    }
    let fluxMap = flux(luminance, width: map.width, height: map.height)
    let samples = referenceStars.map { star -> (magnitude: Double, flux: Float) in
        let f = fluxAt(ra: star.ra, dec: star.dec, fluxMap, width: map.width, height: map.height)
        print(star.name, star.magnitude, "等", "光の量", f)
        return (star.magnitude, f)
    }
    let allPeaks = peakFluxes(luminance, fluxMap, width: map.width, height: map.height)
    for level in levels {
        // この等級より暗い星（と、その程度の淡い光）を消す。境目は少しぼかす。
        // 境目は基準の星（0〜4 等）から直線で決める。それより暗い側は直線が当てにならないので、暗い場所では消さない
        let cut = level.magnitude.map { cutFlux(magnitude: $0, samples) } ?? 0
        let soft = cut * 0.6
        var kept = [Float](repeating: 0, count: n * 4)
        for i in 0..<n {
            let t = cut > 0 ? max(0, min(1, (fluxMap[i] - soft) / (cut - soft))) : 1
            let keep = t * t * (3 - 2 * t)
            for c in 0..<3 { kept[i * 4 + c] = map.pixels[i * 4 + c] * keep }
        }
        var bytes = [UInt8](repeating: 255, count: n * 4)
        let w = map.width, h = map.height
        // 周りの画素の明るさを、距離に応じて弱めたうちの一番明るい値（足し合わせないので天の川は明るくならない）。
        // 正距円筒の画像は赤緯が高いほど横に引き伸ばされて球に貼られるので、横の広がりを 1/cos(赤緯) 倍にして、空の上で丸くする
        for y in 0..<h {
            let dec = (90 - (Double(y) + 0.5) / Double(h) * 180) * .pi / 180
            let stretch = Float(1 / max(cos(dec), 0.2))
            let reachX = min(Int((Float(starRadius) * stretch).rounded(.up)), 15)
            var weights: [(dx: Int, dy: Int, k: Float)] = []
            for dy in -starRadius...starRadius {
                for dx in -reachX...reachX {
                    let ex = Float(dx) / stretch
                    let d2 = ex * ex + Float(dy * dy)
                    guard d2 <= Float(starRadius * starRadius) else { continue }
                    weights.append((dx, dy, exp(-d2 / (2 * starSigma * starSigma))))
                }
            }
            for x in 0..<w {
                var best = SIMD3<Float>(repeating: 0)
                for (dx, dy, k) in weights {
                    let yy = min(max(y + dy, 0), h - 1)
                    let j = (yy * w + (x + dx + w) % w) * 4
                    best = simd_max(best, SIMD3(kept[j], kept[j + 1], kept[j + 2]) * k)
                }
                let i = (y * w + x) * 4
                for c in 0..<3 { bytes[i + c] = srgb(level.sky[c] + best[c]) }
            }
        }
        print(level.name, "等級", level.magnitude.map { "\($0)" } ?? "全部", "光の量の境目", cut, "残る星", allPeaks.filter { $0 >= cut }.count)
        save(bytes, width: map.width, height: map.height, to: output.appending(path: "\(level.name).png"), type: .png, alpha: false)
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("使い方: swift scripts/make_sky_textures.swift <原本のフォルダ> <出力フォルダ>") }
let input = URL(filePath: arguments[1]), output = URL(filePath: arguments[2])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
makeMoon(input.appending(path: "lroc_color_poles_4k.tif"), output)
makeStars(input.appending(path: "starmap_2020_4k.exr"), output)
