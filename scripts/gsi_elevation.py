#!/usr/bin/env python3
"""国土地理院の標高 API で、地点ごとの地面の標高（DEM）を取り、床面標高に反映する（task.md の 2-06・1-07）。

  python3 scripts/gsi_elevation.py fetch           # 全地点の標高を取り docs/data/gsi-elevation.json に保存（1 秒に 1 回）
  python3 scripts/gsi_elevation.py apply           # 保存した応答から反映案を表示するだけ
  python3 scripts/gsi_elevation.py apply --write   # spots.json と docs/data/gsi-elevation.json を書き換える

反映の決まり（根拠は docs/data/gsi-elevation.md）
- 地上の地点（公園・広場・河川敷）: floorElevation = DEM。ただし建物データのシーンの地盤標高（PLATEAU）と
  DEM の差が GROUND_TOLERANCE を超える地点は変えずに「要確認」とする（建物の高さと基準がずれるため）
- 展望台・屋上: docs/facilities/observatory-heights.json の公式の高さを使う。地上 ◯ m なら DEM ＋ 高さ、
  海抜 ◯ m ならその値。公式で確かめられていない地点は変えない
"""

import argparse
import copy
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPOTS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/spots.json"
BUILDINGS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/buildings.json"
RECORD = ROOT / "docs/data/gsi-elevation.json"
OBSERVATORY_HEIGHTS = ROOT / "docs/facilities/observatory-heights.json"

API = "https://cyberjapandata2.gsi.go.jp/general/dem/scripts/getelevation.php"
REQUEST_INTERVAL = 1.0      # 通信の間隔 [s]。地理院の API に負荷をかけない
REQUEST_TIMEOUT = 20.0      # [s]
GROUND_TOLERANCE = 2.0      # シーンの地盤標高と DEM の差の許容 [m]
ELEVATION_DIGITS = 1
GROUND_CATEGORIES = {"park", "plaza", "riverside"}
ELEVATED_CATEGORIES = {"observatory", "rooftop"}
NO_DATA = "-----"           # 地理院の API が標高を返せないときの値
USER_AGENT = "Astera-JPHACKS2026 (https://github.com/jphacks/tkb_2635)"


def api_url(latitude, longitude):
    query = urllib.parse.urlencode({"lon": longitude, "lat": latitude, "outtype": "JSON"})
    return f"{API}?{query}"


def parse_response(response):
    """API の応答から (標高 [m], 標高の出典) を取り出す。標高が無いときは (None, 出典)。"""
    if not isinstance(response, dict):
        raise ValueError(f"応答が JSON のオブジェクトではない: {response!r}")
    raw = response.get("elevation")
    source = response.get("hsrc")
    if raw is None or raw == NO_DATA or source == NO_DATA:
        return None, None if source == NO_DATA else source
    try:
        value = float(raw)
    except (TypeError, ValueError) as error:
        raise ValueError(f"標高が数値でない: {raw!r}") from error
    return value, source


def dem_label(source):
    """「5m（写真測量）」→「DEM5A」のような短い名前。分からない出典はそのまま返す。"""
    labels = {"1m（レーザ）": "DEM1A", "5m（レーザ）": "DEM5A", "5m（写真測量）": "DEM5B",
              "5m（航空レーザ測深）": "DEM5C", "10m": "DEM10B"}
    return labels.get(source, source)


