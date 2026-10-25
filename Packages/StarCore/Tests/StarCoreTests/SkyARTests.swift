import Foundation
import Testing
@testable import StarCore

/// 真北を向いて立てたスマホ（画面を自分に向け、背面カメラは水平に北）。端末の x=東、y=上、z=南
private let uprightFacingNorth = DeviceAttitude(m11: 0, m12: -1, m13: 0,
                                                m21: 0, m22: 0, m23: 1,
                                                m31: -1, m32: 0, m33: 0)

/// 北向きのまま、背面カメラを仰角 60° まで上げたスマホ（上端は上・後ろ=南へ向く）
private let tiltedUp60: DeviceAttitude = {
    let c = cos(60.0 * .pi / 180), s = sin(60.0 * .pi / 180)
    return DeviceAttitude(m11: 0, m12: -1, m13: 0, m21: -s, m22: 0, m23: c, m31: -c, m32: 0, m33: -s)
}()

private func direction(altitude: Double, azimuth: Double) -> LocalVector {
    LocalVector(HorizontalCoord(altitude: altitude, azimuth: azimuth))
}

@Test func lookElevationOfUprightPhoneIsHorizontal() {
    #expect(abs(uprightFacingNorth.lookElevation) < 1e-9)
    let look = uprightFacingNorth.lookDirection
    #expect(abs(look.north - 1) < 1e-9)
}

@Test func lookElevationOfTiltedPhone() {
    #expect(abs(tiltedUp60.lookElevation - 60) < 1e-9)
}

@Test func objectStraightAheadIsAtScreenCenter() throws {
    let projector = CameraProjector(attitude: uprightFacingNorth, width: 400, height: 800)
    let point = try #require(projector.project(direction(altitude: 0, azimuth: 0)))
    #expect(abs(point.x - 200) < 1e-6)
    #expect(abs(point.y - 400) < 1e-6)
}

@Test func objectAboveAndToTheEastAppearsUpperRight() throws {
    let projector = CameraProjector(attitude: uprightFacingNorth, width: 400, height: 800)
    let point = try #require(projector.project(direction(altitude: 10, azimuth: 20)))
    #expect(point.x > 200)
    #expect(point.y < 400)
}

@Test func objectBehindCameraIsNotProjected() {
    let projector = CameraProjector(attitude: uprightFacingNorth, width: 400, height: 800)
    #expect(projector.project(direction(altitude: 0, azimuth: 180)) == nil)
    #expect(projector.project(direction(altitude: 0, azimuth: 90)) == nil)
}

@Test func verticalFieldOfViewPlacesEdgeOfView() throws {
    // 縦の画角が 60° なら、真上へ 30° の方向が画面の上端に来る
    let projector = CameraProjector(attitude: uprightFacingNorth, width: 400, height: 800, verticalFieldOfView: 60)
    let point = try #require(projector.project(direction(altitude: 30, azimuth: 0)))
    #expect(abs(point.y) < 1e-6)
}

@Test func tiltedPhoneSeesZenithNearCenterTopHalf() throws {
    let projector = CameraProjector(attitude: tiltedUp60, width: 400, height: 800)
    let ahead = try #require(projector.project(direction(altitude: 60, azimuth: 0)))
    #expect(abs(ahead.y - 400) < 1e-6)
    let zenith = try #require(projector.project(direction(altitude: 90, azimuth: 0)))
    #expect(zenith.y < 400)
}

@Test func triggerOpensOnceUntilCameraIsLowered() {
    var trigger = SkyARTrigger()
    // 仰角を順に渡したときに、開く（true）はずの順番
    let steps: [(elevation: Double, opens: Bool)] = [
        (10, false),
        (SkyARTrigger.enterElevation - 1, false),
        (SkyARTrigger.enterElevation, true),
        // 上を向けたままなら、もう開かない
        (80, false),
        // 少し下げただけでは、まだ開かない
        (30, false),
        (70, false),
        // 十分下げたら、また開く
        (SkyARTrigger.rearmElevation, false),
        (60, true),
    ]
    for step in steps {
        let opened = trigger.shouldEnter(lookElevation: step.elevation)
        #expect(opened == step.opens, "仰角 \(step.elevation)°")
    }
}

@Test func disarmedTriggerWaitsForCameraToBeLowered() {
    var trigger = SkyARTrigger(isArmed: false)
    let first = trigger.shouldEnter(lookElevation: 80)
    let lowered = trigger.shouldEnter(lookElevation: 10)
    let second = trigger.shouldEnter(lookElevation: 80)
    #expect(!first)
    #expect(!lowered)
    #expect(second)
}

@Test func localVectorConvertsBackToHorizontalCoord() {
    let h = direction(altitude: 35, azimuth: 250).horizontal
    #expect(abs(h.altitude - 35) < 1e-9)
    #expect(abs(h.azimuth - 250) < 1e-9)
}

@Test func skyBelowHorizonLineIsBlockedButBelowGroundIsNot() throws {
    let context = try #require(try SeedData.loadContexts().first)
    let limit = context.horizon.elevation(at: 0) + Recommender.visibilityMargin
    #expect(limit > 0)
    #expect(context.blocksSky(altitude: limit - 0.1, azimuth: 0))
    // 地平線より下は、さえぎられているのではなく見えない向き
    #expect(!context.blocksSky(altitude: -5, azimuth: 0))
}

@Test func snapshotHasMoonPlanetsAndStars() throws {
    let context = try #require(try SeedData.loadContexts().first)
    let snapshot = SkySnapshot.make(context: context, date: Date(timeIntervalSince1970: 1_790_000_000))
    #expect(snapshot.objects.count == 1 + PlanetCatalog.planets.count + StarCatalog.stars.count)
    #expect(Set(snapshot.objects.map(\.id)).count == snapshot.objects.count)
    #expect(snapshot.objects.contains { $0.kind == .moon })
}

@Test func constellationLinesAreDecodedAndPlaced() throws {
    let json = """
    [{"id":"Ori","name":"オリオン座","paths":[[[88.79,7.41],[81.28,6.35],[78.63,-8.2]]]},
     {"id":"Tiny","name":"点だけ","paths":[[[10,10]]]}]
    """
    let lines = try ConstellationLines.decode(Data(json.utf8))
    #expect(lines.count == 2)
    let context = try #require(try SeedData.loadContexts().first)
    let snapshot = SkySnapshot.make(context: context, date: Date(timeIntervalSince1970: 1_790_000_000), constellations: lines)
    let orion = try #require(snapshot.constellations.first { $0.id == "Ori" })
    #expect(orion.polylines.count == 1 && orion.polylines[0].count == 3)
    #expect(orion.label != nil)
    // 点が 1 つだけの折れ線は線にならない
    #expect(snapshot.constellations.first { $0.id == "Tiny" }?.polylines.isEmpty == true)
}

@Test func bundledConstellationFileCanBeDecoded() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("App/Resources/Sky/constellations.json")
    let lines = try ConstellationLines.decode(Data(contentsOf: url))
    #expect(lines.count > 80)
}
