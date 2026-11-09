'use strict';
const baseShow=show;
show=function(page){baseShow(page);if(page==='Pedidos')renderBoard();if(page==='Produtos')mountPreparation();};
function renderBoard(){
  const focus=document.activeElement?.closest('[data-item]');
  const focused=focus?{id:focus.dataset.item,status:focus.dataset.status}:null;
  const items=data.items.filter(i=>role==='admin'||i.sector===role).sort((a,b)=>String(b.status_changed_at||b.created_at).localeCompare(String(a.status_changed_at||a.created_at))||b.id.localeCompare(a.id));
  screen.innerHTML='<h2>Pedidos</h2><p id="board-sync" role="status">Atualização automática a cada 5 segundos</p><div class="order-board">'+[
    ['recebido','Lista de pedidos'],['em preparo','Em preparo'],['pronto','Prontos'],['entregue','Entregues']
  ].map(([status,title])=>{const group=items.filter(i=>i.status===status);return '<section class="board-column"><h3>'+title+' <span>'+group.length+'</span></h3>'+group.map(i=>itemMarkup(i,true)).join('')+(group.length?'':'<p class="muted">Nenhum pedido</p>')+'</section>';}).join('')+'</div><details class="cancelled-orders"><summary>Pedidos cancelados ('+items.filter(i=>i.status==='cancelado').length+')</summary>'+items.filter(i=>i.status==='cancelado').map(i=>itemMarkup(i)).join('')+'</details>';
  bindItems();
  if(focused)Array.from(screen.querySelectorAll('[data-item]')).find(b=>b.dataset.item===focused.id&&b.dataset.status===focused.status)?.focus({preventScroll:true});
}
const originalItemMarkup=itemMarkup;
itemMarkup=function(i,controls=false){
 let html=originalItemMarkup(i,controls);
 if(i.requires_preparation===false)html=html.replace(/<button[^>]*data-status="em preparo"[^>]*>Preparar<\/button>/g,'');
 if(i.status==='cancelado')html=html.replace(' · cancelado ·',' · Pedido cancelado ·');
 return html;
};
let operationBusy=false,boardRefreshing=false;
const originalWork=work;
work=async function(fn){operationBusy=true;try{return await originalWork(fn);}finally{operationBusy=false;}};
const originalBindItems=bindItems;
bindItems=function(){originalBindItems();for(const b of screen.querySelectorAll('[data-status="cancelado"]')){const handler=b.onclick;b.onclick=()=>{if(confirm('Cancelar este pedido? O registro continuará no histórico.'))handler();};}};
setInterval(async()=>{
 if(!token||!data||document.hidden||screen.dataset.view!=='Pedidos'||operationBusy||boardRefreshing)return;
 boardRefreshing=true;
 try{const fresh=await rpc('service_list');if(screen.dataset.view==='Pedidos'&&!operationBusy&&data){const changed=JSON.stringify(data.items)!==JSON.stringify(fresh.items);Object.assign(data,fresh);if(changed)renderBoard();const status=screen.querySelector('#board-sync');if(status)status.textContent='Atualizado às '+new Date().toLocaleTimeString('pt-BR')+' · a cada 5 segundos';}}
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
