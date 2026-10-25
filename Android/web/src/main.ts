import './style.css';
import {back,loadData,onRender,state,ensureWeather} from './state';
import {selection} from './ui/selection';
import {home} from './ui/home';
import {detail,comparison} from './ui/detail';
import {esc} from './ui/dom';
import {settings as openSettings,applyPreferences} from './ui/preferences';
const root=document.querySelector<HTMLElement>('#app')!;
let dispose=()=>{};
function render(){dispose();dispose=()=>{};const route=state.route;
  if(route.page==='select')dispose=selection(root);
  else if(route.page==='home'){dispose=home(root);ensureWeather();}
  else if(route.page==='detail')dispose=detail(root,route.id);
  else dispose=comparison(root,route.id,route.other);
  const settings=document.createElement('button');settings.className='glass';settings.style.marginTop='24px';settings.textContent='設定・データの出典';root.append(settings);
  settings.onclick=()=>openSettings();
}
applyPreferences();
window.Astera={back(){const dialogs=[...document.querySelectorAll<HTMLDialogElement>('dialog[open]')];if(dialogs.length){dialogs.at(-1)!.close();return true;}return back();},suspend(){window.dispatchEvent(new Event('astera-suspend'));}};
document.addEventListener('visibilitychange',()=>{if(document.hidden)window.Astera?.suspend();});
onRender(render);
loadData(message=>{root.innerHTML=`<p class="loading" role="status">${esc(message)}</p>`;}).then(render).catch(error=>{root.innerHTML=`<section class="error-panel"><h1>起動できませんでした</h1><p>${esc(error instanceof Error?error.message:error)}</p><button id="reload" class="glass">再試行</button></section>`;root.querySelector('#reload')!.addEventListener('click',()=>location.reload());});
