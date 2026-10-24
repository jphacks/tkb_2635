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

    private func facade(_ appearance: BuildingFacade) -> PhysicallyBasedMaterial {
        let key = appearance.style.rawValue * 4 + appearance.variant
        if let cached = facades[key] { return cached }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(cgColor: appearance.wall))
        material.roughness = .init(scale: appearance.style == .glass ? 0.38 : 0.85)
        material.metallic = .init(scale: appearance.style == .glass ? 0.15 : 0)
        if let base = appearance.image(emission: false), let glow = appearance.image(emission: true),
           let baseTexture = try? TextureResource.generate(from: base, options: .init(semantic: .color)),
           let glowTexture = try? TextureResource.generate(from: glow, options: .init(semantic: .color)) {
            var sampler = MaterialParameters.Texture.Sampler()
            sampler.modify { descriptor in
                descriptor.sAddressMode = .repeat
                descriptor.tAddressMode = .repeat
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.mipFilter = .linear
            }
            material.baseColor = .init(texture: .init(baseTexture, sampler: sampler))
            material.emissiveColor = .init(color: .white, texture: .init(glowTexture, sampler: sampler))
            material.emissiveIntensity = 0.45
        }
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
            uv += [[0,0],[u,0],[u,v],[0,v]]
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
