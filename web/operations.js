'use strict';
const baseShow=show;
show=function(page){baseShow(page);if(page==='Pedidos')renderBoard();if(page==='Produtos')mountPreparation();};
function renderBoard(){
  const focus=document.activeElement?.closest('[data-item]');
  const focused=focus?{id:focus.dataset.item,status:focus.dataset.status}:null;
  const items=data.items.filter(i=>i.sector==='cozinha'&&(role==='admin'||i.sector===role)).sort((a,b)=>String(b.status_changed_at||b.created_at).localeCompare(String(a.status_changed_at||a.created_at))||b.id.localeCompare(a.id));
  screen.innerHTML='<h2>Pedidos</h2><p id="board-sync" role="status">Atualização automática a cada 5 segundos</p><div class="order-board">'+[
    ['recebido','Lista de pedidos'],['em preparo','Em preparo'],['pronto','Prontos'],['entregue','Entregues']
  ].map(([status,title])=>{const group=items.filter(i=>i.status===status);if(status==='recebido')group.sort((a,b)=>Date.parse(a.created_at)-Date.parse(b.created_at)||a.id.localeCompare(b.id));return '<section class="board-column" data-status="'+status+'"><h3>'+title+' <span>'+group.length+'</span></h3>'+group.map(i=>boardItemCard(i)).join('')+(group.length?'':'<p class="muted">Nenhum pedido</p>')+'</section>';}).join('')+'</div><details class="cancelled-orders"><summary>Pedidos cancelados ('+items.filter(i=>i.status==='cancelado').length+')</summary>'+items.filter(i=>i.status==='cancelado').map(i=>boardItemCard(i)).join('')+'</details>';
  bindItems();
  updateOrderAges();
  if(focused)Array.from(screen.querySelectorAll('[data-item]')).find(b=>b.dataset.item===focused.id&&b.dataset.status===focused.status)?.focus({preventScroll:true});
}
const originalItemMarkup=itemMarkup;
itemMarkup=function(i,controls=false){
 let html=originalItemMarkup(i,controls);
 if(i.requires_preparation===false)html=html.replace(/<button[^>]*data-status="em preparo"[^>]*>Preparar<\/button>/g,'');
 if(i.status==='cancelado')html=html.replace(' · cancelado ·',' · Pedido cancelado ·');
 if(Number(i.paid_amount||0)>0||data.tickets.find(t=>t.id===i.ticket_id)?.closed)html=html.replace(/<button[^>]*data-status="cancelado"[^>]*>Cancelar<\/button>/g,'');
 return html;
};
let operationBusy=false,boardRefreshing=false;
const originalWork=work;
work=async function(fn){operationBusy=true;try{return await originalWork(fn);}finally{operationBusy=false;screen.querySelectorAll('[data-unavailable]').forEach(b=>b.disabled=true);}};
const originalBindItems=bindItems;
bindItems=function(){originalBindItems();for(const b of screen.querySelectorAll('[data-status="cancelado"]')){const handler=b.onclick;b.onclick=()=>{if(confirm('Cancelar este pedido? O registro continuará no histórico.'))handler();};}};
setInterval(async()=>{
 if(!document.hidden&&screen.dataset.view==='Pedidos')updateOrderAges();
 if(!token||!data||document.hidden||screen.dataset.view!=='Pedidos'||operationBusy||boardRefreshing)return;
 boardRefreshing=true;
 try{const [fresh,reception]=await Promise.all([rpc('service_list'),rpc('reception_list')]);if(screen.dataset.view==='Pedidos'&&!operationBusy&&data){const changed=JSON.stringify(data.items)!==JSON.stringify(fresh.items);const ticketChanged=JSON.stringify(data.tickets.map(t=>[t.id,t.participant_name]))!==JSON.stringify(reception.tickets.map(t=>[t.id,t.participant_name]));const phones=new Map(data.tickets.map(t=>[t.id,t.phone]));reception.tickets.forEach(t=>{t.phone=phones.get(t.id)||'';t.created_at=t.sold_at||t.created_at;});Object.assign(data,reception,fresh);if(changed||ticketChanged)renderBoard();const status=screen.querySelector('#board-sync');if(status)status.textContent='Atualizado às '+new Date().toLocaleTimeString('pt-BR')+' · a cada 5 segundos';}}
 catch{const status=screen.querySelector('#board-sync');if(status)status.textContent='Sem atualização. Tentando reconectar…';}
 finally{boardRefreshing=false;}
},5000);
function mountPreparation(){
 for(const row of screen.querySelectorAll('[data-product]')){
  const p=data.products.find(p=>p.id===row.dataset.product);
  const button=document.createElement('button');button.type='button';button.className='preparation-setting';
  button.textContent=p.requires_preparation===false?'Sem preparo · alterar':'Requer preparo · alterar';
  button.setAttribute('aria-label','Alterar preparo de '+p.name);
  button.onclick=()=>work(async()=>{await rpc('set_product_preparation',{p_product:p.id,p_required:p.requires_preparation===false});await load();show('Produtos');});
  row.after(button);
 }
}
const baseDetail=detail;
detail=function(id){baseDetail(id);const payment=screen.querySelector('#payment');if(payment)mountItemPayment(payment,id);};
const boardItemMarkup=itemMarkup;
itemMarkup=function(i,controls=false){
 const total=Math.round(Number(i.price)*i.quantity*100)/100,paid=Number(i.paid_amount||0);
 const label=i.status==='cancelado'?'Não cobrado':paid>=total?'Pago':'Pendente';
 return boardItemMarkup(i,controls).replace('</strong>','</strong> <span class="item-payment '+(label==='Pago'?'paid':'')+'">'+label+'</span>');
};
function mountItemPayment(payment,id){
 const items=data.items.filter(i=>i.ticket_id===id&&i.status!=='cancelado'&&Number(i.paid_amount||0)<Number(i.price)*i.quantity);
 const remaining=i=>Math.round((Number(i.price)*i.quantity-Number(i.paid_amount||0))*100)/100;
 const full=Math.round(items.reduce((sum,i)=>sum+remaining(i),0)*100)/100;
 const key='chatunai-recebimento-'+document.querySelector('#identity').textContent+'-'+id;
 let pending=JSON.parse(sessionStorage.getItem(key)||'null'),busy=false;
 payment.innerHTML='<fieldset><legend>Selecione os itens para receber</legend><button type="button" data-select-all>Selecionar tudo</button>'+items.map(i=>'<label class="payment-item"><input type="checkbox" name="item" value="'+escapeHtml(i.id)+'"><span>'+escapeHtml(i.quantity+' × '+i.name)+'</span><strong>'+money(remaining(i))+'</strong></label>').join('')+(items.length?'':'<p>Nenhum item pendente.</p>')+'</fieldset><p class="charge"><span>Selecionado</span><strong data-selected-total>'+money(0)+'</strong></p><label>Forma<select name="method"><option>Pix</option><option>Dinheiro</option><option>Cartão</option></select></label><div class="payment-actions"><button type="submit" data-receive>Receber itens selecionados</button><button type="button" data-close>Encerrar comanda · '+money(full)+'</button></div><p data-retry role="status" hidden>Recebimento sem confirmação. Confira o envio anterior antes de registrar outro.</p>';
 const selectedItems=()=>Array.from(payment.querySelectorAll('input:checked')).map(el=>el.value);
 const total=()=>Math.round(items.filter(i=>selectedItems().includes(i.id)).reduce((sum,i)=>sum+remaining(i),0)*100)/100;
 function render(){
  const all=payment.querySelector('[data-select-all]');
  all.textContent=items.length&&selectedItems().length===items.length?'Desmarcar tudo':'Selecionar tudo';
  all.disabled=busy||!!pending||!items.length;
  payment.querySelector('[data-selected-total]').textContent=money(total());
  payment.querySelector('[data-retry]').hidden=!pending;
  payment.querySelector('[data-receive]').textContent=pending?'Conferir recebimento anterior':'Receber itens selecionados';
  payment.querySelector('[data-receive]').disabled=busy||(!pending&&!selectedItems().length);
  payment.querySelector('[data-close]').disabled=busy||!!pending;
  payment.querySelectorAll('input,select').forEach(el=>el.disabled=busy||!!pending);
 }
 payment.querySelector('[data-select-all]').onclick=()=>{if(busy||pending||!items.length)return;const checked=selectedItems().length!==items.length;payment.querySelectorAll('input[name="item"]').forEach(el=>el.checked=checked);render();};
 payment.onchange=render;
 async function settle(close){
  if(busy)return;
  if(!pending){if(!close&&!selectedItems().length)return;const amount=close?full:total();const method=payment.elements.method.value;const question=close?'Confirmar o recebimento de '+money(amount)+' por '+method+' e encerrar esta comanda?':'Confirmar o recebimento de '+money(amount)+' por '+method+' pelos itens selecionados? A comanda continuará aberta.';if(!confirm(question))return;
   pending={p_request:crypto.randomUUID(),p_ticket:id,p_items:close?[]:selectedItems(),p_method:payment.elements.method.value,p_close:close,p_expected:close?full:total()};sessionStorage.setItem(key,JSON.stringify(pending));}
  busy=true;render();
  try{const response=await rpc('settle_items',pending);sessionStorage.removeItem(key);pending=null;await load();if(selected===id){detail(id);focusPurchases();}message(response.message);}
  catch(e){if(e.definitive){pending=null;sessionStorage.removeItem(key);}message(e.message);}
  finally{busy=false;if(payment.isConnected)render();}
 }
 payment.onsubmit=e=>{e.preventDefault();settle(false);};
 payment.querySelector('[data-close]').onclick=()=>settle(true);
 render();
}

