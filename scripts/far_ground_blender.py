"""far_ground.py から Blender の Python で呼ばれ、遠くの地面の画像を合成する（4-11）。

    Blender -b --python scripts/far_ground_blender.py -- <作業内容の JSON>

座標の決まりは far_ground.py と同じ（画像の上が北、中心がシーンの原点、1辺 2 × radius [m]）。
"""
import json
import math
from pathlib import Path
import sys

import bpy
import numpy as np

# 夜の地面: 写真の明るさに掛ける色（blender_city_usdz.py の GROUND_NIGHT より暗くして、近くの地面と区別する）
FAR_NIGHT = np.array([0.20, 0.23, 0.33], dtype=np.float32) * 0.55
# 街明かりの色（blender_city_usdz.py の far_lights と同じ暖色）
LIGHT_COLOR = np.array([0.95, 0.70, 0.42], dtype=np.float32)
# 街のぼんやりした明るさと、明かりの点の強さ
GLOW_GAIN, POINT_GAIN = 0.22, 0.95
DARK, BRIGHT = 2.0, 300.0
# 明かりの点の数の上限（画素のうち点になる割合）
POINT_DENSITY = 0.20
# 夜間光（VNL、nW/cm²/sr）を対数で「街の度合い」（0〜1）にする。東京は湾の数から都心の数百まで幅があるので、
# 対数にすると上限に張り付かずに明暗の差が残る。DARK 以下は明かりなし、BRIGHT 以上は最も明るい街とみなす。
# 明かりの点の置き場所は航空写真から決める（屋根・道路は明るく、緑と水は暗い）。
# 地平線の色（Sky3DView の背景と同じ）
HORIZON = np.array([0.02, 0.03, 0.10], dtype=np.float32)


def load(path):
    """画像を (高さ, 幅, 3) の配列で読む。行は上から下。読めなければ None。"""
    if not path.exists():
        return None
    image = bpy.data.images.load(str(path), check_existing=False)
    w, h = image.size
    pixels = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(pixels)
    bpy.data.images.remove(image)
    return pixels.reshape(h, w, 4)[::-1, :, :3]


def mosaic(layer):
    x0, y0, x1, y1 = layer['bounds']
    folder = Path(layer['folder']) / str(layer['zoom'])
    canvas = np.zeros(((y1 - y0 + 1) * 256, (x1 - x0 + 1) * 256, 3), dtype=np.float32)
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            tile = load(folder / str(x) / f'{y}.jpg') if layer['zoom'] > 8 else load(folder / str(x) / f'{y}.png')
            if tile is not None and tile.shape[:2] == (256, 256):
                canvas[(y - y0) * 256:(y - y0 + 1) * 256, (x - x0) * 256:(x - x0 + 1) * 256] = tile
    return canvas


def sample(canvas, layer, lat, lon):
    """緯度経度の配列の位置の色を、モザイクから双線形で取り出す。"""
    n = 256 * 2 ** layer['zoom']
    px = (lon + 180) / 360 * n - layer['bounds'][0] * 256 - 0.5
    py = (1 - np.arcsinh(np.tan(np.radians(lat))) / math.pi) / 2 * n - layer['bounds'][1] * 256 - 0.5
    h, w = canvas.shape[:2]
    px, py = np.clip(px, 0, w - 1.001), np.clip(py, 0, h - 1.001)
    x0, y0 = px.astype(np.int32), py.astype(np.int32)
    fx, fy = (px - x0)[..., None], (py - y0)[..., None]
    top = canvas[y0, x0] * (1 - fx) + canvas[y0, x0 + 1] * fx
    bottom = canvas[y0 + 1, x0] * (1 - fx) + canvas[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bottom * fy


def radiance(layer, lat, lon):
    """切り出した VNL（経緯度の格子、行 0 が北の端）から、緯度経度の配列の位置の値を双線形で取り出す。"""
    grid = np.load(layer['array'])
    info = json.loads(Path(layer['info']).read_text())
    px = np.clip((lon - info['west']) / info['step'] - 0.5, 0, grid.shape[1] - 1.001)
    py = np.clip((info['north'] - lat) / info['step'] - 0.5, 0, grid.shape[0] - 1.001)
    x0, y0 = px.astype(np.int32), py.astype(np.int32)
    fx, fy = px - x0, py - y0
    top = grid[y0, x0] * (1 - fx) + grid[y0, x0 + 1] * fx
    bottom = grid[y0 + 1, x0] * (1 - fx) + grid[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bottom * fy


def city_level(value):
    """放射輝度 [nW/cm²/sr] を、対数で 0（DARK 以下）〜1（BRIGHT 以上）にする。"""
    level = (np.log10(1 + np.maximum(value, 0)) - math.log10(1 + DARK)) / (math.log10(1 + BRIGHT) - math.log10(1 + DARK))
    return np.clip(level, 0, 1).astype(np.float32)


def main():
    job = json.loads(Path(sys.argv[sys.argv.index('--') + 1]).read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    n, radius = job['pixels'], job['radius']
    # 画素の中心の位置（東・北 [m]）。行 0 が北の端
    axis = (np.arange(n, dtype=np.float64) + 0.5) / n * 2 * radius - radius
    east, north = np.meshgrid(axis, -axis)
    lat0, lon0 = job['latitude'], job['longitude']
    lat = lat0 + north / 110_574.0
    lon = lon0 + east / (111_320.0 * math.cos(math.radians(lat0)))

    photo = sample(mosaic(job['photo']), job['photo'], lat, lon)
    city = city_level(radiance(job['lights'], lat, lon))
    luma = photo @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    green = np.clip((photo[..., 1] - (photo[..., 0] + photo[..., 2]) / 2) * 6, 0, 1)
    built = np.clip((luma - 0.22) / 0.35, 0, 1) * (1 - green)
    # 2 乗して、都心（明るい所）は濃く、郊外は薄くする
    density = city ** 2 * built
    # 毎回同じ模様になるよう、乱数の種はシーンの原点から決める
    seed = int(abs(lat0 * 1e4) + abs(lon0 * 1e4)) % (2 ** 32)
    points = (np.random.default_rng(seed).random(density.shape) < density * POINT_DENSITY).astype(np.float32)
    # 近くで拡大されると四角いブロックに見えるので、点を少しにじませて丸い光にする
    soft = points * 0.5
    for dy, dx, w in ((-1, 0, 0.125), (1, 0, 0.125), (0, -1, 0.125), (0, 1, 0.125),
                      (-1, -1, 0.0625), (-1, 1, 0.0625), (1, -1, 0.0625), (1, 1, 0.0625)):
        soft += np.roll(np.roll(points, dy, axis=0), dx, axis=1) * w
    color = (photo * FAR_NIGHT + (density * GLOW_GAIN)[..., None] * LIGHT_COLOR
             + (soft * POINT_GAIN)[..., None] * LIGHT_COLOR)

    distance = np.hypot(east, north)
    t = np.clip((distance - job['fadeStart']) / (radius - job['fadeStart']), 0, 1)
    t = (t * t * (3 - 2 * t))[..., None]
    color = np.clip(color * (1 - t) + HORIZON * t, 0, 1).astype(np.float32)

    image = bpy.data.images.new('far', n, n)
    rgba = np.ones((n, n, 4), dtype=np.float32)
    rgba[..., :3] = color[::-1]
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = job['output']
    image.file_format = 'JPEG'
    bpy.context.scene.render.image_settings.quality = 82
    image.save()
    print('far ground', job['output'], 'points', float(points.mean()))


main()
