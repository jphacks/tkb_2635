import copy
import json
import sys
import unittest
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from facility_sources import HOLIDAYS, KITTE, SKY, TOCHO, SourceError, parse_kitte, parse_sky
from update_official_facilities import SPOTS, update

FIXTURES = Path(__file__).parent / "fixtures"


class FacilityUpdateTests(unittest.TestCase):
    def setUp(self):
        self.spots = json.loads(SPOTS.read_text())
        self.pages = {
            SKY + "ticket/": "sky_ticket.html",
            SKY + "_next/static/chunks/pages/_app-fixture.js": "sky_app.js",
            SKY + "_next/static/chunks/pages/ticket-fixture.js": "sky_ticket.js",
            TOCHO: "tocho.html", KITTE: "kitte.html", HOLIDAYS: "holidays.csv",
        }
        self.content = {url: (FIXTURES / name).read_text() for url, name in self.pages.items()}

    def run_update(self, spots=None, evidence=None, today=date(2026, 10, 24)):
        return update(spots if spots is not None else self.spots, evidence or {}, self.content.__getitem__, today)

    def test_official_values_and_unconfirmed_fields(self):
        updated, checks, report = self.run_update()
        self.assertEqual(report["errors"], {})
        self.assertEqual(len(report["changed"]), 3)
        spots = {s["id"]: s for s in updated}
        self.assertIn("2,700", spots["shibuya_sky"]["admissionFee"])
        self.assertEqual(spots["shibuya_sky"]["openingHours"]["lastAdmission"], "21:20")
        self.assertEqual(spots["tocho_observatory"]["openingHours"]["lastAdmission"], "21:30")
        self.assertEqual(spots["kitte_garden"]["openingHours"]["weeklyOverrides"]["7"]["close"], "22:00")
        self.assertIsNone(spots["kitte_garden"]["reservationRequired"])
        before = {s["id"]: s for s in self.spots}
        for identifier in checks:
            # 施設情報の更新では近傍照明（6-04 の机上評価）を変えない
            self.assertEqual(spots[identifier].get("localGlareLevel"), before[identifier].get("localGlareLevel"))
            self.assertEqual(spots[identifier]["lastVerifiedAt"], "2026-10-24")
        self.assertFalse(spots["tocho_observatory"]["directionMaskVerified"])

    def test_unchanged_next_day_does_not_change_verification_date(self):
        updated, checks, _ = self.run_update()
        again, evidence, report = self.run_update(updated, checks, date(2026, 10, 25))
        self.assertEqual(again, updated)
        self.assertEqual(evidence, checks)
        self.assertEqual(report["changed"], [])

    def test_failure_keeps_entire_facility_and_verification_date(self):
        original = copy.deepcopy(self.spots)
        self.content[TOCHO] = "<h1>メンテナンス</h1>"
        updated, checks, report = self.run_update()
        self.assertIn("tocho_observatory", report["errors"])
        self.assertNotIn("tocho_observatory", checks)
        self.assertEqual(next(s for s in updated if s["id"] == "tocho_observatory"),
                         next(s for s in original if s["id"] == "tocho_observatory"))
        self.assertEqual(self.spots, original)
        self.assertEqual(len(report["changed"]), 2)

    def test_missing_holiday_calendar_keeps_both_schedules(self):
        self.content[HOLIDAYS] = "エラー"
        updated, _, report = self.run_update()
        self.assertEqual(set(report["errors"]), {"tocho_observatory", "kitte_garden"})
        for identifier in report["errors"]:
            self.assertEqual(next(s for s in updated if s["id"] == identifier),
                             next(s for s in self.spots if s["id"] == identifier))

    def test_network_failure_keeps_previous_check_records(self):
        updated, checks, _ = self.run_update()
        def offline(url):
            raise OSError("通信できません")
        again, evidence, report = update(updated, checks, offline, date(2026, 10, 25))
        self.assertEqual(again, updated)
        self.assertEqual(evidence, checks)
        self.assertEqual(len(report["errors"]), 3)

    def test_price_change_updates_only_sky(self):
        updated, checks, _ = self.run_update()
        url = SKY + "_next/static/chunks/pages/ticket-fixture.js"
        self.content[url] = self.content[url].replace("2,700", "2,900")
        changed, _, report = self.run_update(updated, checks)
        self.assertEqual(report["changed"], ["shibuya_sky"])
        self.assertIn("2,900", next(s for s in changed if s["id"] == "shibuya_sky")["admissionFee"])

    def test_irrelevant_facilities_untouched(self):
        updated, _, _ = self.run_update()
        for old, new in zip(self.spots, updated):
            if old["id"] not in {"shibuya_sky", "tocho_observatory", "kitte_garden"}:
                self.assertEqual(old, new)

    def test_holiday_moves_regular_closure_to_next_weekday(self):
        updated, _, _ = self.run_update()
        tocho = next(s for s in updated if s["id"] == "tocho_observatory")["openingHours"]
        self.assertNotIn("2026-11-03", tocho["dateOverrides"])
        self.assertTrue(tocho["dateOverrides"]["2026-11-04"]["closed"])
        self.assertTrue(tocho["dateOverrides"]["2027-01-01"]["unverified"])
        self.assertEqual(tocho["validThrough"], "2027-12-31")

    def test_kitte_never_uses_postmasters_room_hours(self):
        html = self.content[KITTE]
        self.assertEqual(parse_kitte('<h2>旧郵便局長室</h2>11:00〜20:00' + html)["openingHours"]["close"], "23:00")

    def test_ambiguous_or_invalid_sky_hours_are_rejected(self):
        app = self.content[SKY + "_next/static/chunks/pages/_app-fixture.js"]
        ticket = self.content[SKY + "_next/static/chunks/pages/ticket-fixture.js"]
        with self.assertRaises(SourceError):
            parse_sky(app.replace("22:30", "25:00"), ticket)
        with self.assertRaises(SourceError):
            parse_sky(app + app.replace("22:30", "21:00"), ticket)


if __name__ == "__main__":
    unittest.main()
