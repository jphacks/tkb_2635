"""実寸の座標・標高で変換結果を検証する。通信は行わない。"""
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from plateau_citygml import B, G, convert_building, load_codelists
from plateau_to_json import convert

LAT, LON = 35.658, 139.7016
CRS = 'http://www.opengis.net/def/crs/EPSG/0/6697'


def building(identifier='one', bounds=(-10, -20, 10, 20), base=30, roof=50, measured='20', extra=''):
    left, bottom, right, top = bounds
    # 原点付近の実際の緯度・経度へ戻す。期待寸法は40×20mの既知値。
    coords = []
    for east, north, z in [(left, bottom, base), (right, bottom, base),
                            (right, top, roof), (left, top, roof)]:
        coords.extend([LAT + north / 110574, LON + east / (111320 * math.cos(math.radians(LAT))), z])
    height = f'<b:measuredHeight uom="m">{measured}</b:measuredHeight>' if measured is not None else ''
    return f'''<b:Building xmlns:b="{B[1:-1]}" xmlns:g="{G[1:-1]}"
      xmlns:xlink="http://www.w3.org/1999/xlink" g:id="{identifier}">
      <g:name>検証ビル</g:name>{height}{extra}
      <b:lod1Solid><g:Solid><g:exterior><g:CompositeSurface><g:surfaceMember>
      <g:Polygon g:id="surface"><g:exterior><g:LinearRing><g:posList>{' '.join(map(str,coords))}</g:posList>
      </g:LinearRing></g:exterior></g:Polygon></g:surfaceMember></g:CompositeSurface></g:exterior></g:Solid></b:lod1Solid>
      </b:Building>'''


def document(*buildings, crs=CRS):
    return f'''<c:CityModel xmlns:c="http://www.opengis.net/citygml/2.0" xmlns:g="{G[1:-1]}">
    <g:boundedBy><g:Envelope srsName="{crs}" srsDimension="3"/></g:boundedBy>
    {''.join('<c:cityObjectMember>'+b+'</c:cityObjectMember>' for b in buildings)}</c:CityModel>'''


