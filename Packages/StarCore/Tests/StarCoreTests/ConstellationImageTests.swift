import Foundation
import Testing
@testable import StarCore

private func appResource(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources/Sky/\(name)")
}

private func image(_ anchors: String, size: String = "[1000, 1000]") throws -> ConstellationImage {
    let json = #"[{"id":"T","image":"t","size":\#(size),"anchors":[\#(anchors)]}]"#
    return try #require(try ConstellationImage.decode(Data(json.utf8)).first)
}

// MARK: - 基準星の一致

@Test func imageAnchorsLandExactlyOnTheirStars() throws {
    let figure = try image(#"""
    {"star":[90,10],"pixel":[300,200]},{"star":[80,-5],"pixel":[700,800]},
    {"star":[85,2],"pixel":[450,520]},{"star":[92,-3],"pixel":[250,700]}
    """#)
    let placement = try #require(figure.placement)
    let pairs: [((Double, Double), [Double])] = [((300, 200), [90, 10]), ((700, 800), [80, -5]),
                                                 ((450, 520), [85, 2]), ((250, 700), [92, -3])]
    for (pixel, star) in pairs {
        let expected = try #require(EquatorialVector(d3Coordinate: star))
        #expect(placement.sky(x: pixel.0, y: pixel.1).angle(to: expected) < 1e-6)
    }
}

@Test func twoAnchorImageKeepsItsShape() throws {
    let figure = try image(#"{"star":[90,0],"pixel":[400,500]},{"star":[80,0],"pixel":[600,500]}"#)
    let placement = try #require(figure.placement)
    // 拡大縮小・回転だけなので、正方形の角は直角のまま（左右・上下の長さも同じ）
    let c = placement.sky(x: 500, y: 500)
    let east = placement.sky(x: 400, y: 500), north = placement.sky(x: 500, y: 400)
    #expect(abs(c.angle(to: east) - c.angle(to: north)) < 0.01)
}

// MARK: - 上下・左右

@Test func imageTopIsNorthAndRightIsWest() throws {
    // 画像の左に赤経の大きい星（東）、右に小さい星（西）を置く。y は下向きなので、上の画素ほど北
    let figure = try image(#"{"star":[100,0],"pixel":[200,500]},{"star":[90,0],"pixel":[800,500]}"#)
    let placement = try #require(figure.placement)
    let top = placement.sky(x: 500, y: 100), bottom = placement.sky(x: 500, y: 900)
    #expect(top.z > 0 && bottom.z < 0)
    let left = placement.sky(x: 100, y: 500), right = placement.sky(x: 900, y: 500)
    func ra(_ v: EquatorialVector) -> Double { atan2(v.y, v.x) / Astro.deg }
    #expect(ra(left) > ra(right))
    // 網目の 1 行目は画像の上
    let grid = placement.grid(divisions: 4)
    #expect(grid.count == 5 && grid[0].count == 5)
    #expect(grid[0][2].z > grid[4][2].z)
}

@Test func mirroredAnchorsAreAcceptedWithoutFolding() throws {
    // 左右反転した絵（東の星が画像の右）でも、基準点に合わせて裏返して置ける
    let figure = try image(#"""
    {"star":[100,0],"pixel":[800,500]},{"star":[90,0],"pixel":[200,500]},{"star":[95,8],"pixel":[500,150]}
    """#)
    let placement = try #require(figure.placement)
    #expect(placement.sky(x: 800, y: 500).angle(to: EquatorialVector(rightAscension: 100, declination: 0)) < 1e-6)
    #expect(!placement.isFolded)
}

// MARK: - 異常な設定

@Test func invalidImageSettingsAreRejected() throws {
    // 基準点が 1 つ
    #expect(try image(#"{"star":[90,0],"pixel":[500,500]}"#).placement == nil)
    // 画像の上で同じ位置
    #expect(try image(#"{"star":[90,0],"pixel":[500,500]},{"star":[80,0],"pixel":[500,500]}"#).placement == nil)
    // 大きさがおかしい
    #expect(try image(#"{"star":[90,0],"pixel":[400,500]},{"star":[80,0],"pixel":[600,500]}"#, size: "[0, 1000]").placement == nil)
    // 画像の幅が天球の上で大きすぎる（2 画素に 10°）
    #expect(try image(#"{"star":[90,0],"pixel":[500,500]},{"star":[80,0],"pixel":[502,500]}"#).placement == nil)
    // 3 点目の順番が入れ替わって、画像が折れ返る
    #expect(try image(#"""
    {"star":[100,0],"pixel":[200,500]},{"star":[90,0],"pixel":[800,500]},
    {"star":[95,0],"pixel":[900,500]},{"star":[95,5],"pixel":[500,200]}
    """#).placement == nil)
}

// MARK: - 同梱のデータ

@Test func bundledImagesMatchConstellationLines() throws {
    let images = try ConstellationImage.decode(Data(contentsOf: appResource("constellation-images.json")))
    let lines = try ConstellationLines.decode(Data(contentsOf: appResource("constellations.json")))
    #expect(!images.isEmpty)
    for figure in images {
        let line = try #require(lines.first { $0.id == figure.id }, "線の無い星座: \(figure.id)")
        #expect(FileManager.default.fileExists(atPath: appResource("\(figure.image).png").path), "画像が無い: \(figure.image)")
        let placement = try #require(figure.placement, "\(figure.id) を置けない")
        let center = try #require(line.equatorialCenter)
        for anchor in figure.anchors {
            let star = try #require(EquatorialVector(d3Coordinate: anchor.star))
            // 基準の星は、その星座の線の星であること
            #expect(line.stars.contains { $0.angle(to: star) < 0.01 }, "\(figure.id) の基準の星が線に無い")
            #expect(placement.sky(x: anchor.pixel[0], y: anchor.pixel[1]).angle(to: star) < 1e-4)
        }
        // 画像の中心は星座の近くにある
        #expect(placement.sky(x: 512, y: 512).angle(to: center) < 25, "\(figure.id) の画像が星座から離れすぎ")
        #expect(!figure.markedStars.isEmpty)
    }
}

@Test func snapshotPlacesImageGrid() throws {
    let figure = try image(#"{"star":[90,10],"pixel":[300,300]},{"star":[80,-5],"pixel":[700,700]}"#)
    let context = try #require(try SeedData.loadContexts().first)
    let snapshot = SkySnapshot.make(context: context, date: Date(timeIntervalSince1970: 1_790_000_000), images: [figure])
    let placed = try #require(snapshot.images.first)
    #expect(placed.grid.count == SkySnapshot.imageDivisions + 1)
    #expect(placed.grid.allSatisfy { $0.count == SkySnapshot.imageDivisions + 1 })
}

// MARK: - 三角形の一次変換

@Test func triangleAffineMapsCorners() throws {
    let from = [(0.0, 0.0), (10.0, 0.0), (0.0, 10.0)]
    let to = [(5.0, 5.0), (5.0, 25.0), (-15.0, 5.0)]
    let t = try #require(TriangleAffine(from: from, to: to))
    for (p, q) in zip(from, to) {
        #expect(abs(t.a * p.0 + t.c * p.1 + t.tx - q.0) < 1e-9)
        #expect(abs(t.b * p.0 + t.d * p.1 + t.ty - q.1) < 1e-9)
    }
    #expect(TriangleAffine(from: [(0, 0), (1, 1), (2, 2)], to: to) == nil)
}
