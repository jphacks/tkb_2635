"""1つのシーン（地点のまわり）の判定用の箱と 3D ファイルを、PLATEAU と地理院タイルから作り直す。

シーンの設定は docs/data/city-scenes.json に書く（原点・半径・作業フォルダなど）。新しいシーンは、
そこに1行足してこのスクリプトを実行すれば、buildings.json の箱と App/Resources/City/City_<ID>.usdz ができる。
アプリのコードは直さなくてよい（CityModelRenderer がファイル名で見つける）。

    python3 scripts/build_city_scene.py shinjuku                # 全部の手順
    python3 scripts/build_city_scene.py shinjuku --steps boxes  # 一部だけ（手順名は STEPS）

取得したファイルや作業用の画像は設定の work・groundPhoto（リポジトリの外）に置く。取得済みのものは取り直さない。
"""
import argparse
import json
import shutil
import statistics
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'scripts'
CONFIG = ROOT / 'docs/data/city-scenes.json'
BUILDINGS = ROOT / 'Packages/StarCore/Sources/StarCore/Resources/buildings.json'
SPOTS = ROOT / 'Packages/StarCore/Sources/StarCore/Resources/spots.json'
CITY_RESOURCES = ROOT / 'App/Resources/City'
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'
STEPS = ['catalog', 'download', 'boxes', 'shapes', 'textures', 'photo', 'roads', 'model', 'install']
# 基準標高は、原点からこの距離 [m] 以内の建物の地盤標高の中央値にする
GROUND_SAMPLE_RADIUS = 200.0


def load_config(scene_id, path=CONFIG):
    for scene in json.loads(Path(path).read_text()):
        if scene['id'] == scene_id:
            return scene
    raise SystemExit(f'{path} に {scene_id} がありません')


# 作り直しても消さない、手で付けたシーンの設定
KEPT_SCENE_KEYS = ('observerViewEnabled',)


def merge_scene(scenes, scene):
    """buildings.json のシーンの列で、同じ ID のシーンだけを差し替える（無ければ最後に足す）。ほかのシーンは触らない。
    差し替えるときは、目線の可否など KEPT_SCENE_KEYS の設定を前のシーンから引き継ぐ。"""
    merged, replaced = [], False
    for existing in scenes:
        if existing['id'] == scene['id']:
            kept = {key: existing[key] for key in KEPT_SCENE_KEYS if key in existing and key not in scene}
            # 項目の並びを手で付けたときと同じ（name の次）にして、作り直しで差分が出ないようにする
            rebuilt = {}
            for key, value in scene.items():
                rebuilt[key] = value
                if key == 'name':
                    rebuilt.update(kept)
            merged.append({**rebuilt, **kept})
            replaced = True
        else:
            merged.append(existing)
    return merged if replaced else merged + [scene]


def suggest_ground(scene, evidence, radius=GROUND_SAMPLE_RADIUS):
    """原点から radius 以内に中心がある建物の地盤標高（PLATEAU の底面）の中央値 [m]。1m 単位に丸める。"""
    near = {b['id'] for b in scene['buildings'] if (b['x'] ** 2 + b['y'] ** 2) ** 0.5 <= radius}
    bases = [e['baseElevation'] for e in evidence if e['id'] in near]
    if not bases:
        # 広い公園などで近くに建物が無いときは、シーンの全部の建物を使う
        inside = {b['id'] for b in scene['buildings']}
        bases = [e['baseElevation'] for e in evidence if e['id'] in inside]
    if not bases:
        raise ValueError('シーンに建物がありません')
    return float(round(statistics.median(bases)))


def host_buildings(spots, scene_id):
    """このシーンの地点が立っている建物（hostBuildingId）の gml:id。3D では別の部品にする。"""
    return sorted({s['hostBuildingId'] for s in spots if s.get('sceneId') == scene_id and s.get('hostBuildingId')})


def dataset_urls(manifest):
    """GML の URL（…/13104_shinjuku-ku_pref_2025_citygml_1_op/udx/…）から、区ごとの配布ページの URL を作る。"""
    pages = []
    for item in manifest['files']:
        folder = item['url'].split('/udx/')[0].rsplit('/', 1)[1]
        code, name, _, year = folder.split('_')[:4]
        page = f'https://www.geospatial.jp/ckan/dataset/plateau-{code}-{name}-{year}'
        if page not in pages:
            pages.append(page)
    return pages


def source_text(manifest, ground, derived=True):
    cities = '・'.join(f"{c['cityName']}（{c.get('year', 2025)}年度）" for c in manifest['cities'])
    return (f'「3D都市モデル（Project PLATEAU）{cities}」 {" ".join(dataset_urls(manifest))} '
            'を加工してAsteraチームが作成（CC BY 4.0）。LOD1等を直方体近似。'
            + (f'基準標高{ground:g}mは原点の近く（{GROUND_SAMPLE_RADIUS:g}m以内。無ければシーン全体）の建物の地盤標高の中央値。'
               if derived else f'基準標高{ground:g}mは地点の床の標高に合わせた（設定で指定）。')
            + '観測地点の標高は暫定値、現況・現地未確認。')


