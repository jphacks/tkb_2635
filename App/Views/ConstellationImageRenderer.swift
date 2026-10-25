import CoreGraphics
import RealityKit
import StarCore
import UIKit

/// 3D の空の星座の姿の画像（PNG）。星空の球の内側に、画像を球面に沿う網目にして貼る。
/// 置き方（画素 → 天球の向き）は StarCore の `ConstellationImagePlacement` が決め、ここは形と見た目だけを作る。
@MainActor
enum ConstellationImageRenderer {
    private struct Prepared {
        let id: String
        let mesh: MeshResource
        let color: TextureResource
        let opacity: TextureResource
    }

    /// 形と画像は一度だけ作り、地点ごとの空で使い回す
    private static let prepared: [Prepared] = ConstellationData.images.compactMap { prepare($0) }

    static func makeEntities() -> [ModelEntity] {
        prepared.map { item in
            var material = UnlitMaterial()
            material.color = .init(tint: .white, texture: .init(item.color))
            // 透明度は PNG のアルファから作った白黒の画像で与え、四角い背景を出さない
            material.blending = .transparent(opacity: .init(scale: Float(ConstellationStyle.imageOpacity),
                                                            texture: .init(item.opacity)))
            material.faceCulling = .none
            let entity = ModelEntity(mesh: item.mesh, materials: [material])
            entity.name = "constellationImage-" + item.id
            return entity
        }
    }

    private static func prepare(_ image: ConstellationImage) -> Prepared? {
        guard let placement = image.placement,
              let cgImage = ConstellationImageAssets.image(named: image.image)?.cgImage,
              let color = try? TextureResource(image: cgImage, options: .init(semantic: .color)),
              let mask = alphaMask(cgImage),
              let opacity = try? TextureResource(image: mask, options: .init(semantic: .raw)),
              let mesh = mesh(placement.grid(divisions: ConstellationStyle.imageDivisions), name: image.id) else { return nil }
        return Prepared(id: image.id, mesh: mesh, color: color, opacity: opacity)
    }

    /// 網目の点を球面上の三角形にする。UV の v は下が 0 なので、画像の上（行 0）を v = 1 にする
    private static func mesh(_ grid: [[EquatorialVector]], name: String) -> MeshResource? {
        let rows = grid.count - 1
        guard rows > 0, let columns = grid.first.map({ $0.count - 1 }), columns > 0 else { return nil }
        var positions: [SIMD3<Float>] = [], uvs: [SIMD2<Float>] = [], indices: [UInt32] = []
        for (row, line) in grid.enumerated() {
            for (column, v) in line.enumerated() {
                positions.append(SIMD3(Float(v.x), Float(v.y), Float(v.z)) * ConstellationStyle.imageRadius)
                uvs.append([Float(column) / Float(columns), 1 - Float(row) / Float(rows)])
            }
        }
        let stride = UInt32(columns + 1)
        for row in 0..<UInt32(rows) {
            for column in 0..<UInt32(columns) {
                let a = row * stride + column, b = a + stride
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
        }
        var descriptor = MeshDescriptor(name: "constellationImage-" + name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

    /// PNG のアルファを、明るさ = 不透明度の白黒画像にする（どの色の成分を透明度に使っても同じになるように）
    private static func alphaMask(_ image: CGImage) -> CGImage? {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = pixels[i + 3]
            pixels[i] = alpha; pixels[i + 1] = alpha; pixels[i + 2] = alpha; pixels[i + 3] = 255
        }
        return context.makeImage()
    }
}
