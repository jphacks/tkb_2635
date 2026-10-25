"""数画素の疑似 GeoTIFF で VIIRS の変換を検証する。通信は行わない。"""
import json
import math
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import viirs_to_spots as viirs

try:
    import numpy as np
    import rasterio
    from rasterio.transform import from_origin
except ImportError:  # rasterio が無い環境ではラスタを使うテストだけ飛ばす
    rasterio = None

NODATA = -999.0
WEST, NORTH, PIXEL = 139.0, 36.0, 0.01


def center(row, col):
    """画素 (row, col) の中心の緯度・経度。"""
    return NORTH - (row + 0.5) * PIXEL, WEST + (col + 0.5) * PIXEL


def write_raster(path, values, nodata=NODATA):
    array = np.array(values, dtype="float32")
    with rasterio.open(path, "w", driver="GTiff", height=array.shape[0], width=array.shape[1], count=1,
                       dtype="float32", crs="EPSG:4326", transform=from_origin(WEST, NORTH, PIXEL, PIXEL),
                       nodata=nodata) as dataset:
        dataset.write(array, 1)


def spot(spot_id, row, col, **extra):
    latitude, longitude = center(row, col)
    return {"id": spot_id, "name": "検証地点", "latitude": latitude, "longitude": longitude,
            "regionalLightIndex": 0.5, "modelVersion": "test", **extra}


class LightIndexTest(unittest.TestCase):
    def test_null_light_index_is_shown_as_unknown_in_preview(self):
        spots = [{"id": "new_park", "regionalLightIndex": None}]
        results = [{"id": "new_park", "radiance": 5.0, "index": 0.29, "validPixels": 9}]
        self.assertIn("未確認", viirs.format_table(spots, results))
        updated = viirs.apply(spots, results, 2025)[0]
        self.assertEqual(updated["regionalLightIndex"], 0.29)
        self.assertEqual(updated["regionalLightMeasuredAt"], "2025")

    def test_boundaries(self):
        self.assertEqual(viirs.light_index(viirs.R_DARK), 0.0)
        self.assertEqual(viirs.light_index(viirs.R_BRIGHT), 1.0)
        self.assertEqual(viirs.light_index(0.2), 0.0)
        self.assertEqual(viirs.light_index(0.0), 0.0)
        self.assertEqual(viirs.light_index(500.0), 1.0)

    def test_between_is_logarithmic(self):
        # 幾何平均 sqrt(R_DARK×R_BRIGHT) はちょうど中間の 0.5 になる
        self.assertAlmostEqual(viirs.light_index((viirs.R_DARK * viirs.R_BRIGHT) ** 0.5), 0.5)
        # R_DARK = 1 のとき log10(10) / log10(R_BRIGHT)
        self.assertAlmostEqual(viirs.light_index(10.0), 1 / math.log10(viirs.R_BRIGHT))
        self.assertLess(viirs.light_index(10.0), viirs.light_index(100.0))

    def test_year_from_file_name(self):
        self.assertEqual(viirs.guess_year("VNL_npp_2023_global_vcmslcfg_v2_c202402081600.average_masked.dat.tif"),
                         2023)
        self.assertIsNone(viirs.guess_year("night_lights.tif"))


