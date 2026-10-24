"""PLATEAU の道路（tran）の LOD1 の面を、Blender で夜の路面と街灯を作るための JSON に書き出す。

見た目専用。座標はシーンの原点からの x=東・y=北 [m]（高さは使わない）。
地面の写真（download_gsi_photo.py の ground.json）の範囲に一部でも入る面だけを残す。
"""
import argparse
import json
from pathlib import Path
import xml.etree.ElementTree as ET

from plateau_citygml import G, finite, to_local

TRAN = '{http://www.opengis.net/citygml/transportation/2.0}'


def road_rings(road):
    """道路1本の LOD1 の面の外周（緯度・経度の列）を返す。"""
    for surface in road.iter(TRAN + 'lod1MultiSurface'):
        for ring in surface.iter(G + 'LinearRing'):
            pos = ring.find(G + 'posList')
            if pos is None or not pos.text:
                continue
            values = [finite(v) for v in pos.text.split()]
            points = [(values[i], values[i + 1]) for i in range(0, len(values) - 2, 3)]
            if len(points) > 3 and points[0] == points[-1]:
                points = points[:-1]
            if len(points) >= 3:
                yield points


def inside_bounds(points, bounds):
    """面の外接矩形が範囲 (west, south, east, north) [m] と重なるか。"""
    west, south, east, north = bounds
    xs, ys = [p[0] for p in points], [p[1] for p in points]
    return max(xs) >= west and min(xs) <= east and max(ys) >= south and min(ys) <= north


def convert(paths, origin, bounds):
    roads = []
    for path in paths:
        for _, element in ET.iterparse(path, events=('end',)):
            if element.tag != TRAN + 'Road':
                continue
            for ring in road_rings(element):
                points = [to_local(lat, lon, *origin) for lat, lon in ring]
                if inside_bounds(points, bounds):
                    roads.append([round(c, 2) for p in points for c in p])
            element.clear()
    return roads


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('gml', nargs='+', type=Path)
    parser.add_argument('--buildings', type=Path, required=True, help='アプリの buildings.json（原点を読む）')
    parser.add_argument('--scene-id', required=True)
    parser.add_argument('--ground', type=Path, required=True, help='download_gsi_photo.py の ground.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    scene = next(s for s in json.loads(args.buildings.read_text()) if s['id'] == args.scene_id)
    origin = (scene['originLatitude'], scene['originLongitude'])
    info = json.loads(args.ground.read_text())
    west, south = to_local(info['south'], info['west'], *origin)
    east, north = to_local(info['north'], info['east'], *origin)
    roads = convert(args.gml, origin, (west, south, east, north))
    args.output.write_text(json.dumps({'sceneId': scene['id'], 'roads': roads}, separators=(',', ':')))
    print(f'道路の面: {len(roads)}')


if __name__ == '__main__':
    main()
