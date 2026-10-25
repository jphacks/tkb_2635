import type { Assets, Catalog, CityScene, Context, Prediction, Spot, Target,Terrain } from './core/types';
import { makeContext } from './core/geometry';
import { evaluate,rank } from './core/recommender';
import { WeatherClient } from './core/weather';
export type Route={page:'select'}|{page:'home'}|{page:'detail';id:string}|{page:'compare';id:string;other:string};
export function tonight(now=new Date()) {
  const local=new Date(now.getTime()+9*3600000),nine=new Date(local);nine.setUTCHours(21,0,0,0);
  if(local<nine)return new Date(nine.getTime()-9*3600000);
  local.setUTCHours(local.getUTCHours()+1,0,0,0);return new Date(local.getTime()-9*3600000);
}
export const state={route:{page:'select'} as Route,date:tonight(),target:null as Target|null,
  selectedIndex:0,group:'recommended',sort:'near',category:'',location:null as {lat:number;lon:number;accuracy:number}|null,
  locationError:'',weatherError:'',loadingWeather:false,contexts:[] as Context[],catalog:null as Catalog|null,
  assets:{cities:[],wide:[]} as Assets,wide3D:false};
export const weather=new WeatherClient();
let currentPredictions:Prediction[]=[];
let signature='';
export function predictions() {
  if(!state.target||!state.catalog)return [];
  const key=state.target.id+state.date.toISOString()+weatherRevision;
  if(signature!==key) {
    currentPredictions=rank(state.contexts.map(c=>evaluate(c,state.target!,state.date,state.catalog!.stars,
      weather.at(c.spot,state.date),weather.outOfRange(c.spot,state.date))));signature=key;
  }return currentPredictions;
}
let weatherRevision=0;
let attemptedWeather=false;
export function ensureWeather(){if(attemptedWeather)return;attemptedWeather=true;queueMicrotask(()=>void refreshWeather());}
let render=()=>{};
export function onRender(fn:()=>void){render=fn;}
export function redraw(){render();}
export function navigate(route:Route){state.route=route;render();window.scrollTo({top:0});}
export function back() {
  const route=state.route;
  if(route.page==='select')return false;
  navigate(route.page==='compare'?{page:'detail',id:route.id}:route.page==='detail'?{page:'home'}:{page:'select'});
  return true;
}
export async function loadData(progress:(text:string)=>void) {
  const response=await fetch('./generated/data.json');if(!response.ok)throw Error('地点データがありません。prepare:dataを実行してください。');
  const data=await response.json() as {spots:Spot[];scenes:CityScene[];catalog:Catalog;terrain:Terrain};
  const scenes=new Map(data.scenes.map(s=>[s.id,s]));state.catalog=data.catalog;
  const saved=localStorage.getItem('astera.target');state.target=data.catalog.targets.find(t=>t.id===saved)??data.catalog.targets[0];
  state.selectedIndex=data.catalog.targets.findIndex(t=>t.id===state.target!.id);
  for(let i=0;i<data.spots.length;i++) {
    progress(`観測地点の空を計算しています ${i+1}/${data.spots.length}`);
    await new Promise<void>(resolve=>requestAnimationFrame(()=>resolve()));
    const spot=data.spots[i];state.contexts.push(makeContext(spot,spot.sceneId?scenes.get(spot.sceneId):undefined,data.terrain));
  }
  try {const r=await fetch('./generated/models.json');if(r.ok)state.assets=await r.json();}catch{/* 3Dを開いた際に不足を明示する */}
}
export async function refreshWeather() {
  if(state.loadingWeather)return;state.loadingWeather=true;redraw();
  const errors=await weather.refresh(state.contexts.map(c=>c.spot));
  state.weatherError=errors?`${errors}地域の天気を取得できませんでした。未取得の予報は推薦に使いません。`:'';
  state.loadingWeather=false;weatherRevision++;redraw();
}
export function locate() {
  if(!navigator.geolocation){state.locationError='この端末では位置情報を利用できません。';redraw();return;}
  navigator.geolocation.getCurrentPosition(p=>{
    state.location={lat:p.coords.latitude,lon:p.coords.longitude,accuracy:p.coords.accuracy};state.locationError='';redraw();
  },e=>{state.location=null;state.locationError=e.code===1?'位置情報が許可されていません。距離は未取得です。':'現在地を取得できませんでした。距離は未取得です。';redraw();},
  {enableHighAccuracy:true,timeout:15000,maximumAge:60000});
}
