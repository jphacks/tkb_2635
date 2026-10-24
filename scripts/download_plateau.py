"""取得済みの目録に従い、渋谷駅周辺のPLATEAU原本を再取得する。"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = Path(__file__).resolve().parents[1] / 'docs/data/plateau-shibuya-2025.json'
    files = json.loads(manifest.read_text())['files']
    args.output.mkdir(parents=True, exist_ok=True)
    for item in files:
        target = args.output / item['name']
        if target.exists() and digest(target) == item['sha256']:
            print(f'確認済み: {target.name}', flush=True)
            continue
        temporary = target.with_suffix(target.suffix + '.part')
        print(f'取得中: {target.name}', flush=True)
        urllib.request.urlretrieve(item['url'], temporary)
        if temporary.stat().st_size != item['bytes'] or digest(temporary) != item['sha256']:
            raise SystemExit(f'原本と一致しません: {temporary}')
        temporary.replace(target)
        print(f'完了: {target.name}', flush=True)


if __name__ == '__main__':
    main()
