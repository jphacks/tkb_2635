"""夜景の明かりの置き場所（night_lights.py）と道路の取り出し（plateau_roads.py）を検証する。通信は行わない。"""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from night_lights import aviation_points, category, inside, window_quads
from plateau_roads import inside_bounds


def wall(width, height):
    """南向き（外向き -y）の、幅 width・高さ height の壁。"""
    return [(width, 0, 0), (0, 0, 0), (0, 0, height), (width, 0, height)], (0, -1, 0)


class WindowTests(unittest.TestCase):
    def test_windows_sit_in_front_of_wall_and_inside_it(self):
        points, normal = wall(30, 40)
        quads = [q for qs in window_quads(points, normal, 'b', '共同住宅', 0).values() for q in qs]
        self.assertGreater(len(quads), 10)
        for q in quads:
            xs, ys, zs = q[0::3], q[1::3], q[2::3]
            self.assertTrue(all(abs(y + 0.15) < 1e-6 for y in ys))  # 壁から 0.15m 外
            self.assertTrue(min(xs) >= 0 and max(xs) <= 30 and min(zs) >= 0 and max(zs) <= 40)

    def test_quad_faces_outward(self):
        points, normal = wall(30, 40)
        q = next(iter(window_quads(points, normal, 'b', '共同住宅', 0).values()))[0]
        a, b, c = [q[i:i + 3] for i in (0, 3, 6)]
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        cross_y = u[2] * v[0] - u[0] * v[2]
        self.assertLess(cross_y, 0)

    def test_same_input_gives_same_pattern(self):
        points, normal = wall(30, 40)
        self.assertEqual(window_quads(points, normal, 'b', '業務施設', 3),
                         window_quads(points, normal, 'b', '業務施設', 3))

    def test_low_walls_and_roofs_get_no_windows(self):
        points, normal = wall(30, 5)
        self.assertEqual(window_quads(points, normal, 'b', '業務施設', 0), {})
        roof = [(0, 0, 10), (10, 0, 10), (10, 10, 10), (0, 10, 10)]
        self.assertEqual(window_quads(roof, (0, 0, 1), 'b', '業務施設', 0), {})

    def test_group_names_match_schedule(self):
        points, normal = wall(60, 80)
        for usage in ('業務施設', '商業施設', '共同住宅', None):
            for name in window_quads(points, normal, usage or 'x', usage, 0):
                _, group, tone = name.split('_')
                self.assertIn(int(group), range(3))  # NightLightSchedule.windowGroups
                self.assertIn(int(tone), range(3))

    def test_usage_category(self):
        self.assertEqual(category('業務施設'), 'office')
        self.assertEqual(category('店舗等併用住宅'), 'residential')
        self.assertEqual(category('商業施設'), 'commercial')
        self.assertEqual(category(None), 'other')

    def test_inside(self):
        square = [(0, 0), (10, 0), (10, 10), (0, 10)]
        self.assertTrue(inside(5, 5, square))
        self.assertFalse(inside(11, 5, square))


class AviationTests(unittest.TestCase):
    def test_only_tall_buildings_get_lights_on_roof_corners(self):
        roof = [(0, 0, 80), (20, 0, 80), (20, 10, 80), (0, 10, 80), (10, 5, 60)]
        lights = aviation_points(roof, 80)
        self.assertEqual(len(lights), 4)
        self.assertTrue(all(z == 80.5 for _, _, z in lights))
        self.assertEqual(aviation_points(roof, 59), [])


class RoadTests(unittest.TestCase):
    def test_inside_bounds(self):
        bounds = (-100, -100, 100, 100)
        self.assertTrue(inside_bounds([(90, 0), (120, 0), (120, 10)], bounds))
        self.assertFalse(inside_bounds([(150, 0), (160, 0), (160, 10)], bounds))


if __name__ == '__main__':
    unittest.main()