@unittest.skipIf(rasterio is None, "rasterio が入っていない（pip install rasterio）")
class RasterTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.raster = self.root / "VNL_npp_2023_global_test.average_masked.dat.tif"

    def tearDown(self):
        self.directory.cleanup()

    def test_mean_of_3x3_around_spot(self):
        values = [[100, 100, 100, 100, 100],
                  [100, 1, 2, 3, 100],
                  [100, 4, 5, 6, 100],
                  [100, 7, 8, 9, 100],
                  [100, 100, 100, 100, 100]]
        write_raster(self.raster, values)
        [result] = viirs.sample_spots(self.raster, [spot("a", 2, 2)])
        self.assertEqual((result["row"], result["col"]), (2, 2))
        self.assertEqual(result["validPixels"], 9)
        self.assertAlmostEqual(result["radiance"], 5.0)
        self.assertEqual(result["index"], round(viirs.light_index(5.0), 2))

    def test_nodata_and_negative_are_excluded(self):
        values = [[NODATA, 10, -1.5],
                  [10, 10, NODATA],
                  [40, NODATA, NODATA]]
        write_raster(self.raster, values)
        [result] = viirs.sample_spots(self.raster, [spot("a", 1, 1)])
        self.assertEqual(result["validPixels"], 4)
        self.assertAlmostEqual(result["radiance"], 17.5)

    def test_edge_window_is_clipped(self):
        write_raster(self.raster, [[2, 4, 100], [6, 8, 100], [100, 100, 100]])
        [result] = viirs.sample_spots(self.raster, [spot("a", 0, 0)])
        self.assertEqual(result["validPixels"], 4)
        self.assertAlmostEqual(result["radiance"], 5.0)

    def test_all_missing_keeps_current_value(self):
        write_raster(self.raster, [[NODATA] * 3, [NODATA, -2, NODATA], [NODATA] * 3])
        spots = [spot("a", 1, 1)]
        results = viirs.sample_spots(self.raster, spots)
        self.assertIsNone(results[0]["radiance"])
        self.assertIsNone(results[0]["index"])
        self.assertEqual(viirs.apply(spots, results, 2023), spots)

    def test_outside_raster_is_error(self):
        write_raster(self.raster, [[1, 1], [1, 1]])
        with self.assertRaises(ValueError):
            viirs.sample_spots(self.raster, [spot("a", 10, 10)])

    def test_write_updates_only_light_fields(self):
        write_raster(self.raster, [[300] * 3, [300] * 3, [300] * 3])
        spots_path, record_path = self.root / "spots.json", self.root / "record.json"
        original = [spot("a", 1, 1, memo="そのまま", lastVerifiedAt=None), spot("b", 1, 1)]
        spots_path.write_text(json.dumps(original, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        self.assertEqual(viirs.main([str(self.raster), "--spots", str(spots_path), "--record", str(record_path)]), 0)
        self.assertEqual(json.loads(spots_path.read_text(encoding="utf-8")), original, "--dry-run で書き換えない")
        self.assertFalse(record_path.exists())

        viirs.main([str(self.raster), "--write", "--spots", str(spots_path), "--record", str(record_path)])
        text = spots_path.read_text(encoding="utf-8")
        updated = json.loads(text)
        self.assertEqual(text, json.dumps(updated, ensure_ascii=False, indent=2) + "\n")
        for before, after in zip(original, updated):
            keys = list(after)
            position = keys.index("regionalLightIndex")
            self.assertEqual(keys[position + 1:position + 3], ["regionalLightSource", "regionalLightMeasuredAt"])
            self.assertEqual([k for k in keys if k in before], list(before), "既存のキーの順が変わらない")
            self.assertEqual(after["regionalLightIndex"], 1.0)
            self.assertEqual(after["regionalLightSource"], viirs.source_label(2023))
            self.assertEqual(after["regionalLightMeasuredAt"], "2023")
            rest = {k: v for k, v in after.items() if not k.startswith("regionalLight")}
            self.assertEqual(rest, {k: v for k, v in before.items() if not k.startswith("regionalLight")})

        saved = json.loads(record_path.read_text(encoding="utf-8"))
        self.assertEqual(saved["raster"]["file"], self.raster.name)
        self.assertEqual(len(saved["raster"]["sha256"]), 64)
        self.assertIsNone(saved["archive"])
        self.assertEqual(saved["year"], 2023)
        self.assertEqual([s["radiance"] for s in saved["spots"]], [300.0, 300.0])

        # もう一度書いても同じ結果になる（キーが重複しない）
        viirs.main([str(self.raster), "--write", "--spots", str(spots_path), "--record", str(record_path)])
        self.assertEqual(spots_path.read_text(encoding="utf-8"), text)


if __name__ == "__main__":
    unittest.main()
