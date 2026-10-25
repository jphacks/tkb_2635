import type { Horizontal, Star, Target } from './types';
import { planetPosition } from './planets';
export const DEG = Math.PI / 180;
export const norm = (a: number) => ((a % 360) + 360) % 360;
export const days = (date: Date) => date.getTime() / 86400000 + 2440587.5 - 2451545;
export const obliquity = (d: number) => 23.439 - 0.0000004 * d;
export const sidereal = (d: number, lon: number) => norm(280.46061837 + 360.98564736629 * d + lon);
export const refraction = (alt: number) => alt > -1 ? 1.02 / Math.tan((alt + 10.3 / (alt + 5.11)) * DEG) / 60 : 0;
export function equatorial(lambda: number, beta: number, epsilon: number) {
  const l=lambda*DEG,b=beta*DEG,e=epsilon*DEG;
  return {ra:norm(Math.atan2(Math.sin(l)*Math.cos(e)-Math.tan(b)*Math.sin(e),Math.cos(l))/DEG),
    dec:Math.asin(Math.sin(b)*Math.cos(e)+Math.cos(b)*Math.sin(e)*Math.sin(l))/DEG};
}
export function horizontal(ra: number, dec: number, d: number, lat: number, lon: number): Horizontal {
  const h=(sidereal(d,lon)-ra)*DEG,p=lat*DEG,delta=dec*DEG;
  const alt=Math.asin(Math.sin(p)*Math.sin(delta)+Math.cos(p)*Math.cos(delta)*Math.cos(h))/DEG;
  return {altitude:alt+refraction(alt),azimuth:norm(Math.atan2(-Math.cos(delta)*Math.sin(h),
    Math.sin(delta)*Math.cos(p)-Math.cos(delta)*Math.cos(h)*Math.sin(p))/DEG)};
}
export function sunEcliptic(d: number) {
  const l=280.460+0.9856474*d,g=(357.528+0.9856003*d)*DEG;
  return norm(l+1.915*Math.sin(g)+0.020*Math.sin(2*g));
}
export function sun(date: Date, lat: number, lon: number) {
  const d=days(date),eq=equatorial(sunEcliptic(d),0,obliquity(d));
  return horizontal(eq.ra,eq.dec,d,lat,lon);
}
export function moon(date: Date, lat: number, lon: number) {
  const d=days(date),t=d/36525;
  const s=(a:number,b:number)=>Math.sin((a+b*t)*DEG), c=(a:number,b:number)=>Math.cos((a+b*t)*DEG);
  const lambda=218.32+481267.881*t+6.29*s(135,477198.87)-1.27*s(259.3,-413335.36)
    +0.66*s(235.7,890534.22)+0.21*s(269.9,954397.74)-0.19*s(357.5,35999.05)-0.11*s(186.5,966404.03);
  const beta=5.13*s(93.3,483202.02)+0.28*s(228.2,960400.89)-0.28*s(318.3,6003.15)-0.17*s(217.6,-407332.21);
  const parallax=0.9508+0.0518*c(135,477198.87)+0.0095*c(259.3,-413335.36)+0.0078*c(235.7,890534.22)+0.0028*c(269.9,954397.74);
  const eq=equatorial(norm(lambda),beta,obliquity(d)),h=(sidereal(d,lon)-eq.ra)*DEG,p=lat*DEG,delta=eq.dec*DEG;
  const geo=Math.asin(Math.sin(p)*Math.sin(delta)+Math.cos(p)*Math.cos(delta)*Math.cos(h))/DEG;
  const topo=geo-parallax*Math.cos(geo*DEG),phase=norm(lambda-sunEcliptic(d));
  return {position:{altitude:topo+refraction(topo),azimuth:norm(Math.atan2(-Math.cos(delta)*Math.sin(h),
    Math.sin(delta)*Math.cos(p)-Math.cos(delta)*Math.cos(h)*Math.sin(p))/DEG)},
    fraction:(1-Math.cos(beta*DEG)*Math.cos(phase*DEG))/2,phase};
}
export function precess(ra: number, dec: number, d: number) {
  const t=d/36525,zeta=(2306.2181*t+0.30188*t*t+0.017998*t*t*t)/3600,
    z=(2306.2181*t+1.09468*t*t+0.018203*t*t*t)/3600,theta=(2004.3109*t-0.42665*t*t-0.041833*t*t*t)/3600;
  const a0=(ra+zeta)*DEG,d0=dec*DEG,th=theta*DEG;
  const a=Math.cos(d0)*Math.sin(a0),b=Math.cos(th)*Math.cos(d0)*Math.cos(a0)-Math.sin(th)*Math.sin(d0),
    c=Math.sin(th)*Math.cos(d0)*Math.cos(a0)+Math.cos(th)*Math.sin(d0);
  return {ra:norm(Math.atan2(a,b)/DEG+z),dec:Math.atan2(c,Math.hypot(a,b))/DEG};
}
export function starPosition(star: Star,date: Date,lat: number,lon: number) {
  const d=days(date),eq=precess(star.rightAscension*15,star.declination,d);
  return horizontal(eq.ra,eq.dec,d,lat,lon);
}
export function position(target: Target,date: Date,lat: number,lon: number,stars: Star[]): Horizontal {
  if(target.kind==='moon') return moon(date,lat,lon).position;
  if(target.kind==='planet') return planetPosition(target.bodyId,date,lat,lon);
  const star=stars.find(s=>s.id===target.bodyId);
  if(!star) throw new Error(`天体データがありません: ${target.bodyId}`);
  return starPosition(star,date,lat,lon);
}
export function separation(a: Horizontal,b: Horizontal) {
  return Math.acos(Math.max(-1,Math.min(1,Math.sin(a.altitude*DEG)*Math.sin(b.altitude*DEG)
    +Math.cos(a.altitude*DEG)*Math.cos(b.altitude*DEG)*Math.cos((a.azimuth-b.azimuth)*DEG))))/DEG;
}
export const direction = (az: number) => ['北','北北東','北東','東北東','東','東南東','南東','南南東',
  '南','南南西','南西','西南西','西','西北西','北西','北北西'][Math.floor((norm(az)+11.25)/22.5)%16];
