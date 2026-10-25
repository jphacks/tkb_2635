import type { Spot, Weather } from './types';
export const gridId=(lat:number,lon:number)=>`${(Math.round(lat*20)/20).toFixed(2)},${(Math.round(lon*20)/20).toFixed(2)}`;
type Response={hourly:{time:number[];cloud_cover?:(number|null)[];precipitation?:(number|null)[];wind_speed_10m?:(number|null)[];visibility?:(number|null)[]}};
export function decodeWeather(body:Response):Weather[] {
  if(!Array.isArray(body.hourly?.time))throw new Error('天気データの形式が正しくありません');
  const value=(n:unknown,max=Infinity)=>typeof n==='number'&&Number.isFinite(n)&&n>=0&&n<=max?n:null;
  return body.hourly.time.flatMap((t,i)=>typeof t==='number'&&Number.isFinite(t)?[{time:t*1000,cloudCover:value(body.hourly.cloud_cover?.[i],100),
    precipitation:value(body.hourly.precipitation?.[i]),wind:value(body.hourly.wind_speed_10m?.[i]),visibility:value(body.hourly.visibility?.[i])}]:[]);
}
export const nearestWeather=(samples:Weather[],date:Date)=>samples.filter(s=>Math.abs(s.time-date.getTime())<=90*60000)
  .sort((a,b)=>Math.abs(a.time-date.getTime())-Math.abs(b.time-date.getTime()))[0];
export class WeatherClient {
  private cache=new Map<string,{at:number;samples:Weather[]}>();
  constructor(private request:typeof fetch=fetch){}
  samples(spot:Spot){return this.cache.get(gridId(spot.latitude,spot.longitude))?.samples??[];}
  at(spot:Spot,date:Date){return nearestWeather(this.samples(spot),date);}
  outOfRange(spot:Spot,date:Date) {const s=this.samples(spot);return s.length>0&&(date.getTime()<s[0].time-90*60000||date.getTime()>s.at(-1)!.time+90*60000);}
  async refresh(spots:Spot[]):Promise<number> {
    const grid=new Map(spots.map(s=>[gridId(s.latitude,s.longitude),s]));let errors=0;
    const pending=[...grid].filter(([id])=>Date.now()-(this.cache.get(id)?.at??0)>30*60000);
    // 近接地点の予報を共有し、同時通信は3件までにする。
    for(let i=0;i<pending.length;i+=3)await Promise.all(pending.slice(i,i+3).map(async([id,s])=>{
      const params=new URLSearchParams({latitude:String(s.latitude),longitude:String(s.longitude),hourly:'cloud_cover,precipitation,wind_speed_10m,visibility',timeformat:'unixtime',forecast_days:'16'});
      try {const response=await this.request(`https://api.open-meteo.com/v1/forecast?${params}`,{signal:AbortSignal.timeout(15000)});
        if(!response.ok)throw new Error(`天気の通信エラー（HTTP ${response.status}）`);
        const samples=decodeWeather(await response.json());if(!samples.length)throw new Error('天気が空です');
        this.cache.set(id,{at:Date.now(),samples});
      }catch(error){console.warn('天気予報の取得に失敗しました:',String(error));this.cache.delete(id);errors++;}
    }));return errors;
  }
}
