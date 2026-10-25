import { direction, moon, position, separation, sun } from './astro';
import { accessNotices, accessStatus, hoursLabel } from './access';
import { blockedByWindows, obstruction } from './geometry';
import type { Context, Horizontal, Prediction, Star, Target, Weather } from './types';
export const clamp=(n:number,lo=0,hi=1)=>Math.min(hi,Math.max(lo,n));
export const skyBrightness=(a:number)=>clamp((a+18)/12);
export const skyState=(a:number)=>a<=-18?'夜':a<=-12?'天文薄明':a<=-6?'航海薄明':a<=0?'市民薄明':'昼間';
export function moonEffect(m:ReturnType<typeof moon>,target:Horizontal) {
  if(m.position.altitude<=0)return 0;
  return Math.min(1,m.fraction*(.4+.6*Math.sin(m.position.altitude*Math.PI/180))*(separation(m.position,target)<20?1.3:1));
}
export function darkness(sky:number,glare:number|null|undefined,effect:number) {
  return clamp(1-(.45*sky+.25*(glare==null?.5:clamp(glare,0,3)/3)+.30*effect));
}
export const weatherScore=(w:Weather|undefined)=>w?.cloudCover==null?null:clamp(1-w.cloudCover/100)*((w.precipitation??0)>=.1?.2:1);
export function evaluate(context:Context,target:Target,date:Date,stars:Star[],weather?:Weather,outOfRange=false):Prediction {
  const s=context.spot,p=position(target,date,s.latitude,s.longitude,stars),m=moon(date,s.latitude,s.longitude),
    solar=sun(date,s.latitude,s.longitude),sky=skyState(solar.altitude),access=accessStatus(s,date),
    obs=obstruction(context,p.azimuth),mask=blockedByWindows(s,p.azimuth,p.altitude),
    visible=p.altitude>obs+1&&!mask,starBright=target.kind!=='moon'&&solar.altitude>-6,
    moonBright=target.kind==='moon'&&solar.altitude>-6,notices=accessNotices(s,date),w=weatherScore(weather),
    effect=target.kind==='moon'?0:moonEffect(m,p),dark=darkness(s.regionalLightIndex??.5,s.localGlareLevel,effect)*(1-skyBrightness(solar.altitude));
  const verified=s.directionMaskVerified&&(s.indoorOutdoor!=='indoor'||(s.viewingDirectionMask?.length??0)>0)
    &&(s.viewingDirectionMask?.every(r=>Number.isFinite(r.from)&&Number.isFinite(r.to))??true);
  const flags:string[]=[];
  if(s.localGlareLevel==null)flags.push('近傍照明は未確認');
  if(s.regionalLightIndex==null)flags.push('地域の光害は未確認');
  if(s.lightingCheckMethod==='desk')flags.push('近傍照明は机上評価（現地未確認）');
  if(w===null)flags.push(outOfRange?'指定時刻は天気予報の範囲外':'指定時刻の天気予報は未取得');
  if(context.approximate)flags.push('地平線は暫定値');
  if(!s.lastVerifiedAt||access==='unverified')flags.push('営業時間・立入条件は未確認');
  if(!verified)flags.push('窓・柵などの観測方角は未確認');
  if(s.regionalLightIndex!=null&&!s.regionalLightSource)flags.push('地域の光害は暫定値');
  flags.push(...notices.map(n=>n.message));
  const tier=access==='closed'?'unavailable':!visible||starBright?'notVisible':
    moonBright||access==='unverified'||notices.length>0||!s.lastVerifiedAt||w===null||!verified||context.approximate||s.regionalLightIndex==null?'needsCheck':'recommended';
  const reasons:string[]=[];
  if(access==='unverified')reasons.push('指定時刻の入場可否は未確認です。利用できることを確認してからお出かけください。');
  else if(access==='closed')reasons.push(`指定時刻は利用時間外または休園日です（${hoursLabel(s,date)}）。`);
  if(starBright)reasons.push(`指定時刻は${sky}で空が明るいため、恒星は見えません。太陽高度が−6°以下になると見え始めます。`);
  else if(solar.altitude>-6)reasons.push(`指定時刻は${sky}です。月が見える場合もありますが、星空観測には向きません。`);
  else if(sky!=='夜')reasons.push(`${sky}のため、空に残る太陽の光を暗さへ反映しています。`);
  if(p.altitude<=0)reasons.push(`${target.name}は地平線の下にあります。`);
  else if(mask)reasons.push(`${target.name}は${direction(p.azimuth)}・高度${p.altitude.toFixed(0)}°ですが、窓や屋根の向きから見えない見込みです。`);
  else if(visible)reasons.push(`${direction(p.azimuth)}の空が開けており、${target.name}（高度${p.altitude.toFixed(0)}°）を建物に遮られず観測できる見込みです。`);
  else reasons.push(`${target.name}は${direction(p.azimuth)}・高度${p.altitude.toFixed(0)}°で、周辺の建物など（遮蔽仰角${obs.toFixed(0)}°）に隠れる見込みです。`);
  if(weather?.cloudCover!=null)reasons.push(`雲量の予報は${Math.round(weather.cloudCover)}%です。`);
  reasons.push(...flags.map(f=>`${f}。`));
  if(s.indoorOutdoor==='indoor')reasons.push('室内照明の窓への映り込みに注意してください。');
  return {...p,spotId:s.id,tier,score:100*(.35*context.openness+.40*(w??.5)+.25*dark),reasons,flags,
    obstruction:obs,visible:visible&&!starBright,access,openness:context.openness,darkness:dark,weatherScore:w,
    sunAltitude:solar.altitude,skyState:sky,moonEffect:effect,cloudCover:weather?.cloudCover??null};
}
export const tierRank={recommended:0,needsCheck:1,notVisible:2,unavailable:3};
export const rank=(rows:Prediction[])=>rows.sort((a,b)=>tierRank[a.tier]-tierRank[b.tier]||b.score-a.score||a.spotId.localeCompare(b.spotId));
export const tierLabel={recommended:'おすすめ',needsCheck:'要確認',notVisible:'見えない見込み',unavailable:'利用不可'};
