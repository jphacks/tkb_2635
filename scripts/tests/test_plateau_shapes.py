"""3D 用の面の取り出し（plateau_shapes.py）を検証する。通信は行わない。"""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from plateau_shapes import facade_key, normal, outward


class FacadeKeyTests(unittest.TestCase):
    def test_style_matches_swift_rules(self):
        self.assertTrue(facade_key('業務施設', 'x').startswith('facade_0_'))
        self.assertTrue(facade_key('商業施設', 'x').startswith('facade_1_'))
        self.assertTrue(facade_key('共同住宅', 'x').startswith('facade_2_'))
        self.assertTrue(facade_key(None, 'x').startswith('facade_3_'))

    def test_variant_uses_fnv1a_like_swift(self):
        # FNV-1a 32bit("a") = 0xe40c292c、"b" = 0xe70c2de5（BuildingFacade.swift と同じ式）
        self.assertEqual(facade_key(None, 'a'), f'facade_3_{0xe40c292c % 4}')
        self.assertEqual(facade_key(None, 'b'), f'facade_3_{0xe70c2de5 % 4}')


class OrientationTests(unittest.TestCase):
    def test_roof_faces_up(self):
        clockwise = [(0, 0, 10), (0, 1, 10), (1, 1, 10), (1, 0, 10)]
        self.assertGreater(normal(outward(clockwise, (0.5, 0.5)))[2], 0.99)

    def test_wall_faces_away_from_building_center(self):
        # 中心 (0, 0) の建物の、北側 (y=5) の壁。外向きは +y。
        wall = [(-1, 5, 0), (-1, 5, 3), (1, 5, 3), (1, 5, 0)]
        for ring in (wall, wall[::-1]):
            self.assertGreater(normal(outward(ring, (0, 0)))[1], 0.99)

    def test_degenerate_polygon_is_skipped(self):
        self.assertIsNone(outward([(0, 0, 0), (1, 0, 0), (2, 0, 0)], (0, 0)))


if __name__ == '__main__':
    unittest.main()
