'use strict';
const navPaths = {
  'Buscar convite':'M21 21l-5-5 M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
  'Vender convites':'M3 5h18v5a2 2 0 0 0 0 4v5H3v-5a2 2 0 0 0 0-4z M15 8v2m0 4v2',
  'Resumo':'M3 3v18h18 M7 16v-4m5 4V6m5 10V9',
  'Pedidos':'M5 4h14v17l-3-2-4 2-4-2-3 2z M8 8h8m-8 4h6',
  'Caixa':'M3 7h18v12H3z M3 11h18m-6 4h3',
  'Produtos':'M3 7l9-5 9 5v10l-9 5-9-5z M3 7l9 5 9-5m-9 5v10'
};
function decorateNav(button, hint) {
  const label = button.dataset.page;
  button.insertAdjacentHTML('afterbegin', `<svg aria-hidden="true" focusable="false" viewBox="0 0 24 24"><path d="${navPaths[label]}"/></svg>`);
  button.setAttribute('aria-label',label+' — '+hint);
}
function groupTicketSections(container) {
  let section;
  for (const child of Array.from(container.children)) {
    if (child.matches('h2')) {
      section = document.createElement('section');
      section.className = 'ticket-section';
      container.insertBefore(section,child);
    }
    if (section) section.append(child);
  }
}
function mountDesk() {
  const desk = document.querySelector('#desk');
  const side = document.querySelector('#lookup');
  desk.classList.add('open');
  side.innerHTML = `<section class="lookup-card"><h2>Localizar convite</h2>
    <label>Código, nome ou telefone<input id="search" type="search" autocomplete="off" placeholder="Digite o código, nome ou telefone"></label></section>
    <section class="lookup-card"><div class="list-heading"><h3>Comandas recentes</h3><button type="button" id="all-tickets">Ver todas</button></div>
    <div id="matches"></div><button type="button" id="refresh-desk">Atualizar lista</button></section>`;
  screen.innerHTML = '<section class="desk-empty"><h2>Comanda do participante</h2><p>Busque pelo nome, telefone ou número e abra o convite para iniciar o atendimento.</p></section>';
  const search = side.querySelector('#search');
  let all = false;
  function render() {
    const term = search.value.trim().toLocaleLowerCase('pt-BR');
    const tickets = data.tickets.filter(t => term
      ? [t.id,t.code,t.legacy_code,t.participant_name,t.phone].some(v=>String(v||'').toLocaleLowerCase('pt-BR').includes(term)) || (/\d/.test(term) && String(t.phone||'').replace(/\D/g,'').includes(term.replace(/\D/g,'')))
      : all || (!t.closed&&!t.available)).sort((a,b)=>all ? a.code.localeCompare(b.code) : String(b.created_at).localeCompare(String(a.created_at)));
    side.querySelector('h3').textContent = term ? 'Resultados' : all ? 'Todos os convites' : 'Comandas recentes';
    side.querySelector('#matches').innerHTML = (all || term ? tickets : tickets.slice(0,5)).map(t=>
      `<button class="ticket-pick" data-ticket="${escapeHtml(t.id)}" aria-label="Abrir convite ${escapeHtml(t.code)}">
      <strong>${escapeHtml(t.code)}</strong><b>${money(tabTotal(t.id)-tabPaid(t.id))}</b>
      <span>${escapeHtml(t.participant_name||'Sem nome')}${t.phone?" · "+escapeHtml(t.phone):""}</span><small>${t.available?'Disponível':t.closed?'Encerrada':'Aberta'}</small></button>`
    ).join('') || '<p class="muted">Nenhum convite encontrado.</p>';
  }
  side.onoperacao=render;
  search.oninput=render;
  side.querySelector('#matches').onclick=e=>{const button=e.target.closest('[data-ticket]');if(button)detail(button.dataset.ticket);};
  side.querySelector('#all-tickets').onclick=e=>{all=!all;search.value='';e.currentTarget.textContent=all?'Ver recentes':'Ver todas';render();};
  side.querySelector('#refresh-desk').onclick=()=>work(async()=>{await load();render();if(selected)detail(selected);});
  render();
  mountScanner();
}
function separateManagement(nav) {
  const group=document.createElement('details');
  group.className='management';
  group.innerHTML='<summary>Gestão do evento</summary><div></div>';
  document.querySelector('.management')?.remove();
  nav.after(group);
  for(const label of ['Resumo','Produtos']){
    const button=nav.querySelector('[data-page="'+label+'"]');
    if(button)group.lastElementChild.append(button);
  }
  group.onclick=e=>{const b=e.target.closest('[data-page]');if(b)show(b.dataset.page);};
}

