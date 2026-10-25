import * as T from 'three';
import {DEG} from '../core/astro';
/** ARは現在地・現在時刻。選択地点の予測とは分離する。 */
export async function startAR(shell:HTMLElement,camera:T.PerspectiveCamera,updateSky:(lat:number,lon:number,date:Date)=>void,status:(text:string)=>void,active=()=>true) {
  if(!window.AsteraDevice?.available())throw Error('方位センサー非対応です。観測者視点を利用してください。');
  if(!navigator.mediaDevices?.getUserMedia)throw Error('この端末ではカメラを利用できません。');
  const p=await new Promise<GeolocationPosition>((resolve,reject)=>navigator.geolocation.getCurrentPosition(resolve,()=>reject(Error('ARには現在地の許可が必要です。設定で許可して再度お試しください。')),{enableHighAccuracy:true,timeout:15000,maximumAge:30000}));
  if(!shell.isConnected||!active())return ()=>{};
  let stream:MediaStream;
  try{stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280}},audio:false});}catch{throw Error('カメラを開始できません。カメラ権限や他のアプリによる使用を確認してください。');}
  const video=document.createElement('video');video.className='camera-layer';video.autoplay=true;video.muted=true;video.playsInline=true;video.srcObject=stream;shell.prepend(video);shell.querySelector('canvas')?.classList.add('ar-canvas');
  let stopped=false,cleanup=()=>{};
  const abort=()=>{if(stopped)return;stopped=true;cleanup();stream.getTracks().forEach(t=>t.stop());video.srcObject=null;video.remove();shell.querySelector('canvas')?.classList.remove('ar-canvas');window.AsteraDevice?.setTracking(false);};
  const onSuspend=()=>abort();window.addEventListener('astera-suspend',onSuspend,{once:true});
  try{await video.play();if(!shell.isConnected||document.hidden||!active()){abort();return abort;}
    const lat=p.coords.latitude,lon=p.coords.longitude,alt=p.coords.altitude??0;
    const orient=(event:Event)=>{const d=(event as CustomEvent<{forward:number[];up:number[]}>).detail,angle=window.AsteraDevice!.declination?.(lat,lon,alt,Date.now())??0;
      const convert=(v:number[])=>new T.Vector3(v[0],v[2],-v[1]).applyAxisAngle(new T.Vector3(0,1,0),-angle*DEG);
      camera.up.copy(convert(d.up));camera.lookAt(camera.position.clone().add(convert(d.forward)));};
    window.addEventListener('astera-orientation',orient);window.AsteraDevice!.setTracking(true);
    const refresh=()=>{updateSky(lat,lon,new Date());status(`現在地・現在時刻のAR / 位置精度 ±${Math.round(p.coords.accuracy)}m。方位と画角は概算です。磁気の影響やカメラ画角でずれます。`);};refresh();
    const timer=setInterval(refresh,30000);cleanup=()=>{clearInterval(timer);window.removeEventListener('astera-orientation',orient);window.removeEventListener('astera-suspend',onSuspend);};
  }catch(e){abort();throw e;}return abort;
}
