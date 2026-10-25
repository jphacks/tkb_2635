"""PLATEAU の LOD2 の形から、遮蔽判定用の「部分の箱」（東西・南北にそろえた小さな直方体）を作り、buildings.json に書き込む（4-13）。

外接直方体は、斜めに建つ建物や、低い基壇の上に細い塔が立つ建物を大きくふくらませる（渋谷ストリームでは、
空いている基壇の上まで 169m の壁があることになり、地上から見える月が「隠れる」と出た）。
そこで建物の屋根・設備の面を真上から CELL m の格子に塗り、マスごとの最も高い点を高さにして、
同じ高さのマスを長方形にまとめる。高さは 3D（plateau_shapes.py）と同じく、建物の箱の高さで切りそろえる。
"""
import argparse
import json
import math
import re
from pathlib import Path

import numpy as np

from plateau_citygml import G, iter_buildings, to_local
from plateau_shapes import surfaces

# 格子の 1 マスの大きさ [m]。縁の位置の誤差は半マス（1m）まで
CELL = 2.0
# 高さをこの単位で切り上げてから、同じ高さのマスをまとめる [m]
HEIGHT_STEP = 1.0


def footprint_heights(polygons, cell):
    """面（東・北・高さ [m] の点列）を真上から格子に塗り、マスごとの最も高い点を返す。"""
    xs = [x for p in polygons for x, _, _ in p]
    ys = [y for p in polygons for _, y, _ in p]
    x0, y0 = math.floor(min(xs) / cell) * cell, math.floor(min(ys) / cell) * cell
    nx, ny = int(math.ceil((max(xs) - x0) / cell)) + 1, int(math.ceil((max(ys) - y0) / cell)) + 1
    grid = np.zeros((ny, nx))
    cx = x0 + (np.arange(nx) + 0.5) * cell
    cy = y0 + (np.arange(ny) + 0.5) * cell
    for polygon in polygons:
        px = np.array([p[0] for p in polygon]); py = np.array([p[1] for p in polygon])
        top = max(p[2] for p in polygon)
        i0, i1 = np.searchsorted(cx, px.min()), np.searchsorted(cx, px.max(), side='right')
        j0, j1 = np.searchsorted(cy, py.min()), np.searchsorted(cy, py.max(), side='right')
        if i0 >= i1 or j0 >= j1:
            continue
        gx, gy = np.meshgrid(cx[i0:i1], cy[j0:j1])
        inside = np.zeros(gx.shape, dtype=bool)
        # 偶奇法で、マスの中心が面の内側にあるかを調べる
        for k in range(len(px)):
            ax, ay, bx, by = px[k - 1], py[k - 1], px[k], py[k]
            crosses = (ay > gy) != (by > gy)
            with np.errstate(divide='ignore', invalid='ignore'):
                xcross = ax + (gy - ay) * (bx - ax) / (by - ay)
            inside ^= crosses & (gx < xcross)
        region = grid[j0:j1, i0:i1]
        region[inside] = np.maximum(region[inside], top)
    return grid, x0, y0


def merge_cells(grid, x0, y0, cell):
    """同じ高さのマスを長方形にまとめる（横に伸ばしてから、同じ幅・高さの行を縦につなぐ）。"""
    ny, nx = grid.shape
    used = np.zeros(grid.shape, dtype=bool)
    parts = []
    for j in range(ny):
        for i in range(nx):
            h = grid[j, i]
            if h <= 0 or used[j, i]:
                continue
            i1 = i
            while i1 + 1 < nx and grid[j, i1 + 1] == h and not used[j, i1 + 1]:
                i1 += 1
            j1 = j
            while j1 + 1 < ny and np.all(grid[j1 + 1, i:i1 + 1] == h) and not used[j1 + 1, i:i1 + 1].any():
                j1 += 1
            used[j:j1 + 1, i:i1 + 1] = True
            w, d = (i1 - i + 1) * cell, (j1 - j + 1) * cell
            parts.append([round(x0 + i * cell + w / 2, 2), round(y0 + j * cell + d / 2, 2), w, d, float(h)])
    return parts


def building_parts(element, box, origin, ground, cell, clamp):
    polygons = []
    for role, _, ring in surfaces(element):
        if role == 'ground':
            continue
        points = []
        for lat, lon, alt in ring:
            east, north = to_local(lat, lon, *origin)
            points.append((east, north, alt - ground))
        polygons.append(points)
    if not polygons:
        return None
    grid, x0, y0 = footprint_heights(polygons, cell)
    grid = np.where(grid > 0, np.ceil(grid / HEIGHT_STEP) * HEIGHT_STEP, 0)
    if clamp:
        # 3D（plateau_shapes.py）と同じく、建物の箱の高さを超える塔屋・設備は切りそろえる（2-08）
        grid = np.minimum(grid, box['height'])
    parts = merge_cells(grid, x0, y0, cell)
    return parts or None


def add_parts(scene, paths, cell=CELL, clamp=True):
    origin = (scene['originLatitude'], scene['originLongitude'])
    boxes = {b['id']: b for b in scene['buildings']}
    done = 0
    for path in paths:
        for element, _, _ in iter_buildings(path):
            box = boxes.get(element.get(G + 'id'))
            if box is None or 'parts' in box:
                continue
            parts = building_parts(element, box, origin, scene['groundElevation'], cell, clamp)
            if parts:
                box['parts'] = parts
                done += 1
    return done


def dumps(scenes):
    """buildings.json の書式（字下げ 2）のまま、部分の箱 [x, y, 幅, 奥行き, 高さ] だけは 1 行にする。"""
    text = json.dumps(scenes, ensure_ascii=False, indent=2, allow_nan=False)
    return re.sub(r'\[\s+(-?[\d.]+),\s+(-?[\d.]+),\s+(-?[\d.]+),\s+(-?[\d.]+),\s+(-?[\d.]+)\s+\]',
                  r'[\1, \2, \3, \4, \5]', text) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('gml', nargs='+', type=Path)
    parser.add_argument('--buildings', type=Path, required=True, help='アプリの buildings.json（上書きする）')
    parser.add_argument('--scene-id', required=True)
    parser.add_argument('--cell', type=float, default=CELL)
    parser.add_argument('--no-clamp', action='store_true', help='箱の高さで切りそろえない（2-08 の比較用）')
    parser.add_argument('--output', type=Path, help='書き出し先。省略時は --buildings を上書き')
    args = parser.parse_args()
    scenes = json.loads(args.buildings.read_text())
    scene = next(s for s in scenes if s['id'] == args.scene_id)
    for b in scene['buildings']:
        b.pop('parts', None)
    done = add_parts(scene, args.gml, args.cell, not args.no_clamp)
    total = sum(len(b.get('parts', [])) for b in scene['buildings'])
    (args.output or args.buildings).write_text(dumps(scenes))
    print(f'{len(scene["buildings"])} 棟のうち {done} 棟に部分の箱 {total} 個を付けた')


if __name__ == '__main__':
    main()
