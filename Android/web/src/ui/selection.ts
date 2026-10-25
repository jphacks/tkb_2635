import {state,navigate} from '../state';
import {button,bind,esc,modal,targetArt} from './dom';
import {tone} from './sound';
import {cabinSpace} from './cabin-space';
export function selection(root:HTMLElement) {
  const targets=state.catalog!.targets;
  root.innerHTML=`<section class="selection"><p class="eyebrow">ASTERA / OBSERVATION DECK</p><h1>宇宙から、星を選ぶ</h1>
    <p class="muted">左右にスライドして、中央の天体をタップ</p>
    <div class="target-slider" role="region" aria-label="観測する天体">${targets.map((t,i)=>`<button class="target-page ${i===state.selectedIndex?'centered':''}" data-index="${i}" aria-label="${esc(t.name)}を選択">${targetArt(t)}<span>${esc(t.name)}</span></button>`).join('')}</div>
    <div class="actions">${button('previous','‹','round glass')}<p>ALIGN · SELECT · EXPLORE</p>${button('next','›','round glass')}</div>
    <p class="muted">天体を選んだら、地球の観測場所へ。</p></section>`;
  const slider=root.querySelector<HTMLDivElement>('.target-slider')!;
  const pages=[...slider.querySelectorAll<HTMLButtonElement>('.target-page')];
  const align=(index:number)=>slider.scrollTo({left:Math.max(0,Math.min(targets.length-1,index))*slider.clientWidth,behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'instant':'smooth'});
  let frame=0;
  slider.addEventListener('scroll',()=>{cancelAnimationFrame(frame);frame=requestAnimationFrame(()=>{
    state.selectedIndex=Math.max(0,Math.min(targets.length-1,Math.round(slider.scrollLeft/slider.clientWidth)));
    pages.forEach((p,i)=>p.classList.toggle('centered',i===state.selectedIndex));
  });});
  requestAnimationFrame(()=>slider.scrollTo({left:state.selectedIndex*slider.clientWidth,behavior:'instant'}));
  pages.forEach((page,index)=>page.addEventListener('click',()=>{
    if(index!==state.selectedIndex){align(index);return;}
    const target=targets[index];tone('select');
    const d=modal(`<p class="eyebrow">選択の確認</p>${targetArt(target)}<h2>${esc(target.name)}</h2>
      <p>この天体を選択しますか？</p>${target.note?`<p class="muted">${esc(target.note)}</p>`:''}
      <div class="actions"><button data-close class="glass">戻る</button><button id="confirm-target" class="primary">確定</button></div>`);
    d.querySelector('#confirm-target')!.addEventListener('click',()=>{state.target=target;
      localStorage.setItem('astera.target',target.id);d.close();navigate({page:'home'});});
  }));
  bind('previous',()=>align(state.selectedIndex-1));bind('next',()=>align(state.selectedIndex+1));
  const dispose=cabinSpace(root.querySelector<HTMLElement>('.selection')!);return ()=>{cancelAnimationFrame(frame);dispose();};
}
