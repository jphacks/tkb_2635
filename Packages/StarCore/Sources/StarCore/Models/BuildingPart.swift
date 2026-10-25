import Foundation

/// 遮蔽判定に使う、建物の一部分の箱（東西・南北にそろえた直方体）。
/// 外接直方体は斜めの建物や低い基壇の上の塔をふくらませるので、LOD2 の形から作った小さな箱の集まりで建物を表す（4-13）。
/// JSON では `[x, y, 幅, 奥行き, 高さ]` の配列 1 つで書く（建物 1 棟に数十個あるため）。
public struct BuildingPart: Codable, Sendable, Equatable {
    /// 中心の東・北方向の距離 [m]（シーン原点から。Building.x・y と同じ）
    public var x: Double
    public var y: Double
    /// 東西方向の幅 [m]
    public var width: Double
    /// 南北方向の奥行き [m]
    public var depth: Double
    /// シーンの groundElevation からの高さ [m]（Building.height と同じ）
    public var height: Double

    public init(x: Double, y: Double, width: Double, depth: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.depth = depth
        self.height = height
    }

    public init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self)
        y = try values.decode(Double.self)
        width = try values.decode(Double.self)
        depth = try values.decode(Double.self)
        height = try values.decode(Double.self)
        guard values.isAtEnd, width > 0, depth > 0, height > 0 else {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: "部分の箱は正の [x, y, 幅, 奥行き, 高さ] の 5 つ")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(contentsOf: [x, y, width, depth, height])
    }
}

extension Building {
    /// 遮蔽判定に使う箱。部分の箱（parts）があればそれを、無ければ建物全体の箱 1 つを返す。
    public var judgmentParts: [BuildingPart] {
        parts ?? [BuildingPart(x: x, y: y, width: width, depth: depth, height: height)]
    }

    /// 部分の箱 1 つを、同じ建物（ID・名前・用途）の箱として返す。3D の赤枠を実際に効いた部分に合わせるため。
    func restricted(to part: BuildingPart) -> Building {
        var result = self
        result.x = part.x
        result.y = part.y
        result.width = part.width
        result.depth = part.depth
        result.height = part.height
        result.parts = nil
        return result
    }
}
