"""区の広域 3D を作る（Blender の中で動く）。`build_wide_ward.py` から呼ばれる。

  Blender -b --python scripts/wide_ward_blender.py -- 作業フォルダ 出力.usdz

作業フォルダの `glb/*.glb`（Draco を展開できる形に直した LOD1 の建物）と `rtc.json`（タイルごとの
CESIUM_RTC の中心 = 地球中心座標 [m]）を読み、建物ごとに「向き付きの箱」1つに置き換えて、
区ぜんぶを 1 つのメッシュにして USDZ に書き出す。

座標は `plateau_citygml.to_local` と同じ係数の平面（東 [m]・北 [m]・高さ [m]）。原点は渋谷の原点。
高さはジオイド高（東京 約 36.7m）を引いて標高にする。
"""
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

ORIGIN_LATITUDE = 35.658
ORIGIN_LONGITUDE = 139.7016
GEOID_HEIGHT = 36.7
# 小さすぎる・低すぎる建物は、遠くから見ると形にならないので入れない。
MIN_FOOTPRINT = 25.0    # [m²]
MIN_HEIGHT = 5.0        # [m]
# 1 区あたりの建物の上限。越えたときは「高さ × 床の大きさ」が小さい順に落とす。
MAX_BUILDINGS = 15_000
# 壁の窓明かりのタイル画像（アプリの WideWindowTexture。窓 8 列 × 8 階）1 枚が覆う大きさ [m]。
# 窓 1 マスは BuildingFacade と同じ横 3.6m・縦 3.9m。側面の UV はこの長さで割って繰り返す。
TILE_WIDTH = 8 * 3.6
TILE_HEIGHT = 8 * 3.9
# 屋根の UV（画像の中の窓の無い所 = 外壁の色の 1 点）。窓の無い面はここを指す
ROOF_UV = (0.01, 0.01)

A = 6378137.0
F = 1 / 298.257222101
E2 = F * (2 - F)


def ecef_to_geodetic(xyz):
    x, y, z = xyz[:, 0], xyz[:, 1], xyz[:, 2]
    lon = np.arctan2(y, x)
    p = np.hypot(x, y)
    lat = np.arctan2(z, p * (1 - E2))
    for _ in range(5):
        n = A / np.sqrt(1 - E2 * np.sin(lat) ** 2)
        height = p / np.cos(lat) - n
        lat = np.arctan2(z, p * (1 - E2 * n / (n + height)))
    n = A / np.sqrt(1 - E2 * np.sin(lat) ** 2)
    height = p / np.cos(lat) - n
    return np.degrees(lat), np.degrees(lon), height


def to_local(lat, lon, height):
    east = (lon - ORIGIN_LONGITUDE) * 111_320.0 * math.cos(math.radians(ORIGIN_LATITUDE))
    north = (lat - ORIGIN_LATITUDE) * 110_574.0
    return np.stack([east, north, height - GEOID_HEIGHT], axis=1)


