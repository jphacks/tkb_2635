"""RiseSetTests の参照値を skyfield で計算する。

使い方: python3 scripts/rise_set_reference.py
- 暦は JPL DE421（~/.cache/skyfield に置く。無ければ初回に取得する）
- 地点は渋谷駅東口（35.658, 139.702816, 標高 0 m）
- 対象の夜は 2026-10-24 12:00 JST 〜 2026-10-25 12:00 JST
- 出入りは「天体の中心が、大気差 34′ を見込んだ地平線（幾何高度 -34′）を通る時刻」
  （almanac.risings_and_settings の radius_degrees=0, horizon_degrees=-34/60）
- 南中は almanac.meridian_transits の上方通過
"""

from datetime import datetime, timedelta, timezone

from skyfield import almanac
from skyfield.api import Loader, Star, wgs84
from skyfield.searchlib import find_maxima

JST = timezone(timedelta(hours=9))
LATITUDE = 35.658
LONGITUDE = 139.702816
HORIZON_DEGREES = -34 / 60
# 暦ファイル（約 17 MB）はリポジトリに入れず、ユーザーのキャッシュに置く
load = Loader("~/.cache/skyfield")


def main() -> None:
    ts = load.timescale()
    eph = load("de421.bsp")
    observer = wgs84.latlon(LATITUDE, LONGITUDE)
    t0 = ts.from_datetime(datetime(2026, 10, 24, 12, tzinfo=JST))
    t1 = ts.from_datetime(datetime(2026, 10, 25, 12, tzinfo=JST))

    # シリウスは J2000.0 の座標（StarCatalog と同じ値）から。skyfield は歳差を入れる
    sirius = Star(ra_hours=6.7525, dec_degrees=-16.716)
    polaris = Star(ra_hours=2.5303, dec_degrees=89.264)
    targets = {"moon": eph["moon"], "sirius": sirius, "polaris": polaris}

    for name, target in targets.items():
        f = almanac.risings_and_settings(eph, target, observer, horizon_degrees=HORIZON_DEGREES)
        times, events = almanac.find_discrete(t0, t1, f)
        for t, e in zip(times, events):
            label = "出" if e == 1 else "入り"
            print(name, label, t.utc_iso(), t.astimezone(JST).strftime("%H:%M:%S JST"))
        g = almanac.meridian_transits(eph, target, observer)
        times, events = almanac.find_discrete(t0, t1, g)
        for t, e in zip(times, events):
            if e == 1:
                print(name, "南中", t.utc_iso(), t.astimezone(JST).strftime("%H:%M:%S JST"))

    # Astera の南中は「高度が一番高い時刻」なので、月はそれも出す
    observer_at = eph["earth"] + observer

    def moon_altitude(t):
        return observer_at.at(t).observe(eph["moon"]).apparent().altaz()[0].degrees

    moon_altitude.step_days = 0.02
    times, altitudes = find_maxima(t0, t1, moon_altitude)
    for t, alt in zip(times, altitudes):
        print("moon 高度極大", t.utc_iso(), t.astimezone(JST).strftime("%H:%M:%S JST"), f"{alt:.2f}°")


if __name__ == "__main__":
    main()
