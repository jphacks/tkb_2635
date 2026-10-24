# 6-06 World Atlas（Falchi 2016）から天頂の空の明るさを取る

担当: ミスミ。記録日: 2026-10-24。状態: **原本を入手できず、止めている**（値は入れていない）。

VIIRS（6-03）は「地上から上向きに出る光の量」で、星を見る人が知りたい「天頂の空の明るさ」とは違う。World Atlas は天頂の人工光の輝度をモデルで直接求めたもので、これを Bortle 等級相当の参考表示に使う案。スコア・推薦の順位には使わない予定（P2 の参考表示）。

## 出典と利用条件（2026-10-24 確認）

- データ: Supplement to: The New World Atlas of Artificial Night Sky Brightness（GFZ Data Services）
- DOI: [10.5880/GFZ.1.4.2016.001](https://doi.org/10.5880/GFZ.1.4.2016.001)
- 中身: 人工光による天頂輝度のモデル値（mcd/m²）、30 秒角（約 1 km）の GeoTIFF 1 枚（約 2.9 GB）。2015 年の VIIRS をもとにした計算値で、実測ではない。星・天の川などの自然光は含まない
- ライセンス: CC BY-NC 4.0（DataCite のメタデータに `CC-BY-NC-4.0`、アクセスは `Open access` と記載）。非営利なら加工・再配布してよい。出典の表示が条件
- 引用:

> Falchi, F., Cinzano, P., Duriscoe, D., Kyba, C. C. M., Elvidge, C. D., Baugh, K., Portnov, B. A., Rybnikova, N. A., Furgoni, R. (2016). The new world atlas of artificial night sky brightness. Science Advances, 2(6), e1600377. doi:10.1126/sciadv.1600377

> Falchi, F. et al. (2016). Supplement to: The New World Atlas of Artificial Night Sky Brightness. GFZ Data Services. doi:10.5880/GFZ.1.4.2016.001

## 入手を試した結果

| 手順 | 結果 |
|---|---|
| `https://doi.org/10.5880/GFZ.1.4.2016.001` | GFZ Data Services の案内ページに移る（登録の画面は出ない） |
| 案内ページの「Download data and description」 | `https://dataservices.gfz.de/landing-page-downloads/3/primary` → `https://datapub.gfz.de/download/10.5880.GFZ.1.4.2016.001/` へ転送 |
| `datapub.gfz.de` への接続（curl・アプリ内ブラウザ、2026-10-24 に数回） | **つながらない**。名前は 139.17.228.237 に引けるが、443 番への接続が時間切れになる。`www.gfz.de` と `dataservices.gfz.de` は開ける |
| ミスミの Chrome（2026-10-24） | 同じく `ERR_CONNECTION_TIMED_OUT`（応答時間が長すぎる） |
| 依頼元セッションの Chrome・curl（2026-10-24） | https・http とも 20 秒で時間切れ。旧ホスト名 `datapub.gfz-potsdam.de` も同じ IP（139.17.228.237）で同じ結果。案内ページ `dataservices.gfz.de` は 200 で開く |
| ほかの配布元 | 公式のミラーは見つからなかった。CIRES の KMZ は表示用の画像で、輝度の値は取れない |

登録が要るかどうかは、ファイル一覧のページが開けないため確かめられていない（案内ページまでは登録なしで開ける）。

## 再開するときの手順（案）

1. `datapub.gfz.de` がつながるか確かめ、GeoTIFF を `~/Downloads/world-atlas/` に保存する（Git に入れない。SHA-256 を記録する）
2. `scripts/viirs_to_spots.py` に倣い、各地点の 3×3 画素平均の人工光輝度 A [mcd/m²] を取る
3. 自然光（Falchi 2016 では 174 µcd/m² = 0.174 mcd/m²、約 22.0 mag/arcsec²）を足した総輝度 L [mcd/m²] から、mag/arcsec² = −2.5·log10(L / 1.08×10⁸) を求める（1.08×10⁵ cd/m² ≈ 0 mag/arcsec²）。単位を取り違えやすいので、式と定数は論文本文で確かめてから使う
4. Bortle 相当の区分（定数 1 か所）を決め、`spots.json` に `skyBrightnessMagArcsec2`・`bortleClass`・`skyBrightnessSource` を省略可で書き戻す
5. 詳細画面の光害セクションに「空の明るさ（天頂）」の 1 行を足す（値が無ければ出さない）
