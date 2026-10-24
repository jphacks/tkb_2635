"""3D の建物データの外側を地平線までつなぐ「遠くの地面」の画像を、シーンごとに作る（4-11）。

地理院タイルの航空写真（ズーム 13）を半径 20 km ぶんつないで夜の暗さにし、衛星の夜間光（NASA Black Marble）を
街明かりの色で重ね、端（15〜20 km）は空の地平線の色になじませる。画像の合成は Blender の Python で行う
（far_ground_blender.py。numpy が入っているため）。

    python3 scripts/far_ground.py shinjuku          # docs/data/city-scenes.json のシーン
    python3 scripts/far_ground.py --all             # 全シーン（buildings.json の全部）

出力は App/Resources/Far/far_<シーンID>.jpg と、範囲を書いた far_<シーンID>.json。
ファイルを置くだけで、アプリ（FarGroundRenderer）がそのシーンの遠くの地面として描く。

出典: 国土地理院「地理院タイル（全国最新写真（シームレス））」、NASA Earth Observatory「Black Marble 2016」（NASA GIBS で配信）
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import math
import os
from pathlib import Path
import subprocess
import threading
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BUILDINGS = ROOT / 'Packages/StarCore/Sources/StarCore/Resources/buildings.json'
OUTPUT = ROOT / 'App/Resources/Far'
CACHE = ROOT.parent / 'outputs/far-ground-tiles'
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'

PHOTO_URL = 'https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg'
LIGHTS_URL = ('https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/VIIRS_Black_Marble/default/2016-01-01/'
              'GoogleMapsCompatible_Level8/{z}/{y}/{x}.png')
PHOTO_ZOOM = 13
LIGHTS_ZOOM = 8  # Black Marble の配信の最大ズーム（約 500 m/画素）
# 画像が覆う範囲（シーンの原点から東西南北に）[m] と、なじませ始める距離 [m]
RADIUS = 20_000.0
FADE_START = 15_000.0
# 画像の1辺の画素数（約 20 m/画素）。描画用のメモリは約 16 MB（設計メモ）
PIXELS = 2048
SOURCE = ('国土地理院「地理院タイル（全国最新写真（シームレス））」・NASA Earth Observatory「Black Marble 2016」'
          '（NASA GIBS）を加工して作成')


def local_to_latlon(east, north, latitude, longitude):
    """シーン原点からの東・北 [m] を緯度経度にする（StarCore の CityScene.localPosition の逆）。"""
    return (latitude + north / 110_574.0,
            longitude + east / (111_320.0 * math.cos(math.radians(latitude))))


def world_pixel(latitude, longitude, zoom):
    """ウェブメルカトルの世界の画素座標 (x, y)（タイル 256 画素）。"""
    n = 256 * 2 ** zoom
    x = (longitude + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(latitude))) / math.pi) / 2 * n
    return x, y


def tile_range(latitude, longitude, radius, zoom):
    """原点から radius [m] 四方を覆うタイルの (x0, y0, x1, y1)（両端を含む）。"""
    north, west = local_to_latlon(-radius, radius, latitude, longitude)
    south, east = local_to_latlon(radius, -radius, latitude, longitude)
    x0, y0 = world_pixel(north, west, zoom)
    x1, y1 = world_pixel(south, east, zoom)
    return int(x0 // 256), int(y0 // 256), int(x1 // 256), int(y1 // 256)


def fade(distance, start=FADE_START, end=RADIUS):
    """地平線の色へなじませる割合（0: そのまま、1: 地平線の色）。なめらかに変える。"""
    t = min(max((distance - start) / (end - start), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def fetch(url, target):
    if target.exists() and target.stat().st_size > 0:
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    # 隣のシーンと同時に同じタイルを取っても壊れないよう、一時ファイルの名前は処理ごとに分ける
    temporary = target.with_suffix(f'{target.suffix}.{os.getpid()}.{threading.get_ident()}.part')
    urllib.request.urlretrieve(url, temporary)
    temporary.replace(target)
    return 1


def tiles(kind, url, zoom, bounds):
    x0, y0, x1, y1 = bounds
    jobs = [(url.format(z=zoom, x=x, y=y), CACHE / kind / f'{zoom}/{x}/{y}{Path(url).suffix}')
            for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        fetched = sum(pool.map(lambda job: fetch(*job), jobs))
    return fetched, len(jobs)


def plan(scene):
    """Blender に渡す作業の内容（タイルの場所と範囲）。"""
    lat, lon = scene['originLatitude'], scene['originLongitude']
    photo = tile_range(lat, lon, RADIUS, PHOTO_ZOOM)
    lights = tile_range(lat, lon, RADIUS, LIGHTS_ZOOM)
    return {'sceneId': scene['id'], 'latitude': lat, 'longitude': lon, 'radius': RADIUS, 'fadeStart': FADE_START,
            'pixels': PIXELS, 'photo': {'zoom': PHOTO_ZOOM, 'bounds': photo, 'folder': str(CACHE / 'photo')},
            'lights': {'zoom': LIGHTS_ZOOM, 'bounds': lights, 'folder': str(CACHE / 'lights')},
            'output': str(OUTPUT / f'far_{scene["id"]}.jpg')}


def build(scene):
    job = plan(scene)
    for kind, url in (('photo', PHOTO_URL), ('lights', LIGHTS_URL)):
        fetched, total = tiles(kind, url, job[kind]['zoom'], job[kind]['bounds'])
        print(f'{scene["id"]}: {kind} {total} 枚（新しく {fetched} 枚）', flush=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    work = CACHE / f'{scene["id"]}.plan.json'
    work.write_text(json.dumps(job))
    subprocess.run([BLENDER, '-b', '--python', str(ROOT / 'scripts/far_ground_blender.py'), '--', str(work)],
                   check=True, stdout=subprocess.DEVNULL)
    # アプリが読む範囲の情報（画像の1辺が覆う長さ [m]。中心はシーンの原点）
    info = {'sceneId': scene['id'], 'meters': 2 * RADIUS, 'source': SOURCE}
    (OUTPUT / f'far_{scene["id"]}.json').write_text(json.dumps(info, ensure_ascii=False, indent=2) + '\n')
    size = Path(job['output']).stat().st_size / 1e6
    print(f'{scene["id"]}: {job["output"]}（{size:.1f} MB）', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('scene_ids', nargs='*')
    parser.add_argument('--all', action='store_true', help='buildings.json の全シーン')
    args = parser.parse_args()
    scenes = json.loads(BUILDINGS.read_text())
    chosen = scenes if args.all else [s for s in scenes if s['id'] in args.scene_ids]
    if not chosen:
        parser.error('シーン ID を指定するか --all を付けてください')
    for scene in chosen:
        build(scene)


if __name__ == '__main__':
    main()
