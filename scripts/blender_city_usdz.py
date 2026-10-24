"""plateau_shapes.py の JSON から、アプリで読む都市の 3D ファイル（USDZ）を Blender で作る。

使い方（リポジトリのルートで）:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender_city_usdz.py -- 入力.json 出力.usdz [地面の写真のフォルダ]

地面の写真のフォルダは download_gsi_photo.py の出力。指定すると、地理院タイルの航空写真を貼った地面（ground_photo）を足す。

PLATEAU の実写テクスチャ（約4,000枚）は、縮めて 4096px 四方の画像（アトラス）数枚にまとめて USDZ に埋め込む。
部品（＝描画の回数）を少なく保ち、実機の GPU メモリに収めるため。写真の無い面は形と UV だけを書き出し、
アプリが部品の名前（facade_<種類>_<模様>・roof）で夜景の窓や屋上の素材を付ける。
座標は x=東・y=北・z=シーンの地面からの高さ [m]。RealityKit は Z 上向きの USD を Y 上向きに直して読む。
"""
import json
import math
from pathlib import Path
import sys

import bmesh
import bpy
from mathutils import Vector
import numpy as np

# App/Views/BuildingFacade.swift の columnMeters × tileColumns、floorMeters × tileRows と合わせる。
FACADE_TILE_U = 3.6 * 8
FACADE_TILE_V = 3.9 * 8
# 屋上・設備の CC0 テクスチャ1枚が覆う大きさ [m]
ROOF_TILE = 6.0
ATLAS = 4096
# アトラスの枚数の目安。1枚 4096px 四方で、GPU メモリは約 90MB（ミップマップ込み）。
ATLAS_BUDGET = 2
PAD = 2
# 地面の航空写真の1辺の画素数（約1.6km 四方を 0.8m/画素ほどにする）
GROUND_PIXELS = 2048


def tiled_uv(name, co, n):
    if abs(n.z) > 0.7:
        return co.x / ROOF_TILE, co.y / ROOF_TILE
    # 壁は水平方向の長さと地面からの高さで貼り、階の帯を建物どうしでそろえる。
    t = Vector((-n.y, n.x)).normalized() if Vector((n.x, n.y)).length > 1e-6 else Vector((1, 0))
    along = co.x * t.x + co.y * t.y
    if name == 'roof':
        return along / ROOF_TILE, co.z / ROOF_TILE
    return along / FACADE_TILE_U, co.z / FACADE_TILE_V


def build(name, polygons, collection, material):
    """polygons は (座標の平らな列, UV の平らな列 または None)。UV が無い面は tiled_uv で貼る。"""
    bm = bmesh.new()
    layer = bm.loops.layers.uv.new('UVMap')
    for flat, uv in polygons:
        points, coords = [], []
        for i in range(0, len(flat), 3):
            p = Vector(flat[i:i + 3])
            if points and (p - points[-1]).length <= 1e-3:
                continue
            points.append(p)
            coords.append(uv[i // 3 * 2:i // 3 * 2 + 2] if uv else None)
        if len(points) > 3 and (points[0] - points[-1]).length <= 1e-3:
            points.pop()
            coords.pop()
        if len(points) < 3:
            continue
        try:
            face = bm.faces.new([bm.verts.new(p) for p in points])
        except ValueError:
            continue
        face.normal_update()
        if face.normal.length < 0.5:
            bm.faces.remove(face)
            continue
        for loop, coord in zip(face.loops, coords):
            loop[layer].uv = coord if coord else tiled_uv(name, loop.vert.co, face.normal)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.005)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='EAR_CLIP')
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return len(mesh.polygons)


def pack(paths):
    """画像を縮めて棚詰めでアトラスに並べる。戻り値は (アトラスの画素の列, 画像ごとの (番号, x, y, 幅, 高さ))。"""
    images = [bpy.data.images.load(str(p), check_existing=False) for p in paths]
    area = sum(i.size[0] * i.size[1] for i in images)
    scale = min(1.0, math.sqrt(ATLAS * ATLAS * ATLAS_BUDGET * 0.8 / area))
    sizes = [(max(4, round(i.size[0] * scale)), max(4, round(i.size[1] * scale))) for i in images]
    order = sorted(range(len(images)), key=lambda k: -sizes[k][1])
    pages, places = [], [None] * len(images)
    x = y = shelf = 0
    for k in order:
        w, h = sizes[k][0] + 2 * PAD, sizes[k][1] + 2 * PAD
        if x + w > ATLAS:
            x, y, shelf = 0, y + shelf, 0
        if not pages or y + h > ATLAS:
            pages.append(np.zeros((ATLAS, ATLAS, 4), dtype=np.float32))
            x = y = shelf = 0
        image = images[k]
        image.scale(*sizes[k])
        pixels = np.empty(sizes[k][0] * sizes[k][1] * 4, dtype=np.float32)
        image.pixels.foreach_get(pixels)
        tile = pixels.reshape(sizes[k][1], sizes[k][0], 4)
        # ミップマップで隣の写真がにじまないよう、縁の色を外側へ伸ばす。
        pages[-1][y:y + h, x:x + w] = np.pad(tile, ((PAD, PAD), (PAD, PAD), (0, 0)), mode='edge')
        places[k] = (len(pages) - 1, x + PAD, y + PAD, *sizes[k])
        x, shelf = x + w, max(shelf, h)
        bpy.data.images.remove(image)
    print('atlas scale', round(scale, 3), 'pages', len(pages))
    return pages, places


