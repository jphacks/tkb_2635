# 4-08 PLATEAU の実形状・実写テクスチャで 3D を描く

渋谷の 3D を、外接直方体（建物をすっぽり包む箱）＋作り物の窓模様から、**PLATEAU の LOD2（屋根・壁の形まであるデータ）の実際の形と、航空写真から作られた実写の外壁・屋上**に替えた。地面には国土地理院の航空写真を貼った。**見た目だけの変更**で、位置・寸法・地平線・遮蔽判定・スコアは今までどおり `buildings.json` の箱で計算する。

| SHIBUYA SKY（見える） | 展望デッキから見下ろす | 渋谷駅東口 地上（隠れる） |
|---|---|---|
| ![](shibuya-sky.png) | ![](shibuya-sky-deck.png) | ![](ground-blocked.png) |

2026-10-24 21:00 の月。iPhone 17 Pro シミュレータで撮影。

## 何が変わったか

- 1,497 棟を実形状で描く（LOD2 が 1,434 棟、LOD2 が無い 63 棟は LOD1 の柱状）。屋上の段差・塔屋・設備も入る
- 面の約 9 割（61,427 面）に PLATEAU の実写テクスチャを貼る。写真は昼のものなので、**夜は暗く青みに寄せて表示**する（凡例に「建物・地面は昼の実写を暗く表示」と出す）。写真の無い面は CC0 のコンクリート
- 地面は地理院タイルの航空写真（約 1.6km 四方）。その外側は CC0 のアスファルト
- 月が建物に隠れるとき、**h(A) を決めている建物の判定用の箱を赤い枠**で示す。実際の形は箱より細いので、枠が無いと「線が建物の脇を抜けて見えるのに判定は遮られる」ことが起こりうるため
- 観測者の床が建物の屋根より高い地点（SHIBUYA SKY）に、屋上の展望デッキ（足元灯・ガラスの柵）を出す。形はイメージで、計算には使わない
- 1,497 個あった建物の部品を 20 個ほどにまとめたので、描画の回数が減る（実機では未計測）
- 8-06 の窓明かりの素材（`BuildingNightRenderer`）は、3D ファイルが無いシーン（西新宿など）でそのまま使う

## 作り方

```bash
O=../outputs/plateau-shibuya-2025
# 1. 原本の GML を取得（約360MB、リポジトリの外に置く）
python3 scripts/download_plateau.py --output $O

# 2. LOD2 の面と、実写テクスチャの貼り方を取り出す（buildings.json の 1,497 棟だけ。箱の高さで切りそろえる）
python3 scripts/plateau_shapes.py $O/*_bldg_6697_op.gml \
  --buildings Packages/StarCore/Sources/StarCore/Resources/buildings.json \
  --scene-id shibuya --output $O/shibuya-shapes.json

# 3. 使う実写テクスチャ（4,066 枚、約60MB）を取得
python3 scripts/download_plateau_textures.py $O/shibuya-shapes.json --output $O

# 4. 地面の航空写真（地理院タイル z18、14×14 枚）を取得
python3 scripts/download_gsi_photo.py --latitude 35.658 --longitude 139.7016 --radius 800 --output ../outputs/gsi-shibuya

# 5. Blender（4.0.2 で確認）で USDZ にする
/Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender_city_usdz.py -- \
  $O/shibuya-shapes.json App/Resources/City/City_shibuya.usdz ../outputs/gsi-shibuya
```

- 実写テクスチャは合計 3.4 億画素あり、そのままでは実機の GPU メモリに入らない。Blender で 28% に縮め、4096px 四方の画像（アトラス）2 枚にまとめた（GPU 上ではミップマップ込みで 1 枚約 90MB）
- 部品の名前（`atlas_0`・`atlas_1`・`ground_photo`・`roof`・`facade_*`）で、アプリが夜の調子の材質を付ける
- 座標は x=東・y=北・z=シーンの地面からの高さ [m]。RealityKit は Z 上向きの USD を Y 上向きに直して読むことを確かめた
- 坂の上の建物が浮かないよう、壁の下端はシーンの地面（15m）まで伸ばす（箱と同じ扱い）。地面の写真は 0.3m 下に置く
- 中庭などの穴（内側の輪）は扱わず、屋根は埋まる
- ほかのシーンも、`City_<シーンID>.usdz` を足せばコードを直さずに実形状になる。無ければ今までどおり箱で描く

## 判定の箱との違い（2-08 に記録）

LOD2 の最も高い点は、判定の箱（`measuredHeight` と LOD1 から作った高さ）より **中央値 2.2m、最大 24m 高い**（屋上の塔屋・設備などが箱に入っていない）。1,260 棟で箱を超える部分があった。今回は見た目と判定が食い違わないよう、**3D の形を箱の高さで切りそろえた**。箱の高さを LOD2 に合わせるかは判定が変わるので、2-08 で別に決める。

## 出典・ライセンス

- 建物の形・外壁と屋上の写真: 東京都「3D都市モデル（Project PLATEAU）渋谷区（2025年度）」 https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025 を加工して作成。CC BY 4.0
- 地面の写真: 国土地理院「地理院タイル（全国最新写真（シームレス））」 https://maps.gsi.go.jp/development/ichiran.html を加工して作成
- 写真の無い屋上・壁: ambientCG「Concrete034」 https://ambientcg.com/a/Concrete034 （CC0）
- 写真の外側の地面: ambientCG「Asphalt031」 https://ambientcg.com/a/Asphalt031 （CC0）

地理院タイルは出典の明示が利用の条件なので、3D の凡例に「出典: PLATEAU（CC BY 4.0）・国土地理院」と出す。

## 確かめていないこと

- 実機での描画速度・メモリ・アプリの大きさ（3D ファイルは 22MB。シミュレータでは 3D が出るまで 1〜2 秒）
- 3D の向きが実物と合っているか（4-04）。写真と形・地面の写真は、見た目ではずれていない
- 西新宿・丸の内は PLATEAU 化していないので箱のまま（2-05）
