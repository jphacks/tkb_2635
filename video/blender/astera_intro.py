"""発表用の紹介動画の 3D 部分（夜の23区 → 東大本郷へ寄る → 空を見上げて星空）を Blender で描く。

  Blender -b --python video/blender/astera_intro.py -- 出力フォルダ [最初のコマ 最後のコマ] [--preview]

建物は `scripts/build_wide_ward.py --lod 2` で作った区ごとの広域 3D（../outputs/wide2-<区コード>/wide.usdz）。
座標は東 [m]・北 [m]・高さ [m]、原点は渋谷。出典: 国土交通省 Project PLATEAU（CC BY 4.0）。
PNG の連番を書き出し、Remotion でタイトルを重ねる（video/remotion）。
"""
import glob
import math
import sys
from pathlib import Path

import bpy

FPS = 30
FRAMES = 600                      # 20 秒
ORBIT_END = 270                   # 0〜9 秒: 回りながら東大へ寄る
TILT_END = 390                    # 9〜13 秒: 上を向く。残りは星空のまま
TODAI = (5463.0, 6059.0, 0.0)     # 東大本郷（安田講堂付近）
WARDS = '/Users/yuya/Developer/outputs/wide2-*/wide.usdz'


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * t * (t * (6 * t - 15) + 10)


def camera_pose(frame):
    """コマごとのカメラの位置と向き（下向き 0°〜真上 180° の傾き、方位）を返す。"""
    t = smooth(frame / ORBIT_END)
    angle = math.radians(-150 + 135 * t)
    radius = 16000 * (1 - t) + 700 * t
    height = 11000 * (1 - t) ** 1.6 + 160 * (1 - (1 - t) ** 1.6)
    x = TODAI[0] + radius * math.cos(angle)
    y = TODAI[1] + radius * math.sin(angle)
    # 寄るあいだは東大を見る
    dx, dy, dz = TODAI[0] - x, TODAI[1] - y, 60 - height
    yaw = math.atan2(-dx, dy)
    pitch = math.atan2(math.hypot(dx, dy), -dz)
    if frame > ORBIT_END:
        # 少しだけ前へ進みながら、上へ向きを変える
        u = smooth((frame - ORBIT_END) / (TILT_END - ORBIT_END))
        pitch = pitch + (math.radians(158) - pitch) * u
        drift = (frame - ORBIT_END) / FPS
        yaw += math.radians(1.2) * drift
        height += 6 * drift
    return (x, y, height), (pitch, 0.0, yaw)


def node(tree, kind, location, **inputs):
    item = tree.nodes.new(kind)
    item.location = location
    for key, value in inputs.items():
        # operation などはノードの設定、それ以外は入力の値
        if hasattr(item, key):
            setattr(item, key, value)
        else:
            item.inputs[key].default_value = value
    return item


