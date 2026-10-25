#!/usr/bin/env python3
"""地理院の標高タイルから、地点ごとの地形の地平線（方位 1° ごと）を作る（task.md の 2-07）。

  python3 scripts/terrain_horizon.py --cache ../outputs/dem          # 確認だけ（地点ごとの最大仰角を表示）
  python3 scripts/terrain_horizon.py --cache ../outputs/dem --write  # terrain.json を書き出す

地点のまわり 3 km を、方位 1° × 距離 100 m 刻みで標高タイル（DEM10B、ズーム 14）から読み、方位ごとに
「目から見て最も高く見える地形の点」の実効標高（地球の丸みと大気差を引いた値）と距離を記録する。
アプリは目の標高から仰角を計算し直すので、床面標高を直しても作り直さずに済む（ずれるのは最も高く見える点の選び方だけ）。
取ったタイルは --cache（リポジトリの外）に置く。
"""

import argparse
import json
import math
import sys
import time
import urllib.error
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPOTS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/spots.json"
OUTPUT = ROOT / "Packages/StarCore/Sources/StarCore/Resources/terrain.json"

TILE_URL = "https://cyberjapandata.gsi.go.jp/xyz/dem/{z}/{x}/{y}.txt"
SOURCE = "国土地理院 標高タイル（DEM10B、ズーム14）"
ZOOM = 14
TILE_SIZE = 256
RADIUS = 3000.0           # 調べる半径 [m]
STEP = 100.0              # 距離の刻み [m]
AZIMUTHS = 360
EARTH_RADIUS = 6_371_000.0
REFRACTION = 0.13         # 大気差の係数（測量で使う標準値）
REQUEST_INTERVAL = 1.0    # タイルを取る間隔 [s]
REQUEST_TIMEOUT = 20.0
NO_DATA = "e"
HEIGHT_DIGITS = 1
USER_AGENT = "Astera-JPHACKS2026 (https://github.com/jphacks/tkb_2635)"


def tile_pixel(latitude, longitude, zoom=ZOOM):
    """緯度経度 → (タイル x, タイル y, タイル内の列, タイル内の行)。Web メルカトル。"""
    n = 2 ** zoom
    fx = (longitude + 180.0) / 360.0 * n
    lat = math.radians(latitude)
    fy = (1.0 - math.log(math.tan(lat) + 1.0 / math.cos(lat)) / math.pi) / 2.0 * n
    tx, ty = int(fx), int(fy)
    col = min(int((fx - tx) * TILE_SIZE), TILE_SIZE - 1)
    row = min(int((fy - ty) * TILE_SIZE), TILE_SIZE - 1)
    return tx, ty, col, row


def parse_tile(text):
    """標高タイルの CSV（256 行 × 256 列、欠損は "e"）を、行ごとの数値（欠損は None）にする。"""
    rows = []
    for line in text.strip().splitlines():
        rows.append([None if value.strip() == NO_DATA else float(value) for value in line.split(",")])
    if len(rows) != TILE_SIZE or any(len(row) != TILE_SIZE for row in rows):
        raise ValueError("標高タイルが 256×256 でない")
    return rows


def offset(latitude, longitude, azimuth_deg, distance):
    """方位（北=0°、時計回り）と距離 [m] だけ動かした緯度経度（近距離なので平面で近似）。"""
    a = math.radians(azimuth_deg)
    dlat = distance * math.cos(a) / 110_574.0
    dlon = distance * math.sin(a) / (111_320.0 * math.cos(math.radians(latitude)))
    return latitude + dlat, longitude + dlon


def drop(distance):
    """地球の丸みと大気差で、遠くの地面が見かけ上下がる量 [m]。"""
    return (1.0 - REFRACTION) * distance ** 2 / (2.0 * EARTH_RADIUS)


def horizon(latitude, longitude, eye_elevation, elevation_at):
    """方位ごとに、目から最も高く見える地形の点の [実効標高 m, 距離 m]。地形が無い方位は None。"""
    samples = []
    steps = int(RADIUS / STEP)
    for azimuth in range(AZIMUTHS):
        best = None
        for k in range(1, steps + 1):
            distance = k * STEP
            height = elevation_at(*offset(latitude, longitude, azimuth, distance))
            if height is None:
                continue
            effective = height - drop(distance)
            angle = math.atan2(effective - eye_elevation, distance)
            if best is None or angle > best[0]:
                best = (angle, effective, distance)
        samples.append(None if best is None else [round(best[1], HEIGHT_DIGITS), best[2]])
    return samples


def max_angle(samples, eye_elevation):
    angles = [math.degrees(math.atan2(h - eye_elevation, d)) for h, d in (s for s in samples if s)]
    return max(angles) if angles else None


class TileCache:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.tiles = {}
        self.last_request = 0.0

    def tile(self, tx, ty):
        key = (tx, ty)
        if key not in self.tiles:
            path = self.directory / f"{ZOOM}_{tx}_{ty}.txt"
            if not path.exists():
                wait = REQUEST_INTERVAL - (time.monotonic() - self.last_request)
                if wait > 0:
                    time.sleep(wait)
                url = TILE_URL.format(z=ZOOM, x=tx, y=ty)
                request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                try:
                    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
                        path.write_bytes(response.read())
                except urllib.error.HTTPError as error:
                    if error.code != 404:  # 404 は海などでタイルが無い。欠損として扱う
                        raise
                    path.write_text("")
                self.last_request = time.monotonic()
            text = path.read_text()
            self.tiles[key] = parse_tile(text) if text.strip() else None
        return self.tiles[key]

    def elevation(self, latitude, longitude):
        tx, ty, col, row = tile_pixel(latitude, longitude)
        tile = self.tile(tx, ty)
        return None if tile is None else tile[row][col]


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--cache", required=True, help="標高タイルを置くフォルダ（リポジトリの外）")
    parser.add_argument("--write", action="store_true", help="terrain.json を書き出す")
    args = parser.parse_args()

    spots = json.loads(SPOTS.read_text(encoding="utf-8"))
    cache = TileCache(args.cache)
    result = {}
    for spot in spots:
        eye = spot["floorElevation"] + spot["eyeHeight"]
        samples = horizon(spot["latitude"], spot["longitude"], eye, cache.elevation)
        result[spot["id"]] = samples
        angle = max_angle(samples, eye)
        print(f"{spot['id']:28} 目 {eye:7.1f}m  地形の最大仰角 {angle if angle is None else round(angle, 2)}°",
              file=sys.stderr)
    if args.write:
        document = {"source": SOURCE, "generatedAt": date.today().isoformat(), "radius": RADIUS, "step": STEP,
                    "refraction": REFRACTION, "spots": result}
        OUTPUT.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"書き出した: {OUTPUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
