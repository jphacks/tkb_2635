import { position, sun } from './astro';
import type { Context, Star, Target } from './types';
import { obstruction, blockedByWindows } from './geometry';
/** 選んだ日本時間の1日を走査し、交差は二分法で1秒まで詰める。 */
export function riseSet(context:Context,target:Target,date:Date,stars:Star[]) {
  const start=new Date(date.getTime()+9*3600000);start.setUTCHours(0,0,0,0);
  const begin=start.getTime()-9*3600000,end=begin+86400000;
  const altitude=(t:number)=>position(target,new Date(t),context.spot.latitude,context.spot.longitude,stars).altitude;
  const events:{label:string;date:Date}[]=[];
  let previous=altitude(begin),best={t:begin,alt:previous};
  for(let t=begin+5*60000;t<=end;t+=5*60000) {
    const next=altitude(t);if(next>best.alt)best={t,alt:next};
    if((previous<=0&&next>0)||(previous>0&&next<=0)) {
      const rising=next>previous;let lo=t-5*60000,hi=t;
      while(hi-lo>1000){const mid=(lo+hi)/2;if((altitude(mid)>0)===rising)hi=mid;else lo=mid;}
      events.push({label:rising?'昇る（地平線）':'沈む（地平線）',date:new Date((lo+hi)/2)});
    }previous=next;
  }
  events.push({label:'最も高い時刻（5分刻み）',date:new Date(best.t)});
  return events.sort((a,b)=>a.date.getTime()-b.date.getTime());
}
export function observingWindows(context:Context,target:Target,date:Date,stars:Star[]) {
  const intervals:{from:Date;to:Date}[]=[];let open:number|null=null;
  const begin=date.getTime(),end=begin+6*3600000,s=context.spot;
  for(let t=begin;t<=end;t+=5*60000){const p=position(target,new Date(t),s.latitude,s.longitude,stars);
    const visible=p.altitude>obstruction(context,p.azimuth)+1&&!blockedByWindows(s,p.azimuth,p.altitude)
      &&(target.kind==='moon'||sun(new Date(t),s.latitude,s.longitude).altitude<=-6);
    if(visible&&open===null)open=t;
    if((!visible||t===end)&&open!==null){intervals.push({from:new Date(open),to:new Date(t)});open=null;}
  }return intervals;
}
