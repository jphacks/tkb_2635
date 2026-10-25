import Metal
import RealityKit
import StarCore
import SwiftUI

/// 少数の壁面テクスチャを共有し、各建物に合ったUVで繰り返す。
@MainActor
final class BuildingNightRenderer {
    static let shared = BuildingNightRenderer()
    private var facades: [Int: PhysicallyBasedMaterial] = [:]
    private let roof = SimpleMaterial(color: .init(red: 0.09, green: 0.12, blue: 0.17, alpha: 1),
                                      roughness: 0.95, isMetallic: false)

    // RealityViewの明るい既定IBLに依存せず、同じ夜空の反射を各ビューで使う。
    private lazy var nightEnvironment: EnvironmentResource? = {
        let width = 128, height = 64
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        for row in 0..<height {
            let t = Double(row) / Double(height - 1)
            let horizon = max(0, 1 - abs(t - 0.5) * 2)
            context.setFillColor(CGColor(red: 0.10 + horizon * 0.32,
                                         green: 0.17 + horizon * 0.30,
                                         blue: 0.29 + horizon * 0.25, alpha: 1))
            context.fill(CGRect(x: 0, y: row, width: width, height: 1))
        }
        guard let image = context.makeImage() else { return nil }
        return try? EnvironmentResource(equirectangular: image)
    }()

    func configureEnvironment(in root: Entity) {
        guard let environment = nightEnvironment else { return }
        let probe = Entity()
        probe.components.set(ImageBasedLightComponent(source: .single(environment), intensityExponent: 0))
        root.addChild(probe)
        root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: probe))
    }

    func entity(for building: Building, scale: Float, isHost: Bool) -> ModelEntity {
        let size = SIMD3<Float>(Float(building.width), Float(building.height), Float(building.depth)) * scale
        if isHost {
            let host = SimpleMaterial(color: .init(red: 0.20, green: 0.70, blue: 0.76, alpha: 0.35),
                                      roughness: 0.7, isMetallic: false)
            return ModelEntity(mesh: .generateBox(size: size), materials: [host])
        }
        let appearance = BuildingFacade(usage: building.usage, id: building.id)
        let material = facade(appearance)
        do {
            return try ModelEntity(mesh: mesh(size: size, meters: [Float(building.width), Float(building.height), Float(building.depth)]),
                                   materials: [material, roof])
        } catch {
            // GPUリソースの生成に失敗しても建物の形は残す。
            let fallback = SimpleMaterial(color: .init(cgColor: appearance.wall), roughness: 0.8, isMetallic: false)
            return ModelEntity(mesh: .generateBox(size: size), materials: [fallback])
        }
    }

    /// 外壁と窓の材質（同じ種類は使い回す）。ホームの広域 3D（WideCityRenderer）も同じものを使う
    func facade(_ appearance: BuildingFacade) -> PhysicallyBasedMaterial {
        let key = appearance.style.rawValue * 4 + appearance.variant
        if let cached = facades[key] { return cached }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(cgColor: appearance.wall))
        material.roughness = .init(scale: appearance.style == .glass ? 0.38 : 0.85)
        material.metallic = .init(scale: appearance.style == .glass ? 0.15 : 0)
        func texture(_ map: BuildingFacade.Map) -> MaterialParameters.Texture? {
            guard let image = appearance.image(map: map),
                  let resource = try? TextureResource(image: image, options: .init(semantic: map == .normal ? .normal : (map == .roughness ? .scalar : .color))) else { return nil }
            var sampler = MaterialParameters.Texture.Sampler()
            sampler.modify { descriptor in
                descriptor.sAddressMode = .repeat
                descriptor.tAddressMode = .repeat
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.mipFilter = .linear
                descriptor.maxAnisotropy = 8
            }
            return .init(resource, sampler: sampler)
        }
        if let base = texture(.color) {
            // テクスチャだけの白いtintにせず、夜景の色調を明示して白飛びを抑える。
            material.baseColor = .init(tint: .init(red: 0.55, green: 0.64, blue: 0.75, alpha: 1), texture: base)
        }
        material.roughness = .init(scale: 1, texture: texture(.roughness))
        material.normal = .init(texture: texture(.normal))
        if let glow = texture(.emission) {
            // 発光色の定数を足すと壁全体まで光るため、窓だけの画像を渡す。
            material.emissiveColor = .init(texture: glow)
            material.emissiveIntensity = 0.55
        }
        material.specular = .init(scale: 0.35)
        facades[key] = material
        return material
    }

    private func mesh(size: SIMD3<Float>, meters: SIMD3<Float>) throws -> MeshResource {
        let w = size.x / 2, h = size.y / 2, d = size.z / 2
        let faces: [[SIMD3<Float>]] = [
            [[-w,-h,d],[w,-h,d],[w,h,d],[-w,h,d]],
            [[w,-h,-d],[-w,-h,-d],[-w,h,-d],[w,h,-d]],
            [[w,-h,d],[w,-h,-d],[w,h,-d],[w,h,d]],
            [[-w,-h,-d],[-w,-h,d],[-w,h,d],[-w,h,-d]],
            [[-w,h,d],[w,h,d],[w,h,-d],[-w,h,-d]],
            [[-w,-h,-d],[w,-h,-d],[w,-h,d],[-w,-h,d]]
        ]
        let normals: [SIMD3<Float>] = [[0,0,1],[0,0,-1],[1,0,0],[-1,0,0],[0,1,0],[0,-1,0]]
        var positions: [SIMD3<Float>] = [], vertexNormals: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = [], indices: [UInt32] = [], materials: [UInt32] = []
        for (face, vertices) in faces.enumerated() {
            let start = UInt32(positions.count)
            positions += vertices
            vertexNormals += Array(repeating: normals[face], count: 4)
            let width = face < 2 ? meters.x : meters.z
            let u = max(1, width / BuildingFacade.columnMeters) / Float(BuildingFacade.tileColumns)
            let v = max(1, meters.y / BuildingFacade.floorMeters) / Float(BuildingFacade.tileRows)
            // 各面を整数の窓ベイ単位でずらし、隣接面で点灯模様を繰り返さない。
            let offset = Float(face * 3) / Float(BuildingFacade.tileColumns)
            uv += [[offset,0],[u+offset,0],[u+offset,v],[offset,v]]
            indices += [start,start+1,start+2,start,start+2,start+3]
            // 上下の面には窓を描かず、暗い屋根素材を割り当てる。
            materials += [face < 4 ? 0 : 1, face < 4 ? 0 : 1]
        }
        var descriptor = MeshDescriptor(name: "night-building")
        descriptor.positions = .init(positions)
        descriptor.normals = .init(vertexNormals)
        descriptor.textureCoordinates = .init(uv)
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .perFace(materials)
        return try MeshResource.generate(from: [descriptor])
    }
}
