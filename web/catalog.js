function mountCatalog(form, ticketId, products) {
  const quantities = new Map();
  const ticket = data.tickets.find(item => item.id === ticketId);
  const storageKey = 'chatunai-pedido-' + ticketId;
  let submitted = JSON.parse(sessionStorage.getItem(storageKey) || 'null');
  let busy = false;
  const catalog = new Map(products.map(product => [product.id, product]));
  const categories = [
    ['cozinha', 'Alimentos e bebidas'],
    ['cartelas', 'Cartelas']
  ];
  form.innerHTML = '<h2>Novo pedido</h2>' + categories.map(([sector, title]) => {
    const group = products.filter(product => product.sector === sector);
    if (!group.length) return '';
    return '<h3>' + title + '</h3><div class="catalog-grid">' + group.map(product =>
      `<article class="product-card" data-card="${product.id}">
        <strong>${escapeHtml(product.name)}</strong>
        ${product.round ? '<small>Rodada ' + escapeHtml(product.round) + '</small>' : ''}
        <span class="product-price">${money(product.price)}</span>
        <div class="stepper"><button type="button" data-change="-1" aria-label="Retirar uma unidade de ${escapeHtml(product.name)}">−</button>
        <output aria-label="Quantidade">0</output><button type="button" data-change="1" aria-label="Adicionar uma unidade de ${escapeHtml(product.name)}">+</button></div>
      </article>`
    ).join('') + '</div>';
  }).join('') + `<div class="basket"><strong>Pedido · ${escapeHtml(ticket.code)}</strong>
    <div class="basket-lines"></div><p class="basket-total" aria-live="polite"></p>
    <button class="send-cart" type="submit">Lançar na comanda</button></div>`;

  const currentLines = () => submitted?.lines || Array.from(quantities, ([product_id, quantity]) => ({
    product_id, quantity, price: Number(catalog.get(product_id).price)
  }));
  function render() {
    const lines = currentLines();
    for (const card of form.querySelectorAll('[data-card]')) {
      const count = lines.find(line => line.product_id === card.dataset.card)?.quantity || 0;
      card.classList.toggle('chosen', count > 0);
      card.querySelector('output').textContent = count;
      for (const button of card.querySelectorAll('[data-change]')) {
        button.disabled = busy || !!submitted || (button.dataset.change === '-1' ? count === 0 : count === 100);
      }
    }
    form.querySelector('.basket-lines').innerHTML = lines.map(line =>
      `<div>${line.quantity} × ${escapeHtml(catalog.get(line.product_id)?.name || 'Produto')} <span>${money(line.price * line.quantity)}</span></div>`
    ).join('');
    form.querySelector('.basket-total').textContent = lines.length ? 'Total do pedido: ' + money(lines.reduce((sum,line) => sum + Math.round(line.price * 100) * line.quantity, 0) / 100) : 'Nenhum item selecionado.';
    const send = form.querySelector('.send-cart');
    send.disabled = busy || !lines.length;
    send.textContent = busy ? 'Registrando…' : submitted ? 'Conferir envio anterior' : 'Lançar na comanda';
  }
  form.onclick = event => {
    const button = event.target.closest('[data-change]');
    if (!button || submitted || busy) return;
    const id = button.closest('[data-card]').dataset.card;
    const next = Math.max(0, Math.min(100, (quantities.get(id) || 0) + Number(button.dataset.change)));
    if (next) quantities.set(id,next); else quantities.delete(id);
    render();
  };
  form.onsubmit = async event => {
    event.preventDefault();
    if (busy || !currentLines().length) return;
    submitted ??= {id:crypto.randomUUID(), lines:currentLines()};
    sessionStorage.setItem(storageKey,JSON.stringify(submitted));
    busy = true;
    render();
    try {
      const receipt = await rpc('submit_cart',{p_request:submitted.id,p_ticket:ticketId,p_lines:submitted.lines});
      sessionStorage.removeItem(storageKey);
      submitted = null;
      quantities.clear();
      message('Pedido lançado na comanda ' + ticket.code + ': ' + money(receipt.total));
      await load();
      if (selected === ticketId && form.isConnected) detail(ticketId);
    } catch (error) {
      if (error.definitive && submitted) {
        for (const line of submitted.lines) if (catalog.has(line.product_id)) quantities.set(line.product_id,line.quantity);
        submitted = null;
        sessionStorage.removeItem(storageKey);
      }
      message(submitted ? 'Envio sem confirmação. Use “Conferir envio anterior” antes de repetir.' : error.message);
    } finally {
      busy = false;
      if (form.isConnected) render();
    }
  };
  render();
}

