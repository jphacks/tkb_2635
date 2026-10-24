#!/usr/bin/env python3
"""EOG の VIIRS 夜間光（VNL v2.2 年次合成）から、地点ごとの地域の光害の値を作る。

既定は確認だけ（--dry-run）。--write で spots.json と docs/data/viirs-light-index.json を書き換える。
全球 GeoTIFF は大きいので、地点のまわりの 3×3 画素だけを窓読みする。
"""

import argparse
import copy
import hashlib
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPOTS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/spots.json"
RECORD = ROOT / "docs/data/viirs-light-index.json"

# 変換のしきい値 [nW/cm²/sr]。根拠は docs/data/viirs-light-index.md
R_DARK = 1.0      # これ以下は 0（郊外・暗い場所）
R_BRIGHT = 250.0  # これ以上は 1（渋谷駅周辺の実測 235 を上限の目安にした）
WINDOW_SIZE = 3   # 地点の画素を中心に平均する一辺の画素数
INDEX_DIGITS = 2
PRODUCT = "VIIRS VNL v2.2"
LAYER = "average_masked"
PROVIDER = "EOG, Colorado School of Mines"
YEAR_PATTERN = re.compile(r"(?<!\d)(20\d\d)(?!\d)")
HASH_CHUNK = 1 << 20


def light_index(radiance):
    """放射輝度 R を対数で 0〜1 に変換する。"""
    if radiance <= 0:
        return 0.0
    value = (math.log10(radiance) - math.log10(R_DARK)) / (math.log10(R_BRIGHT) - math.log10(R_DARK))
    return min(max(value, 0.0), 1.0)


def source_label(year):
    return f"{PRODUCT} {year} annual {LAYER}（{PROVIDER}）"


def guess_year(path):
    """ファイル名からデータの年を取る。EOG のファイル名は VNL_npp_2023_global_... の形。"""
    match = YEAR_PATTERN.search(Path(path).name)
    return int(match.group(1)) if match else None


def raster_path(path):
    """gzip のままでも読めるように GDAL の仮想パスにする（解凍したほうが速い）。"""
    return f"/vsigzip/{path}" if str(path).endswith(".gz") else str(path)


def sample_radiance(dataset, latitude, longitude):
    """地点の画素を中心とした 3×3 画素の平均 R と、使えた画素数を返す。全部欠損なら R は None。"""
    import numpy as np
    from rasterio.windows import Window

    row, col = dataset.index(longitude, latitude)
    if not (0 <= row < dataset.height and 0 <= col < dataset.width):
        raise ValueError(f"地点 ({latitude}, {longitude}) が画像の範囲外です")
    half = WINDOW_SIZE // 2
    # 画像の端では、はみ出した分を削った窓にする
    top, left = max(row - half, 0), max(col - half, 0)
    bottom, right = min(row + half + 1, dataset.height), min(col + half + 1, dataset.width)
    values = dataset.read(1, window=Window(left, top, right - left, bottom - top), masked=True)
    data = np.ma.masked_invalid(values.astype("float64"))
    data = np.ma.masked_less(data, 0)
    valid = int(data.count())
    radiance = float(data.mean()) if valid else None
    return {"row": int(row), "col": int(col), "validPixels": valid, "radiance": radiance}


def sample_spots(raster, spots):
    import rasterio

    with rasterio.open(raster_path(raster)) as dataset:
        if dataset.crs is None or not dataset.crs.is_geographic:
            raise ValueError(f"緯度経度の画像ではありません（CRS: {dataset.crs}）")
        results = []
        for spot in spots:
            sample = sample_radiance(dataset, spot["latitude"], spot["longitude"])
            radiance = sample["radiance"]
            index = None if radiance is None else round(light_index(radiance), INDEX_DIGITS)
            results.append({"id": spot["id"], "latitude": spot["latitude"], "longitude": spot["longitude"],
                            **sample, "index": index})
        return results


