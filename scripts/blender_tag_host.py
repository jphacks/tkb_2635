"""作り済みの都市の 3D ファイル（City_<シーンID>.usdz）で、観測者が中にいる建物の面を別の部品に分け、
部品名の最後に host_tag（_h + gml:id の英数字 8 文字）を付け直す。

plateau_shapes.py に hosts が無かったころに作ったシーン（渋谷など）は、観測者の建物が他の建物と同じ部品に
まとまっていて、アプリで建物の形に沿った白い光（ObserverEntryRenderer）を出せない。PLATEAU から作り直さずに、
buildings.json の部分の箱（parts、無ければ建物全体の箱）の中にある面だけを切り出す。

使い方（リポジトリのルートで）:
  /Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender_tag_host.py -- <シーンID> 入力.usdz 出力.usdz
"""
import json
from pathlib import Path
import sys

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[1]
BUILDINGS = ROOT / 'Packages/StarCore/Sources/StarCore/Resources/buildings.json'
SPOTS = ROOT / 'Packages/StarCore/Sources/StarCore/Resources/spots.json'
# 窓明かりの板は壁から少し外に浮かせてあるので、箱より少し広く拾う [m]
MARGIN = 1.0

sys.path.insert(0, str(ROOT / 'scripts'))
from plateau_shapes import host_tag  # noqa: E402


def host_boxes(scene_id):
    """このシーンの観測者の建物ごとに、(目印, 部分の箱の列)。箱は (中心x, 中心y, 幅, 奥行き, 高さ)。"""
    scenes = json.loads(BUILDINGS.read_text())
    scenes = scenes['scenes'] if isinstance(scenes, dict) else scenes
    scene = next(s for s in scenes if s['id'] == scene_id)
    hosts = {s['hostBuildingId'] for s in json.loads(SPOTS.read_text())
             if s.get('sceneId') == scene_id and s.get('hostBuildingId')}
    result = []
    for building in scene['buildings']:
        if building['id'] in hosts:
            parts = building.get('parts') or [[building['x'], building['y'], building['width'],
                                               building['depth'], building['height']]]
            result.append((host_tag(building['id']), parts))
    return result


def inside(point, parts):
    x, y, z = point
    return any(abs(x - px) <= w / 2 + MARGIN and abs(y - py) <= d / 2 + MARGIN and z <= h + MARGIN
               for px, py, w, d, h in parts)


def split(obj, tag, parts):
    """obj の面のうち、箱の中にある面を <obj の名前><tag> の新しい部品へ移す。移した面の数を返す。"""
    mesh = bmesh.new()
    mesh.from_mesh(obj.data)
    picked = [face for face in mesh.faces if inside(obj.matrix_world @ face.calc_center_median(), parts)]
    if not picked or len(picked) == len(mesh.faces):
        mesh.free()
        return 0
    host = bmesh.new()
    host.from_mesh(obj.data)
    keep = {face.index for face in picked}
    bmesh.ops.delete(host, geom=[f for f in host.faces if f.index not in keep], context='FACES')
    bmesh.ops.delete(mesh, geom=picked, context='FACES')
    mesh.to_mesh(obj.data)
    mesh.free()
    copy = obj.copy()
    copy.data = obj.data.copy()
    host.to_mesh(copy.data)
    host.free()
    name = obj.name + tag
    copy.name = name
    copy.data.name = name
    for collection in obj.users_collection:
        collection.objects.link(copy)
    return len(keep)


def main():
    scene_id, source, output = sys.argv[sys.argv.index('--') + 1:][:3]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.wm.usd_import(filepath=source)
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    for tag, parts in host_boxes(scene_id):
        if any(o.name.endswith(tag) for o in meshes):
            print('already tagged', tag)
            continue
        # 地面・街灯・遠くの街の光は建物ではない。航空障害灯はアプリが名前（aviation）で点滅させるので分けない
        moved = {o.name: split(o, tag, parts) for o in meshes
                 if not o.name.startswith(('ground', 'far_lights', 'lamps', 'aviation'))}
        print(tag, {k: v for k, v in moved.items() if v})
    bpy.ops.wm.usd_export(filepath=output, export_materials=True, generate_preview_surface=True,
                          export_uvmaps=True, export_normals=True, export_textures_mode='NEW',
                          usdz_downscale_size='KEEP')


main()