def city_material():
    """壁に窓の明かり、屋根は月明かりで少しだけ見える、夜の建物。"""
    material = bpy.data.materials.new('night_city')
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    link = tree.links.new
    out = node(tree, 'ShaderNodeOutputMaterial', (1400, 0))
    geometry = node(tree, 'ShaderNodeNewGeometry', (-1200, 0))
    split_n = node(tree, 'ShaderNodeSeparateXYZ', (-1000, 200))
    link(geometry.outputs['Normal'], split_n.inputs[0])
    split_p = node(tree, 'ShaderNodeSeparateXYZ', (-1000, -200))
    link(geometry.outputs['Position'], split_p.inputs[0])

    # 壁ぞいの横方向の座標（壁の向きに合わせて x と y を混ぜる）
    abs_nx = node(tree, 'ShaderNodeMath', (-800, 300), operation='ABSOLUTE')
    link(split_n.outputs['X'], abs_nx.inputs[0])
    mix_u = tree.nodes.new('ShaderNodeMix')
    mix_u.location = (-600, 0)
    link(abs_nx.outputs[0], mix_u.inputs['Factor'])
    link(split_p.outputs['X'], mix_u.inputs['A'])
    link(split_p.outputs['Y'], mix_u.inputs['B'])

    def grid(value, size, low, high, location):
        scaled = node(tree, 'ShaderNodeMath', location, operation='DIVIDE')
        link(value, scaled.inputs[0])
        scaled.inputs[1].default_value = size
        cell = node(tree, 'ShaderNodeMath', (location[0] + 150, location[1] + 80), operation='FLOOR')
        link(scaled.outputs[0], cell.inputs[0])
        frac = node(tree, 'ShaderNodeMath', (location[0] + 150, location[1] - 80), operation='FRACT')
        link(scaled.outputs[0], frac.inputs[0])
        lo = node(tree, 'ShaderNodeMath', (location[0] + 300, location[1] - 250), operation='GREATER_THAN')
        link(frac.outputs[0], lo.inputs[0])
        lo.inputs[1].default_value = low
        hi = node(tree, 'ShaderNodeMath', (location[0] + 450, location[1] - 250), operation='LESS_THAN')
        link(frac.outputs[0], hi.inputs[0])
        hi.inputs[1].default_value = high
        both = node(tree, 'ShaderNodeMath', (location[0] + 600, location[1] - 250), operation='MULTIPLY')
        link(lo.outputs[0], both.inputs[0])
        link(hi.outputs[0], both.inputs[1])
        return cell.outputs[0], both.outputs[0]

    cell_u, in_u = grid(mix_u.outputs['Result'], 3.6, 0.18, 0.82, (-400, 200))
    cell_v, in_v = grid(split_p.outputs['Z'], 3.4, 0.3, 0.85, (-400, -300))
    combine = node(tree, 'ShaderNodeCombineXYZ', (300, 300))
    link(cell_u, combine.inputs['X'])
    link(cell_v, combine.inputs['Y'])
    noise = node(tree, 'ShaderNodeTexWhiteNoise', (450, 300))
    noise.noise_dimensions = '3D'
    link(combine.outputs[0], noise.inputs['Vector'])
    lit = node(tree, 'ShaderNodeMath', (650, 300), operation='GREATER_THAN')
    link(noise.outputs['Value'], lit.inputs[0])
    lit.inputs[1].default_value = 0.7
    window = node(tree, 'ShaderNodeMath', (650, 0), operation='MULTIPLY')
    link(in_u, window.inputs[0])
    link(in_v, window.inputs[1])
    abs_nz = node(tree, 'ShaderNodeMath', (-800, 500), operation='ABSOLUTE')
    link(split_n.outputs['Z'], abs_nz.inputs[0])
    wall = node(tree, 'ShaderNodeMath', (-600, 500), operation='LESS_THAN')
    link(abs_nz.outputs[0], wall.inputs[0])
    wall.inputs[1].default_value = 0.5
    mask = node(tree, 'ShaderNodeMath', (850, 150), operation='MULTIPLY')
    link(window.outputs[0], mask.inputs[0])
    link(lit.outputs[0], mask.inputs[1])
    mask2 = node(tree, 'ShaderNodeMath', (1000, 150), operation='MULTIPLY')
    link(mask.outputs[0], mask2.inputs[0])
    link(wall.outputs[0], mask2.inputs[1])
    # 明かりの色は、暖色と白をまぜる
    tint = node(tree, 'ShaderNodeValToRGB', (850, 450))
    tint.color_ramp.elements[0].position = 0.65
    tint.color_ramp.elements[0].color = (1.0, 0.55, 0.2, 1)
    tint.color_ramp.elements[1].color = (0.75, 0.85, 1.0, 1)
    link(noise.outputs['Color'], tint.inputs['Fac'])
    # 遠くの街は、窓が細かすぎて白くつぶれるので、離れるほど暗くする
    camera = node(tree, 'ShaderNodeCameraData', (850, -100))
    fade = node(tree, 'ShaderNodeMapRange', (1000, -100))
    link(camera.outputs['View Distance'], fade.inputs['Value'])
    fade.inputs['From Min'].default_value = 400
    fade.inputs['From Max'].default_value = 8000
    fade.inputs['To Min'].default_value = 2.0
    fade.inputs['To Max'].default_value = 1.6
    strength = node(tree, 'ShaderNodeMath', (1150, 150), operation='MULTIPLY')
    link(mask2.outputs[0], strength.inputs[0])
    link(fade.outputs[0], strength.inputs[1])

    bsdf = node(tree, 'ShaderNodeBsdfPrincipled', (1150, -200))
    bsdf.inputs['Base Color'].default_value = (0.035, 0.04, 0.06, 1)
    bsdf.inputs['Roughness'].default_value = 0.8
    link(tint.outputs['Color'], bsdf.inputs['Emission Color'])
    link(strength.outputs[0], bsdf.inputs['Emission Strength'])
    link(bsdf.outputs[0], out.inputs['Surface'])
    return material


def ground_material():
    """地面。道路の明かりがにじんだような、まだらの暖色。"""
    material = bpy.data.materials.new('night_ground')
    material.use_nodes = True
    tree = material.node_tree
    link = tree.links.new
    bsdf = tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (0.01, 0.012, 0.02, 1)
    bsdf.inputs['Roughness'].default_value = 1.0
    coords = node(tree, 'ShaderNodeTexCoord', (-900, 0))
    noise = node(tree, 'ShaderNodeTexNoise', (-700, 0))
    noise.inputs['Scale'].default_value = 0.02
    noise.inputs['Detail'].default_value = 8
    link(coords.outputs['Object'], noise.inputs['Vector'])
    ramp = node(tree, 'ShaderNodeValToRGB', (-500, 0))
    ramp.color_ramp.elements[0].position = 0.55
    ramp.color_ramp.elements[0].color = (0, 0, 0, 1)
    ramp.color_ramp.elements[1].color = (0.03, 0.016, 0.006, 1)
    link(noise.outputs['Fac'], ramp.inputs['Fac'])
    link(ramp.outputs['Color'], bsdf.inputs['Emission Color'])
    bsdf.inputs['Emission Strength'].default_value = 1.0
    return material


