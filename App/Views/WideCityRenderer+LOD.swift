import RealityKit
import StarCore
import SwiftUI

/// 1 つの広域 3D 画面の区の並びと、近い区だけ屋根の形つきに差し替える切り替え。
/// root の子に区ごとの入れ物を置き、入れ物の中に箱（box）と屋根の形つき（detail）を持つ。
@MainActor
final class WideCityLOD {
    /// 近い区を屋根の形つき（LOD2）に切り替えるか。LOD2 には壁の UV が無く、箱の窓明かり（o-9）が近づくと消えて
    /// 形も変わって見えるので、今は切り替えない（LOD2 は読み込まない）。LOD2 に窓を出せるようになったら true にする
    static let usesDetail = false
    /// 同時に屋根の形つきで出す区の数（1 区 約 130 万三角形。23 区ぶんは約 1,400 万で重い）
    static let maxDetailWards = 3
    /// 見ている中心から、この距離 [m] より遠い区は箱のまま
    static let detailMaxDistance: Double = 2_500
    /// カメラがこの距離 [m] より遠いとき（全体を見ているとき）は、どの区も箱のまま
    static let detailMaxCameraDistance: Float = 9_000

    /// 1 単位 = 1m・渋谷の原点。画面側で縮める
    let root = Entity()
    private(set) var bounds: [WideCity.WardBounds] = []
    private var wanted: [String] = []

    /// 区の箱を読み、読めた区から並べる
    func loadBoxes() async {
        await WideCityRenderer.shared.loadBoxes { [self] code, box in
            let ward = Entity()
            ward.name = code
            box.name = "box"
            ward.addChild(box)
            root.addChild(ward)
            // x が東、-z が北
            let b = box.visualBounds(relativeTo: root)
            bounds.append(.init(code: code, minEast: Double(b.min.x), maxEast: Double(b.max.x),
                                minNorth: Double(-b.max.z), maxNorth: Double(-b.min.z)))
        }
    }

    /// 23 区全体の広がり [m]（東・北）。まだ読めていなければ nil
    var extent: (minEast: Double, maxEast: Double, minNorth: Double, maxNorth: Double)? {
        guard !bounds.isEmpty else { return nil }
        return (bounds.map(\.minEast).min()!, bounds.map(\.maxEast).max()!,
                bounds.map(\.minNorth).min()!, bounds.map(\.maxNorth).max()!)
    }

    /// 見ている中心（東・北 [m]）とカメラの距離 [m] から、屋根の形つきにする区を決めて差し替える
    func update(east: Double, north: Double, cameraDistance: Float) {
        let next = !Self.usesDetail || cameraDistance > Self.detailMaxCameraDistance ? [] :
            WideCity.nearestWards(bounds, east: east, north: north,
                                  limit: Self.maxDetailWards, maxDistance: Self.detailMaxDistance)
        guard next != wanted else { return }
        wanted = next
        for ward in root.children {
            if next.contains(ward.name) {
                if let detail = ward.findEntity(named: "detail") {
                    show(detail: detail, in: ward)
                } else {
                    requestDetail(for: ward)
                }
            } else {
                // 箱に戻し、屋根の形つきは手放す（元データは WideCityRenderer が少しだけ持つ）
                ward.findEntity(named: "detail")?.removeFromParent()
                ward.findEntity(named: "box")?.isEnabled = true
            }
        }
    }

    /// いま屋根の形つきで出している区
    var detailedWards: [String] {
        root.children.filter { $0.findEntity(named: "detail")?.isEnabled == true }.map(\.name)
    }

    /// 屋根の形つきを読み、読み終わるまでは箱を出し続ける
    private func requestDetail(for ward: Entity) {
        let code = ward.name
        Task {
            guard let detail = await WideCityRenderer.shared.detail(for: code),
                  wanted.contains(code), ward.findEntity(named: "detail") == nil else { return }
            detail.name = "detail"
            ward.addChild(detail)
            show(detail: detail, in: ward)
        }
    }

    private func show(detail: Entity, in ward: Entity) {
        detail.isEnabled = true
        ward.findEntity(named: "box")?.isEnabled = false
    }
}
