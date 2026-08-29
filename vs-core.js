"use strict";
/* ============================================================================
   WeVois Vendor Settlement Portal - core: state, helpers, loading, auth gates
   Every write goes through a vs_* database function. The browser never inserts
   or updates a row directly, because no table grants it permission to.
   ========================================================================== */

var SB = null;
var S = {
  user:null, profile:null, caps:[], site:null, dirty:false, saving:false, read:null, extra:{approvals:[],mail:[]}, mail:[], missing:null,
  settings:{window_days:5, deemed_approve:true, variance_pct:15},
  vendors:[], sites:[], contracts:[], adjTypes:[], profiles:[], invites:[], audit:[], heads:[],
  period:null, list:[], open:null, stmt:null, tab:"sheet", adminTab:"users",
  err:null, draft:null
};

var ROLE_LABEL = {admin:"Admin", manager:"Vendor Manager", accounts:"Accounts",
                  ceo:"CEO", vp:"VP", vendor:"Vendor"};
var ROLE_NOTE = {
  admin:"Users, vendors, sites and the settlement lifecycle. Not a settlement actor.",
  manager:"Builds statements, answers points, issues revisions.",
  accounts:"Posts processed salary, PF and ESIC. Releases payment.",
  ceo:"Observer. Sees everything, changes nothing.",
  vp:"Observer. Sees everything, changes nothing.",
  vendor:"Own statements only. Raises points, approves."
};

function can(c){ return S.caps.indexOf(c) >= 0; }
function isObserver(){ return !!S.profile && (S.profile.role==="ceo" || S.profile.role==="vp"); }

