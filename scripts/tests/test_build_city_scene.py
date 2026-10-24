"""シーンを量産する手順（plateau_catalog.py・build_city_scene.py・plateau_shapes.py の目印）を検証する。通信は行わない。"""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_city_scene import (BUILDINGS, CONFIG, ROOT, dataset_urls, host_buildings, merge_scene, source_text,
                              suggest_ground)
from plateau_catalog import bounding_box, build_manifest, mesh_bounds, overlaps, select_files
from plateau_shapes import host_tag

URL = 'https://example.com/{code}_{name}_pref_2025_citygml_1_op/udx/{kind}/{mesh}_{kind}_6697_op.gml'


def city(code, name, label, meshes, year=2025):
    return {'cityCode': code, 'cityName': label, 'year': year,
            'metadataZipUrls': [f'https://example.com/{code}_{name}_pref_2025_citygml_1_op_codelists.zip'],
            'files': {kind: [{'code': m, 'maxLod': 2, 'url': URL.format(code=code, name=name, kind=kind, mesh=m)}
                             for m in meshes] for kind in ('bldg', 'tran')}}


class MeshTests(unittest.TestCase):
    def test_tocho_is_in_mesh_53394525(self):
        west, south, east, north = mesh_bounds('53394525')
        self.assertTrue(west <= 139.6917 < east and south <= 35.6896 < north)
        self.assertAlmostEqual(east - west, 1 / 80)
        self.assertAlmostEqual(north - south, 1 / 120)

    def test_bad_code_is_rejected(self):
        with self.assertRaises(ValueError):
            mesh_bounds('5339452')

    def test_box_radius_is_in_meters(self):
        west, south, east, north = bounding_box(35.6896, 139.6917, 500)
        self.assertAlmostEqual((north - south) * 110_574 / 2, 500, places=3)
        self.assertTrue(overlaps((0, 0, 1, 1), (0.5, 0.5, 2, 2)))
        self.assertFalse(overlaps((0, 0, 1, 1), (1, 0, 2, 1)))


class CatalogTests(unittest.TestCase):
    catalog = {'cities': [city('13113', 'shibuya-ku', '渋谷区', ['53394525', '53394514']),
                          city('13104', 'shinjuku-ku', '新宿区', ['53394525', '53394535', '53394600'])]}

    def test_same_mesh_is_taken_once_from_the_smaller_city_code(self):
        files = select_files(self.catalog, bounding_box(35.6896, 139.6917, 500), bounding_box(35.6896, 139.6917, 800))
        names = [(f['cityCode'], f['name']) for f in files]
        self.assertIn(('13104', '53394525_bldg_6697_op.gml'), names)
        self.assertEqual(sum(n == '53394525_bldg_6697_op.gml' for _, n in names), 1)
        # 建物は 500m、道路は 800m の範囲。遠いメッシュ（53394600）は入らない
        self.assertIn('53394514_tran_6697_op.gml', [n for _, n in names])
        self.assertNotIn('53394514_bldg_6697_op.gml', [n for _, n in names])
        self.assertFalse(any('53394600' in n for _, n in names))

    def test_tokyo_ward_is_preferred_over_neighbor_prefecture(self):
        # 県境の向こうの市（埼玉県、コード 11）の同じメッシュは、別年度の別ファイルなので選ばない
        catalog = {'cities': [city('11203', 'kawaguchi-shi', '川口市', ['53394525'], year=2024),
                              city('13104', 'shinjuku-ku', '新宿区', ['53394525'])]}
        files = select_files(catalog, bounding_box(35.6896, 139.6917, 500), bounding_box(35.6896, 139.6917, 800))
        self.assertEqual({f['cityCode'] for f in files}, {'13104'})

    def test_manifest_lists_cities_codelists_and_license(self):
        manifest = build_manifest(self.catalog, latitude=35.6896, longitude=139.6917, building_radius=500,
                                  road_radius=800, query='q')
        self.assertEqual(manifest['license'], 'CC-BY-4.0')
        self.assertTrue(manifest['codelists'].endswith('13104_shinjuku-ku_pref_2025_citygml_1_op_codelists.zip'))
        self.assertIn({'cityCode': '13104', 'cityName': '新宿区', 'year': 2025}, manifest['cities'])
        self.assertTrue(all('sha256' not in f for f in manifest['files']))

    def test_empty_area_fails(self):
        with self.assertRaises(ValueError):
            build_manifest(self.catalog, latitude=35.0, longitude=139.0, building_radius=500, road_radius=800, query='q')

    def test_source_names_every_city_page_and_license(self):
        manifest = build_manifest(self.catalog, latitude=35.6896, longitude=139.6917, building_radius=500,
                                  road_radius=800, query='q')
        self.assertEqual(dataset_urls(manifest), ['https://www.geospatial.jp/ckan/dataset/plateau-13104-shinjuku-ku-2025',
                                                  'https://www.geospatial.jp/ckan/dataset/plateau-13113-shibuya-ku-2025'])
        text = source_text(manifest, 36.0)
        self.assertIn('PLATEAU', text)
        self.assertIn('CC BY 4.0', text)
        self.assertIn('基準標高36m', text)


