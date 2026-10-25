import Foundation

/// アプリで使っているデータ・素材の出典 1 件。出典は設定の「出典とライセンス」にまとめて出し、ふだんの画面には出さない
public struct DataCredit: Identifiable, Sendable, Equatable {
    public let id: String
    /// 何に使っているか（例: 建物の 3D）
    public let purpose: String
    /// データ・素材の名前
    public let name: String
    /// 提供元（出典として表示する名前）
    public let provider: String
    /// ライセンス・利用条件。nil は確認中
    public let license: String?
    public let url: URL?
    /// 加工の内容など
    public let note: String?

    public init(id: String, purpose: String, name: String, provider: String,
                license: String?, url: URL?, note: String? = nil) {
        self.id = id
        self.purpose = purpose
        self.name = name
        self.provider = provider
        self.license = license
        self.url = url
        self.note = note
    }

    /// 画面に出すライセンスの文。確認中は「未確認」と分かるようにする
    public var licenseText: String { license ?? "利用条件を確認中" }
}

public extension DataCredit {
    /// 同梱・取得しているデータの出典の一覧（README の「API・データ」の表と同じ内容にする）
    static let all: [DataCredit] = [
        DataCredit(
            id: "plateau", purpose: "建物の 3D（地点ごと・23 区の広域）",
            name: "3D 都市モデル（Project PLATEAU）東京都 23 区（2025 年度）",
            provider: "国土交通省", license: "CC BY 4.0",
            url: URL(string: "https://www.mlit.go.jp/plateau/"),
            note: "LOD1・LOD2 を Astera チームが加工（直方体近似・軽量化）"),
        DataCredit(
            id: "gsi-tiles", purpose: "遠くの地面・建物の写真",
            name: "地理院タイル（全国最新写真）", provider: "国土地理院",
            license: "国土地理院コンテンツ利用規約",
            url: URL(string: "https://maps.gsi.go.jp/development/ichiran.html"),
            note: "夜の見た目になるよう暗く加工"),
        DataCredit(
            id: "gsi-elevation", purpose: "地点の標高",
            name: "標高 API", provider: "国土地理院",
            license: "国土地理院コンテンツ利用規約",
            url: URL(string: "https://maps.gsi.go.jp/development/elevation_s.html")),
        DataCredit(
            id: "viirs", purpose: "地域の光害・遠くの街明かり",
            name: "VIIRS Nighttime Lights 年次合成 v2.2",
            provider: "Earth Observation Group, Payne Institute for Public Policy, Colorado School of Mines",
            license: "CC BY 4.0", url: URL(string: "https://eogdata.mines.edu/products/vnl/"),
            note: "0〜1 の指標に変換"),
        DataCredit(
            id: "open-meteo", purpose: "天気（雲量・降水量・風速・視程）",
            name: "Open-Meteo Forecast API", provider: "Open-Meteo",
            license: "CC BY 4.0", url: URL(string: "https://open-meteo.com/")),
        DataCredit(
            id: "nasa-starmap", purpose: "背景の星空",
            name: "Deep Star Maps 2020",
            provider: "NASA/Goddard Space Flight Center Scientific Visualization Studio",
            license: "NASA の画像利用ガイドライン",
            url: URL(string: "https://svs.gsfc.nasa.gov/4851")),
        DataCredit(
            id: "gaia", purpose: "背景の星空（Deep Star Maps に含まれる分）",
            name: "Gaia のデータ", provider: "ESA/Gaia/DPAC",
            license: nil, url: URL(string: "https://www.cosmos.esa.int/web/gaia")),
        DataCredit(
            id: "d3-celestial", purpose: "星座線・星座名",
            name: "d3-celestial", provider: "Olaf Frohn",
            license: "BSD-3-Clause", url: URL(string: "https://github.com/ofrohn/d3-celestial")),
        DataCredit(
            id: "nasa-moon", purpose: "月面の画像",
            name: "CGI Moon Kit", provider: "NASA's Scientific Visualization Studio",
            license: "NASA の画像利用ガイドライン",
            url: URL(string: "https://svs.gsfc.nasa.gov/4720")),
        DataCredit(
            id: "nasa-planets", purpose: "惑星の画像",
            name: "NASA の探査機の写真", provider: "NASA",
            license: "パブリックドメイン", url: nil),
        DataCredit(
            id: "bright-star", purpose: "恒星の位置",
            name: "Bright Star Catalogue", provider: "Yale University Observatory",
            license: nil, url: nil, note: "J2000.0 の座標を使用"),
        DataCredit(
            id: "schlyter", purpose: "惑星の位置の計算",
            name: "How to compute planetary positions（軌道要素）", provider: "Paul Schlyter",
            license: nil, url: URL(string: "https://stjarnhimlen.se/comp/ppcomp.html"))
    ]
}
