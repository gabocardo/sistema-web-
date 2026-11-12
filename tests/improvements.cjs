const {chromium}=require('playwright');const fs=require('fs'),path=require('path'),assert=require('assert/strict');
(async()=>{const browser=await chromium.launch({channel:'msedge',headless:true});try{
 const page=await browser.newPage({viewport:{width:1440,height:1000}});await page.clock.install();let errors=[];page.on('pageerror',e=>errors.push(e.message));
 const ticket={id:'t1',code:'0001',participant_name:'Teste',paid:true,price:30,payment_method:'Pix',created_at:'2026-11-09T10:00:00Z',closed:false};
 const products=[{id:'p1',name:'Pizza',sector:'cozinha',price:12,active:true},{id:'p2',name:'Água',sector:'cozinha',price:4,active:true,requires_preparation:false}];
 const items=[{id:'i1',name:'Pizza',sector:'cozinha',ticket_id:'t1',price:12,quantity:1,status:'recebido',paid_amount:0,created_at:ticket.created_at},{id:'i2',name:'Água',sector:'cozinha',ticket_id:'t1',price:4,quantity:2,status:'pronto',paid_amount:0,requires_preparation:false,created_at:ticket.created_at}];const payments=[];let receipts=[],refreshes=0;
 await page.route('https://chatunai.test/**',r=>r.fulfill({path:path.join(__dirname,'../web',new URL(r.request().url()).pathname.slice(1)||'index.html')}));
 await page.route('https://*.supabase.co/**',r=>{const url=r.request().url();let body;
 if(url.includes('/auth/'))body={access_token:'test',refresh_token:'test',expires_in:3600,user:{id:'a',email:'test@example.org'}};
 else if(url.includes('team_members'))body=[{role:'admin'}];
 else if(url.endsWith('reception_list'))body={events:[{id:'event',name:'Bingo Chatunai',ticket_price:30,door_price:35}],tickets:[ticket,{id:'t2',code:'0002',available:true,price:0}],benefits:[],entries:[]};
 else if(url.endsWith('service_list')){refreshes++;body={products,items,payments};}
 else if(url.endsWith('ticket_phones'))body={t1:'11999990000'};
 else if(url.endsWith('settle_items')){let input=r.request().postDataJSON();receipts.push(input);let selected=items.filter(i=>input.p_close||input.p_items.includes(i.id));selected.forEach(i=>i.paid_amount=i.price*i.quantity);payments.push({ticket_id:'t1',amount:input.p_expected});ticket.closed=input.p_close;body={message:input.p_close?'Comanda encerrada':'Itens pagos. Comanda continua aberta.'};}
 else throw Error('Rota inesperada '+url);
 return r.fulfill({json:body});});
 await page.goto('https://chatunai.test/');await page.getByLabel('E-mail').fill('test@example.org');await page.getByLabel('Senha').fill('teste');await page.getByRole('button',{name:'Entrar',exact:true}).click();await page.locator('#search').waitFor();
 assert.equal(await page.getByRole('button',{name:'Ler QR Code'}).count(),0);
 await page.getByRole('button',{name:/Vender convites —/}).click();await page.getByLabel('Tipo de convite').selectOption('porta');assert.deepEqual(await page.locator('#sale [name=method] option').allTextContents(),['Pix','Dinheiro','Cartão']);
 await page.getByRole('button',{name:/Caixa —/}).click();await page.locator('#cash-search').fill('(11) 99999-0000');assert.equal(await page.getByRole('button',{name:'Abrir comanda',exact:true}).count(),1);await page.getByRole('button',{name:'Abrir comanda',exact:true}).click();assert.equal(await page.getByRole('heading',{name:'Receber pagamento',exact:true}).count(),1);
 assert.equal(await page.evaluate(()=>document.activeElement.id),'purchased-items');assert.equal(await page.locator('.qr-ticket').count(),0);
 assert.equal(await page.locator('.guest-details').getAttribute('open'),null);await page.getByText('Dados convidado',{exact:true}).click();assert(await page.getByLabel('Editar nome').isVisible());assert(await page.getByLabel('Telefone',{exact:true}).isVisible());
 assert.equal(await page.locator('.benefits-grid .row').count(),2);assert.deepEqual(await page.locator('.product-card > strong').allTextContents(),['Água','Pizza']);
 await page.locator('#payment input[value=i1]').check();page.once('dialog',d=>{assert.match(d.message(),/12,00.*Pix/);return d.dismiss();});await page.getByRole('button',{name:'Receber itens selecionados',exact:true}).click();assert.equal(receipts.length,0);page.once('dialog',d=>d.accept());await page.getByRole('button',{name:'Receber itens selecionados',exact:true}).click();await page.getByRole('status').filter({hasText:'Itens pagos.'}).waitFor();assert.equal(receipts[0].p_expected,12);assert.equal(receipts[0].p_close,false);assert.equal(ticket.closed,false);assert.equal(await page.locator('#payment input').count(),1);assert(await page.locator('.item-payment.paid').count());
 page.on('dialog',d=>d.accept());await page.getByRole('button',{name:/Encerrar comanda ·/}).click();await page.getByRole('status').filter({hasText:'Comanda encerrada'}).waitFor();assert.equal(receipts[1].p_expected,8);assert.equal(ticket.closed,true);
 await page.getByRole('button',{name:/Pedidos —/}).click();assert.equal(await page.locator('.board-column').count(),4);assert.equal(await page.locator('.board-column .order-actions').first().locator('button').count(),4);assert(await page.locator('.board-column .order-actions').last().getByRole('button',{name:/Preparar/}).isDisabled());items.push({id:'card',name:'Cartela extra',sector:'cartelas',ticket_id:'t1',status:'recebido',price:10,quantity:1,created_at:ticket.created_at});let before=refreshes;items[0].status='em preparo';await page.locator('.board-column').filter({hasText:'Em preparo'}).getByText('Pizza × 1',{exact:true}).waitFor({timeout:12000});assert(refreshes>before);assert.equal(await page.locator(".order-board").getByText("Cartela extra",{exact:false}).count(),0);
 
 const now=Date.now();const fixture=(id,name,status,minutes,changed=minutes)=>({id,name,status,sector:'cozinha',ticket_id:'t1',price:4,quantity:1,created_at:new Date(now-minutes*60000).toISOString(),status_changed_at:new Date(now-changed*60000).toISOString()});
 items.splice(0,items.length,fixture('new','Novo','recebido',1),fixture('old','Antigo','recebido',11),fixture('mid','Intermediário','recebido',6),fixture('del-old','Entrega antiga','entregue',20,5),fixture('del-new','Entrega recente','entregue',30,1));
 await page.locator('[data-board-item="old"]').waitFor({timeout:12000});
 assert.deepEqual(await page.locator('.board-column[data-status="recebido"] [data-board-item]').evaluateAll(els=>els.map(e=>e.dataset.boardItem)),['old','mid','new']);
 assert.deepEqual(await page.locator('.board-column[data-status="entregue"] [data-board-item]').evaluateAll(els=>els.map(e=>e.dataset.boardItem)),['del-new','del-old']);
 assert(await page.locator('[data-board-item="old"]').evaluate(el=>el.classList.contains('order-late')));
 assert(await page.locator('[data-board-item="mid"]').evaluate(el=>el.classList.contains('order-waiting')));
 assert.equal(await page.locator('.board-column[data-status="entregue"] .order-late').count(),0);
 // Age changes without a new server-side order or status update.
 await page.clock.setSystemTime(new Date(now));await page.clock.fastForward(5*60000);
 assert(await page.locator('[data-board-item="mid"]').evaluate(el=>el.classList.contains('order-late')));
 assert(await page.locator('[data-board-item="new"]').evaluate(el=>el.classList.contains('order-waiting')));
 await page.screenshot({path:'qa-board-desktop.png',fullPage:true});await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await page.screenshot({path:'qa-board-mobile.png',fullPage:true});assert.deepEqual(errors,[]);console.log('APROVADO: vendas, QR oculto, benefícios, dados recolhidos, ordem alfabética, foco, pagamento por itens, fechamento, quadro, atualização e celular.');
 }finally{await browser.close();}})().catch(e=>{console.error(e);process.exitCode=1;});

