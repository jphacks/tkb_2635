#!/usr/bin/env python3
"""skyfield（JPL DE421）で月・太陽・恒星の見かけの位置を計算し、StarCore のテスト用の参照値を書き出す（3-03）。

Swift 側（Astro.swift）と同じ条件にそろえるため、
- 高度・方位は観測地点から見た見かけの位置（大気差あり、10°C・1013 hPa）
- 恒星の J2000.0 座標は StarCatalog.swift から読み取る（値の二重管理を避ける）
とする。結果の読み方は docs/astro/verification.md を参照。

使い方:
    python3 -m pip install skyfield
    python3 scripts/verify_astro.py            # フィクスチャを書き出す
    python3 scripts/verify_astro.py --check    # 書き出さずに件数と大きさだけ表示

天体暦 de421.bsp（約 17 MB）は初回に SKYFIELD_DATA（既定は ~/.cache/skyfield）へ取得する。
"""

import argparse
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from skyfield import almanac
from skyfield.api import Loader, Star, wgs84

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "Packages/StarCore/Sources/StarCore/Astro/StarCatalog.swift"
OUTPUT = ROOT / "Packages/StarCore/Tests/StarCoreTests/Fixtures/astro_reference.json"
DATA_DIR = Path(os.environ.get("SKYFIELD_DATA", Path.home() / ".cache/skyfield"))

EPHEMERIS = "de421.bsp"
START = datetime(2026, 10, 24, tzinfo=timezone.utc)
END = datetime(2026, 11, 30, 18, tzinfo=timezone.utc)
STEP = timedelta(hours=6)
TEMPERATURE_C = 10.0
PRESSURE_MBAR = 1013.0
DIGITS = 4
MAX_BYTES = 200 * 1024

OBSERVERS = [
    {"id": "shibuya", "name": "渋谷駅東口", "latitude": 35.658, "longitude": 139.702816},
    {"id": "kasai", "name": "葛西臨海公園", "latitude": 35.643, "longitude": 139.861},
]
STAR_IDS = ["vega", "sirius", "arcturus", "polaris", "antares", "deneb"]

# StarCatalog.swift の 1 行: Star(id: "sirius", name: "...", rightAscension: 6.7525, declination: -16.716, ...)
STAR_PATTERN = re.compile(
    r'Star\(id:\s*"(?P<id>[^"]+)".*?rightAscension:\s*(?P<ra>-?[\d.]+),\s*declination:\s*(?P<dec>-?[\d.]+)'
)


def read_catalog(path: Path) -> dict[str, tuple[float, float]]:
    """StarCatalog.swift から {id: (赤経[時], 赤緯[度])} を取り出す。"""
    stars = {m["id"]: (float(m["ra"]), float(m["dec"])) for m in STAR_PATTERN.finditer(path.read_text())}
    missing = [s for s in STAR_IDS if s not in stars]
    if missing:
        raise SystemExit(f"StarCatalog.swift に見つからない恒星: {missing}")
    return stars


def times() -> list[datetime]:
    result, t = [], START
    while t <= END:
        result.append(t)
        t += STEP
    return result


def apparent(observer, target, t) -> dict[str, float]:
    alt, az, _ = observer.at(t).observe(target).apparent().altaz(
        temperature_C=TEMPERATURE_C, pressure_mbar=PRESSURE_MBAR
    )
    return {"altitude": round(alt.degrees, DIGITS), "azimuth": round(az.degrees, DIGITS)}


def build() -> dict:
    loader = Loader(str(DATA_DIR))
    ts = loader.timescale()
    eph = loader(EPHEMERIS)
    earth, moon, sun = eph["earth"], eph["moon"], eph["sun"]
    catalog = read_catalog(CATALOG)
    stars = {sid: Star(ra_hours=catalog[sid][0], dec_degrees=catalog[sid][1]) for sid in STAR_IDS}

    samples = []
    for obs in OBSERVERS:
        site = earth + wgs84.latlon(obs["latitude"], obs["longitude"])
        for dt in times():
            t = ts.from_datetime(dt)
            moon_pos = apparent(site, moon, t)
            moon_pos["illuminatedFraction"] = round(float(almanac.fraction_illuminated(eph, "moon", t)), DIGITS)
            samples.append({
                "observer": obs["id"],
                "time": dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "moon": moon_pos,
                "sun": apparent(site, sun, t),
                "stars": {sid: apparent(site, star, t) for sid, star in stars.items()},
            })

    return {
        "meta": {
            "source": f"skyfield {__import__('skyfield').__version__} + JPL {EPHEMERIS}",
            "generator": "scripts/verify_astro.py",
            "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "ephemeris": EPHEMERIS,
            "refraction": {"temperatureC": TEMPERATURE_C, "pressureMbar": PRESSURE_MBAR},
            "notes": "高度・方位は観測地点から見た見かけの位置（度、方位は北=0°・東=90°）。"
                     "恒星は StarCatalog.swift の J2000.0 座標を skyfield で観測日の見かけの位置に変換したもの",
        },
        "observers": OBSERVERS,
        "stars": [{"id": sid, "rightAscension": catalog[sid][0], "declination": catalog[sid][1]} for sid in STAR_IDS],
        "samples": samples,
    }


def dump(data: dict) -> str:
    """差分を読みやすくするため、メタ情報は整形し、samples は 1 件 1 行で書く。"""
    compact = {"ensure_ascii": False, "separators": (",", ":")}
    head = {k: v for k, v in data.items() if k != "samples"}
    lines = [json.dumps(s, **compact) for s in data["samples"]]
    body = json.dumps(head, ensure_ascii=False, indent=2)[:-2]
    return body + ',\n  "samples": [\n    ' + ",\n    ".join(lines) + "\n  ]\n}\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="書き出さずに件数と大きさだけ表示する")
    args = parser.parse_args()

    data = build()
    text = dump(data)
    size = len(text.encode())
    print(f"{len(data['samples'])} 件、{size / 1024:.1f} KB")
    if size > MAX_BYTES:
        print(f"大きすぎる（上限 {MAX_BYTES // 1024} KB）", file=sys.stderr)
        return 1
    if not args.check:
        OUTPUT.write_text(text)
        print(f"書き出し: {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