function ticketQR(ticket) {
  const qr = qrcode(0,'M');
  qr.addData(ticket.id);
  qr.make();
  const area = document.createElement('details');
  area.className = 'qr-ticket';
  area.innerHTML = '<summary>Mostrar QR Code do convite</summary><div class="print-ticket"><strong>Bingo Chatunai</strong>' +
    qr.createSvgTag({cellSize:5,margin:20,scalable:true}) + '<b>' + escapeHtml(ticket.code) + '</b></div><button type="button">Imprimir convite</button>';
  const image = area.querySelector('svg');
  image.setAttribute('role','img');
  image.setAttribute('aria-label','QR Code do convite '+ticket.code);
  area.querySelector('button').onclick = () => window.print();
  screen.querySelector('h2').after(area);
}

function mountScanner() {
  const search = document.querySelector('#search');
  if (!search) return;
  const open = document.createElement('button');
  open.textContent = 'Ler QR Code';
  search.closest('label').before(open);
  open.onclick = async () => {
    const dialog = document.createElement('dialog');
    dialog.setAttribute('aria-labelledby','scanner-title');
    dialog.innerHTML = '<h2 id="scanner-title">Ler convite</h2><video playsinline muted></video><p role="status">Abrindo câmera…</p><button type="button">Fechar</button>';
    document.body.append(dialog);
    dialog.showModal();
    let stream, frame;
    const close = () => dialog.close();
    dialog.querySelector('button').onclick = close;
    dialog.onclose = () => {
      cancelAnimationFrame(frame);
      stream?.getTracks().forEach(track => track.stop());
      dialog.remove();
    };
    const status = dialog.querySelector('p');
    try {
      stream = await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});
      if (!dialog.open) { stream.getTracks().forEach(track => track.stop()); return; }
      const video = dialog.querySelector('video');
      video.srcObject = stream;
      await video.play();
      status.textContent = 'Aponte a câmera para o QR do convite.';
      const canvas = document.createElement('canvas');
      const context = canvas.getContext('2d',{willReadFrequently:true});
      let last = 0;
      const scan = async now => {
        if (!dialog.open) return;
        if (now - last > 180 && video.videoWidth) {
          last = now;
          canvas.width = Math.min(video.videoWidth,640);
          canvas.height = Math.round(video.videoHeight * canvas.width / video.videoWidth);
          context.drawImage(video,0,0,canvas.width,canvas.height);
          const pixels = context.getImageData(0,0,canvas.width,canvas.height);
          const code = jsQR(pixels.data,pixels.width,pixels.height);
          if (code) {
            let ticket = data.tickets.find(t => t.id === code.data);
            if (!ticket && /^[a-f0-9-]{36}$/i.test(code.data)) {
              try { await load(); ticket = data.tickets.find(t => t.id === code.data); }
              catch { status.textContent = 'Sem conexão. Feche e tente a busca por código.'; return; }
            }
            if (!dialog.open) return;
            if (ticket) { close(); detail(ticket.id); message('Convite localizado.'); return; }
            status.textContent = 'QR não corresponde a um convite desta lista.';
          }
        }
        frame = requestAnimationFrame(scan);
      };
      frame = requestAnimationFrame(scan);
    } catch {
      stream?.getTracks().forEach(track => track.stop());
      status.textContent = 'Câmera indisponível. Permita o acesso ou feche e busque pelo código.';
    }
  };
}
