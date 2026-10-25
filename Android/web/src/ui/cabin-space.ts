import * as T from 'three';
export function cabinSpace(root:HTMLElement) {
  const canvas=document.createElement('canvas');canvas.className='cabin-space';root.prepend(canvas);
  let renderer:T.WebGLRenderer;try{renderer=new T.WebGLRenderer({canvas,alpha:true,antialias:false});}catch{canvas.remove();return ()=>{};}
  renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));const scene=new T.Scene(),camera=new T.PerspectiveCamera(60,1,.1,1000),points:number[]=[];
  let seed=47;const random=()=>{seed=(seed*1664525+1013904223)>>>0;return seed/4294967296;};
  for(let i=0;i<600;i++)points.push((random()-.5)*450,(random()-.5)*450,-20-random()*400);
  const geometry=new T.BufferGeometry().setAttribute('position',new T.Float32BufferAttribute(points,3)),material=new T.PointsMaterial({size:.55,color:0xbcd9f7,transparent:true,opacity:.55});
  const stars=new T.Points(geometry,material);scene.add(stars);
  const resize=new ResizeObserver(()=>{renderer.setSize(root.clientWidth,root.clientHeight);camera.aspect=root.clientWidth/root.clientHeight;camera.updateProjectionMatrix();});resize.observe(root);
  const reduced=matchMedia('(prefers-reduced-motion:reduce)').matches||localStorage.getItem('astera.reduce')==='on';
  renderer.setAnimationLoop(()=>{if(!document.hidden){if(!reduced)stars.rotation.y+=.00008;renderer.render(scene,camera);}});
  return ()=>{resize.disconnect();renderer.setAnimationLoop(null);geometry.dispose();material.dispose();renderer.dispose();canvas.remove();};
}
