let refreshToken = null;
let tokenExpiresAt = 0;
let refreshing = null;
let sessionVersion = 0;

function acceptSession(auth) {
  token = auth.access_token;
  refreshToken = auth.refresh_token || null;
  tokenExpiresAt = Date.now() + Number(auth.expires_in || 3600) * 1000;
}
function clearSession() {
  sessionVersion++;
  token = null;
  refreshToken = null;
  tokenExpiresAt = 0;
  refreshing = null;
}
async function refreshSession() {
  if (refreshing) return refreshing;
  if (!refreshToken) return;
  const version = sessionVersion;
  const task = (async () => {
    const response = await fetch(config.url + '/auth/v1/token?grant_type=refresh_token', {
      method:'POST', headers:{apikey:config.publishableKey,'Content-Type':'application/json'},
      body:JSON.stringify({refresh_token:refreshToken}),signal:AbortSignal.timeout(20000)
    });
    const auth = await response.json();
    if (version !== sessionVersion) throw new Error('Sessão encerrada.');
    if (!response.ok) {
      if (response.status === 400 || response.status === 401) {
        clearSession();
        document.querySelector('#logout').click();
        message('Sua sessão terminou. Entre novamente para continuar.');
      }
      throw new Error('Não foi possível renovar o acesso. Confira a conexão e tente novamente.');
    }
    acceptSession(auth);
  })();
  refreshing = task;
  try { await task; } finally { if (refreshing === task) refreshing = null; }
}
async function ensureSession() {
  if (token && Date.now() >= tokenExpiresAt - 120000) await refreshSession();
}
setInterval(() => {
  if (document.visibilityState === 'visible' && navigator.onLine) ensureSession().catch(()=>{});
}, 60000);
document.addEventListener('visibilitychange',()=>{
  if(document.visibilityState==='visible') ensureSession().catch(()=>{});
});
