# 4-08 PLATEAU の実形状で 3D を描く

渋谷の 3D を、外接直方体（建物をすっぽり包む箱）から、PLATEAU の LOD2（屋根・壁の形まであるデータ）の実際の形に替えた。**見た目だけの変更**で、位置・寸法・地平線・遮蔽判定・スコアは今までどおり `buildings.json` の箱で計算する。

| SHIBUYA SKY（見える） | 屋上の展望デッキ | 渋谷駅東口 地上（隠れる） |
|---|---|---|
| ![](shibuya-sky.png) | ![](shibuya-sky-deck.png) | ![](ground-blocked.png) |

2026-10-24 21:00 の月。iPhone 17 Pro シミュレータで撮影。

## 何が変わったか

- 1,497 棟を実形状で描く（LOD2 が 1,434 棟、LOD2 が無い 63 棟は LOD1 の柱状）。屋上の段差・塔屋・設備（BuildingInstallation）も入る
- 壁は 8-06 の夜景の窓（用途ごと 4 種 × 4 模様）をそのまま使う。屋上と地面は CC0 の PBR テクスチャ
- 月が建物に隠れるとき、**h(A) を決めている建物の判定用の箱を赤い枠**で示す。実際の形は箱より細いので、枠が無いと「線が建物の脇を抜けて見えるのに判定は遮られる」ことが起こりうるため
- 観測者の床が建物の屋根より高い地点（SHIBUYA SKY）に、屋上の展望デッキ（足元灯・ガラスの柵）を出す。形はイメージで、計算には使わない
- 1,497 個あった建物の部品を 18 個にまとめたので、描画の負担が減る（実機では未計測）

## 作り方

```bash
# 1. 原本を取得（約360MB、リポジトリの外に置く）
python3 scripts/download_plateau.py --output ../outputs/plateau-shibuya-2025

# 2. LOD2 の面を取り出す（buildings.json の 1,497 棟だけ。箱の高さで切りそろえる）
python3 scripts/plateau_shapes.py ../outputs/plateau-shibuya-2025/*_bldg_6697_op.gml \
  --buildings Packages/StarCore/Sources/StarCore/Resources/buildings.json \
  --scene-id shibuya --host-id bldg_7b006717-e9e6-4a94-8843-1f4ce13b2509 \
  --output ../outputs/plateau-shibuya-2025/shibuya-shapes.json

# 3. Blender（4.0.2 で確認）で USDZ にする
/Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender_city_usdz.py -- \
  ../outputs/plateau-shibuya-2025/shibuya-shapes.json App/Resources/City/City_shibuya.usdz
```

- USDZ には形と UV（テクスチャの貼り方）だけを入れ、材質はアプリが部品の名前（`facade_<種類>_<模様>`・`roof`・建物 ID）で付ける
- 座標は x=東・y=北・z=シーンの地面からの高さ [m]。RealityKit は Z 上向きの USD を Y 上向きに直して読むことを確かめた
- 坂の上の建物が浮かないよう、壁の下端はシーンの地面（15m）まで伸ばす（箱と同じ扱い）
- 中庭などの穴（内側の輪。原本1区画のファイル全体で114件）は扱わず、屋根は埋まる
- ほかのシーンも、`City_<シーンID>.usdz` を足せばコードを直さずに実形状になる。無ければ今までどおり箱で描く

## 判定の箱との違い（2-08 に記録）

LOD2 の最も高い点は、判定の箱（`measuredHeight` と LOD1 から作った高さ）より **中央値 2.2m、最大 24m 高い**（屋上の塔屋・設備などが箱に入っていない）。1,260 棟で箱を超える部分があった。今回は見た目と判定が食い違わないよう、**3D の形を箱の高さで切りそろえた**。箱の高さを LOD2 に合わせるかは判定が変わるので、2-08 で別に決める。

## 出典・ライセンス

- 建物の形: 東京都「3D都市モデル（Project PLATEAU）渋谷区（2025年度）」 https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025 を加工して作成。CC BY 4.0
- 屋上: ambientCG「Concrete034」 https://ambientcg.com/a/Concrete034 （CC0）
- 地面: ambientCG「Asphalt031」 https://ambientcg.com/a/Asphalt031 （CC0）
- テクスチャは 1K の JPG を 512px に縮小し、色・法線（OpenGL 形式）・粗さの 3 枚を `App/Resources/City/` に置いた

## 確かめていないこと

- 実機での描画速度・メモリ（シミュレータでは 3D が出るまで 1〜2 秒かかる）
- 3D の向きが実物と合っているか（4-04）
- 西新宿・丸の内は PLATEAU 化していないので箱のまま（2-05）
