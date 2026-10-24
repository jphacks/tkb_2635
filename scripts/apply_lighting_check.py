#!/usr/bin/env python3
"""近くの照明の段階評価（docs/lighting/assessments.json）を spots.json に反映する。

既定は確認だけ（--dry-run）。--write で spots.json を書き換える。
level が null の地点は触らない。決まりは docs/lighting/README.md
"""

import argparse
import copy
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPOTS = ROOT / "Packages/StarCore/Sources/StarCore/Resources/spots.json"
ASSESSMENTS = ROOT / "docs/lighting/assessments.json"

LEVEL_MIN, LEVEL_MAX = 0, 3
METHODS = ("desk", "onsite")
DATE_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# 新しいキーは地域の光害の項目のすぐ後ろに置く（Spot.swift の並びと同じ）
ANCHOR_KEYS = ("regionalLightMeasuredAt", "regionalLightSource", "regionalLightIndex")


def validate(assessments, spot_ids):
    """記録の形を確かめ、問題の一覧を返す。空なら問題なし。"""
    errors = []
    for spot_id, entry in assessments.items():
        if spot_id not in spot_ids:
            errors.append(f"{spot_id}: spots.json に無い地点です")
        level = entry.get("level")
        if level is not None and (isinstance(level, bool) or not isinstance(level, int)
                                  or not LEVEL_MIN <= level <= LEVEL_MAX):
            errors.append(f"{spot_id}: level は {LEVEL_MIN}〜{LEVEL_MAX} の整数か null にしてください（{level!r}）")
        if entry.get("method") not in METHODS:
            errors.append(f"{spot_id}: method は {' / '.join(METHODS)} のどちらかにしてください")
        if not DATE_PATTERN.match(str(entry.get("checkedAt", ""))):
            errors.append(f"{spot_id}: checkedAt は YYYY-MM-DD にしてください")
        if level is not None and not entry.get("sources"):
            errors.append(f"{spot_id}: level を入れるときは sources に出典の URL を書いてください")
    return errors


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


def apply(spots, assessments):
    """level がある地点だけ近傍照明の 3 項目を書き換えた新しい一覧を返す。"""
    updated = []
    for spot in spots:
        entry = assessments.get(spot["id"])
        if entry is None or entry.get("level") is None:
            updated.append(copy.deepcopy(spot))
            continue
        updates = {"localGlareLevel": entry["level"],
                   "lightingCheckDate": entry["checkedAt"],
                   "lightingCheckMethod": entry["method"]}
        # 既に反映済みの地点は localGlareLevel の位置のまま差し替える
        anchor = next((key for key in ("localGlareLevel", *ANCHOR_KEYS) if key in spot), None)
        if anchor is None:
            updated.append({**copy.deepcopy(spot), **updates})
        else:
            updated.append(with_inserted(copy.deepcopy(spot), updates, anchor))
    return updated


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def format_table(spots, assessments):
    lines = [f"{'地点':<24} {'今の値':>6} {'新しい値':>8} {'方法':>6} {'確認日':>10}"]
    for spot in spots:
        entry = assessments.get(spot["id"]) or {}
        current = spot.get("localGlareLevel")
        level = entry.get("level")
        new = "触らない" if level is None else str(level)
        lines.append(f"{spot['id']:<24} {str(current):>6} {new:>8} {entry.get('method', '-'):>6} "
                     f"{entry.get('checkedAt', '-'):>10}")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--spots", type=Path, default=SPOTS)
    parser.add_argument("--assessments", type=Path, default=ASSESSMENTS)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", dest="write", action="store_false", help="表を出すだけ（既定）")
    mode.add_argument("--write", dest="write", action="store_true", help="spots.json を書き換える")
    parser.set_defaults(write=False)
    args = parser.parse_args(argv)

    spots = json.loads(args.spots.read_text(encoding="utf-8"))
    assessments = json.loads(args.assessments.read_text(encoding="utf-8"))
    errors = validate(assessments, {spot["id"] for spot in spots})
    if errors:
        for error in errors:
            print(f"エラー: {error}", file=sys.stderr)
        return 1

    print(format_table(spots, assessments))
    missing = [spot["id"] for spot in spots if spot["id"] not in assessments]
    for spot_id in missing:
        print(f"警告: {spot_id} は assessments.json に記録がありません", file=sys.stderr)

    updated = apply(spots, assessments)
    changed = [after["id"] for before, after in zip(spots, updated) if before != after]
    print("変わる地点: " + ("、".join(changed) if changed else "なし"))
    if not args.write:
        print("（確認のみ。書き換えるには --write を付ける）")
        return 0
    if changed:
        write_json(args.spots, updated)
        print(f"書き換えました: {args.spots}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
