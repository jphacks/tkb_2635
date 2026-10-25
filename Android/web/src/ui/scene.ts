import * as T from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {state,navigate,predictions,redraw} from '../state';
import type {Context,ModelAsset} from '../core/types';
import {localPosition} from '../core/geometry';
import {position,DEG} from '../core/astro';
import {modal,esc,dateLabel} from './dom';
import {sky,vector,disposeTree} from './sky';
import {startAR} from './view-ar';
import {styleCity,windowsOn} from './city-style';
import {wideGround} from './wide-ground';
export function openScene(context:Context,wide=false,ar=false) {
  let destroy=()=>{};const openedDate=+state.date;
  const dialog=modal(`<div class="toolbar"><h2>${wide?'東京23区の3D都市':esc(context.spot.name)}</h2><button data-close class="glass">閉じる</button></div><div class="scene-shell"><div class="scene-tools"><button id="orbit" class="glass">都市を見渡す</button><button id="observer" class="glass">観測者視点</button><button id="motion" class="glass">端末の向き</button><button id="camera" class="glass">カメラAR</button>${wide?'<button id="lod" class="glass">詳細モデル</button>':''}</div><p class="scene-caption">3Dデータを読み込んでいます…</p></div>`,()=>destroy());
  dialog.addEventListener('close',()=>{if(openedDate!==+state.date)redraw();});
  dialog.style.width='min(100vw,1000px)';dialog.style.padding='14px';
  const shell=dialog.querySelector<HTMLElement>('.scene-shell')!,caption=dialog.querySelector<HTMLElement>('.scene-caption')!;
  try{destroy=mountScene(shell,caption,context,wide,ar);}catch(error){caption.textContent='3Dを開始できません。WebGL 2に対応したAndroid System WebViewへ更新してください。';console.error(error);}
  return ()=>{if(dialog.open)dialog.close();};
}
function mountScene(shell:HTMLElement,caption:HTMLElement,context:Context,wide:boolean,initialAR:boolean) {
  const renderer=new T.WebGLRenderer({antialias:true,alpha:true});renderer.setPixelRatio(Math.min(devicePixelRatio,1.6));
  renderer.outputColorSpace=T.SRGBColorSpace;renderer.setClearColor(0x040b19,1);shell.prepend(renderer.domElement);
  const scene=new T.Scene(),camera=new T.PerspectiveCamera(55,1,.1,100000),city=new T.Group();scene.add(city);
  scene.add(new T.HemisphereLight(0xbfd6ff,0x1f2937,2.2));const light=new T.DirectionalLight(0xd8e5ff,2);light.position.set(-1000,3000,1000);scene.add(light);
  const controls=new OrbitControls(camera,renderer.domElement);controls.enableDamping=true;controls.maxDistance=wide?70000:5000;controls.minDistance=2;controls.maxPolarAngle=Math.PI*.495;
  const s=context.spot,local=context.scene?localPosition(context.scene,s.latitude,s.longitude):{east:0,north:0};
  const eye=new T.Vector3(local.east,Math.max(1.6,s.floorElevation+s.eyeHeight-(context.scene?.groundElevation??0)),-local.north);
  const target=position(state.target!,state.date,s.latitude,s.longitude,state.catalog!.stars);
  let skyGroup=sky(state.catalog!,state.target!,state.date,s.latitude,s.longitude);scene.add(skyGroup);
  const rayGeometry=new T.BufferGeometry().setFromPoints([eye,eye.clone().add(vector(target,1000))]);
  const rayMaterial=new T.LineBasicMaterial({color:predictions().find(p=>p.spotId===s.id)?.visible?0x88e5bc:0xf38f8f,transparent:true,opacity:.8,depthTest:false});
  const directionRay=new T.Line(rayGeometry,rayMaterial);if(!wide)scene.add(directionRay);else{rayGeometry.dispose();rayMaterial.dispose();}
  const time=document.createElement('label');time.className='scene-time';time.innerHTML=`<span>${dateLabel(state.date)}</span><input type="range" min="-360" max="360" step="5" value="0" aria-label="3Dの時刻を動かす">`;if(!wide)shell.append(time);
  const baseTime=+state.date,slider=time.querySelector('input')!;
  slider.onchange=()=>{if(mode==='ar'||arPending)return;state.date=new Date(baseTime+Number(slider.value)*60000);time.querySelector('span')!.textContent=dateLabel(state.date);scene.remove(skyGroup);disposeTree(skyGroup);skyGroup=sky(state.catalog!,state.target!,state.date,s.latitude,s.longitude);scene.add(skyGroup);
    const target=position(state.target!,state.date,s.latitude,s.longitude,state.catalog!.stars),p=predictions().find(p=>p.spotId===s.id)!;
    rayGeometry.setFromPoints([eye,eye.clone().add(vector(target,1000))]);rayMaterial.color.set(p.visible?0x88e5bc:0xf38f8f);city.traverse(o=>{const match=/windows_(\d)_/.exec(o.name);if(match)o.visible=windowsOn(Number(match[1]),state.date);});caption.textContent=`${p.visible?'建物に遮られない見込み':'建物・地平線・空の明るさに注意'} / ${dateLabel(state.date)}`;
  };
  let disposed=false,stopAR=()=>{},mode='orbit',motion=false,observerYaw=target.azimuth,observerPitch=target.altitude,generation=0,arPending=false;
  const restoreSky=()=>{scene.remove(skyGroup);disposeTree(skyGroup);skyGroup=sky(state.catalog!,state.target!,state.date,s.latitude,s.longitude);scene.add(skyGroup);};
  const reset=()=>{generation++;if(mode==='ar')restoreSky();directionRay.visible=!wide;time.hidden=wide;stopAR();stopAR=()=>{};window.AsteraDevice?.setTracking(false);motion=false;mode='orbit';controls.enabled=true;renderer.setClearAlpha(1);camera.position.set(eye.x+1000,eye.y+1000,eye.z+1000);controls.target.copy(eye);controls.update();caption.textContent='ドラッグで回転・ピンチで拡大。3D形状と遮蔽判定用の建物は精度が異なる場合があります。';};
  const observer=()=>{reset();mode='observer';controls.enabled=false;camera.position.copy(eye);camera.up.set(0,1,0);camera.lookAt(eye.clone().add(vector(target,1)));caption.textContent='選択地点・選択日時の予測。ドラッグで周囲を見ることができます。';};
  const enableAR=async()=>{if(arPending)return;arPending=true;observer();const token=generation;city.visible=false;directionRay.visible=false;time.hidden=true;renderer.setClearAlpha(0);caption.textContent='カメラと現在地の許可を確認しています…';
    try{const stop=await startAR(shell,camera,(lat,lon,date)=>{scene.remove(skyGroup);disposeTree(skyGroup);skyGroup=sky(state.catalog!,state.target!,date,lat,lon);scene.add(skyGroup);},message=>caption.textContent=message,()=>!disposed&&generation===token);if(disposed||generation!==token){stop();return;}stopAR=stop;mode='ar';}
    catch(e){if(!disposed&&generation===token){city.visible=true;directionRay.visible=true;time.hidden=false;renderer.setClearAlpha(1);caption.textContent=String(e instanceof Error?e.message:e);}}finally{arPending=false;}
  };
  const click=(id:string,fn:()=>void)=>shell.querySelector('#'+id)?.addEventListener('click',fn);
  click('orbit',()=>{city.visible=true;reset();});click('observer',()=>{city.visible=true;observer();});click('camera',()=>void enableAR());
  click('motion',()=>{if(!window.AsteraDevice?.available()){caption.textContent='端末の方位センサーを利用できません。ドラッグで操作してください。';return;}observer();motion=true;window.AsteraDevice.setTracking(true);caption.textContent='選択地点の予測を端末の向きで確認中。磁気の影響で方向がずれる場合があります。';});
  const orient=(event:Event)=>{if(!motion||mode!=='observer')return;const d=(event as CustomEvent<{forward:number[];up:number[]}>).detail;
    const declination=window.AsteraDevice?.declination?.(s.latitude,s.longitude,s.floorElevation,state.date.getTime())??0;
    const convert=(v:number[])=>new T.Vector3(v[0],v[2],-v[1]).applyAxisAngle(new T.Vector3(0,1,0),-declination*DEG);
    camera.up.copy(convert(d.up));camera.lookAt(camera.position.clone().add(convert(d.forward)));};window.addEventListener('astera-orientation',orient);
  let drag:{x:number;y:number}|null=null;
  const down=(e:PointerEvent)=>{if(mode==='observer'&&!motion){drag={x:e.clientX,y:e.clientY};renderer.domElement.setPointerCapture(e.pointerId);}};
  const move=(e:PointerEvent)=>{if(!drag)return;observerYaw-=(e.clientX-drag.x)*.15;observerPitch=Math.max(-85,Math.min(85,observerPitch+(e.clientY-drag.y)*.15));drag={x:e.clientX,y:e.clientY};camera.lookAt(camera.position.clone().add(vector({azimuth:observerYaw,altitude:observerPitch},1)));};
  renderer.domElement.addEventListener('pointerdown',down);renderer.domElement.addEventListener('pointermove',move);renderer.domElement.addEventListener('pointerup',()=>drag=null);renderer.domElement.addEventListener('pointercancel',()=>drag=null);
  const resize=new ResizeObserver(()=>{const w=shell.clientWidth,h=shell.clientHeight;renderer.setSize(w,h);camera.aspect=w/h;camera.updateProjectionMatrix();});resize.observe(shell);
  renderer.setAnimationLoop(()=>{if(disposed)return;if(mode==='orbit')controls.update();skyGroup.position.copy(camera.position);renderer.render(scene,camera);});
  const loader=new GLTFLoader();let loading=false;
  const load=async(asset:ModelAsset)=>{const gltf=await loader.loadAsync('./generated/'+asset.file);if(disposed){disposeTree(gltf.scene);return;}
    styleCity(gltf.scene,state.date,wide?undefined:s.hostBuildingId);gltf.scene.userData.assetId=asset.id;city.add(gltf.scene);};
  const loadModels=async(lod:number)=>{if(loading)return;loading=true;caption.textContent='3D都市を読み込んでいます…';
    try{let assets=wide?state.assets.wide.filter(a=>a.lod===lod):state.assets.cities.filter(a=>a.id===s.sceneId);if(!assets.length)throw Error('この地点の3Dモデルは同梱されていません。');
      // LOD2は中心に近い2区だけに絞り、モバイルのメモリを使い切らない。
      if(wide&&lod===2){const nearest=[...city.children].sort((a,b)=>new T.Box3().setFromObject(a).getCenter(new T.Vector3()).distanceToSquared(controls.target)-new T.Box3().setFromObject(b).getCenter(new T.Vector3()).distanceToSquared(controls.target)).slice(0,2).map(o=>o.userData.assetId);assets=assets.filter(a=>nearest.includes(a.id));}
      const old=[...city.children].filter(o=>assets.some(a=>a.id===o.userData.assetId));for(let i=0;i<assets.length;i++){await load(assets[i]);if(disposed)return;caption.textContent=`3D都市 ${i+1}/${assets.length}`;}
      for(const o of old){city.remove(o);disposeTree(o);}if(wide&&lod===1){const box=new T.Box3().setFromObject(city),center=box.getCenter(new T.Vector3()),size=box.getSize(new T.Vector3());controls.target.copy(center);camera.position.copy(center).add(new T.Vector3(size.x*.4,Math.max(size.x,size.z)*.7,size.z*.5));controls.update();}
      caption.textContent='PLATEAUの都市モデル。ドラッグで回転・ピンチで拡大できます。';
    }catch(e){caption.textContent=`3Dの読み込みに失敗しました：${e instanceof Error?e.message:String(e)}`;}finally{loading=false;}
  };
  click('lod',()=>void loadModels(2));reset();void loadModels(1);if(initialAR)void enableAR();
  if(wide){for(const id of ['observer','motion','camera'])shell.querySelector<HTMLButtonElement>('#'+id)!.hidden=true;
    const origin=state.contexts.find(c=>c.scene?.id==='shibuya')!.scene!,pins:T.Object3D[]=[];
    void wideGround(origin).then(ground=>{if(disposed)disposeTree(ground);else scene.add(ground);}).catch(()=>{if(!disposed)caption.textContent='航空写真を読み込めません。3D建物は表示します。';});
    for(const c of state.contexts){const p=localPosition(origin,c.spot.latitude,c.spot.longitude),mesh=new T.Mesh(new T.SphereGeometry(110,8,6),new T.MeshBasicMaterial({color:0xbce8f4,depthTest:false}));mesh.position.set(p.east,c.spot.floorElevation+180,-p.north);mesh.userData.spotId=c.spot.id;pins.push(mesh);scene.add(mesh);}
    const ray=new T.Raycaster();let downAt=[0,0];renderer.domElement.addEventListener('pointerdown',e=>downAt=[e.clientX,e.clientY]);
    renderer.domElement.addEventListener('pointerup',e=>{if(Math.hypot(e.clientX-downAt[0],e.clientY-downAt[1])>8)return;const rect=renderer.domElement.getBoundingClientRect();ray.setFromCamera(new T.Vector2((e.clientX-rect.left)/rect.width*2-1,-(e.clientY-rect.top)/rect.height*2+1),camera);const hit=ray.intersectObjects(pins)[0];if(hit){shell.closest<HTMLDialogElement>('dialog')!.close();navigate({page:'detail',id:hit.object.userData.spotId});}});
  }
  const suspend=()=>{stopAR();stopAR=()=>{};motion=false;window.AsteraDevice?.setTracking(false);if(mode==='ar'){if(!disposed)restoreSky();mode='observer';renderer.setClearAlpha(1);city.visible=true;directionRay.visible=!wide;time.hidden=wide;caption.textContent='カメラを停止しました。再開するには「カメラAR」を押してください。';}};
  window.addEventListener('astera-suspend',suspend);
  return ()=>{disposed=true;suspend();window.removeEventListener('astera-suspend',suspend);window.removeEventListener('astera-orientation',orient);resize.disconnect();controls.dispose();renderer.setAnimationLoop(null);disposeTree(scene);renderer.dispose();renderer.domElement.remove();};
}
