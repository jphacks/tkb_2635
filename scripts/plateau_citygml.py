"""PLATEAU CityGML 2.0（EPSG:6697）の建物・LOD1形状を読む。"""
import math
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

B = '{http://www.opengis.net/citygml/building/2.0}'
G = '{http://www.opengis.net/gml}'
C = '{http://www.opengis.net/citygml/2.0}'
XLINK = '{http://www.w3.org/1999/xlink}href'


def finite(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError('NaN・無限大は使用できません')
    return result


def to_local(lat, lon, origin_lat, origin_lon):
    return ((lon - origin_lon) * 111_320.0 * math.cos(math.radians(origin_lat)),
            (lat - origin_lat) * 110_574.0)


def iter_buildings(path):
    """cityObjectMemberごとに解放し、都市全体のXMLをメモリに保持しない。"""
    stack = []
    document_srs = None
    dimension = None
    for event, element in ET.iterparse(path, events=('start', 'end')):
        if event == 'start':
            stack.append(element)
            if element.tag == G + 'Envelope' and len(stack) == 3:
                document_srs = element.get('srsName')
                dimension = element.get('srsDimension')
        else:
            if element.tag == B + 'Building':
                yield element, document_srs, dimension
            if element.tag in (C + 'cityObjectMember',
                                '{http://www.opengis.net/citygml/appearance/2.0}appearanceMember'):
                if len(stack) > 1:
                    stack[-2].remove(element)
                element.clear()
            stack.pop()


def load_codelists(path):
    if path is None:
        return {}
    path = Path(path)
    result = {}

    def read(name, data):
        tree = ET.fromstring(data)
        entries = {}
        for entry in tree.iter(G + 'Definition'):
            code, label = entry.findtext(G + 'name'), entry.findtext(G + 'description')
            if code and label:
                entries[code.strip()] = label.strip()
        basename = Path(name).name
        if basename in result and result[basename] != entries:
            raise ValueError(f'同名のコードリストが競合しています: {basename}')
        result[basename] = entries

    if path.is_file():
        with ZipFile(path) as archive:
            for name in sorted(archive.namelist()):
                if name.endswith('.xml'):
                    read(name, archive.read(name))
    else:
        if not path.is_dir():
            raise ValueError(f'コードリストがありません: {path}')
        for item in sorted(path.rglob('*.xml')):
            read(item.name, item.read_bytes())
    return result


def solid_points(building, srs, dimension):
    identifiers = {e.get(G + 'id'): e for e in building.iter() if e.get(G + 'id')}
    solids = building.findall(B + 'lod1Solid')
    if not solids:
        solids = building.findall('.//' + B + 'BuildingPart/' + B + 'lod1Solid')
    if not solids:
        raise ValueError('LOD1の立体形状がありません')
    points = []

    def walk(node, crs, dim, active):
        crs, dim = node.get('srsName', crs), node.get('srsDimension', dim)
        href = node.get(XLINK)
        if href:
            if not href.startswith('#') or href[1:] not in identifiers:
                raise ValueError(f'建物内で解決できない形状参照: {href}')
            if href in active:
                raise ValueError('形状参照が循環しています')
            walk(identifiers[href[1:]], crs, dim, active | {href})
        if node.tag in (G + 'posList', G + 'pos'):
            if not crs or not re.search(r'(?:/|:)6697$', crs):
                raise ValueError(f'対応していない座標系: {crs}（EPSG:6697が必要）')
            if str(dim) != '3':
                raise ValueError(f'座標の次元が3ではありません: {dim}')
            values = [finite(v) for v in (node.text or '').split()]
            if not values or len(values) % 3 or (node.tag == G + 'pos' and len(values) != 3):
                raise ValueError('座標の個数が不正です')
            for i in range(0, len(values), 3):
                lat, lon, altitude = values[i:i + 3]
                if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                    raise ValueError('緯度・経度の範囲が不正です（順序は緯度、経度）')
                points.append((lat, lon, altitude))
        for child in node:
            walk(child, crs, dim, active)

    for solid in solids:
        walk(solid, building.get('srsName', srs), building.get('srsDimension', dimension), set())
    if not points:
        raise ValueError('LOD1形状の座標がありません')
    return points


class BelowSceneGround(ValueError):
    """屋根がシーンの基準標高より低い建物（坂の下など）。平坦と見なすシーンでは空をふさがないので入れない。"""


def convert_building(element, srs, dimension, origin, ground, radius, codelists):
    identifier = element.get(G + 'id')
    if not identifier:
        raise ValueError('建物のgml:idがありません')
    points = solid_points(element, srs, dimension)
    positions = [to_local(lat, lon, *origin) for lat, lon, _ in points]
    left, right = min(x for x, _ in positions), max(x for x, _ in positions)
    bottom, top = min(y for _, y in positions), max(y for _, y in positions)
    # 中心が範囲外でも、長方形が円にかかる大きな建物は残す。
    if math.hypot(max(left, 0, -right), max(bottom, 0, -top)) > radius:
        return None
    base, roof = min(p[2] for p in points), max(p[2] for p in points)
    measured = element.find(B + 'measuredHeight')
    height = None
    raw_height = None
    if measured is not None:
        if measured.get('uom', 'm') not in ('m', 'urn:ogc:def:uom:OGC::m'):
            raise ValueError('measuredHeightはメートル単位が必要です')
        height = raw_height = finite(measured.text)
        if height == -9999:
            height = None
        if height is not None and height < 0:
            raise ValueError('measuredHeightが負の値です')
        # 原本の0は未確認値として扱い、LOD1形状から求める。
        if height == 0:
            height = None
    # 平坦なシーンでも元の屋根標高を失わない。両方あるときは高い方を採用。
    roof = max(roof, base + height) if height is not None else roof
    effective_height = roof - ground
    if right <= left or top <= bottom or roof <= base:
        raise ValueError('建物の幅・奥行き・高さが正ではありません')
    if effective_height <= 0:
        raise BelowSceneGround(f'屋根 {roof:.1f}m がシーンの地面 {ground:g}m より低い')
    usage = element.find(B + 'usage')
    label = None
    code = usage.text.strip() if usage is not None and usage.text else None
    if code:
        codefile = Path(usage.get('codeSpace', '')).name
        label = codelists.get(codefile, {}).get(code)
    result = {'id': identifier, 'name': element.findtext(G + 'name') or identifier,
              'x': round((left + right) / 2, 3), 'y': round((bottom + top) / 2, 3),
              'width': round(right - left, 3), 'depth': round(top - bottom, 3),
              'height': round(effective_height, 3), 'usage': label}
    if min(result['width'], result['depth'], result['height']) <= 0:
        raise ValueError('丸め後の建物の寸法が0になりました')
    details = {'id': identifier, 'baseElevation': base, 'geometryRoofElevation': max(p[2] for p in points),
               'measuredHeight': height, 'rawMeasuredHeight': raw_height, 'adoptedRoofElevation': roof, 'usageCode': code,
               'usageCodeSpace': usage.get('codeSpace') if usage is not None else None}
    return result, details
