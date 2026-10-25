import Foundation

/// 任意の位置から観測できる地域。範囲と標高を JSON に足すことで対象を広げる。
public struct ObservationRegion: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let sceneId: String
    public let latitude: Double
    public let longitude: Double
    public let selectionRadius: Double
    public let buildingRadius: Double
    public let elevationSource: String
    public let elevationSourceURL: URL
    public let generatedAt: String
    public let surface: ObservationElevationGrid
    public let terrain: ObservationElevationGrid
    public let sampleLatitude: Double
    public let sampleLongitude: Double
    /// デモ地点の表示名。省略時は地域名を使う。
    public var sampleName: String?

    public var sampleLabel: String { sampleName ?? "\(name)のサンプル" }

    /// 登録された推薦地点とは別に、デモ専用の建物シーンを読み込む。
    public static func loadSupplementalScenes() throws -> [CityScene] {
        guard let url = Bundle.module.url(forResource: "observation-scenes", withExtension: "json") else { return [] }
        return try JSONDecoder().decode([CityScene].self, from: Data(contentsOf: url))
    }

    public static func loadBundled() throws -> [ObservationRegion] {
        guard let url = Bundle.module.url(forResource: "observation-regions", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url))
    }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
        && Distance.greatCircleKm(fromLatitude: self.latitude, fromLongitude: self.longitude,
                                  toLatitude: latitude, toLongitude: longitude) * 1_000 <= selectionRadius
    }

    public func context(at fix: ObservationLocationFix, scene: CityScene, now: Date = Date()) throws -> SpotContext {
        try fix.validate(now: now)
        guard contains(latitude: fix.latitude, longitude: fix.longitude) else { throw ObservationLocationError.outsideRegion }
        guard scene.id == sceneId, scene.observerViewEnabled == true,
              abs(scene.originLatitude - latitude) < Self.originTolerance,
              abs(scene.originLongitude - longitude) < Self.originTolerance else {
            throw ObservationLocationError.missingScene
        }
        let point = scene.localPosition(latitude: fix.latitude, longitude: fix.longitude)
        guard let floor = surface.elevation(east: point.east, north: point.north) else {
            throw ObservationLocationError.missingElevation
        }
        let eyeElevation = floor + Self.eyeHeight
        // 建物内を空が開けた場所として扱わない。建物を勝手に除外したり、地点を道路へ動かしたりしない。
        for building in scene.buildings {
            if building.judgmentParts.contains(where: {
                scene.groundElevation + $0.height > eyeElevation
                && abs(point.east - $0.x) <= $0.width / 2
                && abs(point.north - $0.y) <= $0.depth / 2
            }) { throw ObservationLocationError.insideBuilding }
        }
        let spot = Spot(
            id: "current-\(id)-\(fix.latitude)-\(fix.longitude)",
            name: "現在地", ward: "", category: .plaza,
            latitude: fix.latitude, longitude: fix.longitude, floorElevation: floor,
            floorElevationSource: elevationSource + "（格子から補間）", eyeHeight: Self.eyeHeight,
            indoorOutdoor: .outdoor, directionMaskVerified: false,
            openingHours: OpeningHours(alwaysOpen: false, note: "立入条件は未確認"),
            modelVersion: "current-location-v1",
            memo: "地上の屋外を想定。立入条件・周辺照明は未確認。"
        )
        var position = spot
        position.sceneId = sceneId
        let buildings = HorizonProfile.compute(spot: position, scene: scene)
        guard let elevations = terrain.horizon(east: point.east, north: point.north, eyeElevation: eyeElevation) else {
            throw ObservationLocationError.missingElevation
        }
        return SpotContext(spot: position, scene: scene, horizon: buildings.combined(withTerrain: elevations))
    }

    public static let eyeHeight = 1.5
    private static let originTolerance = 0.0000001
}
