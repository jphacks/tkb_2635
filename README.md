# Astera（アステラ）東京都23区 星空観測支援アプリ

[![IMAGE ALT TEXT HERE](https://jphacks.com/wp-content/uploads/2026/07/IMG_5316.png)](https://www.youtube.com/watch?v=piaNsc6ilBI)

## 製品概要
**「今夜、どこへ行けば、どんな星空が見えるのか。」**

### 背景(製品開発のきっかけ、課題等）
都市部では、天気が良くても高層ビルに遮られて星や月が見えないことが多い。人工照明や雲、観測場所の高さによっても見え方は変わる。展望台や屋上には営業時間・料金・立入制限もある。これらをまとめて確かめる手段がない。

### 製品説明（具体的な製品の説明）
東京都23区の公園・広場・河川敷・展望台・屋上を対象に、指定した日時と天体（月・明るい恒星）について、観測に向いた地点を推薦する iPhone アプリ。
建物の形、観測者の目の高さ、天体の位置、雲量、光害、施設の利用時間をもとに判定し、建物と天体の位置関係を 3D で表示する。

### 特長
#### 1. 観測者の高さを考慮した遮蔽判定
地点ごとに「床面の標高＋目線の高さ」を持たせ、方位 1° ごとに周囲の建物の最大仰角（地平線プロファイル）を計算する。同じ渋谷駅付近でも、地上では月がビルに隠れ、SHIBUYA SKY では見えることを示せる。
#### 2. 3D プレビュー
建物と観測地点、天体の方向を RealityKit で描画する。見える場合は緑、遮られる場合は赤の線で示す。
#### 3. 根拠を示す推薦
「南南東の空が開けており、指定時刻の月を建物に遮られず観測できる見込みです。ただし、周辺照明は未確認です。」のように理由を表示する。未確認のデータは 0 として扱わず、「要確認」として区別する。

### 解決出来ること
「せっかく出かけたのにビルで見えなかった」「展望台が閉まっていた」を事前に避けられる。

### 今後の展望
- PLATEAU の建物データ・国土地理院 DEM の取り込み（現在は手作りの概略データ）
- VIIRS 夜間光による地域の光害指標（現在は暫定値）
- 現地調査による近傍照明の評価、施設情報の確認
- 地上と展望台の比較画面、時刻スライダー、現在地からの距離

### 注力したこと（こだわり等）
* 地上と展望台で月の見え方が変わることを、計算と 3D の両方で示す
* スコアは観測できる確率ではないこと、未確認のデータがあることを画面上で明示する

## 開発技術
### 活用した技術
#### API・データ
* [Open-Meteo](https://open-meteo.com/) Forecast API（雲量・降水量・風速・視程、CC BY 4.0）
* Bright Star Catalogue（明るい恒星の J2000.0 座標を抜粋）
* 建物データ: 手作りの概略データ（PLATEAU 取り込み予定）

#### フレームワーク・ライブラリ・モジュール
* SwiftUI（画面はすべて SwiftUI）
* MapKit for SwiftUI（地点の地図表示）
* RealityKit / RealityView（3D プレビュー）
* Swift Testing（計算ロジックのテスト）

#### デバイス
* iPhone（iOS 18 以降）

### 独自技術
#### ハッカソンで開発した独自機能・技術
* 月・太陽・恒星の位置計算（[Astro.swift](Packages/StarCore/Sources/StarCore/Astro/Astro.swift)）: 天文年鑑の低精度式を Swift で実装。Astronomy Engine と比べ、月の位置の誤差は 0.7° 以内（テストで確認）
* 地平線プロファイルと空の開放度（[HorizonProfile.swift](Packages/StarCore/Sources/StarCore/Geometry/HorizonProfile.swift)）
* 観測地点の推薦（[Recommender.swift](Packages/StarCore/Sources/StarCore/Scoring/Recommender.swift)）: 立入条件 → 可視性 → 天気 → 暗さ → 順位付け → 推薦理由

## 開発の始め方

施設情報（SHIBUYA SKY・都庁南展望室・KITTEガーデン）の公式確認と日次更新PRについては、[公式施設情報の運用](docs/facilities/README.md)を参照。
毎朝の自動確認は、GitHub 側の許可（管理者の設定）待ちで、まだ動いていない。許可が出るまでは、手元で `python3 scripts/update_official_facilities.py --write` を実行し、変更があれば PR を `develop` に出す。

```bash
brew install xcodegen
xcodegen generate
open StarSpot.xcodeproj
```

計算ロジックのテスト:

```bash
cd Packages/StarCore && swift test
```

### 構成
```
App/                       SwiftUI アプリ（一覧・詳細・3D プレビュー）
Packages/StarCore/         モデル・天体計算・遮蔽判定・天気・スコア（ローカル Swift Package）
  Sources/StarCore/Resources/spots.json      観測地点（9地点、5種類）
  Sources/StarCore/Resources/buildings.json  渋谷・西新宿の建物（概略）
scripts/plateau_to_json.py PLATEAU 変換のスタブ
```

### スコア
- 暗さ D = clamp(1 − (0.45·地域の光害 + 0.25·近傍照明 + 0.30·月明かり), 0, 1)
- 総合 S = 100 (0.35·空の開放度 + 0.40·天気 + 0.25·暗さ)
- 利用時間外・天体が見えない地点は、スコアに関係なく下位にする

### データについての注意
* 公園・広場・河川敷の既存6地点に、確認済みの利用時間と未確認の区別を反映（[1-06の調査と運用](docs/night-access/README.md)）。新宿御苑の季節・休園日判定は2026〜2027年が対象。SHIBUYA SKY・都庁南展望室・KITTEガーデンは1-03〜1-05で確認した公式情報を使用。臨時の閉鎖は公式案内を確認すること
* 地域の光害指標・近傍照明は未取り込み・未確認（画面に表示される）
* 恒星の位置は歳差を補正していないため、0.4° 程度の誤差がある

### PLATEAU原本の取得（2-02）

渋谷駅周辺の2025年度版CityGML原本を取得済みです。出典、利用条件、再取得コマンドは [取得記録](docs/data/plateau-shibuya-2025.md) を参照してください。アプリ向けの変換と建物データの置き換えは次の作業（2-03・2-04）です。
