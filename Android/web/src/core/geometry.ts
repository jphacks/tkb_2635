import { DEG, norm } from './astro';
import type { Building, CityScene, Context, Spot } from './types';
export const localPosition=(scene:CityScene,lat:number,lon:number) => ({
  east:(lon-scene.originLongitude)*111320*Math.cos(scene.originLatitude*DEG),north:(lat-scene.originLatitude)*110574
});
export function rayHit(ox:number,oy:number,dx:number,dy:number,b:Building):number|null {
  let min=-Infinity,max=Infinity;
  for(const [o,d,lo,hi] of [[ox,dx,b.x-b.width/2,b.x+b.width/2],[oy,dy,b.y-b.depth/2,b.y+b.depth/2]]) {
    if(Math.abs(d)<1e-12){if(o<lo||o>hi)return null;continue;}
    const a=(lo-o)/d,c=(hi-o)/d;min=Math.max(min,Math.min(a,c));max=Math.min(max,Math.max(a,c));
    if(max<min)return null;
  }
  return min>.5?min:null;
}
export function computeHorizon(spot:Spot,scene:CityScene):number[] {
  const o=localPosition(scene,spot.latitude,spot.longitude),eye=spot.floorElevation+spot.eyeHeight,samples=Array<number>(360).fill(0);
  const directions=samples.map((_,i)=>[Math.sin(i*DEG),Math.cos(i*DEG)]);
  for(const b of scene.buildings) {
    if(b.id===spot.hostBuildingId||scene.groundElevation+b.height<=eye)continue;
    const minX=b.x-b.width/2,maxX=b.x+b.width/2,minY=b.y-b.depth/2,maxY=b.y+b.depth/2;
    let lo=0,hi=359;
    if(!(o.east>=minX-1&&o.east<=maxX+1&&o.north>=minY-1&&o.north<=maxY+1)) {
      const center=Math.atan2(b.x-o.east,b.y-o.north)/DEG;
      const delta=[[minX,minY],[minX,maxY],[maxX,minY],[maxX,maxY]].map(([x,y])=>norm(Math.atan2(x-o.east,y-o.north)/DEG-center+180)-180);
      lo=Math.floor(center+Math.min(0,...delta))-1;hi=Math.ceil(center+Math.max(0,...delta))+1;
    }
    for(let i=lo;i<=hi;i++) {
      const ix=((i%360)+360)%360,[dx,dy]=directions[ix],distance=rayHit(o.east,o.north,dx,dy,b);
      if(distance!==null)samples[ix]=Math.max(samples[ix],Math.atan2(scene.groundElevation+b.height-eye,distance)/DEG);
    }
  }
  return samples;
}
export function makeContext(spot:Spot,scene?:CityScene):Context {
  const horizon=scene?computeHorizon(spot,scene):Array<number>(360).fill(spot.approxHorizonElevation??10);
  return {spot,scene,horizon,approximate:!scene,openness:horizon.reduce((s,h)=>s+1-Math.sin(Math.max(0,h)*DEG),0)/360};
}
export const obstruction=(context:Context,az:number)=>context.horizon[Math.round(norm(az))%360];
export function inRange(az:number,from:number,to:number) {
  if(Math.abs(to-from)>=360)return true;
  const a=norm(az),f=norm(from),t=norm(to);return f<=t?(a>=f&&a<=t):(a>=f||a<=t);
}
export function blockedByWindows(s:Spot,az:number,alt:number) {
  return (s.viewingDirectionMask!=null&&!s.viewingDirectionMask.some(r=>inRange(az,r.from,r.to)))
    ||(s.maxVisibleAltitude!=null&&alt>s.maxVisibleAltitude);
}
export function distanceKm(lat:number,lon:number,s:Pick<Spot,'latitude'|'longitude'>) {
  const a=Math.sin((s.latitude-lat)*DEG/2)**2+Math.cos(lat*DEG)*Math.cos(s.latitude*DEG)*Math.sin((s.longitude-lon)*DEG/2)**2;
  return 6371*2*Math.atan2(Math.sqrt(a),Math.sqrt(Math.max(0,1-a)));
}
