"""広域 3D の建物の壁に貼る、夜の窓明かりのタイル画像を作る（task.md の o-9）。

    python3 scripts/wide_windows_texture.py      # App/Resources/Wide/WideWindows.png を作る（Pillow が要る）

画像 1 枚が、窓 8 列 × 8 階（横 32m × 縦 28m、wide_ward_blender.py の TILE_WIDTH・TILE_HEIGHT）を表し、
上下左右に繰り返して貼る。アプリ（WideCityRenderer）は、この画像を自分で光る色（emissive）として使う。
外壁は暗い青、窓は点いている所だけ暖色〜青白く光る（色は CityModelRenderer の窓明かりの 3 色と同じ）。
左下の角（屋根の UV と、UV の無い LOD2 が指す所）は外壁の色にしておく。
"""
import random
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'App/Resources/Wide/WideWindows.png'
SIZE = 256
COLUMNS = 8
FLOORS = 8
# 1 マスの中の窓の位置（マスの大きさに対する割合）
WINDOW_X = (0.18, 0.82)
WINDOW_Y = (0.25, 0.75)
# 点いている窓の割合（BuildingFacade の夜の点灯率に近い値）
LIT_RATIO = 0.35
WALL = (6, 8, 13)
DARK_GLASS = (12, 16, 26)
# CityModelRenderer.lightColor の窓の 3 色（暖色・白っぽい暖色・青白い）と、その出やすさ
TONES = [((255, 189, 102), 5), ((255, 224, 168), 3), ((219, 232, 250), 2)]
SEED = 2635


def main():
    rng = random.Random(SEED)
    image = Image.new('RGB', (SIZE, SIZE), WALL)
    draw = ImageDraw.Draw(image)
    cell_w, cell_h = SIZE / COLUMNS, SIZE / FLOORS
    colors = [tone for tone, weight in TONES for _ in range(weight)]
    for column in range(COLUMNS):
        for floor in range(FLOORS):
            # 左下の角のマスは、屋根が指す外壁の色のまま残す
            if column == 0 and floor == FLOORS - 1:
                continue
            x0 = column * cell_w + WINDOW_X[0] * cell_w
            x1 = column * cell_w + WINDOW_X[1] * cell_w
            y0 = floor * cell_h + WINDOW_Y[0] * cell_h
            y1 = floor * cell_h + WINDOW_Y[1] * cell_h
            lit = rng.random() < LIT_RATIO
            color = rng.choice(colors) if lit else DARK_GLASS
            if lit:
                # 明るさを少しばらつかせる
                factor = rng.uniform(0.6, 1.0)
                color = tuple(int(c * factor) for c in color)
            draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=color)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    image.save(OUTPUT, optimize=True)
    print(OUTPUT, OUTPUT.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
