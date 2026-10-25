import * as T from 'three';
import {localPosition} from '../core/geometry';
import type {CityScene} from '../core/types';
export async function wideGround(origin:CityScene) {
  const r=await fetch('./generated/ground.json');if(!r.ok)throw Error('広域の航空写真を読み込めません');
  const data=await r.json() as {tiles:{file:string;centerLatitude:number;centerLongitude:number;meters:number}[]};
  const group=new T.Group();const loader=new T.TextureLoader();
  try{for(const tile of data.tiles){const texture=await loader.loadAsync('./generated/'+tile.file+'.jpg');texture.colorSpace=T.SRGBColorSpace;texture.anisotropy=4;
    const mesh=new T.Mesh(new T.PlaneGeometry(tile.meters,tile.meters),new T.MeshBasicMaterial({map:texture})),p=localPosition(origin,tile.centerLatitude,tile.centerLongitude);
    mesh.rotation.x=-Math.PI/2;mesh.position.set(p.east,-3,-p.north);group.add(mesh);
  }}catch(error){group.traverse(o=>{if(o instanceof T.Mesh){o.geometry.dispose();o.material.map?.dispose();o.material.dispose();}});throw error;}return group;
}
