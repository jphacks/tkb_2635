"""既存USDZを、座標・UV・画像を保ったGLBへ変換する。元データは変更しない。"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile
import numpy as np
from PIL import Image
from pxr import Ar, Usd, UsdGeom, UsdShade
import trimesh
from convert_sounds import prepare as prepare_sounds
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'Android/web/public/generated/models'


def texture(shader, archive: Path):
    source = shader.GetInput('diffuseColor').GetConnectedSource()
    if not source:
        return None
    node = UsdShade.Shader(source[0].GetPrim())
    file_input = node.GetInput('file')
    asset = file_input.Get() if file_input else None
    if not asset:
        return None
    if asset.resolvedPath:
        value = Ar.GetResolver().OpenAsset(Ar.ResolvedPath(asset.resolvedPath))
        if value:
            image = Image.open(io.BytesIO(bytes(value.GetBuffer()))).convert('RGB')
            image.thumbnail((2048, 2048))
            return image
    with zipfile.ZipFile(archive) as packed:
        name = asset.path.removeprefix('./')
        if name not in packed.namelist():
            matches = [n for n in packed.namelist() if Path(n).name == Path(name).name]
            if len(matches) != 1:
                raise ValueError(f'テクスチャを特定できません: {asset}')
            name = matches[0]
        image = Image.open(io.BytesIO(packed.read(name))).convert('RGB')
        image.thumbnail((2048, 2048))
        return image


def triangulate(counts, indices):
    if np.all(counts == 3):
        return indices.reshape((-1, 3)), np.arange(len(indices))
    triangles, corners, start = [], [], 0
    for count in counts:
        for corner in range(1, int(count) - 1):
            ids = [start, start + corner, start + corner + 1]
            triangles.append(indices[ids])
            corners.extend(ids)
        start += int(count)
    return np.asarray(triangles), np.asarray(corners)


def convert(source: Path, destination: Path):
    stage = Usd.Stage.Open(str(source))
    if stage is None:
        raise ValueError(f'USDZを開けません: {source}')
    up = UsdGeom.GetStageUpAxis(stage)
    units = UsdGeom.GetStageMetersPerUnit(stage)
    cache = UsdGeom.XformCache()
    scene = trimesh.Scene()
    materials = {}
    triangles = 0
    for prim in stage.Traverse():
        if not prim.IsA(UsdGeom.Mesh):
            continue
        mesh = UsdGeom.Mesh(prim)
        points = np.asarray(mesh.GetPointsAttr().Get(), dtype=np.float64)
        counts = np.asarray(mesh.GetFaceVertexCountsAttr().Get())
        indices = np.asarray(mesh.GetFaceVertexIndicesAttr().Get())
        if not len(points) or not len(indices):
            continue
        faces, corners = triangulate(counts, indices)
        world = np.column_stack((points, np.ones(len(points)))) @ np.asarray(cache.GetLocalToWorldTransform(prim))
        vertices = world[:, :3] * units
        if up == 'Z':
            vertices = vertices[:, [0, 2, 1]] * [1, 1, -1]
        uv = None
        for primvar in UsdGeom.PrimvarsAPI(prim).GetPrimvars():
            if str(primvar.GetTypeName()) not in ('texCoord2f[]', 'float2[]'):
                continue
            values = np.asarray(primvar.ComputeFlattened(), dtype=np.float32)
            if not len(values):
                continue
            if primvar.GetInterpolation() == 'faceVarying':
                # UVの継ぎ目だけ頂点を分ける。全三角形を個別頂点にはしない。
                key = np.column_stack((faces.reshape(-1), values[corners]))
                unique, inverse = np.unique(key, axis=0, return_inverse=True)
                vertices = vertices[unique[:, 0].astype(int)]
                uv = unique[:, 1:].astype(np.float32)
                faces = inverse.reshape((-1, 3))
            elif len(values) == len(vertices):
                uv = values
            break
        bound, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
        material = None
        if bound:
            name = str(bound.GetPath())
            if name not in materials:
                surface = bound.ComputeSurfaceSource()[0]
                color = surface.GetInput('diffuseColor').Get() if surface else None
                image = texture(surface, source) if surface else None
                factor = [float(x) for x in (color or (.65, .67, .7))] + [1.0]
                materials[name] = PBRMaterial(name=name, baseColorFactor=factor,
                    baseColorTexture=image, metallicFactor=0.0, roughnessFactor=.85, doubleSided=True)
            material = materials[name]
        geometry = trimesh.Trimesh(vertices=vertices.astype(np.float32), faces=faces, process=False)
        geometry.visual = TextureVisuals(uv=uv, material=material or PBRMaterial(baseColorFactor=[.5,.55,.65,1],doubleSided=True))
        scene.add_geometry(geometry, node_name=prim.GetName(), geom_name=prim.GetName())
        triangles += len(faces)
    if not triangles:
        raise ValueError(f'メッシュが空です: {source}')
    blob = trimesh.exchange.gltf.export_glb(scene, include_normals=False)
    destination.write_bytes(blob)
    return {'triangles': triangles, 'bytes': len(blob), 'sha256': hashlib.sha256(blob).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', help='変換の確認用。例: City_shibuya')
    args = parser.parse_args()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {'cities': [], 'wide': []}
    for folder, prefix, category, lod in [('City','City_','cities',2),('Wide','Wide_','wide',1),('WideLOD2','Wide2_','wide',2)]:
        sources = sorted((ROOT/'App/Resources'/folder).glob(prefix+'*.usdz'))
        if not sources:
            raise FileNotFoundError(f'元の3Dデータがありません: {folder}')
        for source in sources:
            if args.only and source.stem != args.only:
                continue
            dest = OUTPUT/(source.stem+'.glb')
            stamp = dest.with_suffix('.json')
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            previous = json.loads(stamp.read_text()) if stamp.exists() else {}
            result = previous if dest.exists() and previous.get('sourceSha256') == digest else convert(source,dest)
            result.update(sourceSha256=digest, source=source.relative_to(ROOT).as_posix())
            stamp.write_text(json.dumps(result),encoding='utf-8')
            entry = {'id':source.stem.removeprefix(prefix),'file':'models/'+dest.name,'lod':lod,**result}
            manifest[category].append(entry)
            print(source.stem, result['triangles'], result['bytes'], flush=True)
    if not args.only:
        if len([x for x in manifest['wide'] if x['lod']==1]) != 23:
            raise ValueError('広域LOD1は23区すべて必要です')
        (OUTPUT.parent/'models.json').write_text(json.dumps(manifest),encoding='utf-8')
        prepare_sounds(ROOT, OUTPUT.parent)
        # モバイルで88枚の星座画像を同時表示してもメモリを使い切らないサイズにする。
        for image_path in OUTPUT.parent.glob('*.png'):
            image = Image.open(image_path).convert('RGBA')
            if not image_path.name.startswith('constellation-'):
                bounds = image.getchannel('A').getbbox()
                if bounds:
                    image = image.crop(bounds)
            edge = 256 if image_path.name.startswith('constellation-') else 768
            image.thumbnail((edge, edge), Image.Resampling.LANCZOS)
            image.save(image_path)


if __name__ == '__main__':
    main()