def with_inserted(spot, updates, after):
    """キーの順を保ったまま値を入れる。新しいキーは after の直後に置き、差分を小さくする。"""
    result = {}
    for key, value in spot.items():
        if key in updates and key != after:
            continue
        result[key] = updates.get(key, value)
        if key == after:
            for new_key, new_value in updates.items():
                if new_key != after:
                    result[new_key] = new_value
    return result


def apply(spots, results, year):
    """計算できた地点だけ regionalLight* を書き換えた新しい一覧を返す。"""
    by_id = {result["id"]: result for result in results}
    updated = []
    for spot in spots:
        result = by_id.get(spot["id"])
        if result is None or result["index"] is None:
            updated.append(copy.deepcopy(spot))
            continue
        updates = {"regionalLightIndex": result["index"],
                   "regionalLightSource": source_label(year),
                   "regionalLightMeasuredAt": str(year)}
        updated.append(with_inserted(copy.deepcopy(spot), updates, "regionalLightIndex"))
    return updated


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(HASH_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_entry(path):
    return {"file": Path(path).name, "bytes": Path(path).stat().st_size, "sha256": sha256(path)}


def record(raster, year, results, archive=None):
    return {
        "product": PRODUCT,
        "layer": LAYER,
        "provider": PROVIDER,
        "year": year,
        "raster": file_entry(raster),
        "archive": file_entry(archive) if archive else None,
        "unit": "nW/cm²/sr",
        "conversion": {
            "formula": "clamp((log10(R) - log10(R_DARK)) / (log10(R_BRIGHT) - log10(R_DARK)), 0, 1)",
            "R_DARK": R_DARK,
            "R_BRIGHT": R_BRIGHT,
            "windowSize": WINDOW_SIZE,
        },
        "spots": results,
    }


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def format_table(spots, results):
    current = {spot["id"]: spot.get("regionalLightIndex") for spot in spots}
    lines = [f"{'地点':<24} {'R [nW/cm²/sr]':>14} {'画素':>4} {'新しい値':>8} {'今の値':>6}"]
    for result in results:
        radiance = "欠損" if result["radiance"] is None else f"{result['radiance']:.2f}"
        index = "-" if result["index"] is None else f"{result['index']:.2f}"
        lines.append(f"{result['id']:<24} {radiance:>14} {result['validPixels']:>4} {index:>8} "
                     f"{current[result['id']]:>6}")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("raster", type=Path, help="EOG VNL v2.2 の average_masked GeoTIFF（.tif または .tif.gz）")
    parser.add_argument("--year", type=int, help="データの年。省略するとファイル名から取る")
    parser.add_argument("--archive", type=Path, help="配布された .tif.gz（記録に名前と SHA-256 を残す）")
    parser.add_argument("--spots", type=Path, default=SPOTS)
    parser.add_argument("--record", type=Path, default=RECORD)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", dest="write", action="store_false", help="表を出すだけ（既定）")
    mode.add_argument("--write", dest="write", action="store_true", help="spots.json と記録を書き換える")
    parser.set_defaults(write=False)
    args = parser.parse_args(argv)

    if not args.raster.is_file():
        parser.error(f"ファイルがありません: {args.raster}")
    if args.archive and not args.archive.is_file():
        parser.error(f"ファイルがありません: {args.archive}")
    year = args.year or guess_year(args.raster)
    if year is None:
        parser.error("ファイル名から年が分かりません。--year で指定してください")

    spots = json.loads(args.spots.read_text(encoding="utf-8"))
    results = sample_spots(args.raster, spots)
    print(f"{source_label(year)}  {args.raster.name}")
    print(format_table(spots, results))
    missing = [result["id"] for result in results if result["index"] is None]
    for spot_id in missing:
        print(f"警告: {spot_id} は 3×3 画素がすべて欠損のため、値を更新しません", file=sys.stderr)

    if not args.write:
        print("（確認のみ。書き換えるには --write を付ける）")
        return 0
    write_json(args.spots, apply(spots, results, year))
    write_json(args.record, record(args.raster, year, results, args.archive))
    print(f"書き換えました: {args.spots} / {args.record}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
