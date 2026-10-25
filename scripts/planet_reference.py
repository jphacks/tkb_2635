"""PlanetTests の参照値を skyfield で計算する。

使い方: python3 scripts/planet_reference.py
- 暦は JPL DE421（~/.cache/skyfield に置く。無ければ初回に取得する）
- 地点は渋谷駅東口（35.658, 139.702816, 標高 0 m）
- 時刻は 2026-10-24 12:00 UTC と 2026-11-15 09:30 UTC
- 高度・方位は観測地点から見た見かけの位置（光行時間・光行差・章動込み）に、
  気温 10 ℃・気圧 1010 hPa の大気差を入れたもの
- 出力は PlanetTests.swift の `references` にそのまま貼れる形
"""

from datetime import datetime, timezone

from skyfield.api import Loader, wgs84

LATITUDE = 35.658
LONGITUDE = 139.702816
TEMPERATURE_C = 10.0
PRESSURE_MBAR = 1010.0
TIMES = [
    datetime(2026, 10, 24, 12, 0, tzinfo=timezone.utc),
    datetime(2026, 11, 15, 9, 30, tzinfo=timezone.utc),
]
# PlanetCatalog の id → DE421 の天体名
PLANETS = {
    "mercury": "mercury",
    "venus": "venus",
    "mars": "mars",
    "jupiter": "jupiter barycenter",
    "saturn": "saturn barycenter",
}
# 暦ファイル（約 17 MB）はリポジトリに入れず、ユーザーのキャッシュに置く
load = Loader("~/.cache/skyfield")


def main() -> None:
    ts = load.timescale()
    eph = load("de421.bsp")
    observer = eph["earth"] + wgs84.latlon(LATITUDE, LONGITUDE)
    for when in TIMES:
        t = ts.from_datetime(when)
        for planet_id, body in PLANETS.items():
            apparent = observer.at(t).observe(eph[body]).apparent()
            alt, az, _ = apparent.altaz(temperature_C=TEMPERATURE_C, pressure_mbar=PRESSURE_MBAR)
            print(
                f'        Reference(planet: "{planet_id}", time: "{when.strftime("%Y-%m-%dT%H:%M:%SZ")}", '
                f"altitude: {alt.degrees:.3f}, azimuth: {az.degrees:.3f}),"
            )


if __name__ == "__main__":
    main()
