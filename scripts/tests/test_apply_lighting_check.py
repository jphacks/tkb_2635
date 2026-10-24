"""近くの照明の段階評価を spots.json に反映する処理を検証する。通信は行わない。"""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import apply_lighting_check as lighting


def spot(spot_id, **extra):
    return {"id": spot_id, "name": "検証地点", "regionalLightIndex": 0.5,
            "regionalLightSource": "VIIRS", "regionalLightMeasuredAt": "2025",
            "modelVersion": "test", **extra}


def entry(level, method="desk", checked_at="2026-10-24", sources=("https://example.com/",)):
    return {"level": level, "method": method, "checkedAt": checked_at, "sources": list(sources), "note": "検証"}


class ApplyTests(unittest.TestCase):
    def test_level_is_written_after_regional_light(self):
        [result] = lighting.apply([spot("a")], {"a": entry(2)})
        self.assertEqual(result["localGlareLevel"], 2)
        self.assertEqual(result["lightingCheckDate"], "2026-10-24")
        self.assertEqual(result["lightingCheckMethod"], "desk")
        keys = list(result)
        start = keys.index("regionalLightMeasuredAt") + 1
        self.assertEqual(keys[start:start + 3], ["localGlareLevel", "lightingCheckDate", "lightingCheckMethod"])
        self.assertEqual(keys[-1], "modelVersion")

    def test_null_level_is_left_untouched(self):
        original = spot("a", localGlareLevel=1, lightingCheckDate="2026-01-01", lightingCheckMethod="onsite")
        [result] = lighting.apply([original], {"a": entry(None)})
        self.assertEqual(result, original)
        [plain] = lighting.apply([spot("b")], {"b": entry(None)})
        self.assertNotIn("localGlareLevel", plain)

    def test_spot_without_assessment_is_left_untouched(self):
        original = spot("a")
        self.assertEqual(lighting.apply([original], {}), [original])

    def test_existing_values_are_replaced_in_place(self):
        original = spot("a", localGlareLevel=1, lightingCheckDate="2026-01-01", lightingCheckMethod="desk")
        [result] = lighting.apply([original], {"a": entry(3, method="onsite", checked_at="2026-11-01")})
        self.assertEqual(list(result), list(original))
        self.assertEqual((result["localGlareLevel"], result["lightingCheckMethod"]), (3, "onsite"))

    def test_zero_is_written(self):
        [result] = lighting.apply([spot("a")], {"a": entry(0)})
        self.assertEqual(result["localGlareLevel"], 0)

    def test_input_is_not_modified(self):
        spots = [spot("a")]
        lighting.apply(spots, {"a": entry(2)})
        self.assertNotIn("localGlareLevel", spots[0])


class ValidateTests(unittest.TestCase):
    def test_valid_entries_pass(self):
        self.assertEqual(lighting.validate({"a": entry(2), "b": entry(None, sources=())}, {"a", "b"}), [])

    def test_bad_entries_are_reported(self):
        cases = {
            "unknown": entry(1),
            "a": entry(4),
            "b": entry(True),
            "c": entry(1, method="guess"),
            "d": entry(1, checked_at="10/24"),
            "e": entry(1, sources=()),
        }
        errors = lighting.validate(cases, {"a", "b", "c", "d", "e"})
        for spot_id in cases:
            self.assertTrue(any(error.startswith(f"{spot_id}:") for error in errors), spot_id)


class MainTests(unittest.TestCase):
    def run_main(self, spots, assessments, *flags):
        with tempfile.TemporaryDirectory() as directory:
            spots_path = Path(directory) / "spots.json"
            assessments_path = Path(directory) / "assessments.json"
            lighting.write_json(spots_path, spots)
            lighting.write_json(assessments_path, assessments)
            code = lighting.main(["--spots", str(spots_path), "--assessments", str(assessments_path), *flags])
            return code, json.loads(spots_path.read_text(encoding="utf-8")), spots_path.read_text(encoding="utf-8")

    def test_dry_run_does_not_write(self):
        code, written, _ = self.run_main([spot("a")], {"a": entry(2)})
        self.assertEqual(code, 0)
        self.assertNotIn("localGlareLevel", written[0])

    def test_write_keeps_format(self):
        code, written, text = self.run_main([spot("a"), spot("b")], {"a": entry(2), "b": entry(None)}, "--write")
        self.assertEqual(code, 0)
        self.assertEqual(written[0]["localGlareLevel"], 2)
        self.assertNotIn("localGlareLevel", written[1])
        self.assertTrue(text.endswith("}\n]\n"))
        self.assertIn('  {\n    "id": "a",', text)

    def test_invalid_assessment_stops_before_writing(self):
        code, written, _ = self.run_main([spot("a")], {"a": entry(5)}, "--write")
        self.assertEqual(code, 1)
        self.assertNotIn("localGlareLevel", written[0])


class RepositoryDataTests(unittest.TestCase):
    def test_repository_assessments_are_valid(self):
        spots = json.loads(lighting.SPOTS.read_text(encoding="utf-8"))
        assessments = json.loads(lighting.ASSESSMENTS.read_text(encoding="utf-8"))
        self.assertEqual(lighting.validate(assessments, {s["id"] for s in spots}), [])
        self.assertEqual(set(assessments), {s["id"] for s in spots})

    def test_repository_spots_match_assessments(self):
        spots = json.loads(lighting.SPOTS.read_text(encoding="utf-8"))
        assessments = json.loads(lighting.ASSESSMENTS.read_text(encoding="utf-8"))
        self.assertEqual(lighting.apply(spots, assessments), spots, "assessments.json を --write で反映してください")


if __name__ == "__main__":
    unittest.main()
