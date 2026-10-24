"""シーンの原点と半径から、PLATEAU の配布目録（建物・道路の GML の URL）を作る。

PLATEAU の公式カタログ API（https://api.plateauview.mlit.go.jp/datacatalog/）に範囲で問い合わせ、
建物は判定の半径、道路は地面の写真の半径にかかる 3次メッシュ（約1km 四方）の GML を選ぶ。
東京都の 2025 年度データは、同じメッシュ番号なら区が違っても同じファイルなので、メッシュごとに1つだけ選ぶ。
書き出した目録は download_plateau.py・download_plateau_textures.py が読む。
"""
import argparse
import json
import math
from pathlib import Path
import urllib.request

CATALOG = 'https://api.plateauview.mlit.go.jp/datacatalog/citygml/r:{west},{south},{east},{north}'
METERS_PER_DEG_LAT = 110_574.0
METERS_PER_DEG_LON = 111_320.0


def bounding_box(latitude, longitude, radius):
    """原点から radius [m] の正方形の (west, south, east, north) [度]"""
    dlat = radius / METERS_PER_DEG_LAT
    dlon = radius / (METERS_PER_DEG_LON * math.cos(math.radians(latitude)))
    return longitude - dlon, latitude - dlat, longitude + dlon, latitude + dlat


def mesh_bounds(code):
    """3次メッシュ番号（8桁）の (west, south, east, north) [度]"""
    if len(code) != 8 or not code.isdigit():
        raise ValueError(f'3次メッシュ番号ではありません: {code}')
    south = int(code[0:2]) / 1.5 + int(code[4]) / 12 + int(code[6]) / 120
    west = 100 + int(code[2:4]) + int(code[5]) / 8 + int(code[7]) / 80
    return west, south, west + 1 / 80, south + 1 / 120


def overlaps(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def preference(city):
    """同じメッシュのファイルを選ぶ順番（小さいほど先）"""
    return (not city['cityCode'].startswith('13'), -city.get('year', 0), city['cityCode'])


def select_files(catalog, buildings_box, roads_box):
    """カタログの応答から、範囲にかかる建物（bldg）と道路（tran）の GML をメッシュごとに1つ選ぶ。

    同じメッシュが複数の市区にあるときは、東京都（コード 13）・新しい年度・コードが小さい順に1つ使う。
    東京都の区どうしは同じファイルだが、県境の向こうの市（埼玉県など）は年度もファイルも別なので、区を優先する。
    """
    chosen = {}
    for city in sorted(catalog['cities'], key=preference):
        for kind, box in (('bldg', buildings_box), ('tran', roads_box)):
            for item in city.get('files', {}).get(kind, []):
                key = (kind, item['code'])
                if key in chosen or not overlaps(mesh_bounds(item['code']), box):
                    continue
                chosen[key] = {'name': item['url'].rsplit('/', 1)[1], 'url': item['url'],
                               'cityCode': city['cityCode'], 'cityName': city['cityName'], 'year': city.get('year'),
                               'maxLod': item.get('maxLod'), 'features': item.get('features'),
                               'lod2': item.get('lod2')}
    return [chosen[k] for k in sorted(chosen)]


def codelists_url(catalog, city_code):
    """建物の用途コードを読むためのコードリスト ZIP の URL"""
    for city in catalog['cities']:
        if city['cityCode'] == city_code:
            return next((u for u in city.get('metadataZipUrls', []) if u.endswith('_codelists.zip')), None)
    return None


def build_manifest(catalog, *, latitude, longitude, building_radius, road_radius, query):
    files = select_files(catalog, bounding_box(latitude, longitude, building_radius),
                         bounding_box(latitude, longitude, road_radius))
    if not any(f['name'].endswith('_bldg_6697_op.gml') for f in files):
        raise ValueError('範囲に建物の GML がありません。原点と半径を確認してください')
    cities = sorted({(f['cityCode'], f['cityName'], f['year']) for f in files})
    first = next(f for f in files if '_bldg_' in f['name'])
    return {'dataset': '3D都市モデル（Project PLATEAU）',
            'cities': [{'cityCode': c, 'cityName': n, 'year': y} for c, n, y in cities],
            'year': max(f['year'] or 0 for f in files), 'catalog_query': query,
            'codelists': codelists_url(catalog, first['cityCode']),
            'license': 'CC-BY-4.0', 'license_url': 'https://creativecommons.org/licenses/by/4.0/',
            'files': files}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--latitude', type=float, required=True)
    parser.add_argument('--longitude', type=float, required=True)
    parser.add_argument('--building-radius', type=float, default=500, help='建物を取る半径 [m]')
    parser.add_argument('--road-radius', type=float, default=800, help='道路と地面の写真の半径 [m]')
    parser.add_argument('--output', type=Path, required=True, help='書き出す目録（JSON）')
    args = parser.parse_args()
    west, south, east, north = bounding_box(args.latitude, args.longitude, max(args.building_radius, args.road_radius))
    query = CATALOG.format(west=round(west, 4), south=round(south, 4), east=round(east, 4), north=round(north, 4))
    with urllib.request.urlopen(query) as response:
        catalog = json.load(response)
    manifest = build_manifest(catalog, latitude=args.latitude, longitude=args.longitude,
                              building_radius=args.building_radius, road_radius=args.road_radius, query=query)
    if args.output.exists():
        # 取得済みのファイルの大きさと SHA-256 は残す（download_plateau.py が書き足す）
        known = {f['name']: f for f in json.loads(args.output.read_text())['files']}
        for item in manifest['files']:
            for key in ('bytes', 'sha256'):
                if key in known.get(item['name'], {}):
                    item[key] = known[item['name']][key]
    args.output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f"{len(manifest['files'])} ファイル: " + ', '.join(f['name'] for f in manifest['files']))


if __name__ == '__main__':
    main()
