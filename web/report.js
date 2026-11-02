'use strict';

function mountReport(host, data) {
  const panel = document.createElement('section');
  panel.className = 'report';
  panel.innerHTML = `<h2>Relatório financeiro</h2>
    <div class="report-filters">
      <label>Consultar<select name="view"><option value="tickets">Vendas de convites</option><option value="payments">Recebimentos de comandas</option><option value="items">Consumo por setor</option></select></label>
      <label>De<input type="date" name="start"></label><label>Até<input type="date" name="end"></label>
      <label>Pagamento<select name="method"><option value="">Todos</option><option>Pix</option><option>Dinheiro</option><option>Cartão</option><option>Pendente</option></select></label>
      <label>Setor<select name="sector"><option value="">Todos</option><option value="cozinha">Cozinha</option><option value="cartelas">Cartelas</option></select></label>
    </div><p class="muted" data-note></p><p data-total aria-live="polite"></p>
    <button type="button">Exportar CSV</button><div class="scroll" data-preview></div>`;
  host.append(panel);
  const field = name => panel.querySelector('[name="' + name + '"]');
  const tickets = new Map(data.tickets.map(t => [t.id, t]));
  const day = new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo',year:'numeric',month:'2-digit',day:'2-digit'});
  const number = new Intl.NumberFormat('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2,useGrouping:false});
  let rows, headers;
  function render() {
    const view = field('view').value;
    const items = view === 'items';
    field('sector').parentElement.hidden = !items;
    field('method').parentElement.hidden = items;
    field('method').querySelector('option:last-child').hidden = view === 'payments';
    if (view === 'payments' && field('method').value === 'Pendente') field('method').value = '';
    const notes = {tickets:'Período pela data da venda. O pagamento mostra a situação atual do convite.',payments:'Período pela data do recebimento no caixa. Inclui pagamentos parciais.',items:'Período pelo lançamento do pedido. O valor representa consumo e exclui itens cancelados.'};
    panel.querySelector('[data-note]').textContent = notes[view];
    headers = ['Data','Convite',...(items ? ['Setor','Produto','Quantidade'] : ['Pagamento']),'Valor (R$)'];
    rows = [];
    let cents = 0;
    for (const record of data[view]) {
      const when = new Date(record.created_at);
      const key = day.format(when);
      if ((field('start').value && key < field('start').value) || (field('end').value && key > field('end').value)) continue;
      const ticket = view === 'tickets' ? record : tickets.get(record.ticket_id);
      const method = view === 'tickets' ? (record.paid ? record.payment_method || 'Não informado' : 'Pendente') : record.method;
      if (items && (record.status === 'cancelado' || (field('sector').value && field('sector').value !== record.sector))) continue;
      if (!items && field('method').value && method !== field('method').value) continue;
      const amount = view === 'payments' ? record.amount : record.price * (items ? record.quantity : 1);
      cents += Math.round(amount * 100);
      rows.push([key,ticket?.code || '',...(items ? [record.sector,record.name,record.quantity] : [method]),number.format(amount)]);
    }
    rows.sort((a,b)=>b[0].localeCompare(a[0]));
    panel.querySelector('[data-total]').textContent = rows.length + ' registro(s) · Total ' + money(cents / 100);
    panel.querySelector('button').disabled = !rows.length;
    panel.querySelector('[data-preview]').innerHTML = rows.length ? '<table><thead><tr>' + headers.map(h=>'<th>'+escapeHtml(h)+'</th>').join('') + '</tr></thead><tbody>' + rows.slice(0,50).map(r=>'<tr>'+r.map(c=>'<td>'+escapeHtml(c)+'</td>').join('')+'</tr>').join('') + '</tbody></table>' + (rows.length>50?'<p>Mostrando 50 registros. O CSV inclui todos os resultados.</p>':'') : '<p>Nenhum registro para os filtros selecionados.</p>';
  }
  panel.onchange = render;
  panel.querySelector('button').onclick = () => {
    const cell = value => {
      const s = String(value);
      return '"' + (/^[\s]*[=+@-]/.test(s) ? "'" : '') + s.replaceAll('"','""') + '"';
    };
    const csv = [headers,...rows].map(row=>row.map(cell).join(';')).join('\r\n');
    const url = URL.createObjectURL(new Blob(['\uFEFF',csv],{type:'text/csv;charset=utf-8'}));
    const a = document.createElement('a');
    a.href = url;
    a.download = 'bingo-chatunai-'+field('view').value+'.csv';
    a.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);
  };
  render();
}
