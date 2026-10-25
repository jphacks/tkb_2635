import type { Spot, Hours } from './types';
export const tokyoParts=(date:Date)=>{
  const d=new Date(date.getTime()+9*3600000);
  return {day:d.toISOString().slice(0,10),monthDay:d.toISOString().slice(5,10),weekday:String(d.getUTCDay()+1),minute:d.getUTCHours()*60+d.getUTCMinutes()};
};
export function minutes(value?:string) {
  if(!value||!/^\d{2}:\d{2}$/.test(value))return null;
  const [h,m]=value.split(':').map(Number);return h<24&&m<60?h*60+m:null;
}
export function accessHours(spot:Spot,date:Date):Hours|null {
  const p=tokyoParts(date),seasons=spot.accessRules?.seasonalHours;
  let hours=spot.openingHours;
  if(seasons) {
    const match=seasons.filter(s=>s.fromMonthDay<=s.throughMonthDay
      ?p.monthDay>=s.fromMonthDay&&p.monthDay<=s.throughMonthDay:p.monthDay>=s.fromMonthDay||p.monthDay<=s.throughMonthDay);
    if(match.length!==1)return null;hours=match[0].hours;
  }
  const override=hours.dateOverrides?.[p.day]??hours.weeklyOverrides?.[p.weekday];
  return {...hours,open:override?.open??hours.open,close:override?.close??hours.close,lastAdmission:override?.lastAdmission??hours.lastAdmission};
}
export function accessStatus(spot:Spot,date:Date):'open'|'closed'|'unverified' {
  const p=tokyoParts(date),rules=spot.accessRules;
  if(rules?.unverified||(rules?.validFrom&&p.day<rules.validFrom)||(rules?.validThrough&&p.day>rules.validThrough))return 'unverified';
  const h=accessHours(spot,date);
  if(!h||(h.validFrom&&p.day<h.validFrom)||(h.validThrough&&p.day>h.validThrough))return 'unverified';
  const override=h.dateOverrides?.[p.day]??h.weeklyOverrides?.[p.weekday];
  if(override?.unverified)return 'unverified';
  if(override?.closed||rules?.closedDates?.includes(p.day))return 'closed';
  if(h.alwaysOpen)return 'open';
  const start=minutes(h.open),end=minutes(h.close);
  if(start===null||end===null||start===end)return 'unverified';
  const adjustedEnd=end<=start?end+1440:end,now=p.minute<start&&end<=start?p.minute+1440:p.minute;
  let admission=adjustedEnd;
  if(h.lastAdmission!=null){const last=minutes(h.lastAdmission);if(last===null)return 'unverified';
    admission=last<start&&end<=start?last+1440:last;if(admission<start||admission>adjustedEnd)return 'unverified';}
  return now>=start&&now<adjustedEnd&&now<=admission?'open':'closed';
}
export function accessNotices(spot:Spot,date:Date) {
  const day=tokyoParts(date).day;return spot.accessRules?.areaRestrictions?.filter(n=>n.from<=day&&day<=n.through)??[];
}
export function hoursLabel(spot:Spot,date:Date) {
  if(accessStatus(spot,date)==='unverified')return '未確認';
  const h=accessHours(spot,date);if(!h)return '未確認';if(h.alwaysOpen)return '常時開放';
  return `${h.open}〜${h.close}${h.lastAdmission?`（最終入場 ${h.lastAdmission}）`:''}`;
}