def fetch_one(latitude, longitude):
    request = urllib.request.Request(api_url(latitude, longitude), headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch(spots, fetched_at):
    records = {}
    for index, spot in enumerate(spots):
        if index:
            time.sleep(REQUEST_INTERVAL)
        latitude, longitude = spot["latitude"], spot["longitude"]
        try:
            response = fetch_one(latitude, longitude)
        except Exception as error:  # 1 地点の失敗で全体を止めない。記録に残して後で取り直す
            print(f"{spot['id']}: 取得できない（{error}）", file=sys.stderr)
            response = None
        records[spot["id"]] = {"latitude": latitude, "longitude": longitude,
                               "url": api_url(latitude, longitude), "response": response}
        print(spot["id"], response)
    return {"fetchedAt": fetched_at, "api": API, "elevations": records}


def scene_grounds(buildings):
    return {scene["id"]: scene["groundElevation"] for scene in buildings}


def plan(spots, record, grounds, heights):
    """地点ごとの反映案（DEM・シーンの地盤・差・新しい床面標高・出典・判定）を返す。"""
    fetched_at = record["fetchedAt"]
    rows = []
    for spot in spots:
        entry = record["elevations"].get(spot["id"])
        dem, source = parse_response(entry["response"]) if entry and entry["response"] else (None, None)
        ground = grounds.get(spot.get("sceneId"))
        diff = None if dem is None or ground is None else round(dem - ground, 2)
        row = {"id": spot["id"], "category": spot["category"], "dem": dem, "demSource": source,
               "sceneGround": ground, "difference": diff, "current": spot["floorElevation"],
               "floorElevation": None, "floorElevationSource": None, "status": None}
        if dem is None:
            row["status"] = "DEM なし（変えない）"
        elif spot["category"] in GROUND_CATEGORIES:
            if diff is not None and abs(diff) > GROUND_TOLERANCE:
                row["status"] = f"要確認（シーンの地盤との差 {diff:+.1f}m、変えない）"
            else:
                row["floorElevation"] = round(dem, ELEVATION_DIGITS)
                row["floorElevationSource"] = f"国土地理院 {dem_label(source)} {fetched_at}"
                row["status"] = "DEM を反映"
        elif spot["category"] in ELEVATED_CATEGORIES:
            official = heights.get(spot["id"])
            if not official or official.get("aboveGround") is None and official.get("aboveSeaLevel") is None:
                row["status"] = "公式未確認（変えない）"
            elif official.get("aboveSeaLevel") is not None:
                row["floorElevation"] = float(official["aboveSeaLevel"])
                row["floorElevationSource"] = (f"公式サイト 海抜{official['aboveSeaLevel']:g}m {official['verifiedAt']} "
                                               f"{official['url']}")
                row["status"] = "公式の海抜を反映"
            else:
                height = float(official["aboveGround"])
                row["floorElevation"] = round(dem + height, ELEVATION_DIGITS)
                row["floorElevationSource"] = (f"公式サイト 地上{height:g}m + 国土地理院 {dem_label(source)} "
                                               f"{dem:g}m {official['verifiedAt']} {official['url']}")
                row["status"] = "公式の高さ + DEM を反映"
        else:
            row["status"] = "種類が対象外（変えない）"
        rows.append(row)
    return rows


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


def apply(spots, rows):
    by_id = {row["id"]: row for row in rows}
    updated = []
    for spot in spots:
        row = by_id.get(spot["id"])
        if row is None or row["floorElevation"] is None:
            updated.append(copy.deepcopy(spot))
            continue
        updates = {"floorElevation": row["floorElevation"], "floorElevationSource": row["floorElevationSource"]}
        updated.append(with_inserted(spot, updates, after="floorElevation"))
    return updated


def load(path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["fetch", "apply"])
    parser.add_argument("--write", action="store_true", help="apply で spots.json を書き換える")
    args = parser.parse_args()

    spots = load(SPOTS)
    if args.command == "fetch":
        dump(RECORD, fetch(spots, date.today().isoformat()))
        print(f"保存: {RECORD.relative_to(ROOT)}")
        return

    record = load(RECORD)
    heights = load(OBSERVATORY_HEIGHTS)["spots"] if OBSERVATORY_HEIGHTS.exists() else {}
    rows = plan(spots, record, scene_grounds(load(BUILDINGS)), heights)
    for row in rows:
        print(f"{row['id']:28} DEM={row['dem']!s:>6} 地盤={row['sceneGround']!s:>5} 差={row['difference']!s:>6} "
              f"{row['current']!s:>6} → {row['floorElevation']!s:>6}  {row['status']}")
    if args.write:
        dump(SPOTS, apply(spots, rows))
        record["applied"] = rows
        dump(RECORD, record)
        print("書き換えた: spots.json と gsi-elevation.json")


if __name__ == "__main__":
    main()
