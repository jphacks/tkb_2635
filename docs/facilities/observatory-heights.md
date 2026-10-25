# 展望台・屋上の床の高さ（task.md の 1-07）

2026-10-25 に、展望台・屋上 12 地点の公式サイトを開いて「展望フロアの高さ」を確かめた。紹介記事・Wikipedia は出典にしていない。
採用した値は `spots.json` の `floorElevation`、出典は `floorElevationSource` に入れた（入力は [observatory-heights.json](observatory-heights.json)、反映は `scripts/gsi_elevation.py apply --write`）。

- 「地上 ◯ m」の地点: 床面標高 = 国土地理院 DEM の地面の標高（[gsi-elevation.json](../data/gsi-elevation.json)）＋ 公式の高さ
- 「海抜 ◯ m」の地点: 公式の値をそのまま使う
- 公式に高さが無い地点: 値を変えず、`floorElevationSource` は null（画面では「暫定値」）、`memo` に「公式未確認」と理由を書いた
- 目線の高さ `eyeHeight` は立って見る前提の 1.5 m のまま。床から窓の上端・下端の高さは、どの地点の公式サイトにも書かれていなかった（東京シティビューの「天高11メートル」、天望デッキの「高さ2mの窓ガラス」は窓の位置が分からないので使っていない）

| 地点 | 公式の高さ | DEM [m] | 採用した床面標高 [m]（前の値） | 出典 | 確認日 | 未確認の理由・注意 |
|---|---|---|---|---|---|---|
| SHIBUYA SKY | 「渋谷上空229m」 | 14.9 | 244（変えず） | [公式](https://www.shibuya-scramble-square.com/sky/observation/) | 2026-10-25 | **公式未確認**。229m が床の高さか建物の高さかが書かれていない（英語ページは建物も展望も「約230m」） |
| 東京都庁 展望室 | 地上202m | 41.0 | 243.0（242） | [公式](https://www.zaimu.metro.tokyo.lg.jp/tochousha/goannai/tenbou) | 2026-10-25 | 南北の展望室で値は分かれていない |
| KITTE ガーデン | なし（「6階の屋上庭園」） | 3.2 | 36（変えず） | [公式](https://marunouchi.jp-kitte.jp/guide/facilities.jsp) | 2026-10-25 | **公式未確認**。高さの記載なし |
| 東京スカイツリー 天望デッキ | 地上350m | 1.9 | 351.9（350.3） | [公式](https://www.tokyo-skytree.jp/floor/tembodeck_350/) | 2026-10-25 | 前は PLATEAU の地盤 0.3 m を足していた |
| 東京タワー メインデッキ | 150m | 18.5 | 168.5（168.4） | [公式](https://www.tokyotower.co.jp/maindeck/) | 2026-10-25 | 地上か海抜かの明記なし。地上として扱った |
| 東京タワー トップデッキ | 250m | 18.5 | 268.5（268.4） | [公式](https://tdt.tokyotower.co.jp/topdecktour/) | 2026-10-25 | 同上 |
| サンシャイン60展望台 | 海抜251m | 29.8 | 251.0（251） | [公式](https://sunshinecity.jp/observatory/) | 2026-10-25 | |
| 東京シティビュー | 海抜250m | 20.2 | 250.0（250、紹介記事の値） | [公式](https://tcv.roppongihills.com/jp/enjoy/friends/index.html) | 2026-10-25 | 値は同じで、出典が公式になった |
| 六本木ヒルズ スカイデッキ | 海抜270m | 20.2 | 270.0（270、紹介記事の値） | [公式 FAQ](https://art-view.roppongihills.com/jp/info/faq/) | 2026-10-25 | **公式のお知らせ（2024-04）で一般営業を終了**（[お知らせ](https://tcv.roppongihills.com/jp/news/2024/04/7228/)）。地点の扱いは要相談 |
| 浅草文化観光センター 展望テラス | なし（「8階 展望テラス」） | 4.2 | 43.5（変えず） | [台東区](https://www.city.taito.lg.jp/bunka_kanko/kankoinfo/info/oyakudachi/kankocenter/a-tic-gaiyo.html) | 2026-10-25 | **公式未確認**。高さの記載なし |
| カレッタ汐留 SKY VIEW | 確かめられず | 3.6 | 203.4（変えず） | [公式](https://www.caretta.jp/) | 2026-10-25 | **公式未確認**。公式サイトがメンテナンス中で開けない（検索の抜粋には「地上約200ｍ」） |
| タワーホール船堀 展望室 | 103m（塔は115m） | -1.0 | 102.0（101.7） | [公式](https://www.towerhall.jp/facility/) | 2026-10-25 | 地上か海抜かの明記なし。地上として扱った |

## 建物データとの基準のずれ

展望台では、DEM と建物データのシーンの地盤標高の差が 2 m を超える地点（都庁 +5.0 m、東京タワー +3.5 m、六本木 -9.8 m）でも公式の値を使った。
展望台の高さ（100〜350 m）に比べて差が小さく、六本木の 2 地点は海抜の値で DEM を使わないため。地上の地点では 2 m を超えたら変えていない（[gsi-elevation.md](../data/gsi-elevation.md)）。
