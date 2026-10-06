(function(){
const cfg=window.TAREFAS_CFG||{};
if(!cfg.url||!cfg.key||!window.supabase)return; // sem configuração: o app funciona só neste aparelho
const sb=window.supabase.createClient(cfg.url,cfg.key);
const cj=o=>JSON.stringify(o,(k,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.keys(v).sort().reduce((a,x)=>(a[x]=v[x],a),{}):v);
const E=s=>document.querySelector(s),now=()=>new Date().toISOString();
let uid=null,hh=null,mem=null,email='',ready=false,busy=false,again=false,tm=null,subs=null,snap={};
try{snap=JSON.parse(localStorage.getItem('tf1snap'))||{}}catch(e){}
const ssnap=()=>{try{localStorage.setItem('tf1snap',JSON.stringify(snap))}catch(e){}};
function ov(h){let d=E('#sy');if(!d){d=document.createElement('div');d.id='sy';d.style.cssText='position:fixed;inset:0;z-index:60;background:var(--bg);color:var(--tx);overflow:auto;padding:calc(24px + env(safe-area-inset-top,0px)) 20px 24px';document.body.appendChild(d)}d.innerHTML='<div style="max-width:420px;margin:0 auto">'+h+'</div>'}
const ovx=()=>{const d=E('#sy');if(d)d.remove()},msg=m=>{const e=E('#sm');if(e)e.textContent=m};
const tr=m=>/Anonymous sign-ins/i.test(m)?'Preencha o e-mail e a senha.':/Invalid login/i.test(m)?'E-mail ou senha incorretos.':/already registered/i.test(m)?'Este e-mail já tem conta. Toque em Entrar.':/at least 6/i.test(m)?'A senha precisa de 6 caracteres ou mais.':m;
function login(m){ov(`<h2>✅ Tarefas</h2><p class="mu">Entre para sincronizar com sua esposa.</p><label>E-mail<input id="se" type="email" autocomplete="email"></label><label>Senha (mín. 6)<input id="sp" type="password" autocomplete="current-password"></label><button class="b" onclick="SYNC.si()">Entrar</button><button class="b g" onclick="SYNC.su()">Criar conta</button><p class="mu" id="sm">${m||''}</p>`)}
function onb(m){ov(`<h2>Quase lá</h2><label>Seu nome<input id="sn" placeholder="Ex.: Rafael"></label><button class="b" onclick="SYNC.cr()">Criar nossa casa</button><p class="mu">Ou, se seu parceiro(a) já criou a casa, digite o código dela:</p><label>Código<input id="sc" autocapitalize="none"></label><button class="b g" onclick="SYNC.jn()">Entrar com código</button><button class="b g" onclick="SYNC.out()">Sair</button><p class="mu" id="sm">${m||''}</p>`)}
async function si(){const em=E('#se').value.trim(),pw=E('#sp').value;if(!em||!pw)return msg('Preencha o e-mail e a senha.');const{error}=await sb.auth.signInWithPassword({email:em,password:pw});if(error)return msg(tr(error.message));boot()}
async function su(){const em=E('#se').value.trim(),pw=E('#sp').value;if(!em||!pw)return msg('Preencha o e-mail e a senha.');const{data,error}=await sb.auth.signUp({email:em,password:pw});if(error)return msg(tr(error.message));if(!data.session)return msg('Conta criada. Confirme pelo e-mail e depois toque em Entrar (ou desligue "Confirm email" no Supabase).');boot()}
async function cr(){const n=E('#sn').value.trim();if(!n)return msg('Digite seu nome');const{error}=await sb.rpc('create_household',{nick:n});if(error)return msg(error.message);boot()}
async function jn(){const n=E('#sn').value.trim(),c=E('#sc').value.trim();if(!n||!c)return msg('Digite seu nome e o código');const{error}=await sb.rpc('join_household',{invite:c,nick:n});if(error)return msg(error.message);S.tasks=[];S.rot=[];snap={};ssnap();boot()}
async function out(){try{await sb.auth.signOut()}catch(e){}ready=false;if(subs){sb.removeChannel(subs);subs=null}S.tasks=[];S.rot=[];S.sy=0;S.me='eu';snap={};ssnap();try{localStorage.removeItem('tf1mem')}catch(e){}save();cl();render();login()}
function cache(){try{return JSON.parse(localStorage.getItem('tf1mem'))}catch(e){return null}}
async function boot(){const{data:{session}}=await sb.auth.getSession();if(!session){login();return}uid=session.user.id;email=session.user.email;
const r=await sb.from('members').select('*').eq('user_id',uid).maybeSingle();
if(r.error){const c=cache();if(c){mem=c.mem;hh=mem.household;Object.assign(WHO,c.who);ovx();start()}return}
if(!r.data){onb();return}mem=r.data;hh=mem.household;
const n=await sb.from('members').select('slot,name');(n.data||[]).forEach(x=>{if(x.name)WHO[x.slot]=x.name});
try{localStorage.setItem('tf1mem',JSON.stringify({mem,who:{eu:WHO.eu,ela:WHO.ela}}))}catch(e){}
ovx();start()}
function ap(row){const k=row.kind+':'+row.id,arr=row.kind==='task'?S.tasks:S.rot,i=arr.findIndex(x=>x.id===row.id);
if(row.deleted){if(i>=0)arr.splice(i,1);delete snap[k];return}
const d=row.data;d.id=row.id;
if(i>=0){if(snap[k]!==undefined&&cj(arr[i])!==snap[k])return;arr[i]=d}else arr.push(d);
snap[k]=cj(d)}
async function pull(){const r=await sb.from('items').select('*').eq('household',hh);if(r.error)return;r.data.forEach(ap);ssnap();render()}
async function push(){if(!ready)return;if(busy){again=true;return}busy=true;
try{const cur={};S.tasks.forEach(t=>cur['task:'+t.id]=t);S.rot.forEach(r=>cur['rot:'+r.id]=r);const ins=[];
for(const k in cur){const o=cur[k],c=cj(o);if(snap[k]===c)continue;const p=k.indexOf(':'),kind=k.slice(0,p),id=k.slice(p+1);
if(snap[k]===undefined)ins.push({k,c,row:{household:hh,id,kind,owner:uid,priv:!!o.priv,data:o}});
else{const r=await sb.from('items').update({priv:!!o.priv,data:o,deleted:false,updated_at:now()}).eq('household',hh).eq('id',id);if(!r.error)snap[k]=c}}
if(ins.length){const r=await sb.from('items').insert(ins.map(x=>x.row));
if(!r.error)ins.forEach(x=>snap[x.k]=x.c);
else for(const x of ins){const u=await sb.from('items').update({priv:x.row.priv,data:x.row.data,deleted:false,updated_at:now()}).eq('household',hh).eq('id',x.row.id);if(!u.error)snap[x.k]=x.c}}
for(const k of Object.keys(snap)){if(cur[k])continue;const id=k.slice(k.indexOf(':')+1);const r=await sb.from('items').update({deleted:true,updated_at:now()}).eq('household',hh).eq('id',id);if(!r.error)delete snap[k]}
ssnap()}catch(e){}
busy=false;if(again){again=false;push()}}
function subscribe(){if(subs)sb.removeChannel(subs);subs=sb.channel('items-'+hh).on('postgres_changes',{event:'*',schema:'public',table:'items',filter:'household=eq.'+hh},p=>{if(p.new&&p.new.id){ap(p.new);ssnap();render()}}).subscribe()}
async function start(){S.me=mem.slot;S.sy=1;window.meLabel=()=>'👤 '+(WHO[S.me]||'Eu');E('#me').onclick=account;await pull();ready=true;await push();subscribe();render()}
async function account(){const r=await sb.from('households').select('code').maybeSingle();modal(`<h3>👤 ${esc(WHO[S.me])}</h3><p class="mu">${esc(email)}</p><p>Código da casa: <b>${r.data?esc(r.data.code):'—'}</b></p><p class="mu">Passe este código para sua esposa criar a conta dela e escolher "Entrar com código".</p><button class="b g" onclick="SYNC.sync()">⟳ Sincronizar agora</button><button class="b d" onclick="SYNC.out()">Sair (apaga os dados deste aparelho)</button>`)}
window.onSave=()=>{if(!ready)return;clearTimeout(tm);tm=setTimeout(push,900)};
addEventListener('online',()=>{if(ready)push().then(pull)});
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&ready)push().then(pull)});
window.SYNC={si,su,cr,jn,out,sync:async()=>{await push();await pull();toast('Sincronizado')}};
boot().catch(()=>{});
})();
