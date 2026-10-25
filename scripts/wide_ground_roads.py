"""広域 3D の地面に、23 区すべての道路の明かりを足すための道路の下絵（マスク）を作る（task.md の o-9 の続き）。

PLATEAU の「交通（道路）モデル LOD1」のベクトルタイル（MVT）を区ごとに取り、道路の面を 1 枚の白黒の絵に塗る。
`wide_ground_detail.py` が、この絵を使って夜の地面に路面と街灯の明かりを足す。見た目専用で、判定には使わない。

取ったタイルは ../outputs/wide-road-tiles/（リポジトリの外）に置き、2 回目からは取り直さない。
出典: 国土交通省 Project PLATEAU（CC BY 4.0）
"""
from concurrent.futures import ThreadPoolExecutor
import json
import math
from pathlib import Path
import urllib.error
import urllib.request

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT.parent / 'outputs/wide-road-tiles'
CATALOG = 'https://api.plateauview.mlit.go.jp/datacatalog/plateau-datasets'
WARDS = [f'131{n:02d}' for n in range(1, 24)]
MIN_ZOOM, LEAF_ZOOM = 12, 15
# 道路の幅が 1 画素に満たなくても消えないよう、この倍率で塗ってから縮める
SUPERSAMPLE = 3


def fetch(url):
    """タイルを取る。無い（404）か空なら None。"""
    try:
        with urllib.request.urlopen(url, timeout=60) as response:
            return response.read() or None
    except urllib.error.HTTPError as error:
        if error.code in (403, 404):
            return None
        raise


def varint(data, i):
    value = shift = 0
    while True:
        byte = data[i]
        i += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, i
        shift += 7


def fields(data):
    """protobuf の 1 階層ぶんを (番号, 値) で返す（長さ付きは bytes、数は int）。"""
    i = 0
    while i < len(data):
        key, i = varint(data, i)
        number, kind = key >> 3, key & 7
        if kind == 0:
            value, i = varint(data, i)
        elif kind == 2:
            length, i = varint(data, i)
            value, i = data[i:i + length], i + length
        elif kind == 1:
            value, i = data[i:i + 8], i + 8
        elif kind == 5:
            value, i = data[i:i + 4], i + 4
        else:
            raise ValueError(f'知らない形式: {kind}')
        yield number, value


def unpack(data):
    values, i = [], 0
    while i < len(data):
        value, i = varint(data, i)
        values.append(value)
    return values


def polygons(tile):
    """MVT から、面（外周と穴）を [(外周の点の列, [穴の点の列])] で返す。点はタイル内の座標と、その範囲。"""
    result = []
    for number, layer in fields(tile):
        if number != 3:
            continue
        extent, features = 4096, []
        for n, value in fields(layer):
            if n == 5:
                extent = value
            elif n == 2:
                features.append(value)
        for feature in features:
            kind, geometry = 0, []
            for n, value in fields(feature):
                if n == 3:
                    kind = value
                elif n == 4:
                    geometry = unpack(value)
            if kind != 3:
                continue
            result.extend(rings(geometry))
    return result, extent


def rings(geometry):
    """ジオメトリの命令列から、外周ごとに穴をまとめて返す。"""
    x = y = i = 0
    ring, all_rings = [], []
    while i < len(geometry):
        command, count = geometry[i] & 7, geometry[i] >> 3
        i += 1
        if command == 7:
            if len(ring) >= 3:
                all_rings.append(ring)
            ring = []
            continue
        for _ in range(count):
            dx, dy = geometry[i], geometry[i + 1]
            i += 2
            x += (dx >> 1) ^ -(dx & 1)
            y += (dy >> 1) ^ -(dy & 1)
            if command == 1:
                ring = []
            ring.append((x, y))
    grouped = []
    for ring in all_rings:
        # 面積の符号で外周（正）と穴（負）を分ける。穴は直前の外周に付ける
        area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(ring, ring[1:] + ring[:1]))
        if area >= 0 or not grouped:
            grouped.append((ring, []))
        else:
            grouped[-1][1].append(ring)
    return grouped


def tile_latlon(z, x, y, px, py, extent):
    n = 2 ** z
    longitude = (x + px / extent) / n * 360 - 180
    latitude = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * (y + py / extent) / n))))
    return latitude, longitude


def ward_urls():
    datasets = json.loads(urllib.request.urlopen(CATALOG, timeout=120).read())['datasets']
    urls = {d['city_code']: d['url'] for d in datasets if d.get('id', '').endswith('_tran_lod1') and d.get('format') == 'MVT'}
    return {code: urls[code] for code in WARDS if code in urls}


def cached_tile(code, url, z, x, y):
    path = CACHE / code / f'{z}_{x}_{y}.mvt'
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(fetch(url.format(z=z, x=x, y=y)) or b'')
    return path.read_bytes() or None


def ward_leaf_tiles(code, url, box):
    """区の道路タイル（LEAF_ZOOM）を、上のズームから中身のある所だけたどって集める。box は緯度経度の範囲。"""
    south, west, north, east = box

    def span(z):
        n = 2 ** z
        def tx(lon): return int((lon + 180) / 360 * n)
        def ty(lat): return int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n)
        return range(tx(west), tx(east) + 1), range(ty(north), ty(south) + 1)

    xs, ys = span(MIN_ZOOM)
    frontier = [(MIN_ZOOM, x, y) for x in xs for y in ys]
    leaves = []
    with ThreadPoolExecutor(8) as pool:
        for z in range(MIN_ZOOM, LEAF_ZOOM + 1):
            found = list(pool.map(lambda t: (t, cached_tile(code, url, *t)), frontier))
            present = [t for t, data in found if data]
            if z == LEAF_ZOOM:
                leaves = [(t, data) for t, data in found if data]
            else:
                frontier = [(z + 1, 2 * x + dx, 2 * y + dy) for _, x, y in present for dx in (0, 1) for dy in (0, 1)]
    return leaves


def road_masks(regions, to_local, pixels):
    """regions: [(west, east, south, north) [m]] ごとに道路の白黒の絵（0〜1、上が北）を返す。

    to_local(latitude, longitude) は中心からの (東, 北) [m] を返す関数。
    """
    size = pixels * SUPERSAMPLE
    images = [Image.new('L', (size, size), 0) for _ in regions]
    draws = [ImageDraw.Draw(image) for image in images]
    # 区の範囲は、全地域の外接矩形を緯度経度に直さず、広めの 40 km 四方で取る
    box = (35.40, 139.45, 35.95, 140.05)
    count = 0
    for code, url in ward_urls().items():
        for (z, x, y), data in ward_leaf_tiles(code, url, box):
            shapes, extent = polygons(data)
            for outer, holes in shapes:
                for ring, fill in [(outer, 255)] + [(h, 0) for h in holes]:
                    points = [to_local(*tile_latlon(z, x, y, px, py, extent)) for px, py in ring]
                    for (west, east, south, north), draw in zip(regions, draws):
                        xs = [p[0] for p in points]
                        ys = [p[1] for p in points]
                        if max(xs) < west or min(xs) > east or max(ys) < south or min(ys) > north:
                            continue
                        scale = size / (east - west)
                        draw.polygon([((e - west) * scale, (north - n) * scale) for e, n in points], fill=fill)
                    count += 1
        print(code, '道路の面の累計', count, flush=True)
    return [np.asarray(image.resize((pixels, pixels), Image.BOX), dtype=np.float32) / 255 for image in images]
