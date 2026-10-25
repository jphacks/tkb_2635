"""タイトルの文字を、手書きの動きに使う SVG のパスにする（Remotion が読む JSON を書き出す）。

  python3 video/scripts/title_paths.py Astera video/remotion/src/title-paths.json

書体は macOS の Snell Roundhand（Bold）。fontTools が要る（pip install fonttools）。
"""
import json
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTCollection

FONT = '/System/Library/Fonts/Supplemental/SnellRoundhand.ttc'


def main():
    text, output = sys.argv[1], sys.argv[2]
    fonts = TTCollection(FONT).fonts
    font = next(f for f in fonts if 'Bold' in f['name'].getDebugName(2)) if len(fonts) > 1 else fonts[0]
    glyph_set = font.getGlyphSet()
    cmap = font.getBestCmap()
    ascender = font['hhea'].ascent
    glyphs, x = [], 0
    for char in text:
        name = cmap[ord(char)]
        pen = SVGPathPen(glyph_set)
        glyph_set[name].draw(pen)
        bounds = BoundsPen(glyph_set)
        glyph_set[name].draw(bounds)
        glyphs.append({'char': char, 'x': x, 'd': pen.getCommands(), 'bounds': bounds.bounds})
        x += glyph_set[name].width
    xs = [g['x'] + g['bounds'][0] for g in glyphs] + [g['x'] + g['bounds'][2] for g in glyphs]
    ys = [g['bounds'][1] for g in glyphs] + [g['bounds'][3] for g in glyphs]
    json.dump({'glyphs': glyphs, 'box': [min(xs), min(ys), max(xs), max(ys)], 'ascender': ascender},
              open(output, 'w'), ensure_ascii=False)
    print(font['name'].getDebugName(4), [min(xs), min(ys), max(xs), max(ys)])


if __name__ == '__main__':
    main()
