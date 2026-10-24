import Foundation

/// 取得した予報を格子 ID ごとに覚えておき、新しいうちは取り直さないための入れ物
public struct WeatherCache: Sendable {
    /// 取得してからこの時間は、同じ格子の予報を取り直さない。
    /// Open-Meteo の予報は 1 時間ごとに更新されるので、それより短くする。
    public static let freshFor: TimeInterval = 30 * 60

    private struct Entry: Sendable {
        var samples: [Weather]
        var fetchedAt: Date
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// 覚えている予報。取得していない・失敗した格子は nil。
    public func samples(for gridId: String) -> [Weather]? {
        entries[gridId]?.samples
    }

    /// 取得してから freshFor 以内か
    public func isFresh(_ gridId: String, now: Date = Date()) -> Bool {
        guard let entry = entries[gridId] else { return false }
        return now.timeIntervalSince(entry.fetchedAt) < Self.freshFor
    }

    /// 取りに行く必要がある格子（覚えていない、または古い）
    public func gridsToFetch(_ gridIds: some Sequence<String>, now: Date = Date()) -> Set<String> {
        Set(gridIds.filter { !isFresh($0, now: now) })
    }

    public mutating func store(_ samples: [Weather], for gridId: String, fetchedAt: Date = Date()) {
        entries[gridId] = Entry(samples: samples, fetchedAt: fetchedAt)
    }

    public mutating func remove(_ gridId: String) {
        entries.removeValue(forKey: gridId)
    }
}
