"""PLATEAU の建物データを、アプリが読む buildings.json の形に変換する（未実装のスタブ）。

今後の手順:
1. PLATEAU（東京都23区）の CityGML または 3D Tiles から、対象地点の周囲 500m ほどの建物を取り出す
2. 建物ごとに、平面形の外接長方形・計測高さ（measuredHeight）・用途（usage）を読む
3. シーン原点の緯度経度から、東・北方向の距離 [m] に変換する
4. Packages/StarCore/Sources/StarCore/Resources/buildings.json と同じ形で書き出す

現在の buildings.json は、PLATEAU を取り込む前の手作りの概略データ。
"""

import json
import math
import sys


def to_local(lat: float, lon: float, origin_lat: float, origin_lon: float) -> tuple[float, float]:
    """緯度経度をシーン原点からの (東, 北) [m] に変換する。アプリ側の CityScene.localPosition と同じ式。"""
    east = (lon - origin_lon) * 111_320.0 * math.cos(math.radians(origin_lat))
    north = (lat - origin_lat) * 110_574.0
    return east, north


def main() -> None:
    raise SystemExit("未実装: PLATEAU の読み込み処理をここに書く")


if __name__ == "__main__":
    main()