def tile_buildings(path, center):
    """1 タイルから建物ごとの (中心x, 中心y, 長さ, 幅, 角度, 底, 屋根) を返す。"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    out = []
    for obj in bpy.data.objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.data
        mesh.calc_loop_triangles()
        count = len(mesh.vertices)
        if count == 0:
            continue
        co = np.empty(count * 3)
        mesh.vertices.foreach_get('co', co)
        co = co.reshape(-1, 3)
        tri = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int64)
        mesh.loop_triangles.foreach_get('vertices', tri)
        tri = tri.reshape(-1, 3)
        # Blender の glTF 取り込みは Y-up → Z-up 変換済みなので、そのまま地球中心座標のずれ。
        ecef = co.astype(np.float64) + np.asarray(center, dtype=np.float64)
        local = to_local(*ecef_to_geodetic(ecef))
        # Draco の展開後は頂点が共有されない。位置（1cm）で同一視して、つながりを調べる。
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
        for value in np.unique(face_label):
            pts = local[vertex_label == value]
            xy = pts[:, :2]
            mean = xy.mean(axis=0)
            centered = xy - mean
            eigen = np.linalg.eigh(np.cov(centered.T) if len(xy) > 2 else np.eye(2))[1]
            axis = eigen[:, 1]
            angle = math.atan2(axis[1], axis[0])
            c, s = math.cos(angle), math.sin(angle)
            u = centered[:, 0] * c + centered[:, 1] * s
            v = -centered[:, 0] * s + centered[:, 1] * c
            length, width = u.max() - u.min(), v.max() - v.min()
            mid_u, mid_v = (u.max() + u.min()) / 2, (v.max() + v.min()) / 2
            cx = mean[0] + mid_u * c - mid_v * s
            cy = mean[1] + mid_u * s + mid_v * c
            out.append((cx, cy, length, width, angle, pts[:, 2].min(), pts[:, 2].max()))
    return out


def wall_uv(boxes):
    """面ごとの UV（建物 × 5 面 × 4 頂点 × 2）。面の順と頂点の順は build_mesh の faces と同じ。
    側面は、横は辺の長さ、縦は高さをメートルのまま TILE_WIDTH・TILE_HEIGHT で割って窓の大きさをそろえる。
    建物ごとに横をずらして、隣の建物と同じ窓の並びにならないようにする。屋根は ROOF_UV の 1 点。"""
    n = len(boxes)
    _, _, length, width, _, bottom, top = boxes.T
    height = (top - bottom) / TILE_HEIGHT
    # 黄金比で建物ごとに散らす（乱数を使わず、作り直しても同じ見た目にする）
    shift = (np.arange(n) * 0.618034) % 1.0
    uv = np.empty((n, 5, 4, 2))
    uv[:, 0] = ROOF_UV
    # 側面は (0,1,5,4)・(1,2,6,5)・(2,3,7,6)・(3,0,4,7)。辺の長さは length, width, length, width
    for side, edge in enumerate((length, width, length, width), start=1):
        u0 = shift + side * 0.25
        u1 = u0 + edge / TILE_WIDTH
        uv[:, side, 0] = np.stack([u0, np.zeros(n)], axis=1)
        uv[:, side, 1] = np.stack([u1, np.zeros(n)], axis=1)
        uv[:, side, 2] = np.stack([u1, height], axis=1)
        uv[:, side, 3] = np.stack([u0, height], axis=1)
    return uv


def build_mesh(boxes):
    n = len(boxes)
    cx, cy, length, width, angle, bottom, top = boxes.T
    c, s = np.cos(angle), np.sin(angle)
    corners = np.array([(-1, -1), (1, -1), (1, 1), (-1, 1)], dtype=np.float64)
    verts = np.empty((n, 8, 3))
    for i, (sx, sy) in enumerate(corners):
        lx, ly = sx * length / 2, sy * width / 2
        verts[:, i, 0] = cx + lx * c - ly * s
        verts[:, i, 1] = cy + lx * s + ly * c
        verts[:, i, 2] = bottom
        verts[:, i + 4] = verts[:, i]
        verts[:, i + 4, 2] = top
    base = (np.arange(n) * 8)[:, None]
    faces = np.array([(4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)])
    faces = (base[:, None, :] + faces[None]).reshape(-1, 4)
    mesh = bpy.data.meshes.new('wide')
    mesh.vertices.add(n * 8)
    mesh.vertices.foreach_set('co', verts.reshape(-1).astype(np.float32))
    mesh.loops.add(len(faces) * 4)
    mesh.loops.foreach_set('vertex_index', faces.reshape(-1))
    mesh.polygons.add(len(faces))
    mesh.polygons.foreach_set('loop_start', np.arange(len(faces)) * 4)
    mesh.polygons.foreach_set('loop_total', np.full(len(faces), 4))
    uv = mesh.uv_layers.new(name='UVMap')
    uv.data.foreach_set('uv', wall_uv(boxes).reshape(-1).astype(np.float32))
    mesh.update()
    mesh.validate()
    return mesh


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    work, output = Path(argv[0]), argv[1]
    rtc = json.loads((work / 'rtc.json').read_text())
    boxes = []
    for name in sorted(rtc):
        boxes += tile_buildings(work / 'glb' / name, rtc[name])
    boxes = np.array(boxes, dtype=np.float64)
    total = len(boxes)
    keep = (boxes[:, 2] * boxes[:, 3] >= MIN_FOOTPRINT) & (boxes[:, 6] - boxes[:, 5] >= MIN_HEIGHT)
    boxes = boxes[keep]
    if len(boxes) > MAX_BUILDINGS:
        weight = (boxes[:, 6] - boxes[:, 5]) * np.sqrt(boxes[:, 2] * boxes[:, 3])
        boxes = boxes[np.argsort(-weight)[:MAX_BUILDINGS]]
    tallest = boxes[np.argmax(boxes[:, 6])]
    print(f'WIDE buildings={total} kept={len(boxes)} '
          f'tallest east={tallest[0]:.0f} north={tallest[1]:.0f} top={tallest[6]:.0f}')

    bpy.ops.wm.read_factory_settings(use_empty=True)
    mesh = build_mesh(boxes)
    obj = bpy.data.objects.new('wide', mesh)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new('wide')
    material.use_nodes = True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.62, 0.64, 0.68, 1)
    material.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value = 0.9
    mesh.materials.append(material)
    mesh.shade_flat()
    bpy.ops.wm.usd_export(filepath=output, export_materials=True, generate_preview_surface=True,
                          export_normals=True, export_uvmaps=True)


if __name__ == '__main__':
    main()
