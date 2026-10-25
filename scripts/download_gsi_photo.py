"""シーンの地面に貼る航空写真を、地理院タイル（全国最新写真（シームレス））から取得する。

出典: 国土地理院「地理院タイル（全国最新写真（シームレス））」 https://maps.gsi.go.jp/development/ichiran.html
出力フォルダに z/x/y.jpg とタイルの範囲（ground.json）を書く。blender_city_usdz.py が読んで地面にする。
"""
import argparse
import json
import math
from pathlib import Path
import urllib.request

URL = 'https://cyberjapandata.gsi.go.jp/xyz/seamlessphoto/{z}/{x}/{y}.jpg'


def tile(lat, lon, zoom):
    n = 2 ** zoom
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return int(x), int(y)


def corner(x, y, zoom):
    """タイルの左上の緯度・経度"""
    n = 2 ** zoom
    return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n)))), x / n * 360 - 180


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--latitude', type=float, required=True)
    parser.add_argument('--longitude', type=float, required=True)
    parser.add_argument('--radius', type=float, default=800, help='原点からの範囲 [m]')
    parser.add_argument('--zoom', type=int, default=18)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    dlat = args.radius / 110_574
    dlon = args.radius / (111_320 * math.cos(math.radians(args.latitude)))
    x0, y0 = tile(args.latitude + dlat, args.longitude - dlon, args.zoom)
    x1, y1 = tile(args.latitude - dlat, args.longitude + dlon, args.zoom)
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            target = args.output / f'{args.zoom}/{x}/{y}.jpg'
            if target.exists():
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            urllib.request.urlretrieve(URL.format(z=args.zoom, x=x, y=y), target)
    north, west = corner(x0, y0, args.zoom)
    south, east = corner(x1 + 1, y1 + 1, args.zoom)
    info = {'zoom': args.zoom, 'x0': x0, 'y0': y0, 'columns': x1 - x0 + 1, 'rows': y1 - y0 + 1,
            'north': north, 'south': south, 'west': west, 'east': east,
            'source': '国土地理院「地理院タイル（全国最新写真（シームレス））」'}
    (args.output / 'ground.json').write_text(json.dumps(info, ensure_ascii=False, indent=2))
    print(f"{info['columns']}×{info['rows']} 枚")


if __name__ == '__main__':
    main()
