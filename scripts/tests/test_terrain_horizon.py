"""地形の地平線の計算を、作った標高で検証する。通信は行わない。"""
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import terrain_horizon as terrain


class TerrainHorizonTests(unittest.TestCase):
    def test_parse_tile_reads_numbers_and_missing(self):
        row = ",".join(["1.5"] * 255 + ["e"])
        rows = terrain.parse_tile("\n".join([row] * 256))
        self.assertEqual(rows[0][0], 1.5)
        self.assertIsNone(rows[0][255])

    def test_parse_tile_rejects_wrong_size(self):
        with self.assertRaises(ValueError):
            terrain.parse_tile("1,2\n3,4")

    def test_tile_pixel_of_tokyo(self):
        tx, ty, col, row = terrain.tile_pixel(35.658, 139.7016)
        self.assertEqual((tx, ty), (14549, 6452))
        self.assertTrue(0 <= col < 256 and 0 <= row < 256)

    def test_flat_ground_is_below_the_eye(self):
        samples = terrain.horizon(35.6, 139.7, 11.5, lambda lat, lon: 10.0)
        self.assertEqual(len(samples), 360)
        self.assertLess(terrain.max_angle(samples, 11.5), 0)

    def test_hill_to_the_north_is_above_the_eye(self):
        def elevation(lat, lon):
            return 60.0 if lat > 35.6 + 450 / 110_574.0 else 10.0
        samples = terrain.horizon(35.6, 139.7, 11.5, elevation)
        height, distance = samples[0]
        self.assertEqual(distance, 500.0)
        self.assertGreater(math.degrees(math.atan2(height - 11.5, distance)), 5)
        self.assertLess(terrain.max_angle([samples[180]], 11.5), 0)

    def test_missing_data_gives_none(self):
        samples = terrain.horizon(35.6, 139.7, 11.5, lambda lat, lon: None)
        self.assertTrue(all(sample is None for sample in samples))


if __name__ == "__main__":
    unittest.main()
