import {modal,esc} from './dom';
import {state,redraw} from '../state';
export function editDate() {
  const local=new Date(state.date.getTime()+9*3600000).toISOString().slice(0,16);
  const dialog=modal(`<h2>観測する日時</h2><p>日本時間で選択してください。</p>
    <label>日付と時刻<input id="date-draft" type="datetime-local" value="${esc(local)}" required></label>
    <div class="actions"><button data-close class="glass">キャンセル</button><button id="date-apply" class="primary">適用</button></div>`);
  dialog.querySelector('#date-apply')!.addEventListener('click',()=>{
    const input=dialog.querySelector<HTMLInputElement>('#date-draft')!;
    if(!input.reportValidity())return;
    const next=new Date(input.value+':00+09:00');if(!Number.isFinite(next.getTime()))return;
    state.date=next;dialog.close();redraw();
  });
}
