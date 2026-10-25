"""遠くの地面（far_ground.py）の範囲・タイル・なじませ方を検証する。通信と Blender は使わない。"""
import json
import math
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from far_ground import (BUILDINGS, FADE_START, OUTPUT, PHOTO_ZOOM, RADIUS, fade, local_to_latlon, plan, tile_range,
                        world_pixel)

SHIBUYA = (35.658, 139.7016)


class CoordinateTests(unittest.TestCase):
    def test_local_offsets_match_starcore_scale(self):
        # StarCore の CityScene.localPosition と同じ係数（1° = 110,574 m・111,320 m × cos 緯度）
        lat, lon = local_to_latlon(1000, 2000, *SHIBUYA)
        self.assertAlmostEqual((lat - SHIBUYA[0]) * 110_574, 2000, places=6)
        self.assertAlmostEqual((lon - SHIBUYA[1]) * 111_320 * math.cos(math.radians(SHIBUYA[0])), 1000, places=6)

    def test_world_pixel_origin_and_axes(self):
        self.assertEqual(world_pixel(0, 0, 0), (128, 128))
        x0, y0 = world_pixel(*SHIBUYA, 13)
        x1, y1 = world_pixel(SHIBUYA[0] + 0.01, SHIBUYA[1] + 0.01, 13)
        # 東へ行くと x が増え、北へ行くと y が減る
        self.assertGreater(x1, x0)
        self.assertLess(y1, y0)

    def test_tile_numbers_match_the_city_model_ground_photo(self):
        # 都市モデルの地面の写真（download_gsi_photo.py）と同じタイルの番号の付け方
        from download_gsi_photo import tile
        for lat, lon in (SHIBUYA, (35.7101, 139.8107), (35.6175, 139.8366)):
            for zoom in (13, 18):
                x, y = world_pixel(lat, lon, zoom)
                self.assertEqual((int(x // 256), int(y // 256)), tile(lat, lon, zoom))


class RangeTests(unittest.TestCase):
    def test_tiles_cover_the_whole_square(self):
        x0, y0, x1, y1 = tile_range(*SHIBUYA, RADIUS, PHOTO_ZOOM)
        for east, north in ((-RADIUS, RADIUS), (RADIUS, -RADIUS), (-RADIUS, -RADIUS), (RADIUS, RADIUS)):
            x, y = world_pixel(*local_to_latlon(east, north, *SHIBUYA), PHOTO_ZOOM)
            self.assertTrue(x0 <= x // 256 <= x1 and y0 <= y // 256 <= y1)
        # ズーム 13 のタイルは約 4 km 四方なので、40 km 四方は 10〜12 枚四方
        self.assertTrue(10 <= x1 - x0 + 1 <= 12)

    def test_fade_is_smooth_between_start_and_edge(self):
        self.assertEqual(fade(0), 0)
        self.assertEqual(fade(FADE_START), 0)
        self.assertEqual(fade(RADIUS), 1)
        self.assertEqual(fade(RADIUS * 2), 1)
        values = [fade(d) for d in range(int(FADE_START), int(RADIUS) + 1, 250)]
        self.assertEqual(values, sorted(values))
        self.assertAlmostEqual(fade((FADE_START + RADIUS) / 2), 0.5)

    def test_plan_names_the_output_by_scene_id(self):
        job = plan({'id': 'shibuya', 'originLatitude': SHIBUYA[0], 'originLongitude': SHIBUYA[1]})
        self.assertTrue(job['output'].endswith('App/Resources/Far/far_shibuya.jpg'))
        self.assertEqual(job['photo']['zoom'], PHOTO_ZOOM)
        self.assertEqual(job['radius'], RADIUS)


class BundledFilesTests(unittest.TestCase):
    def test_every_far_image_has_info_and_a_scene(self):
        scenes = {s['id'] for s in json.loads(BUILDINGS.read_text())}
        images = sorted(OUTPUT.glob('far_*.jpg'))
        if not images:
            self.skipTest('遠くの地面の画像がまだ無い')
        for image in images:
            scene_id = image.stem.removeprefix('far_')
            self.assertIn(scene_id, scenes)
            info = json.loads(image.with_suffix('.json').read_text())
            self.assertEqual(info['sceneId'], scene_id)
            self.assertEqual(info['meters'], 2 * RADIUS)
            self.assertIn('国土地理院', info['source'])
            self.assertIn('VIIRS Nighttime Lights V2.2', info['source'])


class VnlCropTests(unittest.TestCase):
    def test_window_covers_every_scene_with_margin(self):
        from vnl_crop import EAST, NORTH, SOUTH, WEST, window
        for scene in json.loads(BUILDINGS.read_text()):
            north, west = local_to_latlon(-RADIUS, RADIUS, scene['originLatitude'], scene['originLongitude'])
            south, east = local_to_latlon(RADIUS, -RADIUS, scene['originLatitude'], scene['originLongitude'])
            self.assertTrue(WEST <= west and east <= EAST and SOUTH <= south and north <= NORTH, scene['id'])
        # 15 秒角・左上が (-180, 75) の全世界の画像での行・列
        rows = window((-180.0, 75.0, 1 / 240), (33601, 86401))
        self.assertEqual(rows[1] - rows[0], int((75 - SOUTH) * 240) + 1 - int((75 - NORTH) * 240))
        with self.assertRaises(ValueError):
            window((0.0, 10.0, 1 / 240), (100, 100))


if __name__ == '__main__':
    unittest.main()
