"""広域 3D の地面（夜の航空写真）を細かくする（task.md の o-9 の続き）。

いまの地面 `far_hibiya_park.jpg`（日比谷を中心に東西南北 20 km、2048 画素 ≒ 20 m/画素）は、夜の暗さと
衛星の夜間光が焼き込んであるが、近づくとぼやける。夜間光の元データ（far_ground.py が使う VIIRS）が無くても作れるよう、
地理院タイルの航空写真（ズーム 14 ≒ 8 m/画素）から細かい明暗（道路の筋・川・建物の影）だけを取り出し、
いまの夜の画像に掛け合わせる。全体の明るさと色はいまの画像のまま、細かさだけが上がる。

    python3 scripts/wide_ground_detail.py      # App/Resources/Wide/WideGround_<行>_<列>.jpg（2×2 枚）と WideGround.json を作る（Pillow・numpy が要る）

取ったタイルは ../outputs/wide-ground-tiles/（リポジトリの外）に置き、2 回目からは取り直さない。
出典: 国土地理院「地理院タイル（全国最新写真（シームレス））」、Earth Observation Group（VIIRS 夜間光、CC BY 4.0）
"""
from concurrent.futures import ThreadPoolExecutor
import io
import json
import math
from pathlib import Path
import urllib.error
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

from wide_ground_roads import road_masks

ROOT = Path(__file__).resolve().parents[1]
SOURCE_IMAGE = ROOT / 'App/Resources/Far/far_hibiya_park.jpg'
OUTPUT = ROOT / 'App/Resources/Wide'
CACHE = ROOT.parent / 'outputs/wide-ground-tiles'
PHOTO_URL = 'https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg'
# far_hibiya_park.jpg の中心と範囲（far_hibiya_park.json・buildings.json の hibiya_park と同じ）
CENTER_LATITUDE = 35.6732
CENTER_LONGITUDE = 139.7562
HALF = 20_000.0
# 縦横に何枚に分けるか、1 枚の画素数（20 km / 2560 ≒ 7.8 m/画素）、地理院タイルのズーム
SPLIT = 2
PIXELS = 2560
ZOOM = 14
# 細かい明暗を掛ける強さと、掛ける比の範囲（暗い所が真っ黒・明るい所が白飛びしないように）
DETAIL_STRENGTH = 1.0
DETAIL_RANGE = (0.3, 3.0)
QUALITY = 80
# 道路（PLATEAU の道路モデル）の明かり: 路面に足す暖色の光の強さ（0〜255 の明るさ）
ROAD_GLOW = 46.0
ROAD_COLOR = np.array([1.0, 0.72, 0.42], dtype=np.float32)
# 写真の無いタイル（海など）の明るさ
NO_PHOTO = 40
SOURCE = ('国土地理院「地理院タイル（全国最新写真（シームレス））」・Earth Observation Group, Payne Institute for Public Policy, '
          'Colorado School of Mines（VIIRS Nighttime Lights V2.2、CC BY 4.0）・国土交通省 Project PLATEAU（交通（道路）モデル、CC BY 4.0）を加工して作成')


def latlon(east, north):
    """日比谷の中心からの東・北 [m] → 緯度経度（StarCore の localPosition の逆）"""
    return (CENTER_LATITUDE + north / 110_574.0,
            CENTER_LONGITUDE + east / (111_320.0 * math.cos(math.radians(CENTER_LATITUDE))))


def world_pixel(latitude, longitude):
    n = 256 * 2 ** ZOOM
    x = (longitude + 180) / 360 * n
    y = (1 - math.log(math.tan(math.radians(latitude)) + 1 / math.cos(math.radians(latitude))) / math.pi) / 2 * n
    return x, y


def tile(x, y):
    path = CACHE / f'{ZOOM}/{x}/{y}.jpg'
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            data = urllib.request.urlopen(PHOTO_URL.format(z=ZOOM, x=x, y=y), timeout=60).read()
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            data = b''    # 海の上など写真の無いタイル。空のファイルで「無い」ことを覚えておく
        path.write_bytes(data)
    data = path.read_bytes()
    if not data:
        # 写真が無い所は一様な明るさにして、細かい明暗を足さない
        return Image.new('L', (256, 256), NO_PHOTO)
    return Image.open(io.BytesIO(data)).convert('L')


