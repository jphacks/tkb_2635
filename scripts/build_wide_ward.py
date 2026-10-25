"""区ごとの広域 3D（低詳細）を作る（task.md の o-1）。

PLATEAU の「建築物モデル LOD1」の 3D Tiles を区ごとに取り、建物を向き付きの箱 1 つずつにして、
`App/Resources/Wide/Wide_<区コード>.usdz` を書き出す。細かい建物・実写は、地点ごとの 3D（`build_city_scene.py`）が受け持つ。

  python3 scripts/build_wide_ward.py 13104            # 新宿区
  python3 scripts/build_wide_ward.py 13104 --steps build   # 取得済みのデータから作り直すだけ

手順は `download → build → install`。作業フォルダは `../outputs/wide-<区コード>`（リポジトリの外）。
区コードは 13101（千代田区）〜 13123（江戸川区）。出典: 国土交通省 Project PLATEAU（CC BY 4.0）。
"""
import argparse
import json
import shutil
import struct
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = 'https://api.plateauview.mlit.go.jp/datacatalog/plateau-datasets'
BLENDER = '/Applications/Blender.app/Contents/MacOS/Blender'
STEPS = ('download', 'build', 'install')


def fetch(url, retries=3):
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=120) as response:
                return response.read()
        except OSError:
            if attempt == retries - 1:
                raise


def tileset_url(code):
    datasets = json.loads(fetch(CATALOG))['datasets']
    for item in datasets:
        if item.get('id') == f'{code}_bldg_lod1' and item.get('format') == '3D Tiles':
            return item['url'], item['city']
    raise SystemExit(f'区コード {code} の LOD1 3D Tiles が見つからない')


def tile_names(node, out):
    uri = node.get('content', {}).get('uri')
    if uri:
        out.append(uri)
    for child in node.get('children', []):
        tile_names(child, out)
    return out


def b3dm_to_glb(data):
    """b3dm（または 3D Tiles 1.1 の glb）から glTF を取り出し、Blender が読める形にする。

    中心の地球中心座標（CESIUM_RTC、または 1.1 の glb ではノードの移動量）を別に返す。
    Blender が読めない拡張（EXT_*）と、取り込みで落ちる _BATCHID・_FEATURE_ID は外す。
    """
    if data[:4] == b'glTF':
        glb = data
    else:
        _, _, _, ft_json, ft_bin, bt_json, bt_bin = struct.unpack('<4sIIIIII', data[:28])
        glb = data[28 + ft_json + ft_bin + bt_json + bt_bin:]
    if len(glb) < 20:
        return None, None    # 建物が入っていない空のタイル
    json_length = struct.unpack('<I', glb[12:16])[0]
    gltf = json.loads(glb[20:20 + json_length])
    rest = glb[20 + json_length:]
    center = gltf.get('extensions', {}).get('CESIUM_RTC', {}).get('center', [0, 0, 0])
    for node in gltf.get('nodes', []):
        if 'translation' in node:
            # glTF は Y 上。地球中心座標（Z 上）に直す。ノードの移動は取り除き、頂点は中心からの差にする。
            x, y, z = node.pop('translation')
            center = [x, -z, y]
    gltf.pop('extensions', None)
    for key in ('extensionsRequired', 'extensionsUsed'):
        gltf[key] = [name for name in gltf.get(key, [])
                     if name != 'CESIUM_RTC' and not name.startswith('EXT_')]
    for mesh in gltf['meshes']:
        for primitive in mesh['primitives']:
            primitive.get('extensions', {}).pop('EXT_mesh_features', None)
            draco = primitive.get('extensions', {}).get('KHR_draco_mesh_compression')
            for attributes in (primitive['attributes'], draco['attributes'] if draco else {}):
                for name in [n for n in attributes if n == '_BATCHID' or n.startswith('_FEATURE_ID')]:
                    attributes.pop(name)
    body = json.dumps(gltf, separators=(',', ':')).encode()
    body += b' ' * (-len(body) % 4)
    out = (struct.pack('<4sII', b'glTF', 2, 20 + len(body) + len(rest)) +
           struct.pack('<I4s', len(body), b'JSON') + body + rest)
    return out, center


def download(code, work):
    url, city = tileset_url(code)
    base = url.rsplit('/', 1)[0] + '/'
    tileset = json.loads(fetch(url))
    names = sorted(set(tile_names(tileset['root'], [])))
    (work / 'glb').mkdir(parents=True, exist_ok=True)
    centers = {}

    def one(name):
        # フォルダが違っても同じ名前のタイルがあるので、フォルダ名も名前に含める
        out_name = str(Path(name).with_suffix('')).replace('/', '_') + '.glb'
        target = work / 'glb' / out_name
        glb, center = b3dm_to_glb(fetch(base + name))
        if glb is None:
            return out_name, None
        target.write_bytes(glb)
        return out_name, center

    with ThreadPoolExecutor(8) as pool:
        for out_name, center in pool.map(one, names):
            if center is not None:
                centers[out_name] = center
    (work / 'rtc.json').write_text(json.dumps(centers))
    print(f'{city}: タイル {len(names)} 枚を取得')


def build(work):
    output = work / 'wide.usdz'
    subprocess.run([BLENDER, '-b', '--python', str(ROOT / 'scripts/wide_ward_blender.py'),
                    '--', str(work), str(output)], check=True)
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('code', help='区コード（例: 13104）')
    parser.add_argument('--steps', default=','.join(STEPS), help='動かす手順をコンマで（既定: すべて）')
    args = parser.parse_args()
    steps = args.steps.split(',')
    unknown = [step for step in steps if step not in STEPS]
    if unknown:
        raise SystemExit(f'知らない手順: {unknown}（使えるのは {STEPS}）')
    work = ROOT.parent / 'outputs' / f'wide-{args.code}'
    if 'download' in steps:
        download(args.code, work)
    if 'build' in steps:
        build(work)
    if 'install' in steps:
        target = ROOT / 'App/Resources/Wide' / f'Wide_{args.code}.usdz'
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(work / 'wide.usdz', target)
        print(f'{target.relative_to(ROOT)}: {target.stat().st_size / 1e6:.1f} MB')


if __name__ == '__main__':
    sys.exit(main())