def atlas_material(index, pixels, folder):
    image = bpy.data.images.new(f'atlas_{index}', ATLAS, ATLAS)
    image.pixels.foreach_set(pixels.ravel())
    image.filepath_raw = str(folder / f'atlas_{index}.jpg')
    image.file_format = 'JPEG'
    bpy.context.scene.render.image_settings.quality = 85
    image.save()
    material = bpy.data.materials.new(f'atlas_{index}')
    material.use_nodes = True
    texture = material.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    shader = material.node_tree.nodes['Principled BSDF']
    shader.inputs['Roughness'].default_value = 0.85
    material.node_tree.links.new(texture.outputs['Color'], shader.inputs['Base Color'])
    return material


def ground_photo(folder, data, collection, work):
    """地理院タイルをつないだ1枚の画像を、シーンの地面より少し下に貼る。"""
    info = json.loads((folder / 'ground.json').read_text())
    size = 256
    canvas = np.zeros((info['rows'] * size, info['columns'] * size, 4), dtype=np.float32)
    for column in range(info['columns']):
        for row in range(info['rows']):
            image = bpy.data.images.load(str(folder / f"{info['zoom']}/{info['x0'] + column}/{info['y0'] + row}.jpg"))
            pixels = np.empty(size * size * 4, dtype=np.float32)
            image.pixels.foreach_get(pixels)
            # Blender の画素は下の行から並ぶ。タイルの行番号は北（上）から数える。
            bottom = (info['rows'] - 1 - row) * size
            canvas[bottom:bottom + size, column * size:(column + 1) * size] = pixels.reshape(size, size, 4)
            bpy.data.images.remove(image)
    image = bpy.data.images.new('ground_photo', canvas.shape[1], canvas.shape[0])
    image.pixels.foreach_set(canvas.ravel())
    image.scale(GROUND_PIXELS, GROUND_PIXELS)
    image.filepath_raw = str(work / 'ground_photo.jpg')
    image.file_format = 'JPEG'
    image.save()
    material = bpy.data.materials.new('ground_photo')
    material.use_nodes = True
    texture = material.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = image
    material.node_tree.links.new(texture.outputs['Color'], material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])

    # plateau_citygml.to_local と同じ係数で、写真の四隅をシーンの東・北 [m] にする。
    lat0, lon0 = data['originLatitude'], data['originLongitude']
    east = lambda lon: (lon - lon0) * 111_320.0 * math.cos(math.radians(lat0))
    north = lambda lat: (lat - lat0) * 110_574.0
    w, e, s, n = east(info['west']), east(info['east']), north(info['south']), north(info['north'])
    # 建物の壁の下端（高さ 0）とちらつかないよう、少し下げる。
    z = -0.3
    mesh = bpy.data.meshes.new('ground_photo')
    mesh.from_pydata([(w, s, z), (e, s, z), (e, n, z), (w, n, z)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name='UVMap')
    for loop, coord in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = coord
    mesh.materials.append(material)
    collection.objects.link(bpy.data.objects.new('ground_photo', mesh))


def main():
    arguments = sys.argv[sys.argv.index('--') + 1:]
    source, output = arguments[:2]
    source = Path(source)
    data = json.loads(source.read_text())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    collection = bpy.context.scene.collection
    counts = {}
    for name, polygons in sorted(data['groups'].items()):
        # アプリが名前で素材を差し替えるときの目印として、部品と同じ名前の仮の素材を付ける。
        counts[name] = build(name, [(p, None) for p in polygons], collection, bpy.data.materials.new(name))

    pages, places = pack([source.parent / p for p in data['images']])
    folder = Path(output).parent / 'atlas-work'
    folder.mkdir(exist_ok=True)
    grouped = [[] for _ in pages]
    for index, flat, uv in data['textured']:
        page, x, y, w, h = places[index]
        # 写真の中の位置を、アトラスの中の位置へ置き換える（UV は左下が原点）。
        mapped = [((x + min(max(u, 0), 1) * w) / ATLAS, (y + min(max(v, 0), 1) * h) / ATLAS)
                  for u, v in zip(uv[::2], uv[1::2])]
        grouped[page].append((flat, [c for p in mapped for c in p]))
    for page, polygons in enumerate(grouped):
        name = f'atlas_{page}'
        counts[name] = build(name, polygons, collection, atlas_material(page, pages[page], folder))

    if len(arguments) > 2:
        ground_photo(Path(arguments[2]), data, collection, folder)

    bpy.ops.wm.usd_export(filepath=output, export_materials=True, generate_preview_surface=True,
                          export_uvmaps=True, export_normals=True, export_textures=True)
    print('triangles', sum(counts.values()), counts)


main()
