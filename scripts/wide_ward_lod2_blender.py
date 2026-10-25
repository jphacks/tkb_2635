"""区の広域 3D を LOD2（屋根の形つき）で作る（Blender の中で動く）。`build_wide_ward.py --lod 2` から呼ばれる。

  Blender -b --python scripts/wide_ward_lod2_blender.py -- 作業フォルダ 出力.usdz

箱にする `wide_ward_blender.py` と同じく、小さい・低い建物を落とし、座標は同じ平面（原点は渋谷の原点）にする。
違いは建物を箱にせず、形をそのまま残すこと。容量を抑えるために、地面側（下向き）の面を捨て、
近い頂点をつなぎ、同じ平面の面を 1 つにまとめる。
"""
import json
import os
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from wide_ward_blender import (MIN_FOOTPRINT, MIN_HEIGHT, ecef_to_geodetic, to_local)

WELD = float(os.environ.get('LOD2_WELD', 20))             # 頂点をつなぐ細かさ [1/m]（20 で 5cm）
FLAT_ANGLE = float(os.environ.get('LOD2_ANGLE', 0.035))   # 同じ平面とみなす角度 [rad]（約 2°）
NORMALS = os.environ.get('LOD2_NORMALS', '0') == '1'      # 面の向きを USDZ に入れるか
DOWN_NORMAL = -0.5   # これより下を向く面は捨てる
# 1 区あたりの三角形の上限（つなぐ前）。越えたときは「高さ × 床の大きさ」が小さい建物から落とす。
# 渋谷区（約 113 万）で 13MB なので、約 15MB に収まる。
MAX_TRIANGLES = int(os.environ.get('LOD2_MAX_TRIANGLES', 1_300_000))


def tile_buildings(path, center):
    """1 タイルから、残す建物ごとの (重み, 三角形（面数 × 3 点 × 3）) を返す。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    out = []
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or len(obj.data.vertices) == 0:
            continue
        mesh = obj.data
        mesh.calc_loop_triangles()
        co = np.empty(len(mesh.vertices) * 3)
        mesh.vertices.foreach_get('co', co)
        ecef = co.reshape(-1, 3).astype(np.float64) + np.asarray(center, dtype=np.float64)
        local = to_local(*ecef_to_geodetic(ecef))
        tri = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int64)
        mesh.loop_triangles.foreach_get('vertices', tri)
        tri = tri.reshape(-1, 3)
        # 位置（1cm）で同一視して、建物ごとのつながりを調べる（箱版と同じ）。
        key = np.round(local * 100).astype(np.int64)
        _, vertex_id, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
        inverse = inverse.reshape(-1)
        label = np.arange(len(vertex_id))
        corner = inverse[tri]
        while True:
            low = label[corner].min(axis=1)
            new = label.copy()
            for k in range(3):
                np.minimum.at(new, corner[:, k], low)
            if (new == label).all():
                break
            label = new
        face_label = label[corner[:, 0]]
        vertex_label = label[inverse]
        a, b, c = local[tri[:, 0]], local[tri[:, 1]], local[tri[:, 2]]
        normal = np.cross(b - a, c - a)
        length = np.linalg.norm(normal, axis=1)
        up = normal[:, 2] / np.maximum(length, 1e-9)
        usable = (up > DOWN_NORMAL) & (length > 1e-6)
        for value in np.unique(face_label):
            pts = local[vertex_label == value]
            size = pts.max(axis=0) - pts.min(axis=0)
            if size[0] * size[1] < MIN_FOOTPRINT or size[2] < MIN_HEIGHT:
                continue
            faces = tri[(face_label == value) & usable]
            if len(faces):
                out.append((size[2] * np.sqrt(size[0] * size[1]), local[faces].astype(np.float32)))
    return out


def build_mesh(triangles):
    """三角形（面数 × 3 点 × 3）から、近い頂点をつないだメッシュを作る。"""
    points = triangles.reshape(-1, 3)
    key = np.round(points * WELD).astype(np.int64)
    _, first, inverse = np.unique(key, axis=0, return_index=True, return_inverse=True)
    inverse = inverse.reshape(-1)
    faces = inverse.reshape(-1, 3)
    faces = faces[(faces[:, 0] != faces[:, 1]) & (faces[:, 1] != faces[:, 2]) & (faces[:, 0] != faces[:, 2])]
    mesh = bpy.data.meshes.new('wide')
    mesh.from_pydata(points[first].tolist(), [], faces.tolist())
    mesh.update()
    return mesh


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    work, output = Path(argv[0]), argv[1]
    rtc = json.loads((work / 'rtc.json').read_text())
    cache = work / 'triangles.npy'
    if cache.exists():
        triangles = np.load(cache)
    else:
        buildings = []
        for name in sorted(rtc):
            buildings += tile_buildings(work / 'glb' / name, rtc[name])
        buildings.sort(key=lambda item: -item[0])
        count, kept = 0, []
        for _, faces in buildings:
            if count + len(faces) > MAX_TRIANGLES:
                break
            kept.append(faces)
            count += len(faces)
        print(f'WIDE2 buildings={len(buildings)} kept={len(kept)}')
        triangles = np.concatenate(kept)
        np.save(cache, triangles)
    print(f'WIDE2 triangles={len(triangles)}')

    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = build_mesh(triangles)
    graph = bmesh.new()
    graph.from_mesh(mesh)
    bmesh.ops.dissolve_limit(graph, angle_limit=FLAT_ANGLE, verts=graph.verts, edges=graph.edges)
    graph.to_mesh(mesh)
    graph.free()
    print(f'WIDE2 verts={len(mesh.vertices)} faces={len(mesh.polygons)}')

    obj = bpy.data.objects.new('wide', mesh)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new('wide')
    material.use_nodes = True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.62, 0.64, 0.68, 1)
    material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
    mesh.materials.append(material)
    mesh.shade_flat()
    bpy.ops.wm.usd_export(filepath=output, export_materials=True, generate_preview_surface=True,
                          export_normals=NORMALS)


if __name__ == '__main__':
    main()
