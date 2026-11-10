// Local simulation: ten isolated browser sessions share a mock API. No production load.
const {chromium}=require('playwright');const fs=require('fs'),path=require('path'),assert=require('assert/strict'),vm=require('vm');
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
 const items=[];let calls=0;const errors=[];
 const ticket={id:'t',code:'0001',participant_name:'Teste',paid:true,price:30,created_at:'2026-11-09T12:00:00Z'};
 const product={id:'p',name:'Pizza',price:12,sector:'cozinha',active:true};
 async function api(route){calls++;const url=route.request().url();let body;
 if(url.includes('/auth/'))body={access_token:'test',refresh_token:'r',expires_in:3600,user:{id:'u',email:'test@example.org'}};
 else if(url.includes('team_members'))body=[{role:'admin'}];
 else if(url.endsWith('reception_list'))body={events:[],tickets:[ticket],entries:[],benefits:[]};
 else if(url.endsWith('ticket_phones'))body={t:'11999990000'};
 else if(url.endsWith('service_list'))body={products:[product],items,payments:[]};
 else if(url.endsWith('submit_cart')){const p=route.request().postDataJSON();items.push({id:p.p_request,ticket_id:'t',name:'Pizza',sector:'cozinha',quantity:1,price:12,status:'recebido',created_at:new Date().toISOString()});body={total:12};}
 else throw Error('Unexpected '+url);await route.fulfill({json:body});}
 const pages=await Promise.all(Array.from({length:10},async()=>{const context=await browser.newContext({viewport:{width:390,height:844}});await context.route('https://chatunai.test/**',r=>r.fulfill({path:path.join(__dirname,'../web',new URL(r.request().url()).pathname.slice(1)||'index.html')}));await context.route('https://*.supabase.co/**',api);const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));await page.goto('https://chatunai.test/');await page.getByLabel('E-mail').fill('test@example.org');await page.getByLabel('Senha').fill('test');await page.getByRole('button',{name:'Entrar',exact:true}).click();await page.locator('#search').waitFor();return page;}));
 await Promise.all(pages.slice(1).map(p=>p.getByRole('button',{name:/Pedidos —/}).click()));
 await pages[0].getByRole('button',{name:'Abrir convite 0001'}).click();await pages[0].getByRole('button',{name:'Adicionar uma unidade de Pizza'}).click();await pages[0].getByRole('button',{name:'Lançar na comanda'}).click();
 await Promise.all(pages.slice(1).map(p=>p.locator('.order-board').getByText('Pizza × 1',{exact:true}).waitFor({timeout:15000})));
 assert.equal(items.length,1);assert.deepEqual(errors,[]);
 console.log('PASS: pedido de uma sessão apareceu em outras nove sem recarregar; '+calls+' chamadas na API simulada.');
 }finally{await browser.close();}
 // Advance a virtual clock beyond three hours, with short-lived access tokens.
 let now=0,refreshes=0;const sandbox={token:null,config:{url:'https://example.test',publishableKey:'test'},Date:{now:()=>now},AbortSignal,document:{addEventListener(){},visibilityState:'visible'},navigator:{onLine:true},setInterval(){},fetch:async()=>{refreshes++;return {ok:true,json:async()=>({access_token:'new',refresh_token:'r'+refreshes,expires_in:3600})};}};
 vm.createContext(sandbox);vm.runInContext(fs.readFileSync(path.join(__dirname,'../web/session.js'),'utf8'),sandbox);vm.runInContext("acceptSession({access_token:'start',refresh_token:'r',expires_in:3600})",sandbox);
 for(let minute=1;minute<=190;minute++){now=minute*60000;await vm.runInContext('ensureSession()',sandbox);}
 assert(refreshes>=3);assert.equal(sandbox.token,'new');console.log('PASS: renovação automática por 190 minutos simulados.');
})().catch(e=>{console.error(e);process.exitCode=1;});
