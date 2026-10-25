import Foundation

/// GPS の高度は使わず、座標・水平精度・取得時刻だけを観測に使う。
public struct ObservationLocationFix: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let horizontalAccuracy: Double
    public let timestamp: Date

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    public func validate(now: Date = Date()) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { throw ObservationLocationError.invalidLocation }
        guard horizontalAccuracy.isFinite, horizontalAccuracy >= 0,
              horizontalAccuracy <= Self.maximumAccuracy else { throw ObservationLocationError.inaccurateLocation }
        guard timestamp.timeIntervalSince1970.isFinite,
              abs(timestamp.timeIntervalSince(now)) <= Self.maximumAge else {
            throw ObservationLocationError.staleLocation
        }
    }

    public static let maximumAccuracy = 25.0
    private static let maximumAge = 60.0
}

public enum ObservationLocationError: LocalizedError, Sendable {
    case invalidLocation, inaccurateLocation, staleLocation, outsideRegion
    case missingScene, missingElevation, insideBuilding

    public var errorDescription: String? {
        switch self {
        case .invalidLocation: "現在地を読み取れませんでした。もう一度取得してください。"
        case .inaccurateLocation: "現在地の誤差が大きいため、建物との位置関係を確かめられません。位置情報の「正確な位置情報」をオンにし、空の開けた屋外で再取得してください。"
        case .staleLocation: "現在地の情報が古くなっています。もう一度取得してください。"
        case .outsideRegion: "現在地は試作の対象範囲外です。対応している地域の中でお試しください。"
        case .missingScene: "周辺の建物データを読み込めませんでした。"
        case .missingElevation: "この位置の地面・地形の標高データがありません。"
        case .insideBuilding: "取得した位置が建物の中に重なっています。地上の屋外へ移動し、現在地を再取得してください。"
        }
    }
}