function boardItemCard(item){
 const active=['recebido','em preparo','pronto'].includes(item.status);
 const ticket=data.tickets.find(t=>t.id===item.ticket_id);
 const actions=[
  ['em preparo','Preparar',item.status==='recebido'&&item.requires_preparation!==false],
  ['pronto','Pronto',['recebido','em preparo'].includes(item.status)],
  ['entregue','Entregue',active],
  ['cancelado','Cancelar',['recebido','em preparo'].includes(item.status)&&!ticket?.closed&&!Number(item.paid_amount||0)]
 ];
 const buttons='<div class="order-actions">'+actions.map(([status,label,enabled])=>'<button type="button" '+(enabled?'data-item="'+escapeHtml(item.id)+'" data-status="'+status+'"':'disabled data-unavailable')+' aria-label="'+label+' — '+escapeHtml(item.name)+'">'+label+'</button>').join('')+'</div>';
 return itemMarkup(item,false).replace('<div class="row">','<div class="row" data-board-item="'+escapeHtml(item.id)+'">').replace(/<\/div>$/,(active?'<span class="order-warning" role="img" aria-label="Atenção: pedido aguardando há pelo menos 10 minutos" hidden>⚠️</span><p class="order-wait" hidden></p>':'')+buttons+'</div>');
}

function orderAge(item,now=Date.now()){
 if(!['recebido','em preparo','pronto'].includes(item.status))return null;
 const elapsed=Math.max(0,now-Date.parse(item.created_at));
 if(!Number.isFinite(elapsed)||elapsed<5*60000)return null;
 return {level:elapsed>=10*60000?'late':'waiting',minutes:Math.floor(elapsed/60000)};
}
function updateOrderAges(){
 if(!data)return;
 const now=Date.now();
 for(const card of screen.querySelectorAll('[data-board-item]')){
  const item=data.items.find(i=>i.id===card.dataset.boardItem);
  const age=item?orderAge(item,now):null;
  card.classList.toggle('order-waiting',age?.level==='waiting');
  card.classList.toggle('order-late',age?.level==='late');
  const warning=card.querySelector('.order-warning');
  if(warning)warning.hidden=age?.level!=='late';
  const label=card.querySelector('.order-wait');
  if(label){label.hidden=!age;label.textContent=age?'Aguardando entrega há '+age.minutes+' min':'';}
 }
}
