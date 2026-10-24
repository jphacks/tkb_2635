/// 東京から見える代表的な明るい恒星（Bright Star Catalogue の J2000.0 座標から抜粋）
public enum StarCatalog {
    public static let stars: [Star] = [
        Star(id: "sirius", name: "シリウス", rightAscension: 6.7525, declination: -16.716, magnitude: -1.46),
        Star(id: "arcturus", name: "アークトゥルス", rightAscension: 14.2610, declination: 19.182, magnitude: -0.05),
        Star(id: "vega", name: "ベガ", rightAscension: 18.6156, declination: 38.784, magnitude: 0.03),
        Star(id: "capella", name: "カペラ", rightAscension: 5.2782, declination: 45.998, magnitude: 0.08),
        Star(id: "rigel", name: "リゲル", rightAscension: 5.2423, declination: -8.202, magnitude: 0.13),
        Star(id: "procyon", name: "プロキオン", rightAscension: 7.6550, declination: 5.225, magnitude: 0.34),
        Star(id: "betelgeuse", name: "ベテルギウス", rightAscension: 5.9195, declination: 7.407, magnitude: 0.42),
        Star(id: "altair", name: "アルタイル", rightAscension: 19.8464, declination: 8.868, magnitude: 0.76),
        Star(id: "aldebaran", name: "アルデバラン", rightAscension: 4.5987, declination: 16.509, magnitude: 0.86),
        Star(id: "antares", name: "アンタレス", rightAscension: 16.4901, declination: -26.432, magnitude: 0.96),
        Star(id: "spica", name: "スピカ", rightAscension: 13.4199, declination: -11.161, magnitude: 0.97),
        Star(id: "pollux", name: "ポルックス", rightAscension: 7.7553, declination: 28.026, magnitude: 1.14),
        Star(id: "fomalhaut", name: "フォーマルハウト", rightAscension: 22.9608, declination: -29.622, magnitude: 1.16),
        Star(id: "deneb", name: "デネブ", rightAscension: 20.6905, declination: 45.280, magnitude: 1.25),
        Star(id: "regulus", name: "レグルス", rightAscension: 10.1395, declination: 11.967, magnitude: 1.35),
        Star(id: "castor", name: "カストル", rightAscension: 7.5767, declination: 31.888, magnitude: 1.58),
        Star(id: "bellatrix", name: "ベラトリックス", rightAscension: 5.4189, declination: 6.350, magnitude: 1.64),
        Star(id: "polaris", name: "北極星", rightAscension: 2.5303, declination: 89.264, magnitude: 1.98),
    ]

    public static func star(id: String) -> Star? {
        stars.first { $0.id == id }
    }
}
