"""惑星の写真から、天体選択画面で使う透明背景の画像を作る（task.md の 8-13）。

  python3 scripts/make_planet_images.py <原本のフォルダ> App/Resources/Planets

原本（リポジトリの外に置く。すべて NASA の探査機の画像で、Wikimedia Commons ではパブリックドメイン）:
  mercury.jpg  MESSENGER（NASA/JHUAPL/CIW）   Mercury_in_color_-_Prockter07-edit1.jpg
  venus.jpg    Mariner 10（NASA/JPL）          Venus_from_Mariner_10.jpg
  mars.jpg     Viking 探査機のモザイク（NASA/USGS） Mars_Valles_Marineris_EDIT.jpg
  jupiter.jpg  Cassini-Huygens（NASA/JPL）      Jupiter_by_Cassini-Huygens.jpg
  saturn.jpg   Cassini（NASA/JPL/Space Science Institute） Saturn_during_Equinox.jpg

黒い背景は、明るさから透明度を作って抜く（夜空の上にそのまま重ねるため）。
水星の欠けた形は、写真に写っている位相そのもの。
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops

MAX_SIDE = 900
NAMES = ['mercury', 'venus', 'mars', 'jupiter', 'saturn']


def cut_out(path):
    image = Image.open(path).convert('RGB')
    luma = image.convert('L')
    # 暗い背景を透明にする。縁がぎざぎざしないよう、少し明るくなる範囲でなだらかにつなぐ。
    alpha = luma.point(lambda v: 0 if v < 10 else min(255, (v - 10) * 255 // 30))
    box = alpha.point(lambda v: 255 if v > 128 else 0).getbbox()
    image.putalpha(alpha)
    image = image.crop(box)
    scale = MAX_SIDE / max(image.size)
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    return image


def main():
    source, output = Path(sys.argv[1]), Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        image = cut_out(source / f'{name}.jpg')
        target = output / f'planet_{name}.png'
        image.save(target, optimize=True)
        print(f'{target.name}: {image.width}x{image.height} {target.stat().st_size / 1e3:.0f} KB')


if __name__ == '__main__':
    main()
