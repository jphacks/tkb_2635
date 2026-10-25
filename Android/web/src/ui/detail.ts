import {state,predictions,navigate,redraw} from '../state';
import {directionLabel as direction} from './preferences';
import {hoursLabel} from '../core/access';
import {riseSet,observingWindows} from '../core/rise-set';
import {tierLabel} from '../core/recommender';
import {bind,esc,dateLabel,timeLabel,notice,categoryLabel} from './dom';
import {editDate} from './date-editor';
import {openScene} from './scene';
export function detail(root:HTMLElement,id:string) {
  const c=state.contexts.find(c=>c.spot.id===id)!,s=c.spot,p=predictions().find(p=>p.spotId===id)!;
  const events=riseSet(c,state.target!,state.date,state.catalog!.stars),windows=observingWindows(c,state.target!,state.date,state.catalog!.stars);
  const metric=(label:string,value:string)=>`<div class="metric"><small>${esc(label)}</small><strong>${esc(value)}</strong></div>`;
  root.innerHTML=`<div class="toolbar"><button id="back">‹ スポット一覧</button><button id="date" class="glass">${dateLabel(state.date)} ⌄</button></div><p class="eyebrow">${esc(s.ward)} / ${esc(categoryLabel(s.category))}</p><h1 class="detail-title">${esc(s.name)}</h1>
  <p><span class="badge ${p.tier}">${tierLabel[p.tier]}</span> ${esc(state.target!.name)}を観測</p>
  <div class="section actions"><button id="city" class="primary">3D都市・観測者視点</button><button id="ar" class="glass">カメラARを開く</button></div>
  <div class="detail-metrics">${metric('観測スコア',`${Math.round(p.score)}${p.weatherScore===null?'（暫定）':''}`)}${metric('天体の方角・高度',`${direction(p.azimuth)}・${p.altitude.toFixed(1)}°`)}${metric('建物の遮蔽仰角',`${p.obstruction.toFixed(1)}°`)}${metric('空の開放度',`${Math.round(p.openness*100)}%`)}${metric('雲量',p.cloudCover===null?'未取得':`${p.cloudCover.toFixed(0)}%`)}${metric('空の明るさ',p.skyState)}</div>
  <div class="time-control"><label for="time">時刻を動かして見え方を調べる（前後6時間）</label><input id="time" type="range" min="-360" max="360" step="5" value="0"><output id="time-preview">${dateLabel(state.date)}</output></div>
  ${state.target!.note?notice(state.target!.note):''}<section class="detail-section"><h2>この判定の理由</h2><ul>${p.reasons.map(r=>`<li>${esc(r)}</li>`).join('')}</ul></section>
  <section class="detail-section"><h2>昇る・沈む時刻</h2>${events.map(e=>`<p>${esc(e.label)}　${timeLabel(e.date)}</p>`).join('')}<p class="caption">地平線を基準にした概算です。建物は次の時間帯へ反映しています。</p></section>
  <section class="detail-section"><h2>今から6時間の見える方向</h2>${windows.map(w=>`<p>${timeLabel(w.from)}〜${timeLabel(w.to)}</p>`).join('')||'<p>建物と空の明るさの条件を満たす時間はありません。</p>'}<p class="caption">5分刻みの概算。天気と入場条件は別途確認してください。</p></section>
  <section class="detail-section"><h2>施設情報</h2><p>床面標高：${s.floorElevation.toFixed(1)} m ／ 出典：${esc(s.floorElevationSource||"暫定値・未確認")}</p><p>利用時間：${esc(hoursLabel(s,state.date))}</p>${[['料金',s.admissionFee],['予約',s.reservationRequired===undefined?undefined:s.reservationRequired?'必要':'不要'],['入場条件',s.accessConditions],['天候による休止',s.weatherClosureConditions],['撮影制限',s.photographyRestrictions],['観測方向',s.viewingDirectionNotes],['確認日',s.lastVerifiedAt]].map(([k,v])=>`<p>${k}：${esc(v||'未確認')}</p>`).join('')}${s.officialWebsite?.startsWith('https://')?`<p><a href="${esc(s.officialWebsite)}" target="_blank" rel="noopener">施設の公式情報 ↗</a></p>`:''}<p><a href="https://www.google.com/maps/dir/?api=1&destination=${s.latitude},${s.longitude}" target="_blank" rel="noopener">ここまでの経路を調べる ↗</a></p></section>
  <section class="detail-section"><h2>ほかの地点と比較</h2><select id="other" class="glass" aria-label="比較する地点">${state.contexts.filter(x=>x.spot.id!==id).map(x=>`<option value="${esc(x.spot.id)}" ${x.spot.id===s.comparisonSpotId?'selected':''}>${esc(x.spot.name)}</option>`).join('')}</select><button id="compare" class="glass">比較する</button></section>`;
  bind('back',()=>navigate({page:'home'}));bind('date',editDate);
  let close=()=>{};bind('city',()=>{close();close=openScene(c);});bind('ar',()=>{close();close=openScene(c,false,true);});
  bind('compare',()=>navigate({page:'compare',id,other:root.querySelector<HTMLSelectElement>('#other')!.value}));
  const base=state.date.getTime(),slider=root.querySelector<HTMLInputElement>('#time')!;
  slider.oninput=()=>{root.querySelector('#time-preview')!.textContent=dateLabel(new Date(base+Number(slider.value)*60000));};
  slider.onchange=()=>{state.date=new Date(base+Number(slider.value)*60000);redraw();};return ()=>close();
}
export function comparison(root:HTMLElement,id:string,other:string) {
  root.innerHTML=`<div class="toolbar"><button id="back">‹ 詳細へ</button><button id="date" class="glass">${dateLabel(state.date)} ⌄</button></div><h1>${esc(state.target!.name)}の観測条件を比較</h1><div class="compare-grid section">${[id,other].map(key=>{const c=state.contexts.find(c=>c.spot.id===key)!,p=predictions().find(p=>p.spotId===key)!;return `<section class="compare-panel"><h2>${esc(c.spot.name)}</h2><p class="badge ${p.tier}">${tierLabel[p.tier]}</p><p>スコア ${Math.round(p.score)}${p.weatherScore===null?'（暫定）':''}</p><p>高度 ${p.altitude.toFixed(1)}°</p><p>遮蔽仰角 ${p.obstruction.toFixed(1)}°</p><p>開放度 ${Math.round(p.openness*100)}%</p><p>${esc(p.reasons.join(' '))}</p><button data-scene="${esc(key)}" class="glass">3Dで確認</button></section>`;}).join('')}</div>`;
  bind('back',()=>navigate({page:'detail',id}));bind('date',editDate);let close=()=>{};
  root.querySelectorAll<HTMLButtonElement>('[data-scene]').forEach(b=>b.onclick=()=>{close();close=openScene(state.contexts.find(c=>c.spot.id===b.dataset.scene)!);});return ()=>close();
}



