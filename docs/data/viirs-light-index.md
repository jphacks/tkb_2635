# 6-03 VIIRS 夜間光から地域の光害の値を作る

担当: ミスミ。記録日: 2026-10-24。

`spots.json` の `regionalLightIndex`（地域の光害、0〜1）を、衛星から見た夜の明るさで決める。2025 年の年次合成で全 9 地点を差し替えた（2026-10-24）。

## 出典と利用条件

- データ: VIIRS Nighttime Lights（VNL）年次合成 v2.2、2025 年、`average_masked`（背景を 0 にした月平均の年平均）
- 取得元: <https://eogdata.mines.edu/nighttime_light/annual/v22/2025/>
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
R_DARK = 1.0、R_BRIGHT = 250.0 [nW/cm²/sr]
```

しきい値の考え方:

- 人の目の明るさの感じ方は対数に近いので、R をそのまま比べず対数にする
- 郊外・暗い場所は 1 nW/cm²/sr 以下になるのが目安なので R_DARK = 1 とした
- 上限は、最初は都心の目安 100〜200 から R_BRIGHT = 150 としていた。2025 年の原本で確かめると、渋谷駅東口は 3×3 平均 188・中心画素 235 で、150 では渋谷・SHIBUYA SKY が 1.00 で頭打ちになり、9 地点が 0.70〜1.00 に縮んだ。渋谷駅周辺の実測 235 を上限の目安にして R_BRIGHT = 250 とし、0.63〜0.95 に広げた
- 幾何平均の約 16 nW/cm²/sr がちょうど 0.5 になる

2025 年の原本での値（3×3 平均。生の値は [viirs-light-index.json](viirs-light-index.json)）:

| 地点 | R [nW/cm²/sr] | index | 前の暫定値 |
|---|---:|---:|---:|
| 渋谷駅東口 地上・SHIBUYA SKY | 188.2 | 0.95 | 0.95 |
| KITTE ガーデン | 124.5 | 0.87 | 0.95 |
| 新宿中央公園 | 110.0 | 0.85 | 0.90 |
| 都庁 南展望室 | 91.9 | 0.82 | 0.90 |
| 新宿御苑 | 86.0 | 0.81 | 0.80 |
| 代々木公園 | 53.2 | 0.72 | 0.80 |
| 葛西臨海公園 | 50.8 | 0.71 | 0.55 |
| 荒川河川敷 | 33.0 | 0.63 | 0.60 |

R_BRIGHT は 9 地点の値を見て決めたので、地点を大きく増やしたら並びを見直す。

定数は `scripts/viirs_to_spots.py` の先頭の 1 か所にだけ書いてある。変えるときはそこを直して再実行する。

## 実行手順

rasterio が要る（`python3 -m pip install rasterio`）。原本は全球のファイルで大きいので Git には入れず、リポジトリの外に置く。

```bash
# 1. 確認だけ（既定）。地点ごとの R・新しい値・今の値の表が出る（ファイル名は例）
python3 scripts/viirs_to_spots.py ~/Downloads/viirs/VNL_npp_2025_global_vcmslcfg_v2_c202604011200.average_masked.dat.tif

# 2. 書き戻す（--archive に配布された .tif.gz を渡すと、その SHA-256 も記録する）
python3 scripts/viirs_to_spots.py <原本のパス> --archive <原本のパス>.gz --write
```

- `.tif.gz` のままでも読める。全球ファイルを全部は読まず、地点のまわりだけを読む（`gunzip` で解凍しておくと速い）
- データの年はファイル名から取る。取れないときは `--year 2023` を付ける
- `--write` で `spots.json` の `regionalLightIndex`・`regionalLightSource`・`regionalLightMeasuredAt` を書き換え、原本のファイル名・SHA-256・各地点の生の値 R を [viirs-light-index.json](viirs-light-index.json) に残す。ほかの項目と並び順は変えない
- 2025 年の原本: 展開後 BigTIFF 11.6 GB（86401×33601 画素、float32、nodata 未設定）、配布 .tif.gz の SHA-256 は `55cdc85d…95e3ab`（全体は記録の JSON）
- 地点を足したら、同じコマンドをもう一度実行する
- テスト: `python3 -m pytest scripts/tests/test_viirs_to_spots.py`（数画素の疑似 GeoTIFF を使い、通信しない）

## 制約

- 画素は約 460 m（東京の緯度で東西 約 380 m × 南北 約 460 m）。公園の中と外の差のような細かい違いは出ない。近くの街灯などは別の項目（近傍照明 `localGlareLevel`、6-04）で扱う
- 1 年の平均なので、季節・曜日・時刻（深夜の消灯など）による違いは分からない
- 雲のある夜は除いて平均している。月明かりのある夜も除くので、月の明るさは含まない（月明かりはアプリで別に計算している）。積雪による反射の影響は、東京では小さいと考えている（確かめていない）
- VIIRS は真上から見た明るさで、夜空の明るさ（スカイグロー）を直接測ったものではない。地域の目安として使う
- `average_masked` は光の無い背景を 0 にしているので、暗い場所は R が 0 になり、index も 0 になる。0 は「暗い」という値なので欠損として除かない（除くのは nodata と負の値だけ）