def run(*command):
    print('$', ' '.join(map(str, command)), flush=True)
    subprocess.run([str(c) for c in command], check=True, cwd=ROOT)


def gml(work, kind):
    return sorted(work.glob(f'*_{kind}_6697_op.gml'))


def boxes(config, work, manifest):
    """判定用の箱を作り、buildings.json のこのシーンだけを差し替える。"""
    sys.path.insert(0, str(SCRIPTS))
    from plateau_citygml import load_codelists
    from plateau_to_json import convert, write_json
    codelists = load_codelists(work / Path(manifest['codelists']).name) if manifest.get('codelists') else {}
    common = dict(scene_id=config['id'], name=config['name'], latitude=config['latitude'],
                  longitude=config['longitude'], radius=config['buildingRadius'], codelists=codelists)
    ground = config.get('groundElevation')
    if ground is None:
        # まず地面 0m で読んで、原点の近くの建物の地盤標高から基準標高を決める。
        scenes, report = convert(gml(work, 'bldg'), ground=0.0, source='', **common)
        ground = suggest_ground(scenes[0], report['buildings'])
        print(f'基準標高 {ground:g}m（原点から {GROUND_SAMPLE_RADIUS:g}m 以内の建物の地盤標高の中央値）')
    scenes, report = convert(gml(work, 'bldg'), ground=ground,
                             source=source_text(manifest, ground, config.get('groundElevation') is None), **common)
    write_json(work / f'{config["id"]}-buildings.report.json', report)
    merged = merge_scene(json.loads(BUILDINGS.read_text()), scenes[0])
    BUILDINGS.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + '\n')
    summary = {key: report[key] for key in ('sceneId', 'radiusMeters', 'scanned', 'selected', 'duplicatesRemoved',
                                              'coordinateSystem', 'heightRule', 'selectionRule', 'files')}
    summary['groundElevation'] = ground
    summary['belowSceneGround'] = len(report['belowSceneGround'])
    (ROOT / f'docs/data/{config["id"]}-scene-integration.json').write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(f'{report["selected"]}棟を buildings.json の {config["id"]} に入れました')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('scene_id')
    parser.add_argument('--steps', nargs='+', choices=STEPS, default=STEPS)
    args = parser.parse_args()
    config = load_config(args.scene_id)
    scene_id = config['id']
    manifest_path = ROOT / config['manifest']
    work = (ROOT / config['work']).resolve()
    photo = (ROOT / config['groundPhoto']).resolve()
    shapes = work / f'{scene_id}-shapes.json'
    roads = work / f'{scene_id}-roads.json'
    model = work / 'model' / f'City_{scene_id}.usdz'

    for step in STEPS:
        if step not in args.steps:
            continue
        print(f'== {step}', flush=True)
        if step == 'catalog':
            run(sys.executable, SCRIPTS / 'plateau_catalog.py', '--latitude', config['latitude'],
                '--longitude', config['longitude'], '--building-radius', config['buildingRadius'],
                '--road-radius', config['groundRadius'], '--output', manifest_path)
        elif step == 'download':
            run(sys.executable, SCRIPTS / 'download_plateau.py', '--manifest', manifest_path, '--output', work)
            manifest = json.loads(manifest_path.read_text())
            if manifest.get('codelists') and not (work / Path(manifest['codelists']).name).exists():
                import urllib.request
                urllib.request.urlretrieve(manifest['codelists'], work / Path(manifest['codelists']).name)
        elif step == 'boxes':
            boxes(config, work, json.loads(manifest_path.read_text()))
        elif step == 'shapes':
            hosts = host_buildings(json.loads(SPOTS.read_text()), scene_id)
            run(sys.executable, SCRIPTS / 'plateau_shapes.py', *gml(work, 'bldg'), '--buildings', BUILDINGS,
                '--scene-id', scene_id, '--output', shapes, *[a for h in hosts for a in ('--host', h)],
                *[f'--style={k}={v}' for k, v in config.get('facadeStyles', {}).items()])
        elif step == 'textures':
            run(sys.executable, SCRIPTS / 'download_plateau_textures.py', shapes, '--manifest', manifest_path,
                '--output', work)
        elif step == 'photo':
            run(sys.executable, SCRIPTS / 'download_gsi_photo.py', '--latitude', config['latitude'],
                '--longitude', config['longitude'], '--radius', config['groundRadius'], '--output', photo)
        elif step == 'roads':
            run(sys.executable, SCRIPTS / 'plateau_roads.py', *gml(work, 'tran'), '--buildings', BUILDINGS,
                '--scene-id', scene_id, '--ground', photo / 'ground.json', '--output', roads)
        elif step == 'model':
            model.parent.mkdir(parents=True, exist_ok=True)
            run(BLENDER, '-b', '--python', SCRIPTS / 'blender_city_usdz.py', '--', shapes, model, photo, roads,
                f'--atlas-budget={config.get("atlasBudget", 2)}')
        elif step == 'install':
            shutil.copy2(model, CITY_RESOURCES / model.name)
            print(f'{CITY_RESOURCES / model.name}（{model.stat().st_size / 1e6:.1f} MB）')


if __name__ == '__main__':
    main()
