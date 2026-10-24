"""plateau_shapes.py が書き出した JSON に載っている実写テクスチャだけを、PLATEAU の配布元から取得する。"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('shapes', type=Path, help='plateau_shapes.py の出力')
    parser.add_argument('--output', type=Path, required=True, help='GML を置いたフォルダ')
    args = parser.parse_args()
    manifest = Path(__file__).resolve().parents[1] / 'docs/data/plateau-shibuya-2025.json'
    # 画像は GML と同じ場所の「<区画>_bldg_6697_appearance/」にある。
    bases = {item['name'].removesuffix('_op.gml'): item['url'].rsplit('/', 1)[0]
             for item in json.loads(manifest.read_text())['files'] if item['name'].endswith('_op.gml')}
    images = json.loads(args.shapes.read_text())['images']

    def fetch(relative):
        target = args.output / relative
        if target.exists() and target.stat().st_size > 0:
            return 0
        target.parent.mkdir(parents=True, exist_ok=True)
        mesh = relative.split('/')[0].removesuffix('_appearance')
        temporary = target.with_suffix('.part')
        urllib.request.urlretrieve(f'{bases[mesh]}/{relative}', temporary)
        temporary.replace(target)
        return 1

    with ThreadPoolExecutor(max_workers=16) as pool:
        fetched = sum(pool.map(fetch, images))
    print(f'取得 {fetched} 枚、取得済み {len(images) - fetched} 枚')


if __name__ == '__main__':
    main()