/* ------------------------------------------------------------- formatting */
function inr(n){
  var x = Number(n)||0, neg = x < 0;
  x = Math.abs(Math.round(x));
  var s = String(x), last3 = s.slice(-3), rest = s.slice(0,-3);
  if(rest) last3 = "," + last3;
  rest = rest.replace(/\B(?=(\d{2})+(?!\d))/g, ",");
  return (neg?"-":"") + "₹" + rest + last3;
}
function esc(s){
  return String(s==null?"":s)
    .replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")
    .replace(/"/g,"&quot;").replace(/'/g,"&#39;");
}
function dt(iso){
  if(!iso) return "—";
  var d = new Date(String(iso).length<=10 ? iso+"T00:00:00" : iso);
  if(isNaN(d.getTime())) return "—";
  var M=["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
  var h=d.getHours(), ap=h>=12?"PM":"AM"; h=h%12; if(h===0) h=12;
  var mm=String(d.getMinutes()); if(mm.length<2) mm="0"+mm;
  return d.getDate()+" "+M[d.getMonth()]+" "+d.getFullYear()+", "+h+":"+mm+" "+ap;
}
function dOnly(iso){ if(!iso) return "—"; return dt(iso).split(",")[0]; }
function monthLabel(p){
  if(!p) return "";
  var M=["January","February","March","April","May","June","July",
         "August","September","October","November","December"];
  var d=new Date(String(p).slice(0,10)+"T00:00:00");
  if(isNaN(d.getTime())) return String(p);
  return M[d.getMonth()]+" "+d.getFullYear();
}
function thisMonth(){
  var d=new Date();
  return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-01";
}
function num(id){ var el=document.getElementById(id); return el? Number(String(el.value).replace(/[^0-9.\-]/g,"")||0) : 0; }
function val(id){ var el=document.getElementById(id); return el? String(el.value).trim() : ""; }

function toast(m){
  var t=document.getElementById("toast");
  t.innerHTML='<div class="toast">'+esc(m)+'</div>';
  clearTimeout(toast._t);
  toast._t = setTimeout(function(){ t.innerHTML=""; }, 4000);
}
function closeModal(){ document.getElementById("modal").innerHTML=""; }
function modal(title, body, foot){
  document.getElementById("modal").innerHTML =
    '<div class="ovl" data-act="ovl"><div class="mdl" data-act="mdlstop">'+
    '<div class="mdl-h"><h3>'+title+'</h3><button class="x" data-act="closemodal">&times;</button></div>'+
    '<div class="mdl-b">'+body+'</div>'+(foot?'<div class="mdl-f">'+foot+'</div>':'')+'</div></div>';
}
function busy(on, what){
  document.getElementById("busy").innerHTML = on
    ? '<div class="busy"><span class="spin"></span>'+esc(what||"working...")+'</div>' : '';
}

/* The vs_* functions raise messages written for a person to read. Surface them
   as they are; only translate the framework-level ones. */
function friendly(e){
  var m = (e && (e.message || e.error_description || e.hint || e.details)) || String(e);
  m = String(m).replace(/^ERROR:\s*/,"").replace(/\s*CONTEXT:[\s\S]*$/,"").trim();
  if(/JWT|not authenticated|invalid token/i.test(m)) return "Your session expired. Please sign in again.";
  if(/permission denied|violates row-level security/i.test(m))
    return "Your role ("+(S.profile?ROLE_LABEL[S.profile.role]:"none")+") is not allowed to do that.";
  if(/duplicate key/i.test(m)) return "That already exists.";
  if(/Failed to fetch|NetworkError/i.test(m)) return "Cannot reach the database. Check your connection.";
  return m;
}
async function rpc(fn, args, what){
  busy(true, what);
  try{
    var r = await SB.rpc(fn, args||{});
    if(r.error) throw r.error;
    return r.data;
  } finally { busy(false); }
}
async function call(fn, args, okMsg, what){
  try{
    var d = await rpc(fn, args, what);
    if(okMsg) toast(okMsg);
    return {ok:true, data:d};
  }catch(e){ toast(friendly(e)); return {ok:false, error:e}; }
}


/* ---------------------------------------------------------- schema check */
/* The app and the database are deployed separately, so they can drift: a new
   build talking to a database that has not had the matching patch run. When
   that happens the only symptom is a raw Postgres error at the moment somebody
   tries to use the feature - which is how a vendor came to see
   "new row violates row-level security policy" while attaching a bill.
   So the app asks, once, at sign-in, and says plainly what is missing. */
var PATCHES = [
  {file:"VS-PATCH-1.sql", fn:"vs_add_document",     what:"payroll and PF/ESIC file attachments"},
  {file:"VS-PATCH-2.sql", fn:"vs_sees_site",        what:"keeping each vendor to his own sites"},
  {file:"VS-PATCH-3.sql", fn:"vs_set_site",         what:"editing a site and its tenures"},
  {file:"VS-PATCH-5.sql", fn:"vs_raise_query",      what:"queries, vendor uploads and payroll top-ups"},
  {file:"VS-PATCH-6.sql", fn:"vs_statement_extra",  what:"email notifications and CEO/VP confirmation"}
];

function missingFn(err){
  var m = ((err && (err.message || err.msg)) || "") + " " + ((err && err.code) || "");
  return /could not find the function|does not exist|PGRST202|42883/i.test(m);
}

async function checkSchema(){
  var gone = [];
  await Promise.all(PATCHES.map(async function(p){
    try{
      var r = await SB.rpc(p.fn, {});
      if(r.error && missingFn(r.error)) gone.push(p);
    }catch(e){ if(missingFn(e)) gone.push(p); }
  }));
  /* patch 4 is a capability row, not a function */
  try{
    var c = await SB.from("vs_caps").select("cap").eq("role","manager").eq("cap","post_payroll");
    if(!c.error && (!c.data || !c.data.length))
      gone.push({file:"VS-PATCH-4.sql", fn:"", what:"the vendor manager posting payroll"});
  }catch(e){}
  gone.sort(function(a,b){ return a.file < b.file ? -1 : 1; });
  S.missing = gone;
  return gone;
}

function schemaBanner(){
  var g = S.missing || [];
  if(!g.length) return "";
  var mine = S.profile && ["admin","manager","accounts"].indexOf(S.profile.role) >= 0;
  if(!mine)
    return '<div class="banner b-amber"><div class="ico">&#9888;</div><div>'+
      '<b>Part of this portal is not switched on yet</b>'+
      'Some things will refuse to work until WeVois finishes setting it up. If something you try is refused '+
      'with a message that makes no sense, that is why - tell WeVois rather than working around it.</div></div>';
  return '<div class="banner b-red"><div class="ico">&#9888;</div><div>'+
    '<b>The database is behind this build &mdash; '+g.length+' patch'+(g.length===1?'':'es')+' still to run</b>'+
    'The screens for these are already here, so they look available and then fail with a database error when '+
    'somebody uses them. Open the Supabase SQL editor and run each file below, whole, in order:'+
    '<ul style="margin:8px 0 0 18px;padding:0">'+
    g.map(function(p){ return '<li style="margin:2px 0"><b>'+esc(p.file)+'</b> &mdash; '+esc(p.what)+'</li>'; }).join("")+
    '</ul></div></div>';
}

/* ---------------------------------------------------------------- loading */
async function loadAll(){
  var q = await Promise.all([
    SB.from("vs_settings").select("*").limit(1),
    SB.from("vs_vendors").select("*").order("name"),
    SB.from("vs_sites").select("*").order("name"),
    SB.from("vs_contracts").select("*"),
    SB.from("vs_adj_types").select("*").eq("active",true).order("sort"),
    SB.from("vs_heads").select("*").order("sort"),
    SB.rpc("vs_list_statements", {p_period:null})
  ]);
  if(q[0].data && q[0].data[0]) S.settings = q[0].data[0];
  S.vendors  = q[1].data||[];
  S.sites    = q[2].data||[];
  S.contracts= q[3].data||[];
  S.adjTypes = q[4].data||[];
  S.heads    = q[5].data||[];
  S.list     = q[6].data||[];

  if(can("manage_users")){
    var p = await Promise.all([
      SB.from("vs_profiles").select("*").order("full_name"),
      SB.from("vs_invites").select("*").is("used_at",null).order("created_at",{ascending:false}),
      SB.from("vs_audit").select("*").order("at",{ascending:false}).limit(150)
    ]);
    S.profiles = p[0].data||[]; S.invites = p[1].data||[]; S.audit = p[2].data||[];
    try{
      var mq = await SB.from("vs_mail").select("*").order("created_at",{ascending:false}).limit(80);
      S.mail = mq.data||[];
    }catch(e){ S.mail = []; }
  } else if(can("view_all")){
    var a = await SB.from("vs_audit").select("*").order("at",{ascending:false}).limit(150);
    S.audit = a.data||[];
  }

  if(!S.period){
    var months = {};
    S.list.forEach(function(x){ months[String(x.period).slice(0,10)] = 1; });
    var ks = Object.keys(months).sort();
    S.period = ks.length ? ks[ks.length-1] : thisMonth();
  }
}
async function openStatement(id){
  try{
    var d = await rpc("vs_statement_json", {p_stmt:id}, "opening...");
    S.stmt = d; S.open = id; S.tab = "sheet"; S.draft = null;
    /* approvals and the outbox are staff-only, and older databases have not
       run the patch that provides them - neither should stop a statement
       opening */
    S.extra = {approvals:[], mail:[]};
    try{ S.extra = await rpc("vs_statement_extra", {p_stmt:id}) || S.extra; }catch(e){}
    if(S.profile.role==="vendor"){
      try{ await SB.rpc("vs_mark_viewed",{p_stmt:id}); }catch(e){}
    }
    window.scrollTo(0,0);
    render();
  }catch(e){ toast(friendly(e)); }
}
async function refresh(keepOpen){
  await loadAll();
  if(keepOpen && S.open){
    try{
      S.stmt = await rpc("vs_statement_json",{p_stmt:S.open}); S.draft = null;
      try{ S.extra = await rpc("vs_statement_extra",{p_stmt:S.open}) || S.extra; }catch(e2){}
    }
    catch(e){ S.open = null; S.stmt = null; }
  }
  render();
}

/* ---------------------------------------------------------------- derived */
function curVer(st){ return st.versions[st.versions.length-1]; }
function verByNo(st,n){
  for(var i=0;i<st.versions.length;i++) if(st.versions[i].v===n) return st.versions[i];
  return null;
}
function openPoints(st){
  var n=0;
  (st.points||[]).forEach(function(p){ if(p.status==="open"||p.status==="awaiting_confirm") n++; });
  return n;
}
function pendingChanges(st){
  var n = (st.payroll && st.payroll.pending_fix) ? 1 : 0;
  (st.points||[]).forEach(function(p){
    if(!p.published && ["accepted","partial","rejected","carry_forward","disputed_record"].indexOf(p.status)>=0) n++;
  });
  return n;
}
function statusChip(s){
  var m = {draft:["c-grey","Draft"], sent:["c-blue","Awaiting vendor"], under_query:["c-amber","Under query"],
           approved:["c-green","Approved - to pay"], part_paid:["c-amber","Part paid"], paid:["c-teal","Paid"]}[s]
        || ["c-grey", String(s)];
  return '<span class="chip '+m[0]+'"><span class="d"></span>'+m[1]+'</span>';
}
function effClass(e){ return e==="add"?"eff-add":e==="deduct"?"eff-deduct":"eff-note"; }
function effSign(e){ return e==="add"?"+":e==="deduct"?"-":""; }
function siteName(id){ for(var i=0;i<S.sites.length;i++) if(S.sites[i].id===id) return S.sites[i].name; return "?"; }
function vendorName(id){ for(var i=0;i<S.vendors.length;i++) if(S.vendors[i].id===id) return S.vendors[i].name; return "?"; }
function contractsOfSite(sid){ return S.contracts.filter(function(c){ return c.site_id===sid; }); }
function contractLabel(c){ return vendorName(c.vendor_id)+" — "+siteName(c.site_id); }

/* A readable one-time password. No 0/O/1/l/I, so it survives being read out
   over the phone or copied off a piece of paper. */
function tempPassword(){
  var A = "ABCDEFGHJKMNPQRSTUVWXYZ", a = "abcdefghijkmnpqrstuvwxyz", d = "23456789";
  var pool = A + a + d, out = "";
  var r = new Uint32Array(12);
  (window.crypto || window.msCrypto).getRandomValues(r);
  for(var i=0;i<12;i++) out += pool.charAt(r[i] % pool.length);
  /* guarantee one of each kind */
  return out.slice(0,9) + A.charAt(r[9]%A.length) + a.charAt(r[10]%a.length) + d.charAt(r[11]%d.length);
}

/* Supabase will not let one signed-in browser user create another's login on
   the shared client - doing it there would swap the administrator's own
   session for the new account's. So the sign-up runs on a SECOND client with
   its own storage key and no session persistence. The administrator stays
   signed in as themselves throughout; the new account's session is thrown away
   the moment it is created. */
function provisionClient(){
  return window.supabase.createClient(window.VS_URL, window.VS_ANON, {
    auth: { storageKey:"vs-provision", persistSession:false,
            autoRefreshToken:false, detectSessionInUrl:false }
  });
}

/* ====================================================================== */
/*  AUTH GATES                                                            */
/* ====================================================================== */
function gate(inner){
  document.getElementById("app").innerHTML =
    '<div class="gate"><div class="gate-card">'+
    '<div class="gate-logo"><span class="dot"></span>'+esc(window.VS_ORG||"WeVois")+
    ' <span style="font-weight:400;color:var(--muted);font-size:13px">Vendor Settlement</span></div>'+
    inner+'</div></div>';
}
function viewConfigNeeded(){
  gate('<h1>Not connected yet</h1>'+
    '<p class="sub">Open <b>supabase-config.js</b>, paste your Supabase Project URL and anon public key, then reload this page.</p>'+
    '<div class="decl">Both values are in your Supabase dashboard under <b>Project Settings &rarr; API</b>. '+
    'Use the <b>anon public</b> key - it is designed to sit in a browser. The <b>service_role</b> key must never go in this file; '+
    'it bypasses every policy in the database.</div>');
}
function viewSignIn(needsSetup){
  gate((S.err?'<div class="err">'+esc(S.err)+'</div>':'')+
   (needsSetup
     ? '<h1>Create the first administrator</h1>'+
       '<p class="sub">This database is empty. The first account to sign up becomes the administrator. '+
       'After that, only the administrator can create logins.</p>'+
       '<div class="fld"><label class="fl">Full name</label><input class="inp" id="g-name" placeholder="e.g. Priya Nair"></div>'
     : '<h1>Sign in</h1><p class="sub">Use the email and password your administrator gave you.</p>')+
   '<div class="fld"><label class="fl">Email</label><input class="inp" id="g-email" type="email" autocomplete="username"></div>'+
   '<div class="fld"><label class="fl">Password</label><input class="inp" id="g-pass" type="password" autocomplete="current-password"></div>'+
   '<div class="btnrow"><button class="btn primary" data-act="'+(needsSetup?"signup-first":"signin")+'">'+
     (needsSetup?"Create administrator":"Sign in")+'</button></div>'+
   (needsSetup?'':'<div class="hint" style="margin-top:14px">No login yet? Your administrator creates it and passes you the '+
     'password. You can change it from <b>Change password</b> once you are in.</div>'));
}
function viewNoProfile(){
  gate('<h1>This account is not set up yet</h1>'+
    '<p class="sub">You are signed in as <b>'+esc(S.user.email)+'</b>, but no role has been assigned to it.</p>'+
    '<div class="decl">Ask your administrator to invite this exact email address. Until they do, this account can see nothing at all - '+
    'not a vendor, not a site, not a single figure. That is deliberate, and the database enforces it rather than the screen.</div>'+
    '<div class="btnrow" style="margin-top:16px"><button class="btn" data-act="signout">Sign out</button></div>');
}
