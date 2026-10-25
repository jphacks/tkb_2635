import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import crypto from 'node:crypto';
const root=fileURLToPath(new URL('../../',import.meta.url));
const out=path.join(root,'Android/web/public/generated');
await fs.mkdir(out,{recursive:true});
const licenses=[];
for(const name of ['three','leaflet'])licenses.push(name+'\n'+await fs.readFile(path.join(root,'Android/web/node_modules',name,'LICENSE'),'utf8'));
await fs.writeFile(path.join(out,'THIRD_PARTY_NOTICES.txt'),licenses.join('\n\n'));
const read=p=>fs.readFile(path.join(root,p),'utf8');
const source='Packages/StarCore/Sources/StarCore/';
const starSource=await read(source+'Astro/StarCatalog.swift');
const stars=[...starSource.matchAll(/Star\(id:\s*"([^"]+)",\s*name:\s*"([^"]+)",\s*rightAscension:\s*([-\d.]+),\s*declination:\s*([-\d.]+),\s*magnitude:\s*([-\d.]+)\)/g)]
  .map(([,id,name,ra,dec,magnitude])=>({id,name,rightAscension:+ra,declination:+dec,magnitude:+magnitude}));
if(stars.length<52)throw Error('恒星データを読み取れません');
const targets=[{id:'moon',bodyId:'moon',name:'月',kind:'moon',image:'moon_disk.png'}];
for(const [id,name] of [['mercury','水星'],['venus','金星'],['mars','火星'],['jupiter','木星'],['saturn','土星']])
  targets.push({id:'planet-'+id,bodyId:id,name,kind:'planet',image:'planet_'+id+'.png'});
for(const [id,name,star] of [['orion','オリオン座','betelgeuse'],['taurus','おうし座','aldebaran'],['gemini','ふたご座','pollux'],
  ['ursa_major','おおぐま座','dubhe'],['scorpius','さそり座','antares'],['cygnus','はくちょう座','deneb'],['aquila','わし座','altair'],['cassiopeia','カシオペヤ座','schedar']]) {
  if(!stars.some(s=>s.id===star))throw Error('星座の代表星なし:'+star);
  targets.push({id,bodyId:star,name,kind:'constellation',image:'constellation_'+id+'.png',
    note:`観測場所は代表星「${stars.find(s=>s.id===star).name}」で判定します。星座全体の可視性を保証するものではありません。`});
}
targets.push(...stars.map(s=>({id:'star-'+s.id,bodyId:s.id,name:s.name,kind:'star'})));
const assetFiles=[];
async function walk(dir) {try{for(const e of await fs.readdir(path.join(root,dir),{withFileTypes:true})){
  const p=path.join(dir,e.name);if(e.isDirectory())await walk(p);else assetFiles.push(p);
}}catch(e){if(e.code!=='ENOENT')throw e;}}
await walk('App/Resources/Sky');await walk('App/Resources/Constellations');await walk('App/Resources/Planets');
for(const target of targets.filter(t=>t.image)) {
  const file=assetFiles.find(f=>path.basename(f).replaceAll('-','_')===target.image);
  if(file)await fs.copyFile(path.join(root,file),path.join(out,target.image));
  else if(target.id==='cassiopeia')delete target.image;
  else throw Error('天体画像がありません:'+target.image);
}
const spots=JSON.parse(await read(source+'Resources/spots.json'));
const scenes=JSON.parse(await read(source+'Resources/buildings.json'));
for(const scene of scenes)for(const building of scene.buildings)if(building.parts)building.parts=building.parts.map(p=>Array.isArray(p)?{x:p[0],y:p[1],width:p[2],depth:p[3],height:p[4]}:p);
const lines=JSON.parse(await read('App/Resources/Sky/constellations.json'));
const images=JSON.parse(await read('App/Resources/Sky/constellation-images.json'));
for(const image of images) {
  const file=assetFiles.find(f=>path.basename(f)===image.image+'.png');
  if(file)await fs.copyFile(path.join(root,file),path.join(out,image.image+'.png'));
}
for(const scene of scenes) {
  const file=path.join(root,'App/Resources/Far/far_'+scene.id+'.jpg');
  try {await fs.copyFile(file,path.join(out,'far_'+scene.id+'.jpg'));}catch(e){if(e.code!=='ENOENT')throw e;}
}
const terrain=JSON.parse(await read(source+'Resources/terrain.json'));
for(const spot of spots){const photo=path.join(root,'App/Resources/SpotThumbnails/spot_'+spot.id+'.jpg');try{await fs.copyFile(photo,path.join(out,'spot_'+spot.id+'.jpg'));}catch(e){if(e.code!=='ENOENT')throw e;await fs.copyFile(path.join(out,'far_'+spot.sceneId+'.jpg'),path.join(out,'spot_'+spot.id+'.jpg'));}}
const payload={spots,scenes,terrain,catalog:{targets,stars,lines,images}};
const ground=JSON.parse(await read('App/Resources/Wide/WideGround.json'));
await fs.writeFile(path.join(out,'ground.json'),JSON.stringify(ground));
for(const tile of ground.tiles)await fs.copyFile(path.join(root,'App/Resources/Wide',tile.file+'.jpg'),path.join(out,tile.file+'.jpg'));
const version=crypto.createHash('sha256').update(JSON.stringify(payload)).digest('hex');
await fs.writeFile(path.join(out,'data.json'),JSON.stringify({...payload,version}));
console.log(JSON.stringify({spots:spots.length,scenes:scenes.length,stars:stars.length,targets:targets.length,version}));
