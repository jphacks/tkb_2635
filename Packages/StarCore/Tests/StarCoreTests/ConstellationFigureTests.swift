import Foundation
import Testing
@testable import StarCore

private func appResource(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources/Sky/\(name)")
}

// MARK: - 星座線の形

@Test func d3LongitudeBecomesRightAscension() throws {
    // 経度 -90° は赤経 270°（赤経 18 時）
    let v = try #require(EquatorialVector(d3Coordinate: [-90, 0]))
    #expect(abs(v.x) < 1e-9 && abs(v.y + 1) < 1e-9 && abs(v.z) < 1e-9)
}

@Test func arcKeepsEndpointsAndStaysOnSphere() {
    let a = EquatorialVector(rightAscension: 0, declination: 0)
    let b = EquatorialVector(rightAscension: 90, declination: 0)
    let points = ConstellationGeometry.arc(from: a, to: b, maxStep: 10)
    #expect(points.count == 10)
    #expect(points.first!.angle(to: a) < 1e-6)
    #expect(points.last!.angle(to: b) < 1e-6)
    #expect(points.allSatisfy { abs($0.length - 1) < 1e-9 })
}

@Test func starsAreDeduplicatedAndCenterIsInside() throws {
    let json = """
    [{"id":"T","name":"テスト","paths":[[[10,0],[20,0]],[[20,0],[20,10]]]}]
    """
    let line = try #require(try ConstellationLines.decode(Data(json.utf8)).first)
    #expect(line.stars.count == 3)
    #expect(line.equatorialPolylines.count == 2)
    let center = try #require(line.equatorialCenter)
    // 3 つの星の平均は、どの星からも 10° 以内
    #expect(line.stars.allSatisfy { $0.angle(to: center) < 10 })
}

@Test func orionContainsABrightStar() throws {
    let lines = try ConstellationLines.decode(Data(contentsOf: appResource("constellations.json")))
    let orion = try #require(lines.first { $0.id == "Ori" })
    // リゲル（0.13 等）・ベテルギウス（0.42 等）を含む
    #expect((orion.brightestCatalogMagnitude ?? 9) < 0.5)
}

// MARK: - 星座の線画

@Test func artAnchorsLandOnTheirStars() throws {
    let json = """
    [{"id":"T","anchors":[{"star":[10,0],"at":[0,0]},{"star":[20,5],"at":[4,0]}],
      "strokes":[[[0,0],[4,0]]]}]
    """
    let art = try #require(try ConstellationArt.decode(Data(json.utf8)).first)
    let stroke = try #require(art.equatorialStrokes.first)
    // 2 点だけの線は滑らかにしても両端は基準の星に重なる
    #expect(stroke.first!.angle(to: EquatorialVector(rightAscension: 10, declination: 0)) < 1e-6)
    #expect(stroke.last!.angle(to: EquatorialVector(rightAscension: 20, declination: 5)) < 1e-6)
}

@Test func artIsMirroredAsSeenFromTheGround() throws {
    // 絵の右（+x）は西（赤経が小さい側）、上（+y）は北
    let json = """
    [{"id":"T","anchors":[{"star":[100,0],"at":[-1,0]},{"star":[90,0],"at":[1,0]}],
      "strokes":[[[0,0],[0,1]]]}]
    """
    let art = try #require(try ConstellationArt.decode(Data(json.utf8)).first)
    let stroke = try #require(art.equatorialStrokes.first)
    let top = try #require(stroke.last)
    // 2 単位 = 10° なので、上へ 1 単位は北へ約 5°
    #expect(top.z > 0.08 && top.z < 0.09)
    #expect(abs(atan2(top.y, top.x) / Astro.deg - 95) < 0.5)
}

