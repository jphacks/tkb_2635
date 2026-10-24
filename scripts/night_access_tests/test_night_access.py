"""通信せず、変更検知・未確認の維持・取得失敗を検証する。"""

import json
import io
import sys
import tempfile
import unittest
from pathlib import Path
from socket import timeout as SocketTimeout
from unittest.mock import patch
from urllib.request import Request
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_night_access as runner
import night_access_sources as adapter
from night_access_sources import OfficialRedirect, snapshot

FIXTURE = Path(__file__).parent / "fixtures/park.html"
SOURCE = {"url": "https://example.org/park/", "identity": "試験公園", "label": "試験公園"}


class NightAccessTests(unittest.TestCase):
    def setUp(self):
        self.html = FIXTURE.read_text(encoding="utf-8")
        self.baseline = {"snapshots": {"park": snapshot(SOURCE, self.html)}}

    def check(self, html):
        return runner.check({"park": SOURCE}, self.baseline, lambda _: html, "2026-10-24T06:37:00+09:00")

    def test_identical_page_is_unchanged(self):
        report = self.check(self.html)
        self.assertEqual(report["unchanged"], ["park"])
        self.assertFalse(report["requiresReview"])

    def test_opening_time_change_requires_review(self):
        report = self.check(self.html.replace("22:00", "20:00"))
        self.assertEqual(report["changed"], ["park"])
        self.assertTrue(report["requiresReview"])

    def test_announcement_link_replacement_is_detected(self):
        report = self.check(self.html.replace("closure-1.html", "closure-2.html"))
        self.assertEqual(report["changed"], ["park"])

    def test_script_and_navigation_do_not_create_false_change(self):
        report = self.check(self.html.replace("daily-clock-1", "daily-clock-2").replace("案内1", "案内2"))
        self.assertEqual(report["unchanged"], ["park"])

    def test_whitespace_is_normalized(self):
        self.assertEqual(self.check(self.html.replace("開園時間", "  開園時間\n\n"))["unchanged"], ["park"])

    def test_different_facility_or_error_page_is_not_accepted(self):
        report = self.check(self.html.replace("試験公園", "閉鎖したサイト"))
        self.assertEqual(list(report["errors"]), ["park"])
        self.assertNotIn("park", report["snapshots"])
        self.assertEqual(self.baseline["snapshots"]["park"]["title"], "試験公園 | 公式")

    def test_failure_does_not_hide_success_of_other_source(self):
        def fetch(url):
            if url.endswith("failure/"):
                raise OSError("通信失敗")
            return self.html
        report = runner.check({"park": SOURCE, "failure": {**SOURCE, "url": "https://example.org/failure/"}},
                              self.baseline, fetch)
        self.assertEqual(report["unchanged"], ["park"])
        self.assertIn("failure", report["errors"])

    def test_missing_section_is_a_failure(self):
        source = {**SOURCE, "sections": [["存在しない見出し", "終わり"]]}
        self.assertIn("park", runner.check({"park": source}, self.baseline, lambda _: self.html)["errors"])

    def test_changed_url_is_reviewed_even_when_text_is_unchanged(self):
        changed = {**SOURCE, "url": "https://example.org/replacement/"}
        # 絶対リンクの本文で比較し、URL自体が比較対象であることも確認する。
        html = self.html.replace('href="closure-1.html"', 'href="https://example.org/closure-1.html"')
        baseline = {"snapshots": {"park": snapshot(SOURCE, html)}}
        self.assertEqual(runner.check({"park": changed}, baseline, lambda _: html)["changed"], ["park"])

    def test_removed_source_requires_review(self):
        report = runner.check({}, self.baseline)
        self.assertEqual(report["removed"], ["park"])
        self.assertTrue(report["requiresReview"])

    def test_manual_reference_is_explicit_and_never_fetched(self):
        source = {**SOURCE, "monitor": False, "manualCheckReason": "本文を取得できない補助資料"}
        def fetch(_):
            self.fail("手動参照は自動取得しない")
        report = runner.check({"manual": source}, {}, fetch)
        self.assertEqual(report["manualSources"], ["manual"])
        self.assertIn("手動参照", runner.markdown(report, {"manual": source}, []))

    def test_disabling_a_previously_monitored_source_requires_review(self):
        source = {**SOURCE, "monitor": False}
        report = runner.check({"park": source}, self.baseline)
        self.assertEqual(report["removed"], ["park"])
        self.assertTrue(report["requiresReview"])

    def test_transient_http_failure_is_retried_once(self):
        error = HTTPError(SOURCE["url"], 503, "Unavailable", {}, None)
        with patch.object(adapter, "download_once", side_effect=[error, self.html]) as fetch, patch.object(adapter.time, "sleep"):
            self.assertEqual(adapter.download(SOURCE["url"]), self.html)
            self.assertEqual(fetch.call_count, 2)

    def test_bad_page_is_not_retried(self):
        with patch.object(adapter, "download_once", side_effect=ValueError("形式変更")) as fetch:
            with self.assertRaises(ValueError):
                adapter.download(SOURCE["url"])
            self.assertEqual(fetch.call_count, 1)

    def test_socket_timeout_is_retried_on_python39_too(self):
        with patch.object(adapter, "download_once", side_effect=[SocketTimeout(), self.html]) as fetch, patch.object(adapter.time, "sleep"):
            self.assertEqual(adapter.download(SOURCE["url"]), self.html)
            self.assertEqual(fetch.call_count, 2)

    def test_https_and_host_must_not_change_on_redirect(self):
        handler = OfficialRedirect()
        request = Request(SOURCE["url"])
        for url in ("https://unrelated.example/", "http://example.org/park/"):
            with self.assertRaises(ValueError):
                handler.redirect_request(request, None, 302, "", {}, url)

    def test_unknown_access_stays_unknown_even_when_source_is_unchanged(self):
        candidate = {"name": "試験公園", "sourceIds": ["park"], "nightAccess": None}
        summary = runner.markdown(self.check(self.html), {"park": SOURCE}, [candidate])
        self.assertIn("未確認", summary)
        self.assertIsNone(candidate["nightAccess"])

    def test_accept_does_not_replace_baseline_after_partial_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, value in (("sources", {"park": SOURCE}), ("candidates", []), ("baseline", self.baseline)):
                runner.write_json(root / (name + ".json"), value)
            before = (root / "baseline.json").read_bytes()
            report = runner.check({"park": SOURCE}, self.baseline, lambda _: "unavailable")
            arguments = ["check", "--directory", directory, "--output", str(root / "output"), "--accept-baseline"]
            with patch.object(sys, "argv", arguments), patch.object(runner, "check", return_value=report), patch("sys.stdout", new_callable=io.StringIO):
                self.assertEqual(runner.main(), 1)
            self.assertEqual((root / "baseline.json").read_bytes(), before)

    def test_twenty_candidates_and_existing_six_are_tracked(self):
        directory = runner.DEFAULT_DIRECTORY
        candidates = json.loads((directory / "candidates.json").read_text())
        sources = json.loads((directory / "sources.json").read_text())
        self.assertEqual(len(candidates), 20)
        self.assertEqual(len({c["id"] for c in candidates}), 20)
        self.assertEqual(sum(c["existingSpot"] for c in candidates), 6)
        self.assertEqual(set(sources), {s for c in candidates for s in c["sourceIds"]})
        for candidate in candidates:
            self.assertTrue(any(sources[key].get("monitor") is not False for key in candidate["sourceIds"]))
            self.assertIsNone(candidate["localGlareLevel"])
            if candidate["nightAccess"] is None:
                self.assertIsNone(candidate["accessVerifiedAt"])


if __name__ == "__main__":
    unittest.main()
