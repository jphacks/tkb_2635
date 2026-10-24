"""plateau_shapes.py の JSON から、アプリで読む都市の 3D ファイル（USDZ）を Blender で作る。

使い方（リポジトリのルートで）:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender_city_usdz.py -- 入力.json 出力.usdz

形と UV（テクスチャの貼り方）だけを書き出す。色・窓明かり・屋上のテクスチャはアプリが部品の名前ごとに付ける。
座標は x=東・y=北・z=シーンの地面からの高さ [m]。RealityKit は Z 上向きの USD を Y 上向きに直して読む。
"""
import json
import sys

import bmesh
import bpy
from mathutils import Vector

# App/Views/BuildingFacade.swift の columnMeters × tileColumns、floorMeters × tileRows と合わせる。
FACADE_TILE_U = 3.6 * 8
FACADE_TILE_V = 3.9 * 8
# 屋上・設備の CC0 テクスチャ1枚が覆う大きさ [m]
ROOF_TILE = 6.0


def build(name, polygons, collection):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new('UVMap')
    for flat in polygons:
        points = []
        for i in range(0, len(flat), 3):
            p = Vector(flat[i:i + 3])
            if not points or (p - points[-1]).length > 1e-3:
                points.append(p)
        if len(points) > 3 and (points[0] - points[-1]).length <= 1e-3:
            points.pop()
        if len(points) < 3:
            continue
        try:
            face = bm.faces.new([bm.verts.new(p) for p in points])
        except ValueError:
            continue
        face.normal_update()
        n = face.normal
        if n.length < 0.5:
            bm.faces.remove(face)
            continue
        facade = name != 'roof'
        for loop in face.loops:
            co = loop.vert.co
            if abs(n.z) > 0.7:
                loop[uv].uv = (co.x / ROOF_TILE, co.y / ROOF_TILE)
            else:
                # 壁は水平方向の長さと地面からの高さで貼り、階の帯を建物どうしでそろえる。
                t = Vector((-n.y, n.x)).normalized() if Vector((n.x, n.y)).length > 1e-6 else Vector((1, 0))
                along = co.x * t.x + co.y * t.y
                if facade:
                    loop[uv].uv = (along / FACADE_TILE_U, co.z / FACADE_TILE_V)
                else:
                    loop[uv].uv = (along / ROOF_TILE, co.z / ROOF_TILE)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.005)
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method='BEAUTY', ngon_method='EAR_CLIP')
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for polygon in mesh.polygons:
        polygon.use_smooth = False
    # アプリが名前で素材を差し替えるときの目印として、部品と同じ名前の仮の素材を付ける。
    mesh.materials.append(bpy.data.materials.new(name))
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return len(mesh.polygons)


def main():
    source, output = sys.argv[sys.argv.index('--') + 1:][:2]
    data = json.loads(open(source).read())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    collection = bpy.context.scene.collection
    counts = {name: build(name, polygons, collection) for name, polygons in sorted(data['groups'].items())}
    bpy.ops.wm.usd_export(filepath=output, export_materials=True, generate_preview_surface=True,
                          export_uvmaps=True, export_normals=True, export_textures=False)
    print('triangles', sum(counts.values()), counts)


main()
