# Astera（アステラ）東京都23区 星空観測支援アプリ

[![IMAGE ALT TEXT HERE](https://jphacks.com/wp-content/uploads/2026/07/IMG_5316.png)](https://www.youtube.com/watch?v=piaNsc6ilBI)

## 製品概要
**「今夜、どこへ行けば、どんな星空が見えるのか。」**

### 背景(製品開発のきっかけ、課題等）
都市部では、天気が良くても高層ビルに遮られて星や月が見えないことが多い。人工照明や雲、観測場所の高さによっても見え方は変わる。展望台や屋上には営業時間・料金・立入制限もある。これらをまとめて確かめる手段がない。

### 製品説明（具体的な製品の説明）
東京都23区の公園・広場・河川敷・展望台・屋上を対象に、指定した日時と天体（月・惑星・明るい恒星）について、観測に向いた地点を推薦する iPhone アプリ。
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
- PLATEAU の対象地域拡大・国土地理院 DEM の取り込み（渋谷はPLATEAUを導入済み。西新宿は概略データ）
- 現地調査による近傍照明の評価、施設情報の確認
- 地上と展望台の比較画面、時刻スライダー、現在地からの距離

### 注力したこと（こだわり等）
* 地上と展望台で月の見え方が変わることを、計算と 3D の両方で示す
* スコアは観測できる確率ではないこと、未確認のデータがあることを画面上で明示する

## 開発技術
### 活用した技術
#### API・データ
* [Open-Meteo](https://open-meteo.com/) Forecast API（雲量・降水量・風速・視程、CC BY 4.0）
* 地域の光害: [VIIRS Nighttime Lights](https://eogdata.mines.edu/products/vnl/) 年次合成 v2.2（Earth Observation Group, Payne Institute for Public Policy, Colorado School of Mines、CC BY 4.0）を加工
* Bright Star Catalogue（明るい恒星 52 個の J2000.0 座標・等級を抜粋）、惑星（水星〜土星）は Paul Schlyter「[Computing planetary positions](https://stjarnhimlen.se/comp/ppcomp.html)」の軌道要素
* 建物データ: [東京都・PLATEAU渋谷区2025年度版](https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025)を加工（CC BY 4.0）。渋谷駅周囲500mの1,497棟を直方体近似。西新宿は手作りの概略データ。

#### フレームワーク・ライブラリ・モジュール
* SwiftUI（画面はすべて SwiftUI）
* MapKit for SwiftUI（地点の地図表示）
* RealityKit / RealityView（3D プレビュー）
* Swift Testing（計算ロジックのテスト）

#### デバイス
* iPhone（iOS 18 以降）

### 独自技術
#### ハッカソンで開発した独自機能・技術
* 月・太陽・恒星の位置計算（[Astro.swift](Packages/StarCore/Sources/StarCore/Astro/Astro.swift)）: 天文年鑑の低精度式を Swift で実装。Astronomy Engine と比べ、月の位置の誤差は 0.7° 以内（テストで確認）。惑星（[Planets.swift](Packages/StarCore/Sources/StarCore/Astro/Planets.swift)）は軌道要素から計算し、skyfield（JPL DE421）との差は 2 時刻 × 5 惑星で最大 0.013°（テストの許容差は 0.3°、[説明](docs/astro/planets.md)）
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
  Sources/StarCore/Resources/spots.json      観測地点（12地点、5種類）
  Sources/StarCore/Resources/buildings.json  渋谷（PLATEAU 1,497棟）・西新宿（概略）
scripts/plateau_to_json.py CityGML → アプリ用JSONへの変換
```

### スコア
- 暗さ D = clamp(1 − (0.45·地域の光害 + 0.25·近傍照明 + 0.30·月明かり), 0, 1)
- 総合 S = 100 (0.35·空の開放度 + 0.40·天気 + 0.25·暗さ)
- 太陽高度が −6°（市民薄明の限界）より上なら恒星は「見えない」扱い。−18°（天文薄明の限界）までは太陽の光の残りに応じて暗さ D を直線的に下げる。月は昼間でも除外しないが「推薦」にはしない
- 利用時間外・天体が見えない地点は、スコアに関係なく下位にする

### データについての注意
* 舎人公園・水元公園・駒沢オリンピック公園を追加し、計12地点。追加3地点は建物・樹木・光害などが未確認のため「要確認」。詳細画面には天候による閉鎖条件・撮影機材の制限も表示する（[出典・実機での確認箇所](docs/facilities/observation-conditions.md)）。都庁南展望室は公式の方角案内を表示するが、窓の境界角度は確認待ち。
* 公園・広場・河川敷の既存6地点に、確認済みの利用時間と未確認の区別を反映（[1-06の調査と運用](docs/night-access/README.md)）。新宿御苑の季節・休園日判定は2026〜2027年が対象。SHIBUYA SKY・都庁南展望室・KITTEガーデンは1-03〜1-05で確認した公式情報を使用。臨時の閉鎖は公式案内を確認すること
* 地域の光害指標は VIIRS 夜間光（2025 年の年次合成、約 460 m の画素の年平均）から作った（[手順と出典](docs/data/viirs-light-index.md)）。近傍照明は未確認（画面に表示される）
* 恒星の位置は歳差を補正済みで、精密な計算（skyfield + JPL DE421）との差は 0.01° 未満。章動・光行差・恒星の固有運動は未補正（[検証の記録](docs/astro/verification.md)）

### PLATEAU原本の取得（2-02）

渋谷駅周辺の2025年度版CityGML原本を取得済みです。出典、利用条件、再取得コマンドは [取得記録](docs/data/plateau-shibuya-2025.md) を参照してください。変換（2-03）と渋谷シーンへの組み込み（2-04）まで実施済みです。

### PLATEAU建物の変換（2-03）

取得したCityGMLから、指定地点の周囲500mの建物をアプリ形式のJSONに変換できます。[実行方法・高さの扱い・制約](docs/data/plateau-converter.md)を参照してください。渋谷シーンへの組み込みは[導入記録（2-04）](docs/data/shibuya-scene-integration.md)に記載しています。

### 渋谷のPLATEAU建物（2-04）

東京都「3D都市モデル（Project PLATEAU）渋谷区（2025年度）」を加工してAsteraチームが作成しました（CC BY 4.0）。出典URL・原本のSHA-256・変換規則・建物IDの対応付けは[導入記録](docs/data/shibuya-scene-integration.md)に記載しています。詳細画面の「建物データ」でも出典と収録建物数を確認できます。

建物は外接直方体による近似です。建物ごとの地盤差は屋根標高に反映しますが、地形そのものは再現していません。観測地点の位置はデモ用の代表点、床面標高は暫定値です。原点から500m外の高層建物や現地の立入可否は未確認です。

### 建物の夜景表現（8-06）

3D建物に青灰色の外壁と控えめな暖色の窓明かりを追加しました。用途を参考にした演出で、実際の外壁色・点灯状況を再現するものではありません。[素材と確認状況](docs/design/building-night/README.md)を参照してください。
