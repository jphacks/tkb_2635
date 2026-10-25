"""夜景の明かり（窓・航空障害灯）の置き場所を決める。plateau_shapes.py から使う。

窓の位置や点き方は実物ではなくイメージ。建物 ID・階・列から決まる乱数で、毎回同じ模様にする。
窓は消える順のグループ（0: 22時ごろ消える事務所、1: 23時ごろ、2: 深夜も残る住宅など）と色ごとに
`windows_<グループ>_<色>` にまとめる。アプリはグループごとに時刻で表示を切り替える
（Packages/StarCore/.../NightLightSchedule.swift の windowGroups と数をそろえる）。
"""
import math

FLOOR = 3.6  # 1階分の高さ [m]
BAY = 3.2  # 窓の間隔 [m]
WINDOW_WIDTH = 1.9
WINDOW_BOTTOM, WINDOW_TOP = 1.0, 2.6  # 階の床からの窓の下端・上端 [m]
SHOP_BOTTOM, SHOP_TOP = 0.4, 3.0  # 1階の店先の明かりの帯
OFFSET = 0.15  # 壁からの浮かせ方 [m]。遠くから見ても壁とちらつかないように
MIN_WALL_HEIGHT = 6.0
AVIATION_HEIGHT = 60.0  # 航空法で航空障害灯が要る高さ [m]

# 用途ごとの (点いている割合, 消える順の重み [0, 1, 2], 色の重み [暖色, 白っぽい暖色, 青白い], 階ごとに帯で点くか)
PROFILES = {
    'office': (0.6, (0.7, 0.25, 0.05), (0.35, 0.45, 0.2), True),
    'commercial': (0.55, (0.45, 0.4, 0.15), (0.45, 0.45, 0.1), True),
    'residential': (0.45, (0.15, 0.4, 0.45), (0.8, 0.2, 0.0), False),
    'other': (0.35, (0.4, 0.4, 0.2), (0.5, 0.4, 0.1), False),
}


def category(usage):
    usage = usage or ''
    if '住宅' in usage or '住居' in usage or '宿泊' in usage:
        return 'residential'
    if '業務' in usage or 'オフィス' in usage or '官公庁' in usage or '文教' in usage:
        return 'office'
    if '商業' in usage:
        return 'commercial'
    return 'other'


def has_shopfront(usage):
    usage = usage or ''
    return '商業' in usage or '店舗' in usage


def unit(*parts):
    """文字列から [0, 1) の決まった乱数（FNV-1a 32bit）。"""
    value = 2_166_136_261
    for byte in '|'.join(str(p) for p in parts).encode():
        value = ((value ^ byte) * 16_777_619) & 0xFFFFFFFF
    return value / 2 ** 32


def pick(weights, r):
    total = 0.0
    for index, weight in enumerate(weights):
        total += weight
        if r < total:
            return index
    return len(weights) - 1


def inside(a, z, polygon):
    """(a, z) が多角形 [(a, z), ...] の内側か（偶奇判定）。"""
    result = False
    for (a1, z1), (a2, z2) in zip(polygon, polygon[1:] + polygon[:1]):
        if (z1 > z) != (z2 > z) and a < a1 + (z - z1) * (a2 - a1) / (z2 - z1):
            result = not result
    return result


def window_quads(points, wall_normal, building_id, usage, wall_index):
    """外向きの法線を持つ壁1枚に窓の四角を並べる。戻り値は {部品名: [平らな座標の列, ...]}。"""
    nx, ny, nz = wall_normal
    horizontal = math.hypot(nx, ny)
    if abs(nz) > 0.3 or horizontal < 1e-6:
        return {}
    nx, ny = nx / horizontal, ny / horizontal
    # 壁に沿った向き t と、壁の面の位置 c（壁は鉛直なので水平の位置だけで決まる）
    tx, ty = -ny, nx
    c = sum(x * nx + y * ny for x, y, _ in points) / len(points) + OFFSET
    polygon = [(x * tx + y * ty, z) for x, y, z in points]
    lo, hi = min(a for a, _ in polygon), max(a for a, _ in polygon)
    top = max(z for _, z in polygon)
    if top - min(z for _, z in polygon) < MIN_WALL_HEIGHT or hi - lo < WINDOW_WIDTH + 1:
        return {}

    def quad(a1, a2, z1, z2):
        corners = [(a1, z1), (a2, z1), (a2, z2), (a1, z2)]
        # 外から見て反時計回り（外向き）になるよう、t の向きに並べる
        return [round(v, 2) for a, z in corners for v in (a * tx + c * nx, a * ty + c * ny, z)]

    def fits(a1, a2, z1, z2):
        return all(inside(a, z, polygon) for a, z in ((a1, z1), (a2, z1), (a2, z2), (a1, z2)))

    lit, group_weights, tone_weights, by_floor = PROFILES[category(usage)]
    result = {}
    bays = int((hi - lo) // BAY)
    margin = (hi - lo - bays * BAY) / 2
    for floor in range(int(top // FLOOR) + 1):
        base = floor * FLOOR
        if floor == 0:
            if has_shopfront(usage) and unit(building_id, wall_index, 'shop') < 0.8 and fits(lo + 0.5, hi - 0.5, SHOP_BOTTOM, SHOP_TOP):
                result.setdefault('windows_1_1', []).append(quad(lo + 0.5, hi - 0.5, SHOP_BOTTOM, SHOP_TOP))
            continue
        z1, z2 = base + WINDOW_BOTTOM, base + WINDOW_TOP
        # 事務所などは階ごとにまとめて点く。グループと色も階で決める
        floor_r = unit(building_id, floor)
        run = None
        for bay in range(bays + 1):
            if bay < bays:
                center = lo + margin + BAY * (bay + 0.5)
                a1, a2 = center - WINDOW_WIDTH / 2, center + WINDOW_WIDTH / 2
                r = unit(building_id, wall_index, floor, bay)
                if by_floor:
                    on = floor_r < lit and r > 0.12
                    key = (pick(group_weights, unit(building_id, floor, 'g')), pick(tone_weights, unit(building_id, floor, 't')))
                else:
                    on = r < lit
                    key = (pick(group_weights, unit(building_id, wall_index, floor, bay, 'g')),
                           pick(tone_weights, unit(building_id, wall_index, floor, bay, 't')))
                on = on and fits(a1, a2, z1, z2)
            else:
                on = False
            # 帯で点く建物は、隣どうしの窓を1つの四角にまとめて数を減らす
            if run and (not on or not by_floor or key != run[2]):
                result.setdefault(f'windows_{run[2][0]}_{run[2][1]}', []).append(quad(run[0], run[1], z1, z2))
                run = None
            if on:
                run = (run[0], a2, key) if run else (a1, a2, key)
    return result


def aviation_points(roof_points, height):
    """高さ 60m 以上の建物の屋上の四隅（東西南北の端）に航空障害灯を置く。"""
    if height < AVIATION_HEIGHT:
        return []
    top = [p for p in roof_points if p[2] >= height - 1.0]
    if not top:
        return []
    corners = {min(top, key=lambda p: p[0] + p[1]), max(top, key=lambda p: p[0] + p[1]),
               min(top, key=lambda p: p[0] - p[1]), max(top, key=lambda p: p[0] - p[1])}
    return [[x, y, round(z + 0.5, 2)] for x, y, z in sorted(corners)]
