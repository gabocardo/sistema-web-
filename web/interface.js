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
