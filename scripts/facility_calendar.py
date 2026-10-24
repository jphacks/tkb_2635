"""内閣府の祝日CSVで、休日営業時間と定期休室日を日付ごとに展開する。"""

import calendar
import csv
import io
from datetime import date, timedelta

from facility_sources import SourceError


def holidays_from_csv(value, year):
    rows = csv.reader(io.StringIO(value))
    header = next(rows, [])
    if not header or "国民の祝日" not in header[0]:
        raise SourceError("祝日CSVの形式が変わりました")
    holidays = set()
    for row in rows:
        if len(row) >= 2 and row[0]:
            parts = [int(p) for p in row[0].split("/")]
            holidays.add(date(*parts))
    years = sorted({d.year for d in holidays if d.year >= year})
    if (year not in years or years != list(range(year, max(years, default=year) + 1))
            or any(sum(d.year == y for d in holidays) < 16 for y in years)):
        raise SourceError("当年以降の祝日データが不足しています")
    return holidays, years


def add_calendar(patch, kind, holidays, years):
    hours = patch["openingHours"]
    overrides = {}
    for year in years:
        if kind == "kitte":
            weekend = hours["weeklyOverrides"]["1"]
            overrides.update({d.isoformat(): dict(weekend) for d in sorted(holidays) if d.year == year})
        else:
            closed = {date(year, 1, 2), date(year, 1, 3), *(date(year, 12, d) for d in (29, 30, 31))}
            for month in range(1, 13):
                tuesdays = [date(year, month, day) for day in range(1, calendar.monthrange(year, month)[1]+1)
                            if date(year, month, day).weekday() == 1]
                for day in (tuesdays[0], tuesdays[2]):
                    while day in holidays or day.weekday() >= 5:
                        day += timedelta(days=1)
                    closed.add(day)
            # 元日は通常の開室時間と異なる可能性があるため、確認できるまで推薦しない。
            overrides[date(year, 1, 1).isoformat()] = {"unverified": True}
            overrides.update({d.isoformat(): {"closed": True} for d in sorted(closed)})
    hours["dateOverrides"] = dict(sorted(overrides.items()))
    hours["validFrom"] = f"{min(years)}-01-01"
    hours["validThrough"] = f"{max(years)}-12-31"
    hours["note"] += f" 祝日・定期休室日の反映範囲は{min(years)}〜{max(years)}年（範囲外は要確認）。"
