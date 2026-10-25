import {direction} from '../core/astro';
import {modal} from './dom';
import {soundEnabled,toggleSound} from './sound';
import {redraw,state} from '../state';
export const hour12=()=>localStorage.getItem('astera.clock')==='12';
export const directionLabel=(az:number)=>localStorage.getItem('astera.direction')==='degrees'?`${Math.round(az)}°`:direction(az);
export function applyPreferences(){const theme=localStorage.getItem('astera.theme')??'dark';document.documentElement.classList.toggle('light',theme==='light'||theme==='system'&&matchMedia('(prefers-color-scheme:light)').matches);document.documentElement.classList.toggle('reduce-motion',localStorage.getItem('astera.reduce')==='on');}
export function settings(){
  const select=(id:string,label:string,options:string[][])=>`<label>${label}<select id="${id}" class="glass">${options.map(([v,n])=>`<option value="${v}">${n}</option>`).join('')}</select></label>`;
  const d=modal(`<h2>設定</h2>${select('theme','画面の明るさ',[['dark','ダーク'],['light','ライト'],['system','端末に合わせる']])}${select('clock','時刻',[['24','24時間'],['12','12時間']])}${select('direction','方位',[['name','方角の名前'],['degrees','角度']])}<label>効果音<input id="sound" type="checkbox" ${soundEnabled()?'checked':''}></label><label>動きを少なくする<input id="reduce" type="checkbox" ${localStorage.getItem('astera.reduce')==='on'?'checked':''}></label><p>現在地：${state.location?'取得済み':state.locationError||'未取得'}。カメラと位置情報は使用時だけ許可を求めます。端末の「設定 → アプリ → Astera → 権限」で変更できます。通知は送りません。</p><p class="footnote">都市: 国土交通省 PLATEAU（CC BY 4.0）・国土地理院・EOG/Colorado School of Mines（VIIRS、CC BY 4.0）を加工<br>天気: Open-Meteo（CC BY 4.0）<br>地図: OpenStreetMap contributors（ODbL）<br>月・惑星画像: NASA<br>星座線: d3-celestial（BSD-3-Clause）／星座絵: アプリ既存素材<br>3D: Three.js（MIT） / 地図UI: Leaflet（BSD-2-Clause）</p><button data-close class="glass">閉じる</button>`,()=>{applyPreferences();redraw();});
  for(const id of ['theme','clock','direction']){const el=d.querySelector<HTMLSelectElement>('#'+id)!;el.value=localStorage.getItem('astera.'+id)??({theme:'dark',clock:'24',direction:'name'} as Record<string,string>)[id];el.onchange=()=>{localStorage.setItem('astera.'+id,el.value);applyPreferences();};}
  d.querySelector('#sound')!.addEventListener('change',toggleSound);d.querySelector('#reduce')!.addEventListener('change',e=>{localStorage.setItem('astera.reduce',(e.target as HTMLInputElement).checked?'on':'off');applyPreferences();});
}
