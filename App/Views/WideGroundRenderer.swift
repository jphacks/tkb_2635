import Foundation
import RealityKit
import StarCore

/// 23 区の広域 3D の下に敷く地面（夜の航空写真＋衛星の夜間光）。
/// `WideGround.json` に書いた区画ごとの画像（`WideGround_<行>_<列>.jpg`、scripts/wide_ground_detail.py）を、板に貼って並べる。
/// json が無ければ nil（暗い板だけになる）。
@MainActor
enum WideGroundRenderer {
    private static let name = "WideGround"

    private struct Info: Decodable {
        let tiles: [Tile]
    }

    private struct Tile: Decodable {
        let file: String
        let centerLatitude: Double
        let centerLongitude: Double
        /// 画像の 1 辺が覆う長さ [m]
        let meters: Float
    }

    /// 渋谷の原点の空間（1 単位 = 1m、x が東、-z が北）に置いた、区画の板をまとめた入れ物
    static func ground() async -> Entity? {
        guard let json = Bundle.main.url(forResource: name, withExtension: "json"),
              let info = try? JSONDecoder().decode(Info.self, from: Data(contentsOf: json)) else { return nil }
        let ground = Entity()
        ground.name = WideCityBrightness.groundName
        for tile in info.tiles {
            if let board = await board(tile) { ground.addChild(board) }
        }
        return ground.children.isEmpty ? nil : ground
    }

    private static func board(_ tile: Tile) async -> ModelEntity? {
        guard let image = Bundle.main.url(forResource: tile.file, withExtension: "jpg"),
              let texture = try? await TextureResource(contentsOf: image, options: .init(semantic: .color)),
              let mesh = try? plane(half: tile.meters / 2) else { return nil }
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.minFilter = .linear
            descriptor.magFilter = .linear
            descriptor.mipFilter = .linear
            // 区画の境で隣の画像の端が混ざらないよう、端の画素を伸ばす
            descriptor.sAddressMode = .clampToEdge
            descriptor.tAddressMode = .clampToEdge
            // 斜めから見ても街明かりの点がつぶれにくくする
            descriptor.maxAnisotropy = 16
        }
        // 夜の暗さと街明かりは画像に焼き込んであるので、照明に関係なく画像のまま出す（自分で光る色として貼る）。
        // 強さ 1 で詳細画面の遠くの地面（FarGroundRenderer）と同じ明るさ。遠くから見るときは WideCityBrightness が強める
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .black)
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        material.specular = .init(floatLiteral: 0)
        material.emissiveColor = .init(texture: .init(texture, sampler: sampler))
        material.emissiveIntensity = 1
        let board = ModelEntity(mesh: mesh, materials: [material])
        let center = WideCity.localPosition(latitude: tile.centerLatitude, longitude: tile.centerLongitude)
        board.position = [Float(center.east), 0, -Float(center.north)]
        return board
    }

    /// 上を向いた正方形の板。画像の上が北、右が東（FarGroundRenderer と同じ決まり）
    private static func plane(half: Float) throws -> MeshResource {
        var descriptor = MeshDescriptor(name: "wideGround")
        descriptor.positions = MeshBuffers.Positions([[-half, 0, half], [half, 0, half], [half, 0, -half], [-half, 0, -half]])
        descriptor.normals = MeshBuffers.Normals(Array(repeating: [0, 1, 0], count: 4))
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates([[0, 0], [1, 0], [1, 1], [0, 1]])
        descriptor.primitives = .triangles([0, 1, 2, 0, 2, 3])
        return try MeshResource.generate(from: [descriptor])
    }
}