def marker_material():
    material = bpy.data.materials.new('todai_marker')
    material.use_nodes = True
    bsdf = material.node_tree.nodes['Principled BSDF']
    bsdf.inputs['Base Color'].default_value = (0, 0, 0, 1)
    bsdf.inputs['Emission Color'].default_value = (0.3, 0.85, 1.0, 1)
    bsdf.inputs['Emission Strength'].default_value = 8.0
    return material


def world():
    """空。細かい星を手続きで描き、地平線の近くは街明かりで少し明るくする。"""
    sky = bpy.data.worlds.new('night')
    bpy.context.scene.world = sky
    sky.use_nodes = True
    tree = sky.node_tree
    link = tree.links.new
    background = tree.nodes['Background']
    coords = node(tree, 'ShaderNodeTexCoord', (-1400, 0))
    total = None
    # 大きさの違う星を 3 層重ねる
    for index, (scale, size, power, gain) in enumerate([(90, 0.07, 10, 60), (220, 0.12, 9, 18), (520, 0.18, 8, 6)]):
        voronoi = node(tree, 'ShaderNodeTexVoronoi', (-1100, index * -300))
        voronoi.inputs['Scale'].default_value = scale
        voronoi.inputs['Randomness'].default_value = 1.0
        link(coords.outputs['Generated'], voronoi.inputs['Vector'])
        dot = node(tree, 'ShaderNodeMapRange', (-900, index * -300))
        link(voronoi.outputs['Distance'], dot.inputs['Value'])
        dot.inputs['From Min'].default_value = 0.0
        dot.inputs['From Max'].default_value = size
        dot.inputs['To Min'].default_value = 1.0
        dot.inputs['To Max'].default_value = 0.0
        split = node(tree, 'ShaderNodeSeparateColor', (-900, index * -300 - 150))
        link(voronoi.outputs['Color'], split.inputs[0])
        bright = node(tree, 'ShaderNodeMath', (-700, index * -300 - 150), operation='POWER')
        link(split.outputs['Red'], bright.inputs[0])
        bright.inputs[1].default_value = power
        star = node(tree, 'ShaderNodeMath', (-550, index * -300), operation='MULTIPLY')
        link(dot.outputs[0], star.inputs[0])
        link(bright.outputs[0], star.inputs[1])
        scaled = node(tree, 'ShaderNodeMath', (-400, index * -300), operation='MULTIPLY')
        link(star.outputs[0], scaled.inputs[0])
        scaled.inputs[1].default_value = gain
        if total is None:
            total = scaled.outputs[0]
        else:
            add = node(tree, 'ShaderNodeMath', (-250, index * -300), operation='ADD')
            link(total, add.inputs[0])
            link(scaled.outputs[0], add.inputs[1])
            total = add.outputs[0]
    # 天の川（NASA の星図をぼんやりした光として使う）
    # 最後に見上げた向きに、星図の天の川（画像の u≈0.8, v≈0.35）が来るように回す
    import mathutils
    pitch, _, yaw = camera_pose(FRAMES - 1)[1]
    forward = mathutils.Euler((pitch, 0, yaw)).to_matrix() @ mathutils.Vector((0, 0, -1))
    up = mathutils.Euler((pitch, 0, yaw)).to_matrix() @ mathutils.Vector((0, 1, 0))
    azimuth = (0.8 - 0.5) * 2 * math.pi
    elevation = (0.35 - 0.5) * math.pi
    target = mathutils.Vector((-math.cos(elevation) * math.cos(azimuth), math.cos(elevation) * math.sin(azimuth),
                               math.sin(elevation)))
    rotation = forward.rotation_difference(target)
    mapping = node(tree, 'ShaderNodeMapping', (-900, 400))
    mapping.inputs['Rotation'].default_value = rotation.to_euler()
    link(coords.outputs['Generated'], mapping.inputs['Vector'])
    milky = node(tree, 'ShaderNodeTexEnvironment', (-700, 400))
    link(mapping.outputs[0], milky.inputs['Vector'])
    milky.image = bpy.data.images.load(str(Path(__file__).resolve().parents[2] / 'App/Resources/Sky/stars_dark.png'))
    milky_gain = node(tree, 'ShaderNodeVectorMath', (-450, 400), operation='SCALE')
    link(milky.outputs['Color'], milky_gain.inputs[0])
    milky_gain.inputs['Scale'].default_value = 0.9
    # 地平線の街明かり（下ほど暖色）
    split_dir = node(tree, 'ShaderNodeSeparateXYZ', (-1100, 600))
    link(coords.outputs['Generated'], split_dir.inputs[0])
    horizon = node(tree, 'ShaderNodeMapRange', (-900, 600))
    link(split_dir.outputs['Z'], horizon.inputs['Value'])
    horizon.inputs['From Min'].default_value = 0.0
    horizon.inputs['From Max'].default_value = 0.35
    horizon.inputs['To Min'].default_value = 1.0
    horizon.inputs['To Max'].default_value = 0.0
    glow = node(tree, 'ShaderNodeValToRGB', (-700, 700))
    glow.color_ramp.elements[0].color = (0.002, 0.003, 0.009, 1)
    glow.color_ramp.elements[1].color = (0.06, 0.04, 0.045, 1)
    link(horizon.outputs[0], glow.inputs['Fac'])
    star_color = node(tree, 'ShaderNodeCombineColor', (-100, 0))
    link(total, star_color.inputs['Red'])
    link(total, star_color.inputs['Green'])
    link(total, star_color.inputs['Blue'])
    add1 = node(tree, 'ShaderNodeVectorMath', (100, 300), operation='ADD')
    link(star_color.outputs[0], add1.inputs[0])
    link(milky_gain.outputs[0], add1.inputs[1])
    add2 = node(tree, 'ShaderNodeVectorMath', (300, 300), operation='ADD')
    link(add1.outputs[0], add2.inputs[0])
    link(glow.outputs['Color'], add2.inputs[1])
    link(add2.outputs[0], background.inputs['Color'])
    background.inputs['Strength'].default_value = 1.0