@Test func smoothingPassesThroughAllPoints() {
    let points = [(0.0, 0.0), (1.0, 2.0), (3.0, 1.0)]
    let smooth = ConstellationArt.smoothed(points)
    #expect(smooth.count == 2 * (ConstellationArt.smoothingSteps + 1) + 1)
    for p in points {
        #expect(smooth.contains { abs($0.0 - p.0) < 1e-9 && abs($0.1 - p.1) < 1e-9 })
    }
}

@Test func bundledArtMatchesConstellationLines() throws {
    let art = try ConstellationArt.decode(Data(contentsOf: appResource("constellation-art.json")))
    let lines = try ConstellationLines.decode(Data(contentsOf: appResource("constellations.json")))
    #expect(art.count >= 5)
    for figure in art {
        let line = try #require(lines.first { $0.id == figure.id }, "線の無い星座: \(figure.id)")
        // 基準の星は、その星座の線の星であること
        for anchor in figure.anchors {
            let star = try #require(EquatorialVector(d3Coordinate: anchor.star))
            #expect(line.stars.contains { $0.angle(to: star) < 0.01 }, "\(figure.id) の基準の星が線に無い")
        }
        let center = try #require(line.equatorialCenter)
        // 絵は星座のそばに収まる（大きくずれていない）
        let strokes = figure.equatorialStrokes
        #expect(!strokes.isEmpty)
        #expect(strokes.joined().allSatisfy { $0.angle(to: center) < 40 }, "\(figure.id) の絵が星座から離れすぎ")
    }
}

// MARK: - 名前の間引き

private func candidate(_ id: String, altitude: Double, azimuth: Double, magnitude: Double? = nil) -> ConstellationLabelCandidate {
    ConstellationLabelCandidate(id: id, direction: LocalVector(HorizontalCoord(altitude: altitude, azimuth: azimuth)),
                                brightestMagnitude: magnitude)
}

@Test func labelPickerPrefersViewCenterAndSkipsHorizon() {
    let view = LocalVector(HorizontalCoord(altitude: 40, azimuth: 180))
    let picked = ConstellationLabelPicker.pick([
        candidate("far", altitude: 40, azimuth: 230),
        candidate("center", altitude: 42, azimuth: 182),
        candidate("low", altitude: 1, azimuth: 180),
        candidate("behind", altitude: 40, azimuth: 0),
    ], viewDirection: view, maximumAngle: 60)
    #expect(picked == ["center", "far"])
}

@Test func labelPickerKeepsLabelsApartAndLimitsCount() {
    let view = LocalVector(HorizontalCoord(altitude: 45, azimuth: 180))
    // 近すぎる 2 つのうち、明るい星を含む方が残る
    let pair = ConstellationLabelPicker.pick([
        candidate("dim", altitude: 45, azimuth: 180),
        candidate("bright", altitude: 50, azimuth: 185, magnitude: 0.1),
    ], viewDirection: view, maximumAngle: 90)
    #expect(pair == ["bright"])

    let many = (0..<30).map { candidate("c\($0)", altitude: 20 + Double($0 % 3) * 25, azimuth: Double($0) * 12) }
    let picked = ConstellationLabelPicker.pick(many, viewDirection: view, maximumAngle: 180)
    #expect(picked.count == ConstellationLabelPicker.maximumCount)
}

@Test func viewLookingDownIsLiftedToTheSky() {
    let down = LocalVector(HorizontalCoord(altitude: -30, azimuth: 90))
    let lifted = ConstellationLabelPicker.liftedView(down, maximumAngle: 30)
    #expect(abs(lifted.direction.horizontal.altitude - ConstellationLabelPicker.minimumViewAltitude) < 1e-6)
    #expect(abs(lifted.direction.horizontal.azimuth - 90) < 1e-6)
    #expect(abs(lifted.maximumAngle - (30 + ConstellationLabelPicker.minimumViewAltitude + 30)) < 1e-6)
    // 空を見ているときはそのまま
    let up = LocalVector(HorizontalCoord(altitude: 50, azimuth: 0))
    #expect(ConstellationLabelPicker.liftedView(up, maximumAngle: 30).maximumAngle == 30)
}
