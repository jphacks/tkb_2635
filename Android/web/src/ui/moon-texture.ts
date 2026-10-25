import {DEG} from '../core/astro';
/** 月面写真を保ちながら、計算した月相に沿って明暗境界を付ける。 */
export function phaseImage(source:CanvasImageSource,phase:number) {
  const canvas=document.createElement('canvas');canvas.width=512;canvas.height=512;
  const context=canvas.getContext('2d')!;context.drawImage(source,0,0,512,512);
  const image=context.getImageData(0,0,512,512),sx=Math.sin(phase*DEG),sz=-Math.cos(phase*DEG);
  for(let y=0;y<512;y++)for(let x=0;x<512;x++){const nx=(x-255.5)/256,ny=(y-255.5)/256,r=nx*nx+ny*ny,index=(y*512+x)*4;if(r>1)continue;
    const light=.04+.96*Math.max(0,nx*sx+Math.sqrt(1-r)*sz);for(let channel=0;channel<3;channel++)image.data[index+channel]*=light;
  }context.putImageData(image,0,0);return canvas;
}
