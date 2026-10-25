import CoreGraphics
import RealityKit
import StarCore
import UIKit

/// 3D の空（4-10 月・4-12 星空）を作る。画像は一度だけ読み、比較画面と詳細画面で使い回す。
/// 座標は Sky3DView と同じ（x が東、y が上、-z が北）。見た目だけで、判定には使わない。
@MainActor
final class SkyRenderer {
    static let shared = SkyRenderer()

    /// 星空の球の半径 [単位]（1 単位 = 100 m）。遠くの地面より外に置く
    static let domeRadius: Float = 300
    /// 月の円の直径 [単位]。実物（約 0.5°）の約 12 倍で、見やすさのために大きくしている
    static let moonDiameter: Float = 0.44
    /// 月の暗い側の明るさ（地球照のぶん、真っ黒にしない）
    private static let earthshine: Float = 0.06
    /// 満ち欠けの絵の大きさ [画素]
    private static let moonPixels = 256

    /// 3D に出す出典。PLATEAU・地理院タイル・NASA SVS（月の写真）・EOG（遠くの地面の夜間光 VIIRS VNL）・Gaia は出典の表示が利用の条件
    static let credit = "出典: PLATEAU（CC BY 4.0）・国土地理院・NASA SVS・EOG/Colorado School of Mines（VIIRS 夜間光、CC BY 4.0）・ESA/Gaia/DPAC"

    static let domeName = "starDome"
    static let moonName = "moonDisk"

    private var starTextures: [StarVisibility.Level: TextureResource] = [:]
    private lazy var domeMesh: MeshResource? = try? Self.makeDomeMesh()
    private lazy var moonMesh: MeshResource = Self.makeMoonMesh()
    private lazy var moonDisk: CGImage? = {
        guard let url = Bundle.main.url(forResource: "moon_disk", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    // MARK: - 星空

    /// 星空の球。向き・濃さは updateDome で合わせる
    func makeDome() -> ModelEntity? {
        guard let domeMesh else { return nil }
        let dome = ModelEntity(mesh: domeMesh, materials: [UnlitMaterial(color: .black)])
        dome.name = Self.domeName
        return dome
    }

    /// 星空を、地点・時刻の空に回し、地点の暗さと薄明で濃さを変える
    func updateDome(_ dome: ModelEntity, spot: Spot, date: Date) {
        let sky = SkyOrientation(date: date, latitude: spot.latitude, longitude: spot.longitude)
        let r = Self.domeRadius
        // 列は、赤道座標の x・y・z 軸が 3D のどの向きか（球の頂点は赤道座標で作ってある）
        dome.transform.matrix = float4x4(SIMD4(Self.vector(sky.xAxis) * r, 0), SIMD4(Self.vector(sky.yAxis) * r, 0),
                                         SIMD4(Self.vector(sky.zAxis) * r, 0), SIMD4(0, 0, 0, 1))

        let moon = Astro.moon(date: date, latitude: spot.latitude, longitude: spot.longitude)
        let sun = Astro.sun(date: date, latitude: spot.latitude, longitude: spot.longitude)
        let level = StarVisibility.level(darkness: StarVisibility.skyDarkness(spot: spot, moon: moon))
        let opacity = Float(StarVisibility.opacity(sunAltitude: sun.altitude))
        dome.isEnabled = opacity > 0
        guard opacity > 0, let texture = starTexture(level) else { return }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: opacity))
        material.faceCulling = .none
        dome.model?.materials = [material]
    }

    private func starTexture(_ level: StarVisibility.Level) -> TextureResource? {
        if let cached = starTextures[level] { return cached }
        // 一度に持つのは1枚だけにして、描画用のメモリを節約する
        starTextures.removeAll()
        guard let url = Bundle.main.url(forResource: level.textureName, withExtension: "png"),
              let texture = try? TextureResource.load(contentsOf: url, options: .init(semantic: .color)) else { return nil }
        starTextures[level] = texture
        return texture
    }

