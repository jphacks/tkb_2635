# 6-03 VIIRS 夜間光から地域の光害の値を作る

担当: ミスミ。記録日: 2026-10-24。

`spots.json` の `regionalLightIndex`（地域の光害、0〜1）を、衛星から見た夜の明るさで決める。今は手入力の暫定値で、原本の取り込み後に下の手順で差し替える。

## 出典と利用条件

- データ: VIIRS Nighttime Lights（VNL）年次合成 v2.2、`average_masked`（背景を 0 にした月平均の年平均）
- 提供元: Earth Observation Group（EOG）, Payne Institute for Public Policy, Colorado School of Mines
- 製品ページ: <https://eogdata.mines.edu/products/vnl/>（v2.2 の説明: [VNL_v22_readme_20230707.pptx](https://eogdata.mines.edu/products/vnl/VNL_v22_readme_20230707.pptx)）
- 形式: GeoTIFF（gzip 圧縮）、EPSG:4326、15 秒角（赤道で約 500 m）、単位 nW/cm²/sr
- 入手: ダウンロードには EOG のアカウント登録（無料）が要る
- ライセンス: [CC BY 4.0](https://eogdata.mines.edu/files/EOG_products_CC_License.pdf)。商用を含め加工・再配布してよい。出典の表示と、加工したことの明示が条件

EOG の利用条件（上の PDF、2026-10-24 確認）では、データから作ったものに次のどちらかを付ける。

- 表示: 「This product was made utilizing VIIRS Nighttime Lights data produced by the Earth Observation Group, Payne Institute for Public Policy, Colorado School of Mines.」
- 場所が狭いとき: 「Source: EOG, Colorado School of Mines.」

アプリでは詳細画面の「光害」セクションに出典（`regionalLightSource`、EOG, Colorado School of Mines を含む）を出す。この値は原本の放射輝度を下の式で加工したものである。

発表・資料で使うときは次を引用する（製品ページの記載どおり）。

> Elvidge, C.D., Zhizhin, M., Ghosh T., Hsu FC, Taneja J. Annual time series of global VIIRS nighttime lights derived from monthly averages: 2012 to 2019. Remote Sensing 2021, 13(5), p.922, doi:10.3390/rs13050922

## 変換のしかた

1. 地点の緯度・経度が入る画素を中心に、3×3 画素（約 1.4 km 四方）の放射輝度の平均 R を取る。nodata・負の値は平均から除く。9 画素すべて欠損なら値を更新せず警告する
2. R を対数で 0〜1 に変換する（小数 2 桁に丸める）

```
index = clamp((log10(R) − log10(R_DARK)) / (log10(R_BRIGHT) − log10(R_DARK)), 0, 1)
R_DARK = 1.0、R_BRIGHT = 150.0 [nW/cm²/sr]
```

しきい値の考え方:

- 人の目の明るさの感じ方は対数に近いので、R をそのまま比べず対数にする
- 都心の繁華街は 100〜200 nW/cm²/sr、郊外・暗い場所は 1 以下になるのが目安。その間を 0〜1 に広げるため R_BRIGHT = 150、R_DARK = 1 とした。幾何平均の約 12 nW/cm²/sr がちょうど 0.5 になる
- 23 区内の地点の実際の R は、原本で `--dry-run` を実行して確かめる（まだ確かめていない）

定数は `scripts/viirs_to_spots.py` の先頭の 1 か所にだけ書いてある。変えるときはそこを直して再実行する。

## 実行手順

rasterio が要る（`python3 -m pip install rasterio`）。原本は全球のファイルで大きいので Git には入れず、リポジトリの外に置く。

```bash
# 1. 確認だけ（既定）。地点ごとの R・新しい値・今の値の表が出る（ファイル名は例）
python3 scripts/viirs_to_spots.py ~/Downloads/VNL_npp_2023_global_vcmslcfg_v2_c202402081600.average_masked.dat.tif.gz

# 2. 書き戻す
python3 scripts/viirs_to_spots.py <原本のパス> --write
```

- `.tif.gz` のままでも読める。全球ファイルを全部は読まず、地点のまわりだけを読む（`gunzip` で解凍しておくと速い）
- データの年はファイル名から取る。取れないときは `--year 2023` を付ける
- `--write` で `spots.json` の `regionalLightIndex`・`regionalLightSource`・`regionalLightMeasuredAt` を書き換え、原本のファイル名・SHA-256・各地点の生の値 R を [viirs-light-index.json](viirs-light-index.json) に残す。ほかの項目と並び順は変えない
- 地点を足したら、同じコマンドをもう一度実行する
- テスト: `python3 -m pytest scripts/tests/test_viirs_to_spots.py`（数画素の疑似 GeoTIFF を使い、通信しない）

## 制約

- 画素は約 460 m（東京の緯度で東西 約 380 m × 南北 約 460 m）。公園の中と外の差のような細かい違いは出ない。近くの街灯などは別の項目（近傍照明 `localGlareLevel`、6-04）で扱う
- 1 年の平均なので、季節・曜日・時刻（深夜の消灯など）による違いは分からない
- 雲のある夜は除いて平均している。月明かりのある夜も除くので、月の明るさは含まない（月明かりはアプリで別に計算している）。積雪による反射の影響は、東京では小さいと考えている（確かめていない）
- VIIRS は真上から見た明るさで、夜空の明るさ（スカイグロー）を直接測ったものではない。地域の目安として使う
- `average_masked` は光の無い背景を 0 にしているので、暗い場所は R が 0 になり、index も 0 になる
