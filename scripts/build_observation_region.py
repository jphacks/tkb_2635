#!/usr/bin/env python3
"""既存の建物シーンに、現在地観測の範囲とオフライン用の標高格子を付ける。

python3 scripts/build_observation_region.py --scene shibuya --name 渋谷駅周辺 \
  --sample-latitude 35.658 --sample-longitude 139.702816 \
  --cache /private/tmp/astera-observation-dem \
  --output Packages/StarCore/Sources/StarCore/Resources/observation-regions.json

標高原本は地理院の DEM1A（地面、ズーム17）と DEM10B（遠方地形、ズーム14）。
対象地域の外まで地形を調べるため、地面用20m格子と広域地形用50m格子を分ける。
"""
import argparse
from datetime import date
import hashlib
import json
import math
from pathlib import Path
import time
import urllib.request

from PIL import Image
from terrain_horizon import tile_pixel, REQUEST_TIMEOUT, USER_AGENT

ROOT = Path(__file__).resolve().parents[1]
BUILDINGS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/buildings.json"


def decode_height(pixel):
    value = pixel[0] * 65536 + pixel[1] * 256 + pixel[2]
    if value == 8388608:
        return None
    return (value if value < 8388608 else value - 16777216) * 0.01


class ElevationTiles:
    """更新が続く PNG 標高タイルを読む。無い値は補わず、原本のハッシュを残す。"""
    def __init__(self, directory, layer, zoom):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.tiles = {}
        self.sources = []
        self.layer = layer
        self.zoom = zoom

    def elevation(self, latitude, longitude):
        tx, ty, col, row = tile_pixel(latitude, longitude, zoom=self.zoom)
        key = (tx, ty)
        if key not in self.tiles:
            path = self.directory / f"{self.layer}_{self.zoom}_{tx}_{ty}.png"
            url = f"https://cyberjapandata.gsi.go.jp/xyz/{self.layer}/{self.zoom}/{tx}/{ty}.png"
            if not path.exists():
                request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
                with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
                    path.write_bytes(response.read())
                time.sleep(1)
            with Image.open(path) as image:
                if image.size != (256, 256):
                    raise ValueError("標高タイルは256×256である必要があります")
                self.tiles[key] = image.convert("RGB").copy()
            self.sources.append(dict(url=url, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        return decode_height(self.tiles[key].getpixel((col, row)))


def make_grid(scene, half_width, step, cache):
    count = round(half_width * 2 / step) + 1
    values = []
    meters_per_lon = 111_320.0 * math.cos(math.radians(scene["originLatitude"]))
    for row in range(count):
        lat = scene["originLatitude"] + (-half_width + row * step) / 110_574.0
        for col in range(count):
            lon = scene["originLongitude"] + (-half_width + col * step) / meters_per_lon
            height = cache.elevation(lat, lon)
            values.append(None if height is None else round(height, 2))
    return dict(minEast=-half_width, minNorth=-half_width, step=step,
                columns=count, rows=count, values=values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--sample-latitude", required=True, type=float)
    parser.add_argument("--sample-longitude", required=True, type=float)
    parser.add_argument("--radius", type=float, default=200)
    parser.add_argument("--building-radius", type=float, default=500)
    parser.add_argument("--cache", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    scene = next(s for s in json.loads(BUILDINGS.read_text()) if s["id"] == args.scene)
    surface = ElevationTiles(args.cache, "dem1a_png", 17)
    terrain = ElevationTiles(args.cache, "dem_png", 14)
    region = dict(
        id=args.scene + "-station", name=args.name, sceneId=args.scene,
        latitude=scene["originLatitude"], longitude=scene["originLongitude"],
        selectionRadius=args.radius, buildingRadius=args.building_radius,
        elevationSource="国土地理院 標高タイル（地面 DEM1A・20m格子、地形 DEM10B・50m格子）",
        elevationSourceURL="https://maps.gsi.go.jp/development/demtile.html",
        generatedAt=date.today().isoformat(),
        surface=make_grid(scene, args.radius + 40, 20, surface),
        terrain=make_grid(scene, args.radius + 3_100, 50, terrain),
        sampleLatitude=args.sample_latitude, sampleLongitude=args.sample_longitude,
    )
    region["sourceTiles"] = surface.sources + terrain.sources
    regions = json.loads(args.output.read_text()) if args.output.exists() else []
    regions = [r for r in regions if r["id"] != region["id"]] + [region]
    args.output.write_text(json.dumps(regions, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(f"{region['name']}: {args.output.stat().st_size:,} bytes; "
          f"surface missing={region['surface']['values'].count(None)}, "
          f"terrain missing={region['terrain']['values'].count(None)}")


if __name__ == "__main__":
    main()
