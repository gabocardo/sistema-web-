'use strict';
const config=window.BINGO_CONFIG;
const notice=document.querySelector('#notice');
const form=document.querySelector('#login');
const submit=document.querySelector('#submit');
let token=null;
function message(text){notice.textContent=text;}
async function request(path,options={}){
 const response=await fetch(config.url+path,{...options,headers:{apikey:config.publishableKey,'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`} :{}),...options.headers},signal:AbortSignal.timeout(20000)});
 const data=await response.json().catch(()=>null);
 if(!response.ok)throw new Error(response.status===400||response.status===401?'E-mail ou senha inválidos. Verifique seu acesso.':'Não foi possível concluir a operação. Tente novamente.');
 return data;
}
form.addEventListener('submit',async(event)=>{
 event.preventDefault(); submit.disabled=true; message('Verificando acesso…');
 try{
  const auth=await request('/auth/v1/token?grant_type=password',{method:'POST',body:JSON.stringify({email:document.querySelector('#email').value.trim(),password:document.querySelector('#password').value})});
  token=auth.access_token;
  document.querySelector('#password').value='';
  const members=await request('/rest/v1/team_members?select=role&user_id=eq.'+encodeURIComponent(auth.user.id));
  if(!members.length){token=null;throw new Error('Seu usuário ainda não foi autorizado pela organização.');}
  form.hidden=true;document.querySelector('#account').hidden=false;document.querySelector('#identity').textContent=auth.user.email;message('Acesso verificado.');
 }catch(error){token=null;message(error.name==='TypeError'||error.name==='TimeoutError'?'Sem conexão com o servidor. Nenhuma operação foi confirmada.':error.message);}
 finally{submit.disabled=false;}
});
document.querySelector('#logout').addEventListener('click',()=>{token=null;form.reset();form.hidden=false;document.querySelector('#account').hidden=true;message('Você saiu do sistema.');});
if(!config?.publishableKey){submit.disabled=true;message('Configuração em andamento. O acesso da equipe será liberado após conectar o projeto Supabase.');}
window.addEventListener('offline',()=>message('Você está sem conexão. Aguarde a internet voltar.'));
