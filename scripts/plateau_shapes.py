"""PLATEAU の LOD2 の屋根・壁・屋上設備の面と実写テクスチャの貼り方を、Blender で 3D ファイルにするための JSON に書き出す。

見た目専用。遮蔽判定はアプリの buildings.json（plateau_blocks.py で足した部分の箱）を使う。
そのため、各建物の面は buildings.json の箱の高さを超えないように切りそろえる。
"""
import argparse
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

from night_lights import aviation_points, window_quads
from plateau_citygml import B, G, XLINK, finite, iter_buildings, to_local

APP = '{http://www.opengis.net/citygml/appearance/2.0}'

WALL_KINDS = {'WallSurface', 'ClosureSurface'}
ROOF_KINDS = {'RoofSurface', 'OuterCeilingSurface', 'OuterFloorSurface'}


def facade_key(usage, identifier, styles=None):
    """App/Views/BuildingFacade.swift と同じ規則で外観の種類と模様番号を決める。
    styles（city-scenes.json の facadeStyles）に建物の ID か用途があれば、その種類にする（4 以降はシーン専用の外観）。"""
    usage = usage or ''
    styles = styles or {}
    if identifier in styles or usage in styles:
        style = styles.get(identifier, styles.get(usage))
    elif '住宅' in usage or '住居' in usage:
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


def host_tag(identifier):
    """観測者が中にいる建物の部品に付ける目印（_h と gml:id の英数字の先頭 8 文字）。

    App/Views/CityModelRenderer.swift の hostTag(for:) と同じ規則。部品名の長さの上限に収めるため短くする。
    """
    letters = ''.join(c for c in identifier.removeprefix('bldg_') if c.isalnum())
    return '_h' + letters[:8].lower()


def load_textures(path):
    """ファイル先頭の appearanceMember から、外周の輪の ID → (画像の相対パス, UV の列) を作る。"""
    result = {}
    for _, element in ET.iterparse(path, events=('end',)):
        if element.tag == APP + 'ParameterizedTexture':
            image = element.findtext(APP + 'imageURI').strip()
            for coordinates in element.iter(APP + 'textureCoordinates'):
                values = [float(v) for v in coordinates.text.split()]
                result[coordinates.get('ring').lstrip('#')] = (image, list(zip(values[::2], values[1::2])))
            element.clear()
        elif element.tag == APP + 'appearanceMember':
            # 建物より前にまとめて書かれているので、ここで読み終える。
            break
    return result


def rings(node, identifiers):
    """(輪の ID, 面の外周の座標列（緯度・経度・標高）) を返す。中庭などの内側の穴は扱わない。"""
    href = node.get(XLINK)
    if href:
        target = identifiers.get(href.lstrip('#'))
        if target is not None:
            yield from rings(target, identifiers)
        return
    if node.tag == G + 'Polygon':
        ring = node.find(G + 'exterior/' + G + 'LinearRing')
        pos = ring.find(G + 'posList') if ring is not None else None
        if pos is not None and pos.text:
            values = [finite(v) for v in pos.text.split()]
            yield ring.get(G + 'id'), [tuple(values[i:i + 3]) for i in range(0, len(values) - 2, 3)]
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


def is_outward(points, center):
    """屋根が上向き、壁が建物の中心から外向きの頂点順なら True。面積が無ければ None。"""
    n = normal(points)
    if n is None:
        return None
    if abs(n[2]) > 0.7:
        return n[2] > 0
    cx = sum(p[0] for p in points) / len(points) - center[0]
    cy = sum(p[1] for p in points) / len(points) - center[1]
    return n[0] * cx + n[1] * cy >= 0


def outward(points, center):
    """屋根は上向き、壁は建物の中心から外向きになるよう、頂点の順番をそろえる。"""
    facing = is_outward(points, center)
    return None if facing is None else points if facing else points[::-1]


def surfaces(building):
    """(種類, 輪の ID, 座標列) を返す。LOD2 が無い建物は LOD1 の立体を面の向きで屋根・壁に分ける。"""
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
                for ring_id, ring in rings(geometry, identifiers):
                    found = True
                    yield role, ring_id, ring
    for installation in building.iter(B + 'BuildingInstallation'):
        for geometry in installation.findall(B + 'lod2Geometry'):
            for ring_id, ring in rings(geometry, identifiers):
                yield 'equipment', ring_id, ring
    if found:
        return
    for solid in building.iter(B + 'lod1Solid'):
        for ring_id, ring in rings(solid, identifiers):
            yield 'lod1', ring_id, ring


