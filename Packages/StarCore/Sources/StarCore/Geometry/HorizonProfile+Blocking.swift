import Foundation

extension HorizonProfile {
    /// 方位 azimuth の遮蔽仰角 h(A) を決めている建物（判定に使う直方体）を返す。部分の箱がある建物は、効いた部分の箱を返す。建物が当たらなければ nil。
    /// `compute(spot:scene:)` と同じく方位を 1° 単位に丸め、観測者が立つ建物は除く。3D で「どの箱が隠しているか」を示すために使う。
    public static func highestBuilding(spot: Spot, scene: CityScene, azimuth: Double) -> Building? {
        let p = scene.localPosition(latitude: spot.latitude, longitude: spot.longitude)
        let a = Double(Int(Angle.normalize(azimuth).rounded()) % 360) * .pi / 180
        var best: (building: Building, elevation: Double)?
        for b in scene.buildings where b.id != spot.hostBuildingId {
            for part in b.judgmentParts {
                let top = scene.groundElevation + part.height
                guard top > spot.observerElevation,
                      let distance = rayHit(ox: p.east, oy: p.north, dx: sin(a), dy: cos(a),
                                            minX: part.x - part.width / 2, maxX: part.x + part.width / 2,
                                            minY: part.y - part.depth / 2, maxY: part.y + part.depth / 2)
                else { continue }
                let elevation = atan2(top - spot.observerElevation, distance) * 180 / .pi
                if elevation > (best?.elevation ?? -.infinity) { best = (b.restricted(to: part), elevation) }
            }
        }
        return best?.building
    }
}
