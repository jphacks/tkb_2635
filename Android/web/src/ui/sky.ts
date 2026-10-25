import * as T from 'three';
import {days,horizontal,precess,starPosition,position,moon,DEG} from '../core/astro';
import type {Catalog,Horizontal,Target} from '../core/types';
import {imagePlacement} from '../core/constellation-image';
import {phaseImage} from './moon-texture';
export const vector=(p:Horizontal,r=20000)=>new T.Vector3(Math.sin(p.azimuth*DEG)*Math.cos(p.altitude*DEG)*r,Math.sin(p.altitude*DEG)*r,-Math.cos(p.azimuth*DEG)*Math.cos(p.altitude*DEG)*r);
export function sky(catalog:Catalog,target:Target,date:Date,lat:number,lon:number) {
  const group=new T.Group(),vertices:number[]=[];
  for(const s of catalog.stars)vertices.push(...vector(starPosition(s,date,lat,lon)).toArray());
  const geometry=new T.BufferGeometry().setAttribute('position',new T.Float32BufferAttribute(vertices,3));
  group.add(new T.Points(geometry,new T.PointsMaterial({color:0xe4efff,size:28,sizeAttenuation:true,transparent:true,opacity:.85})));
  for(const image of catalog.images){
    const place=imagePlacement(image),points:number[]=[],uv:number[]=[],indices:number[]=[],n=16;
    for(let row=0;row<=n;row++)for(let col=0;col<=n;col++){const eq=place(image.size[0]*col/n,image.size[1]*row/n),p=precess(eq.ra,eq.dec,days(date));points.push(...vector(horizontal(p.ra,p.dec,days(date),lat,lon),21000).toArray());uv.push(col/n,1-row/n);}
    for(let row=0;row<n;row++)for(let col=0;col<n;col++){const a=row*(n+1)+col,b=a+n+1;indices.push(a,b,a+1,a+1,b,b+1);}
    const g=new T.BufferGeometry().setAttribute('position',new T.Float32BufferAttribute(points,3)).setAttribute('uv',new T.Float32BufferAttribute(uv,2));g.setIndex(indices);
    const texture=new T.TextureLoader().load('./generated/'+image.image+'.png');texture.colorSpace=T.SRGBColorSpace;
    group.add(new T.Mesh(g,new T.MeshBasicMaterial({map:texture,transparent:true,opacity:.28,depthWrite:false,side:T.DoubleSide})));
  }
  for(const constellation of catalog.lines){const points:number[]=[];
    for(const path of constellation.paths)for(let i=1;i<path.length;i++)for(const coord of [path[i-1],path[i]]) {
      const eq=precess(coord[0],coord[1],days(date));points.push(...vector(horizontal(eq.ra,eq.dec,days(date),lat,lon)).toArray());
    }
    const g=new T.BufferGeometry().setAttribute('position',new T.Float32BufferAttribute(points,3));
    group.add(new T.LineSegments(g,new T.LineBasicMaterial({color:0x8bb9e8,transparent:true,opacity:.28})));
  }
  const p=position(target,date,lat,lon,catalog.stars),texture=target.image?new T.TextureLoader().load('./generated/'+target.image,t=>{if(target.kind==='moon'){t.image=phaseImage(t.image,moon(date,lat,lon).phase);t.needsUpdate=true;}}):null;
  if(texture)texture.colorSpace=T.SRGBColorSpace;
  const marker=new T.Sprite(new T.SpriteMaterial({map:texture,color:texture?0xffffff:0xc7e7ff,transparent:true,depthTest:true}));
  marker.position.copy(vector(p));const size=target.kind==='moon'?175:140;marker.scale.set(size,size,1);
  if(texture){texture.onUpdate=()=>{const image=texture.image as {width:number;height:number};if(image?.width&&image.height)marker.scale.set(size*image.width/Math.max(image.width,image.height),size*image.height/Math.max(image.width,image.height),1);};}
  if(target.kind==='constellation')marker.material.map=null;group.add(marker);
  return group;
}
export function disposeTree(object:T.Object3D) {
  const textures=new Set<T.Texture>(),materials=new Set<T.Material>();
  object.traverse(o=>{const mesh=o as T.Mesh;mesh.geometry?.dispose();if(mesh.material)for(const material of Array.isArray(mesh.material)?mesh.material:[mesh.material])materials.add(material);});
  for(const m of materials){for(const value of Object.values(m))if(value instanceof T.Texture)textures.add(value);m.dispose();}
  textures.forEach(t=>t.dispose());
}
