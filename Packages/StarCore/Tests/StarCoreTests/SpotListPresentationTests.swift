import Foundation
import Testing
@testable import StarCore

struct SpotListPresentationTests {
    private func entries() throws -> [SpotListEntry] {
        let contexts = Array(try SeedData.loadContexts().prefix(4))
        let tiers: [RecommendationTier] = [.recommended, .needsCheck, .notVisible, .unavailable]
        return contexts.enumerated().map { index, context in
            var prediction = Recommender.evaluate(context, target: .moon, date: Date(timeIntervalSince1970: 1792843200), weather: nil)
            prediction.tier = tiers[index]
            prediction.totalScore = [42, 51, 51, 30][index]
            return SpotListEntry(spot: context.spot, prediction: prediction,
                                 distanceKm: [nil, 8.2, 7.0, 12.0][index])
        }
    }

    @Test func tabsPartitionEveryStatusWithoutDroppingOrReclassifying() throws {
        let all = try entries()
        let recommended = SpotListPresentation.rows(all, group: .recommended, order: .nearest)
        let review = SpotListPresentation.rows(all, group: .review, order: .nearest)
        #expect(recommended.count == 1)
        #expect(review.count == 3)
        #expect(Set((recommended + review).map(\.id)) == Set(all.map(\.id)))
        #expect(Set(review.map { $0.prediction.tier }) == Set([.needsCheck, .notVisible, .unavailable]))
    }

    @Test func distanceOrdersNumericallyAndMissingDistanceComesLast() throws {
        let all = try entries()
        let review = SpotListPresentation.rows(all, group: .review, order: .nearest)
        #expect(review.map(\.distanceKm) == [7.0, 8.2, 12.0])
        let unknown = SpotListEntry(spot: all[0].spot, prediction: all[1].prediction, distanceKm: nil)
        let mixed = SpotListPresentation.rows([unknown, all[2]], group: .review, order: .nearest)
        #expect(mixed.last?.distanceKm == nil)
    }

    @Test func categoryCountsAndEmptyResultsUseTheSameFilteredEntries() throws {
        let all = try entries()
        let filtered = SpotListPresentation.filtered(all, category: all[0].spot.category)
        #expect(filtered.allSatisfy { $0.spot.category == all[0].spot.category })
        let count = SpotListGroup.allCases.reduce(0) { result, group in
            result + SpotListPresentation.rows(filtered, group: group, order: .score).count
        }
        #expect(count == filtered.count)
        #expect(SpotListPresentation.filtered(all, category: nil).count == all.count)
        #expect(SpotListPresentation.rows([], group: .recommended, order: .score).isEmpty)
    }

    @Test func scoreSortIsDescendingAndTiesHaveStableIds() throws {
        let all = try entries()
        let rows = SpotListPresentation.rows(all, group: .review, order: .score)
        #expect(rows.map { $0.prediction.totalScore } == [51, 51, 30])
        #expect(Array(rows.prefix(2)).map(\.id) == Array(rows.prefix(2)).map(\.id).sorted())
        #expect(rows.map(\.id) == SpotListPresentation.rows(Array(all.reversed()), group: .review, order: .score).map(\.id))
    }
}
