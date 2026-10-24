"""PLATEAU CityGMLをAsteraのCityScene配列に変換する（Python 3.9以上）。"""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import BadZipFile
import xml.etree.ElementTree as ET

from plateau_citygml import BelowSceneGround, convert_building, finite, iter_buildings, load_codelists, to_local


def convert(paths, *, scene_id, name, latitude, longitude, ground, radius, source, codelists=None):
    buildings, evidence, files, below = {}, {}, [], set()
    scanned = duplicates = 0
    for path in sorted(set(map(Path, paths))):
        count = 0
        for element, srs, dimension in iter_buildings(path):
            scanned += 1
            count += 1
            try:
                converted = convert_building(element, srs, dimension, (latitude, longitude),
                                             ground, radius, codelists or {})
            except BelowSceneGround:
                below.add(element.get('{http://www.opengis.net/gml}id'))
                continue
            except (ValueError, TypeError) as error:
                raise ValueError(f'{path.name} / {element.get("{http://www.opengis.net/gml}id")}: {error}') from error
            if converted is None:
                continue
            building, details = converted
            identifier = building['id']
            if identifier in buildings:
                if buildings[identifier] != building or evidence[identifier] != details:
                    raise ValueError(f'同じIDの建物が異なる形状・属性を持っています: {identifier}')
                duplicates += 1
                continue
            buildings[identifier], evidence[identifier] = building, details
        checksum = hashlib.sha256()
        with path.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                checksum.update(block)
        files.append({'name': path.name, 'sha256': checksum.hexdigest(), 'buildingsScanned': count})
    if not buildings:
        raise ValueError('指定範囲に変換可能な建物がありません。原点・半径・入力を確認してください')
    identifiers = sorted(buildings)
    scene = {'id': scene_id, 'name': name, 'originLatitude': latitude, 'originLongitude': longitude,
             'groundElevation': ground, 'source': source,
             'buildings': [buildings[i] for i in identifiers]}
    report = {'sceneId': scene_id, 'radiusMeters': radius, 'scanned': scanned,
              'selected': len(buildings), 'duplicatesRemoved': duplicates,
              'belowSceneGround': sorted(below - set(buildings)),
              'coordinateSystem': 'EPSG:6697 (latitude, longitude, orthometric height)',
              'heightRule': 'max(LOD1 roof elevation, base elevation + measuredHeight) - scene groundElevation',
              'selectionRule': 'axis-aligned building bounding rectangle intersects radius circle',
              'files': files, 'buildings': [evidence[i] for i in identifiers]}
    return [scene], report


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n')
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', nargs='+', type=Path, help='建物GMLファイル（複数指定可）')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', type=Path, help='原典属性・検証用の目録。省略時は出力名.report.json')
    parser.add_argument('--scene-id', required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--latitude', required=True, type=finite)
    parser.add_argument('--longitude', required=True, type=finite)
    parser.add_argument('--ground-elevation', required=True, type=finite, help='シーンの基準標高[m]。仮に0を入れない')
    parser.add_argument('--radius', default=500.0, type=finite, help='抽出半径[m]。既定500')
    parser.add_argument('--source', required=True, help='データ名・提供元・URL・加工表示')
    parser.add_argument('--codelists', type=Path, help='コードリストのディレクトリまたはZIP')
    args = parser.parse_args()
    if not (-90 < args.latitude < 90 and -180 <= args.longitude <= 180) or args.radius <= 0:
        parser.error('緯度・経度または半径の範囲が不正です')
    report_path = args.report or args.output.with_suffix('.report.json')
    inputs = {p.resolve() for p in args.inputs}
    outputs = [args.output.resolve(), report_path.resolve()]
    if any(p in inputs for p in outputs) or len(set(outputs)) != 2:
        parser.error('入力、出力、レポートには別々のパスを指定してください')
    try:
        scenes, report = convert(args.inputs, scene_id=args.scene_id, name=args.name,
                                 latitude=args.latitude, longitude=args.longitude,
                                 ground=args.ground_elevation, radius=args.radius, source=args.source,
                                 codelists=load_codelists(args.codelists))
        write_json(report_path, report)
        write_json(args.output, scenes)
    except (OSError, ValueError, ET.ParseError, BadZipFile) as error:
        parser.exit(1, f'変換に失敗しました: {error}\n')
    print(f'{report["scanned"]}棟を読み込み、{report["selected"]}棟を出力（重複除去{report["duplicatesRemoved"]}件）')


if __name__ == '__main__':
    main()
