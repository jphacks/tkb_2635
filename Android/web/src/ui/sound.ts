export const soundEnabled=()=>localStorage.getItem('astera.sound')!=='off';
const files={select:'se_body_select',found:'se_spot_found',pin:'se_pin_tap',slider:'se_time_tick',scene:'se_map_open',launch:'se_launch',drag:'se_map_gesture'};
const clips=new Map<string,HTMLAudioElement>();let bgm:HTMLAudioElement|undefined,last=0,activated=false;
const allowed=()=>soundEnabled()&&!document.hidden&&window.AsteraDevice?.soundAllowed?.()!==false;
export function toggleSound(){localStorage.setItem('astera.sound',soundEnabled()?'off':'on');sync();}
function sync(){if(!activated)return;if(!allowed()){bgm?.pause();clips.forEach(a=>a.pause());return;}bgm??=new Audio('./generated/bgm_main.m4a');bgm.loop=true;bgm.volume=.10;void bgm.play().catch(()=>{});}
export function tone(name:keyof typeof files) {
  activated=true;sync();if(!allowed()||Date.now()-last<180)return;last=Date.now();
  const file=files[name];let clip=clips.get(file);if(!clip){clip=new Audio('./generated/'+file+'.wav');clips.set(file,clip);}clip.currentTime=0;clip.volume=.45;void clip.play().catch(()=>{});
}
document.addEventListener('visibilitychange',sync);
window.addEventListener('astera-suspend',()=>{bgm?.pause();clips.forEach(a=>a.pause());});
// Androidの消音状態がアプリ表示中に変わった場合も反映する。
setInterval(sync,1000);