class PlateauConversionTests(unittest.TestCase):
    def run_building(self, xml=None, ground=15, radius=500):
        return convert_building(ET.fromstring(xml or building()), CRS, '3',
                                (LAT, LON), ground, radius, {})

    def run_files(self, *contents):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for i, content in enumerate(contents):
                p = Path(directory) / f'{i}.gml'
                p.write_text(content)
                paths.append(p)
            return convert(paths, scene_id='test', name='検証', latitude=LAT, longitude=LON,
                           ground=15, radius=500, source='合成テストデータ')

    def test_dimensions_axes_and_absolute_roof_elevation(self):
        result, evidence = self.run_building()
        self.assertEqual((result['x'], result['y'], result['width'], result['depth']), (0, 0, 20, 40))
        self.assertEqual(result['height'], 35)  # 屋根50m - シーン地面15m
        self.assertEqual(evidence['baseElevation'], 30)
        self.assertIsNone(result['usage'])

    def test_building_below_scene_ground_is_skipped_and_recorded(self):
        # 坂の下で屋根がシーンの地面（15m）より低い建物は、平坦と見なすと空をふさがないので入れない。
        low = building('low', base=2, roof=10, measured='8')
        scenes, report = self.run_files(document(building('one'), low))
        self.assertEqual([b['id'] for b in scenes[0]['buildings']], ['one'])
        self.assertEqual(report['belowSceneGround'], ['low'])

    def test_east_north_axes_have_expected_sign_and_scale(self):
        result, _ = self.run_building(building(bounds=(90, -220, 110, -180)))
        self.assertEqual((result['x'], result['y']), (100, -200))

    def test_measured_height_preserves_taller_roof_and_geometry_is_not_lowered(self):
        result, _ = self.run_building(building(measured='40'))
        self.assertEqual(result['height'], 55)  # 地盤30m+計測40m-基準15m
        result, _ = self.run_building(building(measured='5'))
        self.assertEqual(result['height'], 35)

    def test_missing_and_unknown_height_uses_geometry(self):
        for measured in [None, '0', '-9999']:
            with self.subTest(measured=measured):
                result, evidence = self.run_building(building(measured=measured))
                self.assertEqual(result['height'], 35)
                self.assertIsNone(evidence['measuredHeight'])

    def test_circle_intersection_keeps_edge_building_but_excludes_diagonal(self):
        self.assertIsNotNone(self.run_building(building(bounds=(490, -10, 550, 10))))
        self.assertIsNone(self.run_building(building(bounds=(490, 490, 550, 550))))

    def test_same_id_duplicates_removed_but_conflicts_fail(self):
        scenes, report = self.run_files(document(building()), document(building()))
        self.assertEqual(len(scenes[0]['buildings']), 1)
        self.assertEqual(report['duplicatesRemoved'], 1)
        with self.assertRaisesRegex(ValueError, '同じID'):
            self.run_files(document(building()), document(building(measured='40')))

    def test_code_list_is_resolved_and_unknown_stays_null(self):
        xml = building(extra='<b:usage codeSpace="../../codelists/Building_usage.xml">401</b:usage>')
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory) / 'Building_usage.xml'
            p.write_text(f'<g:Dictionary xmlns:g="{G[1:-1]}"><g:dictionaryEntry><g:Definition><g:description>事務所</g:description><g:name>401</g:name></g:Definition></g:dictionaryEntry></g:Dictionary>')
            lists = load_codelists(directory)
            result, _ = convert_building(ET.fromstring(xml), CRS, '3', (LAT, LON), 15, 500, lists)
            self.assertEqual(result['usage'], '事務所')
        self.assertIsNone(self.run_building(xml)[0]['usage'])

    def test_local_shape_reference_and_building_part(self):
        xml = building().replace('</g:CompositeSurface>', '<g:surfaceMember xlink:href="#surface"/></g:CompositeSurface>')
        self.assertEqual(self.run_building(xml)[0]['height'], 35)
        xml = building().replace('<b:lod1Solid>', '<b:consistsOfBuildingPart><b:BuildingPart><b:lod1Solid>').replace('</b:lod1Solid>', '</b:lod1Solid></b:BuildingPart></b:consistsOfBuildingPart>')
        scenes, _ = self.run_files(document(xml))
        self.assertEqual(len(scenes[0]['buildings']), 1)
        self.assertEqual(scenes[0]['buildings'][0]['height'], 35)

    def test_unsupported_crs_dimension_and_nonfinite_rejected(self):
        with self.assertRaisesRegex(ValueError, '座標系'):
            self.run_files(document(building(), crs='EPSG:3857'))
        with self.assertRaisesRegex(ValueError, '次元'):
            self.run_building(building().replace('<g:posList>', '<g:posList srsDimension="2">'))
        for measured in ['nan', 'inf', '-3']:
            with self.subTest(measured=measured), self.assertRaises(ValueError):
                self.run_building(building(measured=measured))

    def test_unresolved_reference_and_empty_geometry_rejected(self):
        with self.assertRaisesRegex(ValueError, '形状参照'):
            self.run_building(building().replace('<g:surfaceMember>', '<g:surfaceMember xlink:href="#missing">'))
        with self.assertRaisesRegex(ValueError, '座標'):
            self.run_building(building().replace('g:posList', 'g:unknown'))

    def test_empty_region_and_truncated_xml_fail(self):
        with self.assertRaisesRegex(ValueError, '指定範囲'):
            self.run_files(document(building(bounds=(1000, 1000, 1020, 1040))))
        with self.assertRaises(ET.ParseError):
            self.run_files(document(building())[:-15])

    def test_cli_failure_does_not_overwrite_existing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)
            (p / 'bad.gml').write_text(document(building(), crs='EPSG:3857'))
            output = p / 'buildings.json'
            output.write_text('keep this')
            run = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'plateau_to_json.py'),
                                  str(p / 'bad.gml'), '--output', str(output), '--scene-id', 'test',
                                  '--name', '検証', '--latitude', str(LAT), '--longitude', str(LON),
                                  '--ground-elevation', '15', '--source', '合成テスト'], capture_output=True)
            self.assertNotEqual(run.returncode, 0)
            self.assertEqual(output.read_text(), 'keep this')


if __name__ == '__main__':
    unittest.main()
