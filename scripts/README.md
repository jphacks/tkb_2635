# scripts

前処理のスクリプト（Python）。使い方は各ファイルの先頭の説明を見る。

## 追加で入れたもの

| 何に使う | 入れたもの | 入れた場所 |
|---|---|---|
| `vnl_crop.py`（EOG の VIIRS 夜間光 GeoTIFF から東京周辺を切り出す） | `tifffile`・`imagecodecs`・`numpy`（pip） | リポジトリの外の作業用環境 `../outputs/vnl/venv`（`python3 -m venv ../outputs/vnl/venv && ../outputs/vnl/venv/bin/pip install tifffile imagecodecs numpy`） |
| 3D・遠くの地面の画像の合成（`blender_city_usdz.py`・`far_ground_blender.py`・`wide_ward_blender.py`） | Blender 4.0.2（numpy 入り） | `/Applications/Blender.app` |

VNL の元データ（約 11.6GB に展開される）と切り出した `tokyo.npy` はリポジトリに入れない（`../outputs/vnl/`）。

## 区の広域 3D を作る（`build_wide_ward.py`、task.md の o）

PLATEAU の LOD1（建物の箱）3D Tiles を区ごとに取り、建物を向き付きの箱 1 つずつにして `App/Resources/Wide/Wide_<区コード>.usdz` を作る。1 区 約 35 秒、約 5MB（建物は大きい・高い順に 15,000 棟まで。`wide_ward_blender.py` の `MAX_BUILDINGS`）。

```bash
python3 scripts/build_wide_ward.py 13104      # 新宿区。区コードは 13101〜13123（task.md の o-2〜o-4 の割り当て）
xcodegen generate                              # USDZ を足したので、生成された StarSpot.xcodeproj もコミットする
```

- 取ったデータ（1 区 約 370MB）は `../outputs/wide-<区コード>/`（リポジトリの外）。`--steps build,install` で取り直さずに作り直せる
- 原点は渋谷の原点（35.658, 139.7016）。高さはジオイド高 36.7m を引いた標高。区どうしは同じ原点なので、並べるだけでつながる
- `StarSpot.xcodeproj` は区ごとの PR でぶつかりやすい。衝突したら `xcodegen generate` で作り直す
- **o-9 の再生成（窓明かりの UV を付け直す）は 1 区 1 コマンド**: `python3 scripts/build_wide_ward.py <区コード> --steps build,install`（取得済みの `../outputs/wide-<区コード>` から作る。worktree ではなく元の作業コピーで動かす）。終わったら `xcodegen generate`
- 箱の側面には窓明かりの UV（横 32m・縦 28m で 1 枚、屋根は窓の無い 1 点）が付く（o-9）。窓明かりの画像は `python3 scripts/wide_windows_texture.py` で `App/Resources/Wide/WideWindows.png` を作る。UV 付きにすると 1 区 約 7.5MB（UV なしは約 5MB）。UV の無い古い区も、アプリでは外壁の色だけで表示される