def build_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    city = city_material()
    for path in sorted(glob.glob(WARDS)):
        bpy.ops.wm.usd_import(filepath=path)
    for obj in list(scene.objects):
        if obj.type == 'MESH':
            obj.data.materials.clear()
            obj.data.materials.append(city)

    bpy.ops.mesh.primitive_plane_add(size=200000, location=(3500, 2000, -1))
    bpy.context.object.data.materials.append(ground_material())
    # 東大本郷の目印（地面の光の輪）
    bpy.ops.mesh.primitive_torus_add(location=(TODAI[0], TODAI[1], 2), major_radius=260, minor_radius=6)
    bpy.context.object.data.materials.append(marker_material())

    bpy.ops.object.light_add(type='SUN', rotation=(math.radians(55), 0, math.radians(-30)))
    moon = bpy.context.object.data
    moon.energy = 0.25
    moon.color = (0.6, 0.7, 1.0)

    world()

    camera_data = bpy.data.cameras.new('camera')
    camera_data.lens = 26
    camera_data.clip_start = 5
    camera_data.clip_end = 60000
    camera = bpy.data.objects.new('camera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    for frame in range(FRAMES):
        location, rotation = camera_pose(frame)
        camera.location = location
        camera.rotation_euler = rotation
        camera.keyframe_insert('location', frame=frame + 1)
        camera.keyframe_insert('rotation_euler', frame=frame + 1)

    scene.render.engine = 'BLENDER_EEVEE'
    scene.eevee.taa_render_samples = 32
    scene.eevee.use_bloom = True
    scene.eevee.bloom_intensity = 0.06
    scene.eevee.bloom_threshold = 0.9
    scene.view_settings.view_transform = 'Filmic'
    scene.view_settings.look = 'High Contrast'
    scene.render.resolution_x = 1920
    scene.render.resolution_y = 1080
    scene.render.fps = FPS
    scene.render.image_settings.file_format = 'PNG'
    scene.frame_start = 1
    scene.frame_end = FRAMES


def main():
    argv = sys.argv[sys.argv.index('--') + 1:]
    output = Path(argv[0])
    numbers = [int(a) for a in argv[1:] if a.isdigit()]
    build_scene()
    scene = bpy.context.scene
    if '--preview' in argv:
        scene.render.resolution_percentage = 50
        scene.eevee.taa_render_samples = 16
    scene.eevee.taa_render_samples = 16
    if '--sky' in argv:
        # 見上げたあとは街が画面に入らないので、建物を外して速く描く
        for obj in list(scene.objects):
            if obj.type == 'MESH':
                obj.hide_render = True
    if numbers:
        scene.frame_start, scene.frame_end = numbers[0], numbers[-1]
    scene.render.filepath = str(output / 'frame_')
    if '--frames' in argv:
        return
    if '--stills' in argv:
        for frame in numbers:
            scene.frame_set(frame)
            scene.render.filepath = str(output / f'still_{frame:04d}.png')
            bpy.ops.render.render(write_still=True)
        return
    bpy.ops.render.render(animation=True)


if __name__ == '__main__':
    main()