    /// 半径 1 の球。頂点は赤道座標（x = 春分点、z = 天の北極）、UV は星図の画像の位置
    private static func makeDomeMesh() throws -> MeshResource {
        let columns = 96, rows = 48
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for row in 0...rows {
            let dec = 90 - 180 * Double(row) / Double(rows)
            for column in 0...columns {
                // 画像の左端から右へ進む量 [度]。継ぎ目で UV が飛ばないよう、0〜360 をそのまま使う
                let offset = 360 * Double(column) / Double(columns)
                let ra = StarMapProjection.rightAscensionAtLeftEdge
                    + (StarMapProjection.rightAscensionDecreasesToRight ? -offset : offset)
                let v = SkyOrientation.equatorial(rightAscension: ra, declination: dec)
                positions.append(SIMD3(Float(v.x), Float(v.y), Float(v.z)))
                // RealityKit の UV は下が 0
                uvs.append(SIMD2(Float(offset / 360), Float(1 - Double(row) / Double(rows))))
            }
        }
        let stride = UInt32(columns + 1)
        for row in 0..<UInt32(rows) {
            for column in 0..<UInt32(columns) {
                let a = row * stride + column, b = a + stride
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        var descriptor = MeshDescriptor(name: "starDome")
        descriptor.positions = MeshBuffer(positions)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try MeshResource.generate(from: [descriptor])
    }

    // MARK: - 月

    /// 満ち欠けを描いた月の円。明るい側が画像の上（+y）になるように描く。向きは orientMoon で合わせる
    func makeMoon(fraction: Double) -> ModelEntity {
        let moon = ModelEntity(mesh: moonMesh)
        moon.name = Self.moonName
        if let image = phaseImage(fraction: fraction),
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: 1))
            moon.model?.materials = [material]
        } else {
            moon.model?.materials = [UnlitMaterial(color: .systemYellow)]
        }
        return moon
    }

    /// 四角い写真の角が空を隠さないよう、月そのものを円形の面にする。
    private static func makeMoonMesh() -> MeshResource {
        let segments = 96
        let radius = moonDiameter / 2
        var positions: [SIMD3<Float>] = [.zero]
        var uvs: [SIMD2<Float>] = [[0.5, 0.5]]
        var indices: [UInt32] = []
        for index in 0...segments {
            let angle = Float(index) * 2 * .pi / Float(segments)
            let x = cos(angle), y = sin(angle)
            positions.append([x * radius, y * radius, 0])
            uvs.append([(x + 1) / 2, (y + 1) / 2])
            if index > 0 { indices += [0, UInt32(index), UInt32(index + 1)] }
        }
        var descriptor = MeshDescriptor(name: "moonDisk")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(Array(repeating: SIMD3<Float>(0, 0, 1), count: positions.count))
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor]))
            ?? .generatePlane(width: moonDiameter, height: moonDiameter)
    }

    /// 月の円をカメラに向け、明るい側を太陽の方へ回す
    static func orientMoon(_ moon: Entity, cameraPosition: SIMD3<Float>, brightLimb: SIMD3<Float>?) {
        let toCamera = simd_normalize(cameraPosition - moon.position)
        var up = SIMD3<Float>(0, 1, 0)
        if let brightLimb {
            // 明るい側の向きを、カメラから見た面の上に映す
            let projected = brightLimb - simd_dot(brightLimb, toCamera) * toCamera
            if simd_length(projected) > 1e-4 { up = simd_normalize(projected) }
        }
        // look(at:) は -z を相手に向けるので、カメラと反対の点を見せて +z（絵の表）をカメラに向ける
        moon.look(at: moon.position - toCamera, from: moon.position, upVector: up, relativeTo: moon.parent)
    }

    private func phaseImage(fraction: Double) -> CGImage? {
        guard let disk = moonDisk else { return nil }
        let size = Self.moonPixels
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        return pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: space, bitmapInfo: info) else { return nil }
            context.draw(disk, in: CGRect(x: 0, y: 0, width: size, height: size))
            let bytes = buffer.bindMemory(to: UInt8.self)
            for py in 0..<size {
                for px in 0..<size {
                    let x = (Double(px) + 0.5) / Double(size) * 2 - 1
                    // メモリの 1 行目が画像の上
                    let y = 1 - (Double(py) + 0.5) / Double(size) * 2
                    let i = (py * size + px) * 4
                    // 目線表示では空の中央に月が来るため、写真の四角い背景を透過する。
                    if x * x + y * y > 1 {
                        for c in 0..<4 { bytes[i + c] = 0 }
                        continue
                    }
                    guard !MoonPhase.isLit(x: x, y: y, fraction: fraction) else { continue }
                    for c in 0..<3 { bytes[i + c] = UInt8(Float(bytes[i + c]) * Self.earthshine) }
                }
            }
            return context.makeImage()
        }
    }

    // MARK: - 座標

    /// 地平の向き（東・北・天頂）を 3D の向きへ
    static func vector(_ v: LocalVector) -> SIMD3<Float> {
        SIMD3(Float(v.east), Float(v.up), Float(-v.north))
    }

    /// 高度・方位を 3D の単位ベクトルへ
    static func direction(altitude: Double, azimuth: Double) -> SIMD3<Float> {
        vector(LocalVector(HorizontalCoord(altitude: altitude, azimuth: azimuth)))
    }
}
