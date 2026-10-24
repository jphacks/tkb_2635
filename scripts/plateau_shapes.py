"""PLATEAU の LOD2 の屋根・壁・屋上設備の面を、Blender で 3D ファイルにするための JSON に書き出す。

見た目専用。遮蔽判定はアプリの buildings.json（外接直方体）を使い続ける。
そのため、各建物の面は buildings.json の箱の高さを超えないように切りそろえる。
"""
import argparse
import json
import math
from pathlib import Path

from plateau_citygml import B, G, XLINK, finite, iter_buildings, to_local

WALL_KINDS = {'WallSurface', 'ClosureSurface'}
ROOF_KINDS = {'RoofSurface', 'OuterCeilingSurface', 'OuterFloorSurface'}


def facade_key(usage, identifier):
    """App/Views/BuildingFacade.swift と同じ規則で外観の種類と模様番号を決める。"""
    usage = usage or ''
    if '住宅' in usage or '住居' in usage:
        style = 2
    elif '業務' in usage or 'オフィス' in usage:
        style = 0
    elif '商業' in usage or 'ホテル' in usage:
        style = 1
    else:
        style = 3
    value = 2_166_136_261
    for byte in identifier.encode():
        value = ((value ^ byte) * 16_777_619) & 0xFFFFFFFF
    return f'facade_{style}_{value % 4}'


def rings(node, identifiers):
    """面の外周の座標列（緯度・経度・標高）を返す。中庭などの内側の穴は扱わない。"""
    href = node.get(XLINK)
    if href:
        target = identifiers.get(href.lstrip('#'))
        if target is not None:
            yield from rings(target, identifiers)
        return
    if node.tag == G + 'Polygon':
        pos = node.find(G + 'exterior/' + G + 'LinearRing/' + G + 'posList')
        if pos is not None and pos.text:
            values = [finite(v) for v in pos.text.split()]
            yield [tuple(values[i:i + 3]) for i in range(0, len(values) - 2, 3)]
        return
    for child in node:
        yield from rings(child, identifiers)


def normal(points):
    """多角形の単位法線（Newell 法）。面積が無ければ None。"""
    nx = ny = nz = 0.0
    for (x1, y1, z1), (x2, y2, z2) in zip(points, points[1:] + points[:1]):
        nx += (y1 - y2) * (z1 + z2)
        ny += (z1 - z2) * (x1 + x2)
        nz += (x1 - x2) * (y1 + y2)
    length = math.sqrt(nx * nx + ny * ny + nz * nz)
    return (nx / length, ny / length, nz / length) if length > 1e-9 else None


def outward(points, center):
    """屋根は上向き、壁は建物の中心から外向きになるよう、頂点の順番をそろえる。"""
    n = normal(points)
    if n is None:
        return None
    if abs(n[2]) > 0.7:
        return points if n[2] > 0 else points[::-1]
    cx = sum(p[0] for p in points) / len(points) - center[0]
    cy = sum(p[1] for p in points) / len(points) - center[1]
    return points if n[0] * cx + n[1] * cy >= 0 else points[::-1]


def surfaces(building):
    """(種類, 座標列) を返す。LOD2 が無い建物は LOD1 の立体を面の向きで屋根・壁に分ける。"""
    identifiers = {e.get(G + 'id'): e for e in building.iter() if e.get(G + 'id')}
    found = False
    for bounded in building.iter(B + 'boundedBy'):
        for surface in bounded:
            kind = surface.tag.split('}')[-1]
            role = ('wall' if kind in WALL_KINDS else 'roof' if kind in ROOF_KINDS
                    else 'ground' if kind == 'GroundSurface' else None)
            if role is None:
                continue
            for geometry in surface.findall(B + 'lod2MultiSurface'):
                for ring in rings(geometry, identifiers):
                    found = True
                    yield role, ring
    for installation in building.iter(B + 'BuildingInstallation'):
        for geometry in installation.findall(B + 'lod2Geometry'):
            for ring in rings(geometry, identifiers):
                yield 'equipment', ring
    if found:
        return
    for solid in building.iter(B + 'lod1Solid'):
        for ring in rings(solid, identifiers):
            yield 'lod1', ring


