"""確認済みルールの反映と、休日に続く休園日を通信なしで検証する。"""

import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from apply_night_access import DIRECTORY, SPOTS, apply


class AppAccessTests(unittest.TestCase):
    def setUp(self):
        self.spots = json.loads(SPOTS.read_text())
        self.policy = json.loads((DIRECTORY / "app-access.json").read_text())
        self.holidays = json.loads((DIRECTORY / "holidays.json").read_text())

    def test_holiday_shift_special_opening_and_new_year(self):
        spots = apply(self.spots, self.policy, self.holidays)
        rules = next(s for s in spots if s["id"] == "shinjuku_gyoen")["accessRules"]
        self.assertIn("2026-10-13", rules["closedDates"])
        self.assertNotIn("2026-10-12", rules["closedDates"])
        self.assertIn("2026-09-24", rules["closedDates"])
        self.assertNotIn("2026-04-06", rules["closedDates"])
        self.assertNotIn("2026-11-02", rules["closedDates"])
        self.assertIn("2026-12-29", rules["closedDates"])
        self.assertIn("2027-01-03", rules["closedDates"])

    def test_other_facilities_and_observation_coordinates_are_preserved(self):
        updated = apply(self.spots, self.policy, self.holidays)
        for before, after in zip(self.spots, updated):
            if before["id"] not in self.policy:
                self.assertEqual(before, after)
            for field in ("latitude", "longitude", "floorElevation", "eyeHeight"):
                self.assertEqual(before[field], after[field])

    def test_missing_holiday_data_is_not_silently_accepted(self):
        holidays = copy.deepcopy(self.holidays)
        holidays["dates"].remove("2026-11-23")
        with self.assertRaises(ValueError):
            apply(self.spots, self.policy, holidays)

    def test_app_data_matches_reviewed_policy(self):
        self.assertEqual(self.spots, apply(self.spots, self.policy, self.holidays))


if __name__ == "__main__":
    unittest.main()