def photo(west, east, south, north):
    """範囲の航空写真の明るさ（PIXELS × PIXELS、上が北）"""
    lat0, lon0 = latlon(west, north)
    lat1, lon1 = latlon(east, south)
    x0, y0 = world_pixel(lat0, lon0)
    x1, y1 = world_pixel(lat1, lon1)
    tx = range(int(x0 // 256), int(x1 // 256) + 1)
    ty = range(int(y0 // 256), int(y1 // 256) + 1)
    with ThreadPoolExecutor(8) as pool:
        tiles = dict(zip([(x, y) for x in tx for y in ty], pool.map(lambda p: tile(*p), [(x, y) for x in tx for y in ty])))
    mosaic = Image.new('L', (len(tx) * 256, len(ty) * 256))
    for (x, y), image in tiles.items():
        mosaic.paste(image, ((x - tx.start) * 256, (y - ty.start) * 256))
    box = (x0 - tx.start * 256, y0 - ty.start * 256, x1 - tx.start * 256, y1 - ty.start * 256)
    return mosaic.resize((PIXELS, PIXELS), Image.LANCZOS, box=box)


def to_local(latitude, longitude):
    """緯度経度 → 日比谷の中心からの (東, 北) [m]（latlon の逆）"""
    return ((longitude - CENTER_LONGITUDE) * 111_320.0 * math.cos(math.radians(CENTER_LATITUDE)),
            (latitude - CENTER_LATITUDE) * 110_574.0)


def main():
    night = Image.open(SOURCE_IMAGE).convert('RGB')
    size = night.width
    part = 2 * HALF / SPLIT
    tiles = []
    regions = [(-HALF + c * part, -HALF + (c + 1) * part, HALF - (r + 1) * part, HALF - r * part)
               for r in range(SPLIT) for c in range(SPLIT)]
    roads = iter(road_masks(regions, to_local, PIXELS))
    for row in range(SPLIT):
        for column in range(SPLIT):
            west, north = -HALF + column * part, HALF - row * part
            east, south = west + part, north - part
            # いまの夜の画像の、この区画（上が北）を拡大する
            box = tuple(v * size / (2 * HALF) for v in (west + HALF, HALF - north, east + HALF, HALF - south))
            base = np.asarray(night.resize((PIXELS, PIXELS), Image.BICUBIC, box=box), dtype=np.float32)
            light = np.asarray(photo(west, east, south, north), dtype=np.float32) + 8
            # 夜の画像と同じくらいの粗さにぼかした明るさで割り、細かい明暗だけを取り出す
            blur = size / (2 * HALF) * part
            coarse = np.asarray(Image.fromarray(light.astype(np.uint8)).resize((int(blur), int(blur)), Image.BOX)
                                .resize((PIXELS, PIXELS), Image.BICUBIC), dtype=np.float32) + 8
            detail = np.clip(light / coarse, *DETAIL_RANGE) ** DETAIL_STRENGTH
            lit = base * detail[:, :, None]
            # 写真に写らない細い道も含め、PLATEAU の道路の面に暖色の光を足す
            lit += next(roads)[:, :, None] * ROAD_GLOW * ROAD_COLOR
            out = np.clip(lit, 0, 255).astype(np.uint8)
            name = f'WideGround_{row}_{column}'
            Image.fromarray(out).save(OUTPUT / f'{name}.jpg', quality=QUALITY)
            center = latlon((west + east) / 2, (north + south) / 2)
            tiles.append({'file': name, 'centerLatitude': round(center[0], 6), 'centerLongitude': round(center[1], 6),
                          'meters': part})
            print(name, (OUTPUT / f'{name}.jpg').stat().st_size // 1000, 'KB')
    info = {'tiles': tiles, 'source': SOURCE,
            'note': 'far_hibiya_park.jpg（far_ground.py）に地理院タイル（ズーム 14）の細かい明暗を掛け、PLATEAU 道路モデルの明かりを足して作った（scripts/wide_ground_detail.py）'}
    (OUTPUT / 'WideGround.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
