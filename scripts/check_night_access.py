#!/usr/bin/env python3
"""1-06: 公式案内の変更を記録する。夜間の入場可否・アプリの地点情報は自動更新しない。"""

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from night_access_sources import download, snapshot

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DIRECTORY = ROOT / "docs/night-access"


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def check(sources, baseline, fetch=download, checked_at=None):
    report = {"checkedAt": checked_at or datetime.now(ZoneInfo("Asia/Tokyo")).isoformat(),
              "changed": [], "unchanged": [], "new": [], "errors": {}, "snapshots": {}, "manualSources": []}
    for source_id, source in sources.items():
        if source.get("monitor") is False:
            report["manualSources"].append(source_id)
            continue
        try:
            current = snapshot(source, fetch(source["url"]))
            report["snapshots"][source_id] = current
            previous = baseline.get("snapshots", {}).get(source_id)
            if previous is None:
                report["new"].append(source_id)
            elif any(previous.get(key) != current[key] for key in ("url", "sha256")):
                report["changed"].append(source_id)
            else:
                report["unchanged"].append(source_id)
        except (OSError, ValueError, LookupError) as error:
            report["errors"][source_id] = f"{type(error).__name__}: {error}"
    active = {key for key, source in sources.items() if source.get("monitor") is not False}
    report["removed"] = sorted(set(baseline.get("snapshots", {})) - active)
    report["requiresReview"] = bool(report["changed"] or report["new"] or report["removed"] or report["errors"])
    return report


def markdown(report, sources, candidates):
    lines = ["# 1-06 夜間利用の公式情報確認", "", f"確認日時: {report['checkedAt']}", "",
             "これは公式ページの変更検知です。当日の開放や夜間の安全を判定するものではありません。", "",
             f"変更 {len(report['changed'])} / 変更なし {len(report['unchanged'])} / 初回 {len(report['new'])} / "
             f"取得失敗 {len(report['errors'])} / 監視対象から削除 {len(report['removed'])}", ""]
    if report["manualSources"]:
        lines += [f"補助資料 {len(report['manualSources'])}件は手動参照です。自動では取得しません。", ""]
        for source_id in report["manualSources"]:
            source = sources[source_id]
            lines += [f"- 手動参照: [{source['label']}]({source['url']}) — {source['manualCheckReason']}"]
        lines += [""]
    for source_id in report["changed"] + report["new"] + list(report["errors"]):
        source = sources[source_id]
        affected = [item["name"] for item in candidates if source_id in item["sourceIds"]]
        # 外部本文はJSONに格納し、ActionsのMarkdownへ直接挿入しない。
        lines += [f"- [{source['label']}]({source['url']}) — 対象: {'、'.join(affected)}"]
        if source_id in report["errors"]:
            lines += ["  取得失敗。直前の確認結果を維持し、実行記録JSONを確認してください。"]
    if report["removed"]:
        lines += ["", "監視対象からの削除も確認が必要です: " + ", ".join(report["removed"])]
    if not report["requiresReview"]:
        lines += ["監視対象ページに変更はありません。未確認地点の入場可否は未確認のままです。"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=DEFAULT_DIRECTORY)
    parser.add_argument("--output", type=Path, default=Path("/tmp/astera-night-access"))
    parser.add_argument("--accept-baseline", action="store_true", help="内容を人が確認して比較基準を更新する")
    parser.add_argument("--fail-on-change", action="store_true", help="変更時も終了コード2にして要確認とする")
    args = parser.parse_args()
    sources = json.loads((args.directory / "sources.json").read_text(encoding="utf-8"))
    candidates = json.loads((args.directory / "candidates.json").read_text(encoding="utf-8"))
    path = args.directory / "baseline.json"
    baseline = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    report = check(sources, baseline)
    write_json(args.output / "report.json", report)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "summary.md").write_text(markdown(report, sources, candidates), encoding="utf-8")
    if args.accept_baseline and not report["errors"]:
        # 一部だけ失敗した結果を「新しい基準」として採用しない。
        # リポジトリには公式本文の複製を置かず、比較用の指紋だけを保存する。
        fingerprints = {key: {field: value[field] for field in ("url", "title", "sha256")}
                        for key, value in report["snapshots"].items()}
        write_json(path, {"capturedAt": report["checkedAt"], "snapshots": fingerprints})
    print((args.output / "summary.md").read_text(encoding="utf-8"))
    if report["errors"]:
        return 1
    return 2 if args.fail_on_change and report["requiresReview"] else 0


if __name__ == "__main__":
    sys.exit(main())
