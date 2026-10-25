"""同梱するGLBの欠落・破損・スケールをビルド前に検査する。"""
import hashlib
import json
import struct
from pathlib import Path

root = Path(__file__).resolve().parents[2]
folder = root/'Android/web/public/generated'
manifest = json.loads((folder/'models.json').read_text(encoding='utf-8'))
assert len(manifest['cities']) == 32
assert sum(a['lod'] == 1 for a in manifest['wide']) == 23
assert sum(a['lod'] == 2 for a in manifest['wide']) == 23
total = 0
for asset in manifest['cities'] + manifest['wide']:
    blob = (folder/asset['file']).read_bytes()
    magic, version, size = struct.unpack('<III', blob[:12])
    assert magic == 0x46546c67 and version == 2 and size == len(blob)
    assert len(blob) == asset['bytes']
    assert hashlib.sha256(blob).hexdigest() == asset['sha256']
    length, kind = struct.unpack('<II', blob[12:20])
    assert kind == 0x4e4f534a
    document = json.loads(blob[20:20+length])
    positions = [document['accessors'][p['attributes']['POSITION']]
                 for mesh in document['meshes'] for p in mesh['primitives']]
    assert positions and all(p['count'] > 0 for p in positions)
    if asset['id'] == 'shibuya':
        height = max(p['max'][1] for p in positions) - min(p['min'][1] for p in positions)
        assert 200 < height < 600, f'Z-upからY-upへの変換が不正: {height}'
    total += len(blob)
data = json.loads((folder/'data.json').read_text(encoding='utf-8'))
for target in data['catalog']['targets']:
    if target.get('image'):
        assert (folder/target['image']).exists()
for image in data['catalog']['images']:
    assert (folder/(image['image']+'.png')).exists()
print(f"検証成功: 78 GLB / {len(data['spots'])}地点 / 88星座絵 / {total:,} bytes")
