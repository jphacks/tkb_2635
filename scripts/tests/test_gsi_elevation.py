"""保存した地理院の標高 API の応答から、床面標高の反映案を作る処理を検証する。通信は行わない。"""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gsi_elevation as gsi

FETCHED_AT = "2026-10-25"


def spot(spot_id, category, floor, scene="scene", **extra):
    return {"id": spot_id, "category": category, "latitude": 35.0, "longitude": 139.0,
            "floorElevation": floor, "eyeHeight": 1.5, "sceneId": scene, **extra}


def record(responses):
    return {"fetchedAt": FETCHED_AT,
            "elevations": {key: {"response": value} for key, value in responses.items()}}


class ParseResponseTests(unittest.TestCase):
    def test_reads_number_and_source(self):
        self.assertEqual(gsi.parse_response({"elevation": 14.8, "hsrc": "1m（レーザ）"}), (14.8, "1m（レーザ）"))

    def test_reads_integer_elevation(self):
        self.assertEqual(gsi.parse_response({"elevation": 0, "hsrc": "10m"}), (0.0, "10m"))

    def test_no_data_is_none(self):
        self.assertEqual(gsi.parse_response({"elevation": "-----", "hsrc": "-----"}), (None, None))

    def test_rejects_non_number(self):
        with self.assertRaises(ValueError):
            gsi.parse_response({"elevation": "abc", "hsrc": "10m"})

    def test_dem_label(self):
        self.assertEqual(gsi.dem_label("5m（写真測量）"), "DEM5B")
        self.assertEqual(gsi.dem_label("10m"), "DEM10B")
        self.assertEqual(gsi.dem_label("不明"), "不明")


class PlanTests(unittest.TestCase):
    def plan(self, spots, responses, heights=None, ground=15.0):
        return {row["id"]: row for row in gsi.plan(spots, record(responses), {"scene": ground}, heights or {})}

    def test_ground_spot_uses_dem_when_close_to_scene(self):
        rows = self.plan([spot("a", "park", 15)], {"a": {"elevation": 14.8, "hsrc": "1m（レーザ）"}})
        self.assertEqual(rows["a"]["floorElevation"], 14.8)
        self.assertEqual(rows["a"]["floorElevationSource"], "国土地理院 DEM1A 2026-10-25")

    def test_ground_spot_far_from_scene_is_kept(self):
        rows = self.plan([spot("a", "park", 15)], {"a": {"elevation": 17.5, "hsrc": "1m（レーザ）"}})
        self.assertIsNone(rows["a"]["floorElevation"])
        self.assertIn("要確認", rows["a"]["status"])

    def test_observatory_without_official_height_is_kept(self):
        rows = self.plan([spot("o", "observatory", 244)], {"o": {"elevation": 15, "hsrc": "1m（レーザ）"}})
        self.assertIsNone(rows["o"]["floorElevation"])
        self.assertIn("公式未確認", rows["o"]["status"])

    def test_observatory_above_ground_adds_dem(self):
        heights = {"o": {"aboveGround": 350, "verifiedAt": FETCHED_AT}}
        rows = self.plan([spot("o", "observatory", 350.3)], {"o": {"elevation": 1.9, "hsrc": "1m（レーザ）"}}, heights)
        self.assertEqual(rows["o"]["floorElevation"], 351.9)
        self.assertIn("地上350m", rows["o"]["floorElevationSource"])

    def test_observatory_above_sea_level_is_used_as_is(self):
        heights = {"o": {"aboveSeaLevel": 251, "verifiedAt": FETCHED_AT}}
        rows = self.plan([spot("o", "observatory", 250)], {"o": {"elevation": 29.8, "hsrc": "1m（レーザ）"}}, heights)
        self.assertEqual(rows["o"]["floorElevation"], 251.0)

    def test_missing_response_is_kept(self):
        rows = self.plan([spot("a", "park", 15)], {"a": None})
        self.assertIsNone(rows["a"]["floorElevation"])


class ApplyTests(unittest.TestCase):
    def test_inserts_source_after_floor_and_keeps_order(self):
        spots = [spot("a", "park", 15), spot("b", "park", 3)]
        rows = [{"id": "a", "floorElevation": 14.8, "floorElevationSource": "国土地理院 DEM1A 2026-10-25"},
                {"id": "b", "floorElevation": None, "floorElevationSource": None}]
        updated = gsi.apply(spots, rows)
        keys = list(updated[0])
        self.assertEqual(keys[keys.index("floorElevation") + 1], "floorElevationSource")
        self.assertEqual(updated[0]["floorElevation"], 14.8)
        self.assertEqual(updated[1], spots[1])
        self.assertEqual(spots[0]["floorElevation"], 15)  # 元の一覧は書き換えない


if __name__ == "__main__":
    unittest.main()
