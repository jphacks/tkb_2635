import Foundation

/// 推薦計算は変えず、一覧に表示する組み合わせと順序だけを決める。
public enum SpotListGroup: CaseIterable, Hashable, Sendable {
    case recommended, review

    public func contains(_ tier: RecommendationTier) -> Bool {
        switch self {
        case .recommended: tier == .recommended
        case .review: tier != .recommended
        }
    }
}

public enum SpotListOrder: CaseIterable, Hashable, Sendable {
    case nearest, score
}

public struct SpotListEntry: Identifiable, Sendable {
    public let spot: Spot
    public let prediction: Prediction
    public let distanceKm: Double?
    public var id: String { spot.id }

    public init(spot: Spot, prediction: Prediction, distanceKm: Double?) {
        self.spot = spot
        self.prediction = prediction
        self.distanceKm = distanceKm
    }
}

public enum SpotListPresentation {
    public static func entries(contexts: [SpotContext], predictions: [Prediction],
                               distance: (Spot) -> Double?) -> [SpotListEntry] {
        let spots = Dictionary(uniqueKeysWithValues: contexts.map { ($0.id, $0.spot) })
        return predictions.compactMap { prediction in
            spots[prediction.spotId].map {
                SpotListEntry(spot: $0, prediction: prediction, distanceKm: distance($0))
            }
        }
    }

    public static func filtered(_ entries: [SpotListEntry], category: SpotCategory?) -> [SpotListEntry] {
        entries.filter { category == nil || $0.spot.category == category }
    }

    public static func rows(_ entries: [SpotListEntry], group: SpotListGroup,
                            order: SpotListOrder) -> [SpotListEntry] {
        entries.filter { group.contains($0.prediction.tier) }.sorted { a, b in
            if order == .nearest {
                // 取得できない距離を 0km にしない。同距離・未取得同士は既存の段階とスコアで整列。
                let ad = a.distanceKm.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? .infinity
                let bd = b.distanceKm.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? .infinity
                if ad != bd { return ad < bd }
            }
            if order == .nearest && a.prediction.tier != b.prediction.tier {
                return a.prediction.tier < b.prediction.tier
            }
            if a.prediction.totalScore != b.prediction.totalScore {
                return a.prediction.totalScore > b.prediction.totalScore
            }
            return a.id < b.id
        }
    }
}
