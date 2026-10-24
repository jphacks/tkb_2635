import Foundation

/// アプリに同梱した地点・建物データ
public enum SeedData {
    public static func loadSpots() throws -> [Spot] {
        try load("spots", as: [Spot].self)
    }

    public static func loadScenes() throws -> [CityScene] {
        try load("buildings", as: [CityScene].self)
    }

    /// 地点ごとに建物シーンと地平線プロファイルを組み立てる
    public static func loadContexts() throws -> [SpotContext] {
        let scenes = Dictionary(uniqueKeysWithValues: try loadScenes().map { ($0.id, $0) })
        return try loadSpots().map { SpotContext(spot: $0, scene: $0.sceneId.flatMap { scenes[$0] }) }
    }

    private static func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}

/// 地点と、その地点から見た地平線プロファイルの組
public struct SpotContext: Identifiable, Sendable {
    public let spot: Spot
    public let scene: CityScene?
    public let horizon: HorizonProfile

    public var id: String { spot.id }

    public init(spot: Spot, scene: CityScene?) {
        self.spot = spot
        self.scene = scene
        if let scene {
            horizon = HorizonProfile.compute(spot: spot, scene: scene)
        } else {
            horizon = HorizonProfile.uniform(spot.approxHorizonElevation ?? 10, isApproximate: true)
        }
    }
}