function styleQueue(page) {
  const grid=document.createElement('div');
  grid.className='queue-grid';
  grid.append(...screen.querySelectorAll(':scope > .row'));
  screen.append(grid);
  if(page==='Pedidos'){
    if(!grid.children.length)grid.textContent='Nenhum pedido em andamento.';
    return;
  }
  const search=screen.querySelector('#cash-search');
  const normalize=v=>v.toLocaleLowerCase('pt-BR').normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  search.oninput=()=>{
    const query=normalize(search.value.trim());
    let count=0;
    for(const row of grid.children){
      const t=data.tickets.find(t=>t.id===row.querySelector('[data-ticket]').dataset.ticket);
      row.hidden=!normalize(t.code+' '+(t.participant_name||'')).includes(query);
      if(!row.hidden)count++;
    }
    screen.querySelector('#cash-count').textContent=count ? count+' comanda(s) aberta(s)' : 'Nenhuma comanda encontrada.';
  };
  search.oninput();
}
function availableTicket(t){
  selected=t.id;
  screen.innerHTML=`<h2>Convite <span class="code">${escapeHtml(t.code)}</span></h2><p>Disponível para venda</p><button id="sell-this">Registrar venda deste convite</button><button id="back">Voltar</button>`;
  ticketQR(t);
  screen.querySelector('#sell-this').hidden=!['admin','entrada'].includes(role);
  screen.querySelector('#sell-this').onclick=()=>{show('Vender convites');document.querySelector('#sale').elements.ticket.value=t.id;};
  screen.querySelector('#back').onclick=()=>show('Buscar convite');
  document.querySelector('#desk').classList.add('view-ticket');
}
async function mountPhone(id){
  if(!['admin','entrada'].includes(role))return;
  const section=document.createElement('form');
  section.className='phone-editor';
  section.innerHTML='<label>Telefone<input type="tel" name="phone" maxlength="30" autocomplete="tel"></label><button>Salvar telefone</button>';
  screen.querySelector('[data-action="name"]').after(section);
  section.querySelector('button').disabled=true;
  try{
    section.elements.phone.value=data.tickets.find(t=>t.id===id)?.phone||'';
    section.querySelector('button').disabled=false;
  }catch(e){message(e.message);return;}
  section.onsubmit=e=>{e.preventDefault();work(async()=>{await rpc('ticket_phone',{p_ticket:id,p_phone:section.elements.phone.value.trim()});await load();detail(id);message('Telefone atualizado.');});};
}
function focusPurchases(){const target=screen.querySelector('#purchased-items');if(target){target.focus({preventScroll:true});target.scrollIntoView({block:'start'});}}
function organizeGuest(){
  const name=screen.querySelector('#name');
  if(name){
    const details=document.createElement('details');details.className='guest-details';
    details.innerHTML='<summary>Dados convidado</summary>';
    const label=name.closest('label');label.before(details);
    details.append(label,screen.querySelector('[data-action="name"]'),screen.querySelector('.phone-editor'));
  }
  const title=Array.from(screen.querySelectorAll('h2')).find(h=>h.textContent==='Benefícios');
  if(title){const grid=document.createElement('div');grid.className='benefits-grid';title.after(grid);while(grid.nextElementSibling?.classList.contains('row'))grid.append(grid.nextElementSibling);
    const id=selected,legacy=data.benefits.filter(b=>b.ticket_id===id&&['initial_card','final_card'].includes(b.benefit));
    if(legacy.length&&!data.benefits.some(b=>b.ticket_id===id&&b.benefit==='welcome_kit')){
      const note=document.createElement('p');note.textContent='Histórico: '+legacy.map(b=>b.benefit==='initial_card'?'cartela inicial entregue':'cartela final entregue').join(', ')+'. Confirme apenas os itens restantes do kit.';grid.firstElementChild.append(note);
    }
  }
}
