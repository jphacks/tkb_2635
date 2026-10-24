#!/usr/bin/env python3
"""1-06の確認済み方針を既存地点へ反映する。追加候補の座標や標高は生成しない。"""

import argparse
import copy
import json
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "docs/night-access"
SPOTS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/spots.json"


def in_ranges(day, ranges):
    value = day.strftime("%m-%d")
    return any(start <= value <= end if start <= end else value >= start or value <= end
               for start, end in ranges)


def closed_dates(rule, holidays, years):
    result = set()
    for year in years:
        day = date(year, 1, 1)
        while day.year == year:
            if in_ranges(day, rule["annualClosedRanges"]):
                result.add(day.isoformat())
            if day.weekday() == rule["weeklyClosedWeekday"]:
                closure = day
                while rule["shiftHolidayClosure"] and (closure in holidays or closure.weekday() >= 5):
                    closure += timedelta(days=1)
                if closure.year in years and not in_ranges(closure, rule["annualOpenRanges"]):
                    result.add(closure.isoformat())
            day += timedelta(days=1)
    return sorted(result)


def apply(spots, policy, holidays):
    updated = copy.deepcopy(spots)
    by_id = {spot["id"]: spot for spot in updated}
    if set(policy) - set(by_id):
        raise ValueError("方針に記載した既存地点が見つかりません")
    holiday_dates = {date.fromisoformat(day) for day in holidays["dates"]}
    years = sorted({day.year for day in holiday_dates})
    for spot_id, specification in policy.items():
        patch = copy.deepcopy(specification["patch"])
        if "calendarRule" in specification:
            if not years or years != list(range(years[0], years[-1] + 1)):
                raise ValueError("祝日データの対象年が連続していません")
            for year in years:
                if date(year, 1, 1) not in holiday_dates or date(year, 11, 23) not in holiday_dates:
                    raise ValueError("祝日データに不足があります")
            rules = patch["accessRules"]
            rules["closedDates"] = closed_dates(specification["calendarRule"], holiday_dates, years)
            rules["validFrom"] = f"{years[0]}-01-01"
            rules["validThrough"] = f"{years[-1]}-12-31"
        by_id[spot_id].update(patch)
    return updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    spots = json.loads(SPOTS.read_text())
    policy = json.loads((DIRECTORY / "app-access.json").read_text())
    holidays = json.loads((DIRECTORY / "holidays.json").read_text())
    updated = apply(spots, policy, holidays)
    changed = [after["id"] for before, after in zip(spots, updated) if before != after]
    if args.write and changed:
        SPOTS.write_text(json.dumps(updated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("1-06の反映差分: " + ("、".join(changed) if changed else "なし"))
    return 0 if args.write or not changed else 1


if __name__ == "__main__":
    raise SystemExit(main())
