#!/usr/bin/env python3
"""1-03〜1-05: 公式情報を検査し、確認できた施設だけ更新する（標準ライブラリのみ）。"""

import argparse
import copy
import hashlib
import json
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from facility_calendar import add_calendar, holidays_from_csv
from facility_sources import HOLIDAYS, KITTE, SKY, TOCHO, download, parse_kitte, parse_sky, parse_tocho, sky_script, text

ROOT = Path(__file__).resolve().parents[1]
SPOTS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/spots.json"
EVIDENCE = ROOT / "docs/facilities/official-checks.json"
TARGETS = json.loads((Path(__file__).parent / "official_facilities.json").read_text())


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True).encode()).hexdigest()


def official_patch(adapter, url, fetch):
    if adapter == "sky":
        page = fetch(url)
        app = sky_script(page, "/pages/_app-", fetch)
        ticket = sky_script(page, "/pages/ticket-", fetch)
        return parse_sky(app, ticket), None
    if adapter == "tocho":
        html = fetch(url)
        visible = text(html)
        section = visible[visible.index("展望室の混雑状況"):visible.index("貸切イベント・パーティー利用")]
        return parse_tocho(html), digest(section)
    if adapter != "kitte":
        raise ValueError(f"未対応の取得方式: {adapter}")
    html = fetch(url)
    visible = text(html)
    section = visible[visible.index("Roof Garden"):visible.index("SHOP SEARCH")]
    return parse_kitte(html), digest(section)


def update(spots, evidence, fetch=download, today=None):
    today = today or datetime.now(ZoneInfo("Asia/Tokyo")).date()
    updated = copy.deepcopy(spots)
    checks = copy.deepcopy(evidence)
    result = {"checkedAt": today.isoformat(), "changed": [], "errors": {}, "unchanged": []}
    cache = {}

    def cached(url):
        if url not in cache:
            cache[url] = fetch(url)
        return cache[url]

    for spot_id, target in TARGETS.items():
        try:
            task, url, adapter = target["task"], target["url"], target["adapter"]
            spot = next(s for s in updated if s["id"] == spot_id)
            patch, source_digest = official_patch(adapter, url, cached)
            sources = [url]
            if adapter != "sky":
                holidays, years = holidays_from_csv(cached(HOLIDAYS), today.year)
                add_calendar(patch, adapter, holidays, years)
                sources.append(HOLIDAYS)
            else:
                sources.insert(0, SKY)
            check = {"task": task, "sources": sources, "factsHash": digest(patch),
                     "sourceSectionHash": source_digest,
                     "unconfirmed": ["正確な観測可能方位・高度", "近傍照明の段階評価", "当日の臨時閉鎖・混雑・空席"]}
            previous = checks.get(spot_id, {})
            different = any(spot.get(k) != v for k, v in patch.items())
            # 確認日だけの変更で毎日PRを作らない。チェック実行日はActionsのレポートに記録する。
            if different or {k: v for k, v in previous.items() if k != "lastChangedAt"} != check:
                spot.update(patch)
                spot["lastVerifiedAt"] = today.isoformat()
                # 照明や窓の向きは推測で埋めず、既存の未確認状態を維持する。
                check["lastChangedAt"] = today.isoformat()
                checks[spot_id] = check
                result["changed"].append(spot_id)
            else:
                result["unchanged"].append(spot_id)
        except (OSError, ValueError, KeyError, IndexError, StopIteration, TypeError) as error:
            # 施設単位で採用する。部分的な読み取り結果や確認日を上書きしない。
            result["errors"][spot_id] = f"{type(error).__name__}: {error}"
    return updated, checks, result


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, default=Path("/tmp/astera-facility-report.json"))
    parser.add_argument("--write", action="store_true", help="確認できた更新をファイルに書く（省略時は確認のみ）")
    args = parser.parse_args()
    spots = json.loads(SPOTS.read_text())
    evidence = json.loads(EVIDENCE.read_text()) if EVIDENCE.exists() else {}
    updated, checks, result = update(spots, evidence)
    if args.write and result["changed"]:
        write_json(SPOTS, updated)
        write_json(EVIDENCE, checks)
    write_json(args.report, result)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
