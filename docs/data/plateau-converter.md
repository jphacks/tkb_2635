# 2-03 PLATEAU → Astera 建物JSON変換

`scripts/plateau_to_json.py` は、PLATEAUの建物CityGMLを読み、アプリの `[CityScene]` と同じ形のJSONを書き出す。Python 3.9以上、追加ライブラリ・ネットワーク接続は不要。

## 実行例（渋谷）

2-02で取得した原本を `../outputs/plateau-shibuya-2025/` に保存した場合、リポジトリのルートで実行する。

```bash
python3 scripts/plateau_to_json.py \
  ../outputs/plateau-shibuya-2025/*_bldg_6697_op.gml \
  --output ../outputs/plateau-shibuya-2025/shibuya-buildings.json \
  --scene-id shibuya --name 渋谷駅周辺 \
  --latitude 35.6580 --longitude 139.7016 \
  --ground-elevation 15 --radius 500 \
  --codelists ../outputs/plateau-shibuya-2025/13113_shibuya-ku_pref_2025_citygml_1_op_codelists.zip \
  --source '東京都「3D都市モデル（Project PLATEAU）渋谷区（2025年度）」 https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025 を加工してAsteraチームが作成。CC BY 4.0。直方体近似・基準標高15mは既存シーンの暫定値'
```

**15mは既存シーンの暫定基準標高**で、今回測量・DEMから確定した値ではない。別の場所では確認した基準標高を明示的に指定する。省略時に0mを仮定しない。

- `--radius` の既定値は500m。原点と交わる円を対象にする。
- `--codelists` は展開済みフォルダでもZIPでもよい。省略やコードの未解決時は `usage: null` とし、意味を推測しない。
- `--report` で検証レポートの保存先を変えられる。省略時は出力ファイル名の `.json` を `.report.json` にした場所。
- 入力ファイルを上書きするパスや、出力とレポートが同じパスはエラー。
- 変換・検証を全て終えてから出力する。不正な入力では既存の建物JSONを上書きしない。書き込み時は一時ファイルから置き換える。JSONとレポートの2ファイル同時の原子的更新は保証しない。

## 変換方法

1. CityGML 2.0の `bldg:Building` を1棟として扱う。原本の `gml:id` をそのまま保持する。名称がなければIDを表示名に使い、架空の名称を付けない。
2. `lod1Solid` の座標を使用する。建物本体にLOD1がなく建物部分（BuildingPart）にだけある場合は、それらをまとめて1棟にする。建物部分を別の建物として二重出力しない。
3. EPSG:6697の **緯度・経度・標高**、3次元座標のみ対応。未対応の投影座標・楕円体高などを推測で変換しない。文書のEnvelopeから座標系と次元を読み、形状内の明示値を優先する。
4. アプリの `CityScene.localPosition` と同じ係数で原点から東・北のメートルへ変換し、軸に平行な外接長方形にする。円と長方形の最短距離が半径以下なら採用する。建物の中心だけで判定しない。実際の平面形と異なるため、角付近などでは範囲を多めに含む。
5. 高さは下記の規則でシーンの基準標高に揃える。出力の `height` は元の地盤からの計測高さと同じ値とは限らない。

```text
地盤標高 = LOD1の最低標高
形状の屋根標高 = LOD1の最高標高
採用する屋根標高 = max(形状の屋根標高, 地盤標高 + 有効なmeasuredHeight)
出力height = 採用する屋根標高 - シーンのgroundElevation
```

アプリは全建物の地面を同じ標高とみなすため、屋根の絶対標高を保持する。直方体の底面はシーンの地面まで伸び、建物ごとの地盤の傾斜や地下は表現しない。異なる高さ情報があるときは遮蔽を小さく見積もらないよう、高い方を採用する。正式な遮蔽精度を保証するものではない。

原本の `measuredHeight` が欠損・0・今回の原本で観測した `-9999` の場合は未確認として扱い、LOD1形状の屋根標高を使う。元の値はレポートの `rawMeasuredHeight` に保存する。他の負値・NaN・無限大・メートル以外の単位はエラー。幅・奥行き・有効高さが正にならない場合もエラーとし、勝手な高さを補わない。

6. `bldg:usage` の `codeSpace` とコードリストを照合する。未確認コードはレポートに残し、アプリ向けには `null` にする。
7. 同じID・同じ内容の重複は除去する。同じIDで内容が違えばエラー。IDで並べて出力し、再実行時の差分を安定させる。

建物内で解決できる `#id` 形式の形状参照は対応する。外部ファイルへの参照・未解決参照・循環参照・LOD2しかない建物はエラー。CityGML全体をメモリに保持せず、都市オブジェクト単位で処理する。

## 検証結果（2026-10-24）

- 渋谷区2025年度版4区画の9,535棟から1,497棟を出力。
- 全1,497棟の用途コードを名称に変換。47棟は有効な計測高さがなく、LOD1形状から屋根標高を採用。
- 現行Swiftの `CityScene` / `Building` を使い、出力JSONの読み込み、ID重複なし、寸法が正であることを確認。
- 12件のPythonテストで座標の符号・寸法・屋根標高・不明な高さ・円の境界・重複・コードリスト・建物部分・形状参照・不正入力を検証。
- StarCoreのSwiftテスト22件が成功。iOSビルドは環境の `sandbox_apply: Operation not permitted` によりパッケージ解決段階で失敗。

```bash
python3 -m unittest discover -s scripts/tests -p 'test_plateau*.py' -v
```

## アプリに組み込む前に（2-04）

このタスクでは、アプリ同梱の `buildings.json` は置き換えない。次の作業で原本の `gml:id` と観測地点の `hostBuildingId` を対応させる必要がある。いまの `scramble_square` などの仮IDのままだと、自分が立っている建物の除外判定が働かない。

高層建物の位置・高さ、基準標高、現実の方角を確かめ、観測者の高さと揃えてから組み込む。外接直方体は凹凸・屋根形状・窓・地形を表現しない。

## 仕様・出典

- [PLATEAUのCityGMLデータ構造](https://www.mlit.go.jp/plateau/learning/tpc03-2/)
- [PLATEAUの座標・高さ](https://www.mlit.go.jp/plateau/learning/tpc03-4/)
- [計測高さの定義と限界](https://www.mlit.go.jp/plateaudocument02/tocC/tocC_03/tocC_03_02/tocC_03_02_03/)
- [原本データ](https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025)（CC BY 4.0で利用）
