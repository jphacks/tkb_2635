import Foundation

/// 近傍照明（localGlareLevel）の確かめ方。決まりは docs/lighting/README.md
public enum LightingCheckMethod: String, Sendable {
    /// 公式サイトや地図サービスの夜の写真などによる机上評価
    case desk
    /// 夜に現地で確かめた
    case onsite
}

public extension Spot {
    /// 近傍照明の確かめ方。段階評価が無いときや、知らない値のときは nil。
    var localGlareCheck: LightingCheckMethod? {
        guard localGlareLevel != nil else { return nil }
        return lightingCheckMethod.flatMap(LightingCheckMethod.init(rawValue:))
    }

    /// 近傍照明が机上評価だけで、現地では確かめていないか
    var localGlareDeskChecked: Bool { localGlareCheck == .desk }

    /// 詳細画面に出す近傍照明の見出し（例: 「近傍照明（机上評価 2026-10-24）」）
    var localGlareLabel: String {
        let kind = localGlareCheck == .desk ? "机上評価" : "現地確認"
        guard localGlareCheck != nil, let date = lightingCheckDate else { return "近傍照明（\(kind)）" }
        return "近傍照明（\(kind) \(date)）"
    }

    /// 詳細画面に出す近傍照明の説明
    var localGlareNote: String {
        switch localGlareCheck {
        case .desk: "近傍照明は公式サイトや地図の夜の写真から決めた机上評価で、現地では確かめていません。照度の測定値ではありません。"
        case .onsite: "近傍照明は現地で確かめた段階評価で、照度の測定値ではありません。"
        case nil: "近傍照明は現地確認の段階評価で、照度の測定値ではありません。"
        }
    }
}
