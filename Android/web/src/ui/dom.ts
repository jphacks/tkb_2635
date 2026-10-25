import type { Target } from '../core/types';
export const categoryLabel=(value:string)=>({plaza:'広場',observatory:'展望台',park:'公園',rooftop:'屋上',riverside:'河川敷'} as Record<string,string>)[value]??value;
export const esc=(value:unknown)=>String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!));
export const dateLabel=(date:Date)=>new Intl.DateTimeFormat('ja-JP',{timeZone:'Asia/Tokyo',month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit',hour12:localStorage.getItem('astera.clock')==='12'}).format(date);
export const timeLabel=(date:Date)=>new Intl.DateTimeFormat('ja-JP',{timeZone:'Asia/Tokyo',hour:'2-digit',minute:'2-digit',hour12:localStorage.getItem('astera.clock')==='12'}).format(date);
export const targetArt=(t:Target,classes='')=>t.image
  ?`<img class="target-art ${classes}" src="./generated/${esc(t.image)}" alt="${esc(t.name)}" draggable="false">`
  :t.kind==='constellation'?`<svg class="target-art ${classes}" viewBox="0 0 100 100" aria-label="${esc(t.name)}"><path d="M10 25L30 75L50 40L72 70L90 20" fill="none" stroke="#b6e9ff" stroke-width="1.2"/>${[[10,25],[30,75],[50,40],[72,70],[90,20]].map(([x,y])=>`<circle cx="${x}" cy="${y}" r="2" fill="white"/>`).join('')}</svg>`
  :`<div class="target-art star-art ${classes}" role="img" aria-label="${esc(t.name)}"></div>`;
export function button(id:string,label:string,classes='glass'){return `<button id="${id}" class="${classes}">${label}</button>`;}
export function bind(id:string,callback:(e:Event)=>void){document.getElementById(id)?.addEventListener('click',callback);}
export function notice(message:string){return `<p class="notice" role="status">${esc(message)}</p>`;}
export function modal(content:string,onClose?:()=>void) {
  const dialog=document.createElement('dialog');dialog.className='glass modal';dialog.innerHTML=content;document.body.append(dialog);
  dialog.addEventListener('close',()=>{onClose?.();dialog.remove();},{once:true});dialog.showModal();
  dialog.querySelector('[data-close]')?.addEventListener('click',()=>dialog.close());return dialog;
}
export function imageFallbacks(root:HTMLElement) {
  root.querySelectorAll<HTMLImageElement>('img.spot-photo').forEach(img=>img.addEventListener('error',()=>{
    img.hidden=true;img.parentElement?.classList.add('photo-missing');
  },{once:true}));
}