def convert(paths, scene, hosts=(), styles=None):
    """hosts の建物（観測者が中にいる建物）は、部品名に host_tag を付けて別の部品にする（アプリで半透明にするため）。"""
    origin = (scene['originLatitude'], scene['originLongitude'])
    ground = scene['groundElevation']
    boxes = {b['id']: b for b in scene['buildings']}
    groups, textured, images, windows, aviation = {}, [], {}, {}, []
    stats = {'buildings': 0, 'lod2': 0, 'lod1': 0, 'clampedBuildings': 0, 'polygons': 0, 'texturedPolygons': 0,
             'windowQuads': 0, 'aviationLights': 0}
    for path in paths:
        textures = load_textures(path)
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
                       for role, _, ring in raw if role == 'ground' for lat, lon, alt in ring}
            lowest = min(p[2] for _, _, ring in raw for p in ring)

            def on_footing(lat, lon, alt):
                if not footing:
                    return alt <= lowest + 0.3
                base = footing.get((round(lat, 7), round(lon, 7)))
                return base is not None and alt <= base + 0.3

            clamped = False
            suffix = host_tag(identifier) if identifier in hosts else ''
            key = facade_key(box.get('usage'), identifier, styles) + suffix
            is_lod1 = any(role == 'lod1' for role, _, _ in raw)
            roof_points = []
            for role, ring_id, ring in raw:
                if role == 'ground':
                    continue
                texture = textures.get(ring_id)
                uv = texture[1] if texture and len(texture[1]) == len(ring) else None
                if ring[0] == ring[-1]:
                    ring = ring[:-1]
                    uv = uv[:-1] if uv else None
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
                if not is_outward(points, (box['x'], box['y'])):
                    points, uv = points[::-1], uv[::-1] if uv else None
                flat = [c for p in points for c in p]
                stats['polygons'] += 1
                if role == 'wall':
                    for name, quads in window_quads(points, normal(points), identifier, box.get('usage'),
                                                    stats['polygons']).items():
                        windows.setdefault(name + suffix, []).extend(quads)
                        stats['windowQuads'] += len(quads)
                else:
                    roof_points += points
                if uv:
                    # 実写テクスチャがある面。画像は通し番号で持つ。
                    index = images.setdefault(texture[0], len(images))
                    textured.append([index, flat, [round(c, 6) for p in uv for c in p], suffix])
                    stats['texturedPolygons'] += 1
                else:
                    # 写真の無い面は、屋根・設備は屋上素材、壁は用途ごとの窓の素材にまとめる。
                    groups.setdefault(key if role == 'wall' else 'roof' + suffix, []).append(flat)
            lights = aviation_points(roof_points, box['height'])
            aviation += lights
            stats['aviationLights'] += len(lights)
            stats['buildings'] += 1
            stats['lod1' if is_lod1 else 'lod2'] += 1
            stats['clampedBuildings'] += clamped
    ordered = sorted(images, key=images.get)
    return {'groups': groups, 'textured': textured, 'images': ordered, 'windows': windows, 'aviation': aviation}, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('gml', nargs='+', type=Path)
    parser.add_argument('--buildings', type=Path, required=True, help='アプリの buildings.json')
    parser.add_argument('--scene-id', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--host', action='append', default=[],
                        help='観測者が中にいる建物の gml:id（別の部品にする。複数指定可）')
    parser.add_argument('--style', action='append', default=[],
                        help='<用途 または gml:id>=<外観の種類の番号>（複数指定可）')
    args = parser.parse_args()
    scene = next(s for s in json.loads(args.buildings.read_text()) if s['id'] == args.scene_id)
    shapes, stats = convert(args.gml, scene, set(args.host),
                            dict((k, int(v)) for k, v in (a.rsplit('=', 1) for a in args.style)))
    if stats['buildings'] != len(scene['buildings']):
        missing = len(scene['buildings']) - stats['buildings']
        print(f'注意: buildings.json の {missing} 棟は形状が見つからず、3D ファイルに入りません')
    # 画像のパスは GML と同じフォルダからの相対パス
    args.output.write_text(json.dumps({'sceneId': scene['id'], 'originLatitude': scene['originLatitude'],
                                       'originLongitude': scene['originLongitude'], **shapes}, separators=(',', ':')))
    print(json.dumps(stats, ensure_ascii=False))


if __name__ == '__main__':
    main()
