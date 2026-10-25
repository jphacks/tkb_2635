"""EOG の VIIRS 夜間光（VNL V2.2 年平均、average_masked、EPSG:4326、15 秒角）から、東京周辺だけを切り出す（4-11）。

元の GeoTIFF（全世界、展開後 約 11.6GB）はリポジトリに入れず、作業フォルダに置く。
切り出した配列（float32、nW/cm²/sr）と範囲を、far_ground_blender.py が読む .npy と .json に書く。

    # 作業用の Python 環境（tifffile・imagecodecs・numpy）で動かす
    ../outputs/vnl/venv/bin/python scripts/vnl_crop.py ../outputs/vnl/vnl2025.tif --output ../outputs/vnl/tokyo

出典: Earth Observation Group, Payne Institute for Public Policy, Colorado School of Mines
（VIIRS Nighttime Lights V2.2、CC BY 4.0）。Elvidge et al. 2021, Remote Sensing 13(5), 922.
"""
import argparse
import json
from pathlib import Path

# 全 31 シーンの原点から半径 20km（far_ground.py の RADIUS）を含む範囲 [度]
WEST, SOUTH, EAST, NORTH = 139.30, 35.35, 140.15, 36.05


def window(transform, shape, west=WEST, south=SOUTH, east=EAST, north=NORTH):
    """左上の経緯度と画素の大きさから、切り出す行・列の範囲 (row0, row1, col0, col1) を返す。"""
    lon0, lat0, step = transform
    col0, col1 = int((west - lon0) / step), int((east - lon0) / step) + 1
    row0, row1 = int((lat0 - north) / step), int((lat0 - south) / step) + 1
    if not (0 <= row0 < row1 <= shape[0] and 0 <= col0 < col1 <= shape[1]):
        raise ValueError('切り出す範囲が画像の外です')
    return row0, row1, col0, col1


def main():
    import numpy as np
    import tifffile
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('tif', type=Path)
    parser.add_argument('--output', type=Path, required=True, help='書き出す名前（.npy と .json を付ける）')
    args = parser.parse_args()
    with tifffile.TiffFile(args.tif) as tif:
        page = tif.pages[0]
        tie = page.tags['ModelTiepointTag'].value
        scale = page.tags['ModelPixelScaleTag'].value
        transform = (tie[3], tie[4], scale[0])
        rows = window(transform, page.shape)
        data = tif.asarray(out='memmap') if page.is_memmappable else tif.asarray()
        crop = np.asarray(data[rows[0]:rows[1], rows[2]:rows[3]], dtype=np.float32)
    crop = np.nan_to_num(np.clip(crop, 0, None))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    np.save(args.output.with_suffix('.npy'), crop)
    lon0, lat0, step = transform
    info = {'west': lon0 + rows[2] * step, 'north': lat0 - rows[0] * step, 'step': step,
            'rows': crop.shape[0], 'columns': crop.shape[1], 'unit': 'nW/cm2/sr', 'source': args.tif.name}
    args.output.with_suffix('.json').write_text(json.dumps(info, indent=2) + '\n')
    print(f'{crop.shape} 最大 {crop.max():.1f} 中央値 {float(np.median(crop)):.2f}')


if __name__ == '__main__':
    main()
