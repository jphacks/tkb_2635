"""目録（docs/data/plateau-<シーン>-2025.json）に従い、PLATEAU の原本を取得する。

目録に大きさと SHA-256 があれば一致を確かめ、無ければ（plateau_catalog.py で作ったばかりなら）取得した値を目録に書き足す。
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

DEFAULT_MANIFEST = Path(__file__).resolve().parents[1] / 'docs/data/plateau-shibuya-2025.json'


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST, help='目録。省略時は渋谷')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    recorded = False
    for item in manifest['files']:
        target = args.output / item['name']
        if target.exists() and (item.get('sha256') is None or digest(target) == item['sha256']):
            print(f'確認済み: {target.name}', flush=True)
        else:
            temporary = target.with_suffix(target.suffix + '.part')
            print(f'取得中: {target.name}', flush=True)
            urllib.request.urlretrieve(item['url'], temporary)
            if item.get('sha256') is not None and (temporary.stat().st_size != item['bytes']
                                                   or digest(temporary) != item['sha256']):
                raise SystemExit(f'原本と一致しません: {temporary}')
            temporary.replace(target)
            print(f'完了: {target.name}', flush=True)
        if item.get('sha256') is None:
            item['bytes'], item['sha256'] = target.stat().st_size, digest(target)
            recorded = True
    if recorded:
        args.manifest.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        print(f'大きさと SHA-256 を目録に書き足しました: {args.manifest}')


if __name__ == '__main__':
    main()
