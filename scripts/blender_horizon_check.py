"""3D ファイル（City_<シーン>.usdz）の実形状から、観測者の目から見た方位ごとの遮蔽仰角を測る（4-13 の確認用）。

判定（HorizonProfile）と 3D の見た目がずれていないかを、同じ方位・同じ目の高さで比べるために使う。
地面・街灯・遠くの光・航空障害灯は除き、建物の面だけに光線を当てる。

/Applications/Blender.app/Contents/MacOS/Blender -b --python scripts/blender_horizon_check.py -- \
  App/Resources/City/City_shibuya.usdz out.json '{"shibuya_east_plaza": [109.986, 0.0, 1.5]}'
（座標はシーン原点からの東・北 [m] と、シーンの地面からの目の高さ [m]）
"""
import json
import math
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

# 仰角を上から下へ調べる刻み [度]
STEP = 0.1
SKIPPED = ('ground', 'far', 'lamp', 'aviation')

args = sys.argv[sys.argv.index('--') + 1:]
usdz, output, observers = args[0], args[1], json.loads(args[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=usdz)
depsgraph = bpy.context.evaluated_depsgraph_get()
vertices, polygons = [], []
for obj in bpy.context.scene.objects:
    if obj.type != 'MESH' or any(k in obj.name.lower() for k in SKIPPED):
        continue
    mesh = obj.evaluated_get(depsgraph).to_mesh()
    base = len(vertices)
    vertices += [obj.matrix_world @ v.co for v in mesh.vertices]
    polygons += [[base + i for i in p.vertices] for p in mesh.polygons]
tree = BVHTree.FromPolygons(vertices, polygons)

result = {}
for name, (east, north, eye) in observers.items():
    origin = Vector((east, north, eye))
    samples = []
    for azimuth in range(360):
        a = math.radians(azimuth)
        elevation, found = 89.0, 0.0
        while elevation >= 0:
            r = math.radians(elevation)
            direction = Vector((math.sin(a) * math.cos(r), math.cos(a) * math.cos(r), math.sin(r)))
            if tree.ray_cast(origin, direction)[0] is not None:
                found = elevation
                break
            elevation -= STEP
        samples.append(round(found, 1))
    result[name] = samples
with open(output, 'w') as stream:
    json.dump(result, stream)
print(f'{len(result)} 地点の遮蔽仰角を書き出した: {output}')
