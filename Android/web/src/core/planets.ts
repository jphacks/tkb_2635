import {DEG, days, equatorial, horizontal, norm, obliquity} from './astro';
type Pair=[number,number];
type Orbit={n:Pair;i:Pair;w:Pair;a:number;e:Pair;m:Pair};
const jupiter:Orbit={n:[100.4542,2.76854e-5],i:[1.303,-1.557e-7],w:[273.8777,1.64505e-5],a:5.20256,e:[.048498,4.469e-9],m:[19.895,.0830853001]};
const saturn:Orbit={n:[113.6634,2.38980e-5],i:[2.4886,-1.081e-7],w:[339.3939,2.97661e-5],a:9.55475,e:[.055546,-9.499e-9],m:[316.967,.0334442282]};
const sun:Orbit={n:[0,0],i:[0,0],w:[282.9404,4.70935e-5],a:1,e:[.016709,-1.151e-9],m:[356.047,.9856002585]};
const orbits:Record<string,Orbit>={
  mercury:{n:[48.3313,3.24587e-5],i:[7.0047,5e-8],w:[29.1241,1.01444e-5],a:.387098,e:[.205635,5.59e-10],m:[168.6562,4.0923344368]},
  venus:{n:[76.6799,2.46590e-5],i:[3.3946,2.75e-8],w:[54.891,1.38374e-5],a:.723330,e:[.006773,-1.302e-9],m:[48.0052,1.6021302244]},
  mars:{n:[49.5574,2.11081e-5],i:[1.8497,-1.78e-8],w:[286.5016,2.92961e-5],a:1.523688,e:[.093405,2.516e-9],m:[18.6021,.5240207766]},jupiter,saturn
};
const value=(pair:Pair,d:number)=>pair[0]+pair[1]*d;
export function eccentricAnomaly(m:number,e:number) {
  let ea=m+e/DEG*Math.sin(m*DEG)*(1+e*Math.cos(m*DEG));
  for(let i=0;i<20;i++) {const delta=(ea-e/DEG*Math.sin(ea*DEG)-m)/(1-e*Math.cos(ea*DEG));ea-=delta;if(Math.abs(delta)<1e-8)break;}
  return ea;
}
function heliocentric(el:Orbit,d:number) {
  const n=value(el.n,d)*DEG,i=value(el.i,d)*DEG,w=value(el.w,d),e=value(el.e,d),m=norm(value(el.m,d));
  const ea=eccentricAnomaly(m,e)*DEG,xv=el.a*(Math.cos(ea)-e),yv=el.a*Math.sqrt(1-e*e)*Math.sin(ea),
    v=Math.atan2(yv,xv)/DEG,r=Math.hypot(xv,yv),u=(v+w)*DEG;
  const x=r*(Math.cos(n)*Math.cos(u)-Math.sin(n)*Math.sin(u)*Math.cos(i)),
    y=r*(Math.sin(n)*Math.cos(u)+Math.cos(n)*Math.sin(u)*Math.cos(i)),z=r*Math.sin(u)*Math.sin(i);
  return {lon:norm(Math.atan2(y,x)/DEG),lat:Math.atan2(z,Math.hypot(x,y))/DEG,r};
}
function perturbation(kind:string,mj:number,ms:number) {
  const s=(a:number)=>Math.sin(a*DEG),c=(a:number)=>Math.cos(a*DEG);
  if(kind==='jupiter') return {lon:-.332*s(2*mj-5*ms-67.6)-.056*s(2*mj-2*ms+21)+.042*s(3*mj-5*ms+21)
    -.036*s(mj-2*ms)+.022*c(mj-ms)+.023*s(2*mj-3*ms+52)-.016*s(mj-5*ms-69),lat:0};
  if(kind==='saturn') return {lon:.812*s(2*mj-5*ms-67.6)-.229*c(2*mj-4*ms-2)+.119*s(mj-2*ms-3)
    +.046*s(2*mj-6*ms-69)+.014*s(mj-3*ms+32),lat:-.020*c(2*mj-4*ms-2)+.018*s(2*mj-6*ms-49)};
  return {lon:0,lat:0};
}
export function planetPosition(id:string,date:Date,lat:number,lon:number) {
  const el=orbits[id];if(!el)throw new Error('惑星データなし');
  const d=days(date),ds=d+1.5,h=heliocentric(el,ds),p=perturbation(id,value(jupiter.m,ds),value(saturn.m,ds));
  h.lon+=p.lon;h.lat+=p.lat;
  const ss=heliocentric(sun,ds),l=h.lon*DEG,b=h.lat*DEG,sl=ss.lon*DEG;
  const x=h.r*Math.cos(l)*Math.cos(b)+ss.r*Math.cos(sl),y=h.r*Math.sin(l)*Math.cos(b)+ss.r*Math.sin(sl),z=h.r*Math.sin(b);
  const eq=equatorial(norm(Math.atan2(y,x)/DEG),Math.atan2(z,Math.hypot(x,y))/DEG,obliquity(d));
  return horizontal(eq.ra,eq.dec,d,lat,lon);
}
