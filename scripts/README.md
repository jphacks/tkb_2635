# scripts

前処理のスクリプト（Python）。使い方は各ファイルの先頭の説明を見る。

## 追加で入れたもの

| 何に使う | 入れたもの | 入れた場所 |
|---|---|---|
| `vnl_crop.py`（EOG の VIIRS 夜間光 GeoTIFF から東京周辺を切り出す） | `tifffile`・`imagecodecs`・`numpy`（pip） | リポジトリの外の作業用環境 `../outputs/vnl/venv`（`python3 -m venv ../outputs/vnl/venv && ../outputs/vnl/venv/bin/pip install tifffile imagecodecs numpy`） |
| 3D・遠くの地面の画像の合成（`blender_city_usdz.py`・`far_ground_blender.py`） | Blender 4.0.2（numpy 入り） | `/Applications/Blender.app` |

VNL の元データ（約 11.6GB に展開される）と切り出した `tokyo.npy` はリポジトリに入れない（`../outputs/vnl/`）。
