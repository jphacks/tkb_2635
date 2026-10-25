import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_observation_region import decode_height, make_grid


class ObservationRegionBuildTests(unittest.TestCase):
    def test_dem_png_decoding_preserves_sea_level_negative_and_missing(self):
        self.assertEqual(decode_height((0, 0, 0)), 0)
        self.assertEqual(decode_height((255, 255, 156)), -1)
        self.assertEqual(decode_height((0, 5, 200)), 14.8)
        self.assertIsNone(decode_height((128, 0, 0)))

    def test_grid_rows_go_north_and_columns_go_east(self):
        class Coordinates:
            def elevation(self, lat, lon):
                return lat * 1000 + lon
        scene = dict(originLatitude=35.658, originLongitude=139.7016)
        grid = make_grid(scene, 20, 20, Coordinates())
        self.assertEqual((grid["rows"], grid["columns"]), (3, 3))
        self.assertEqual(grid["values"][4], round(35.658 * 1000 + 139.7016, 2))
        self.assertLess(grid["values"][0], grid["values"][6])

    def test_missing_elevations_stay_missing(self):
        class Missing:
            def elevation(self, lat, lon):
                return None
        grid = make_grid(dict(originLatitude=35.658, originLongitude=139.7016), 20, 20, Missing())
        self.assertEqual(grid["values"], [None] * 9)


if __name__ == "__main__":
    unittest.main()
