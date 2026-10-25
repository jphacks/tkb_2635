import L from 'leaflet';
import {state,predictions,navigate,locate,refreshWeather,redraw} from '../state';
import {distanceKm} from '../core/geometry';
import {directionLabel as direction} from './preferences';
import {tierLabel} from '../core/recommender';
import {bind,esc,targetArt,dateLabel,notice,imageFallbacks,categoryLabel} from './dom';
import {editDate} from './date-editor';
import {openScene} from './scene';
export function home(root:HTMLElement):()=>void {
  const rows=predictions(),recommended=rows.filter(p=>p.tier==='recommended');
  const review=rows.filter(p=>p.tier!=='recommended');
  const lookup=new Map(state.contexts.map(c=>[c.spot.id,c]));
  const items=(state.group==='recommended'?recommended:review).filter(p=>!state.category||lookup.get(p.spotId)!.spot.category===state.category);
  const dist=(id:string)=>{const s=lookup.get(id)!.spot;return state.location?distanceKm(state.location.lat,state.location.lon,s)*1000:Infinity;};
  items.sort((a,b)=>state.sort==='score'?b.score-a.score:state.sort==='name'?lookup.get(a.spotId)!.spot.name.localeCompare(lookup.get(b.spotId)!.spot.name,'ja'):dist(a.spotId)-dist(b.spotId));
  const p=rows[0];
  root.innerHTML=`<div class="toolbar"><button id="change-target">‹ 天体を選ぶ</button><button id="location" class="glass">現在地を取得</button></div>
  <header class="hero"><div class="brand">ASTERA</div><div class="hero-grid"><div class="hero-info"><div><p class="field-label">観測する日時</p><button id="date" class="glass date-button">${dateLabel(state.date)} <span>⌄</span></button></div><div><p class="field-label">観測する天体</p><h1 class="target-name">${esc(state.target!.name)}</h1>${p?`<p class="caption">${direction(p.azimuth)}・高度 ${p.altitude.toFixed(0)}°<br>地点ごとの結果は詳細へ</p>`:''}</div></div>${targetArt(state.target!)}</div></header>
  <section class="map-shell"><div id="map" class="map-canvas"></div><h2 class="map-label">観測スポットマップ</h2><div class="map-mode"><button id="wide">23区3D ↗</button></div></section>
  <div class="tabs ${state.group==='recommended'?'':'review'}" role="tablist" aria-label="スポットの状態"><span class="tab-highlight"></span><button id="recommended" role="tab" aria-selected="${state.group==='recommended'}">おすすめ<span class="count">${recommended.length}</span></button><button id="review" role="tab" aria-selected="${state.group!=='recommended'}">要確認<span class="count">${review.length}</span></button></div>
  <div class="list-tools"><select id="sort" aria-label="並べ替え"><option value="near">↕ 近い順</option><option value="score">スコア順</option><option value="name">名前順</option></select><select id="category" aria-label="施設で絞り込み"><option value="">☷ すべて</option>${[...new Set(state.contexts.map(c=>c.spot.category))].map(v=>`<option value="${esc(v)}">${esc(categoryLabel(v))}</option>`).join('')}</select></div>
  ${!state.location?notice(state.locationError||'現在地を取得すると、実際の距離で並べ替えられます。'):''}${state.weatherError?notice(state.weatherError):''}
  <div class="spot-list">${items.map(p=>{const s=lookup.get(p.spotId)!.spot,d=dist(s.id);return `<button class="spot-row" data-spot="${esc(s.id)}"><span class="photo-wrap"><img class="spot-photo" src="./generated/spot_${esc(s.id)}.jpg" alt="${esc(s.name)}の周辺" loading="lazy"></span><span class="row-info"><span class="badge ${p.tier}">${tierLabel[p.tier]}</span><span class="row-name">${esc(s.name)}</span><span class="row-distance">⌖ ${Number.isFinite(d)?`現在地から ${(d/1000).toFixed(1)} km`:'距離は未取得'}</span><span class="row-description">${esc(s.memo||p.reasons[0])}</span></span><span class="row-score"><strong>${Math.round(p.score)}</strong><small>観測スコア${p.weatherScore===null?'（暫定）':''}</small></span><span class="row-arrow">›</span></button>`;}).join('')||'<p class="empty">該当する地点はありません。「要確認」も確認できます。</p>'}</div>
  <div class="section"><button id="weather" class="glass" ${state.loadingWeather?'disabled':''}>${state.loadingWeather?'予報を取得中…':'天気予報を更新'}</button><p class="attribution">天気: Open-Meteo / 都市データ: 国土交通省 PLATEAU<br>未確認の条件は推薦せず、要確認に表示します。</p></div>`;
  bind('change-target',()=>navigate({page:'select'}));bind('date',editDate);bind('location',locate);bind('weather',()=>void refreshWeather());
  let tabTimer=0;const changeGroup=(group:string)=>{state.group=group;const tabs=root.querySelector('.tabs')!;tabs.classList.toggle('review',group!=='recommended');tabs.querySelectorAll('button').forEach(b=>b.setAttribute('aria-selected',String(b.id===(group==='recommended'?'recommended':'review'))));clearTimeout(tabTimer);tabTimer=window.setTimeout(redraw,matchMedia('(prefers-reduced-motion:reduce)').matches?0:240);};
  bind('recommended',()=>changeGroup('recommended'));bind('review',()=>changeGroup('needsCheck'));
  for(const id of ['sort','category'] as const){const el=root.querySelector<HTMLSelectElement>('#'+id)!;el.value=state[id];el.onchange=()=>{state[id]=el.value;redraw();};}
  root.querySelectorAll<HTMLButtonElement>('[data-spot]').forEach(b=>b.onclick=()=>navigate({page:'detail',id:b.dataset.spot!}));imageFallbacks(root);
  const map=L.map(root.querySelector<HTMLElement>('#map')!,{zoomControl:false}).setView([35.68,139.75],11);
  const tiles=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'}).addTo(map);
  let tileError=false;tiles.on('tileerror',()=>{if(tileError)return;tileError=true;const msg=document.createElement('p');msg.className='scene-caption';msg.textContent='地図を取得できません。地点ピンと一覧は利用できます。';root.querySelector('.map-shell')!.append(msg);});
  for(const c of state.contexts){const p=rows.find(p=>p.spotId===c.spot.id)!;L.marker([c.spot.latitude,c.spot.longitude],{title:c.spot.name,icon:L.divIcon({className:'spot-pin '+(p.tier==='recommended'?'':p.tier==='needsCheck'?'review':'closed'),iconSize:[15,15]})}).addTo(map).on('click',()=>navigate({page:'detail',id:c.spot.id}));}
  if(state.location)L.circleMarker([state.location.lat,state.location.lon],{radius:6,color:'#8fcfff'}).addTo(map);
  let closeScene=()=>{};bind('wide',()=>{closeScene();closeScene=openScene(state.contexts[0],true);});
  return ()=>{clearTimeout(tabTimer);closeScene();map.remove();};
}