class SceneTests(unittest.TestCase):
    def test_merge_replaces_only_the_same_scene(self):
        scenes = [{'id': 'shibuya', 'buildings': [1]}, {'id': 'shinjuku', 'buildings': [2]}]
        merged = merge_scene(scenes, {'id': 'shinjuku', 'buildings': [3]})
        self.assertEqual(merged, [{'id': 'shibuya', 'buildings': [1]}, {'id': 'shinjuku', 'buildings': [3]}])
        self.assertEqual(merge_scene(scenes, {'id': 'new', 'buildings': []})[-1]['id'], 'new')
        self.assertEqual(scenes[1]['buildings'], [2])

    def test_bundled_shibuya_is_unchanged_when_rewritten(self):
        # build_city_scene.py の書き出し方で、ほかのシーン（渋谷）の行が変わらないこと
        text = BUILDINGS.read_text()
        scenes = json.loads(text)
        shinjuku = next(s for s in scenes if s['id'] == 'shinjuku')
        self.assertEqual(json.dumps(merge_scene(scenes, shinjuku), ensure_ascii=False, indent=2) + '\n', text)

    def test_ground_is_median_of_nearby_bases(self):
        scene = {'buildings': [{'id': 'a', 'x': 0, 'y': 0}, {'id': 'b', 'x': 100, 'y': 0},
                               {'id': 'c', 'x': 0, 'y': 150}, {'id': 'far', 'x': 900, 'y': 0}]}
        evidence = [{'id': 'a', 'baseElevation': 34.6}, {'id': 'b', 'baseElevation': 36.2},
                    {'id': 'c', 'baseElevation': 38.0}, {'id': 'far', 'baseElevation': 5.0}]
        self.assertEqual(suggest_ground(scene, evidence), 36.0)
        # 近くに建物が無い広い公園では、シーン全部の建物を使う
        self.assertEqual(suggest_ground({'buildings': [{'id': 'far', 'x': 900, 'y': 0}]}, evidence), 5.0)
        with self.assertRaises(ValueError):
            suggest_ground({'buildings': []}, [])

    def test_hosts_are_taken_from_spots_of_the_scene(self):
        spots = [{'sceneId': 'shinjuku', 'hostBuildingId': 'bldg_b'}, {'sceneId': 'shinjuku'},
                 {'sceneId': 'shibuya', 'hostBuildingId': 'bldg_c'}]
        self.assertEqual(host_buildings(spots, 'shinjuku'), ['bldg_b'])

    def test_host_tag_matches_swift_rule(self):
        # App/Views/CityModelRenderer.swift の hostTag(for:) と同じ結果になること
        self.assertEqual(host_tag('bldg_94caaf2f-dec2-41a7-8b0f-06ecd0fac6c7'), '_h94caaf2f')
        self.assertEqual(host_tag('bldg_9-4C_a'), '_h94ca')

    def test_config_points_at_existing_manifests(self):
        for scene in json.loads(CONFIG.read_text()):
            self.assertTrue((ROOT / scene['manifest']).exists(), scene['id'])
            self.assertGreater(scene['buildingRadius'], 0)
            self.assertGreaterEqual(scene['groundRadius'], scene['buildingRadius'])


if __name__ == '__main__':
    unittest.main()