def convert(paths, scene, host_ids):
    origin = (scene['originLatitude'], scene['originLongitude'])
    ground = scene['groundElevation']
    boxes = {b['id']: b for b in scene['buildings']}
    groups, stats = {}, {'buildings': 0, 'lod2': 0, 'lod1': 0, 'clampedBuildings': 0, 'polygons': 0}
    for path in paths:
        for element, _, _ in iter_buildings(path):
            identifier = element.get(G + 'id')
            box = boxes.get(identifier)
            if box is None:
                continue
            raw = list(surfaces(element))
            if not raw:
                continue
            # 底面（GroundSurface）の頂点。LOD1 だけの建物は最も低い頂点を底とみなす。
            footing = {(round(lat, 7), round(lon, 7)): alt
                       for role, ring in raw if role == 'ground' for lat, lon, alt in ring}
            lowest = min(p[2] for _, ring in raw for p in ring)

            def on_footing(lat, lon, alt):
                if not footing:
                    return alt <= lowest + 0.3
                base = footing.get((round(lat, 7), round(lon, 7)))
                return base is not None and alt <= base + 0.3

            clamped = False
            # 観測者が立つ建物は1棟だけの部品にし、アプリが地点ごとに半透明にするか決める。
            key = identifier if identifier in host_ids else facade_key(box.get('usage'), identifier)
            is_lod1 = any(role == 'lod1' for role, _ in raw)
            for role, ring in raw:
                if role == 'ground':
                    continue
                if ring[0] == ring[-1]:
                    ring = ring[:-1]
                if len(ring) < 3:
                    continue
                points, above = [], 0
                for lat, lon, alt in ring:
                    east, north = to_local(lat, lon, *origin)
                    z = alt - ground
                    # 判定の箱より高い屋上の突起は、箱の高さで切りそろえて見た目と判定を合わせる。
                    if z > box['height']:
                        z, clamped, above = box['height'], True, above + 1
                    # 坂の上の建物が浮かないよう、壁の下端をシーンの地面まで伸ばす（アプリの箱と同じ扱い）。
                    if role in ('wall', 'lod1') and z > 0 and on_footing(lat, lon, alt):
                        z = 0.0
                    points.append((round(east, 2), round(north, 2), round(z, 2)))
                if role != 'roof' and above == len(points):
                    continue
                n = normal(points)
                if n is None:
                    continue
                if role == 'lod1':
                    if n[2] < -0.7:
                        continue
                    role = 'roof' if n[2] > 0.7 else 'wall'
                points = outward(points, (box['x'], box['y']))
                # 屋根・設備は暗い屋上素材、壁は用途ごとの窓の素材にまとめる。
                name = key if key == identifier else (key if role == 'wall' else 'roof')
                groups.setdefault(name, []).append([c for p in points for c in p])
                stats['polygons'] += 1
            stats['buildings'] += 1
            stats['lod1' if is_lod1 else 'lod2'] += 1
            stats['clampedBuildings'] += clamped
    return groups, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('gml', nargs='+', type=Path)
    parser.add_argument('--buildings', type=Path, required=True, help='アプリの buildings.json')
    parser.add_argument('--scene-id', required=True)
    parser.add_argument('--host-id', action='append', default=[], help='観測者が立つ建物の ID（1棟だけの部品にする）')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    scene = next(s for s in json.loads(args.buildings.read_text()) if s['id'] == args.scene_id)
    groups, stats = convert(args.gml, scene, set(args.host_id))
    if stats['buildings'] != len(scene['buildings']):
        missing = len(scene['buildings']) - stats['buildings']
        print(f'注意: buildings.json の {missing} 棟は形状が見つからず、3D ファイルに入りません')
    args.output.write_text(json.dumps({'sceneId': scene['id'], 'groups': groups}, separators=(',', ':')))
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == '__main__':
    main()
