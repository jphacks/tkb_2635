import {DEG} from './astro';
import type {ConstellationImage} from './types';
type Vec=[number,number,number];
const dot=(a:Vec,b:Vec)=>a.reduce((n,x,i)=>n+x*b[i],0);
const scale=(v:Vec,s:number)=>v.map(x=>x*s) as Vec;
const add=(a:Vec,b:Vec)=>a.map((x,i)=>x+b[i]) as Vec;
const unit=(v:Vec)=>scale(v,1/Math.hypot(...v));
const cross=(a:Vec,b:Vec):Vec=>[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]];
const equatorial=([ra,dec]:number[]):Vec=>[Math.cos(dec*DEG)*Math.cos(ra*DEG),Math.cos(dec*DEG)*Math.sin(ra*DEG),Math.sin(dec*DEG)];
const kernel=(a:number[],b:number[])=>{const r=(a[0]-b[0])**2+(a[1]-b[1])**2;return r<1e-12?0:r*Math.log(r)/2;};
function solve(matrix:number[][],values:number[]) {
  const m=matrix.map((r,i)=>[...r,values[i]]),n=values.length;
  for(let i=0;i<n;i++){let pivot=i;for(let j=i+1;j<n;j++)if(Math.abs(m[j][i])>Math.abs(m[pivot][i]))pivot=j;
    if(Math.abs(m[pivot][i])<1e-12)throw Error('星座画像の基準点が重なっています');
    [m[i],m[pivot]]=[m[pivot],m[i]];const factor=m[i][i];for(let k=i;k<=n;k++)m[i][k]/=factor;
    for(let j=0;j<n;j++)if(j!==i){const f=m[j][i];for(let k=i;k<=n;k++)m[j][k]-=f*m[i][k];}
  }return m.map(r=>r[n]);
}
/** iOSのConstellationImagePlacementと同じ接平面＋薄板スプライン。 */
export function imagePlacement(image:ConstellationImage) {
  const vectors=image.anchors.map(a=>equatorial(a.star));if(vectors.length<2)throw Error('星座の基準点不足');
  const center=unit(vectors.reduce(add,[0,0,0] as Vec));let east=cross([0,0,1],center);if(Math.hypot(...east)<1e-6)east=[0,1,0];east=unit(east);
  const right=scale(east,-1),up=cross(center,east),source=image.anchors.map(a=>[a.pixel[0],-a.pixel[1]]),target=vectors.map(v=>[dot(v,right)/dot(v,center),dot(v,up)/dot(v,center)]),n=source.length;
  let map:(p:number[])=>number[];
  if(n===2){const [a,b]=source,[c,d]=target,dx=b[0]-a[0],dy=b[1]-a[1],den=dx*dx+dy*dy,wx=d[0]-c[0],wy=d[1]-c[1],re=(wx*dx+wy*dy)/den,im=(wy*dx-wx*dy)/den;map=p=>[c[0]+re*(p[0]-a[0])-im*(p[1]-a[1]),c[1]+im*(p[0]-a[0])+re*(p[1]-a[1])];}
  else {const matrix=Array.from({length:n+3},()=>Array<number>(n+3).fill(0));for(let i=0;i<n;i++){for(let j=0;j<n;j++)matrix[i][j]=kernel(source[i],source[j]);for(let k=0;k<3;k++)matrix[i][n+k]=matrix[n+k][i]=[1,...source[i]][k];}
    const weights=[0,1].map(axis=>solve(matrix,[...target.map(p=>p[axis]),0,0,0]));map=p=>weights.map(w=>w[n]+w[n+1]*p[0]+w[n+2]*p[1]+source.reduce((sum,a,i)=>sum+w[i]*kernel(p,a),0));}
  return (x:number,y:number)=>{const p=map([x,-y]),v=unit(add(add(center,scale(right,p[0])),scale(up,p[1])));return {ra:Math.atan2(v[1],v[0])/DEG,dec:Math.asin(v[2])/DEG};};
}
