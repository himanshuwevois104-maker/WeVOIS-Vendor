"use strict";
/* ============================================================================
   WeVois Vendor Settlement Portal - core: state, helpers, loading, auth gates
   Every write goes through a vs_* database function. The browser never inserts
   or updates a row directly, because no table grants it permission to.
   ========================================================================== */

var SB = null;
var S = {
  user:null, profile:null, caps:[],
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
    try{ S.stmt = await rpc("vs_statement_json",{p_stmt:S.open}); S.draft = null; }
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
       '<p class="sub">This database is empty. The first account to sign up becomes the administrator. After that, nobody gets in without an invitation.</p>'+
       '<div class="fld"><label class="fl">Full name</label><input class="inp" id="g-name" placeholder="e.g. Priya Nair"></div>'
     : '<h1>Sign in</h1><p class="sub">Use the email address your administrator invited.</p>')+
   '<div class="fld"><label class="fl">Email</label><input class="inp" id="g-email" type="email" autocomplete="username"></div>'+
   '<div class="fld"><label class="fl">Password</label><input class="inp" id="g-pass" type="password" autocomplete="current-password"></div>'+
   '<div class="btnrow"><button class="btn primary" data-act="'+(needsSetup?"signup-first":"signin")+'">'+
     (needsSetup?"Create administrator":"Sign in")+'</button>'+
   (needsSetup?'':'<button class="btn" data-act="signup-invited">First time? Set my password</button>')+'</div>'+
   (needsSetup?'':'<div class="hint" style="margin-top:14px">If you have been invited but never signed in, use '+
     '<b>Set my password</b> with the same email address.</div>'));
}
function viewNoProfile(){
  gate('<h1>This account is not set up yet</h1>'+
    '<p class="sub">You are signed in as <b>'+esc(S.user.email)+'</b>, but no role has been assigned to it.</p>'+
    '<div class="decl">Ask your administrator to invite this exact email address. Until they do, this account can see nothing at all - '+
    'not a vendor, not a site, not a single figure. That is deliberate, and the database enforces it rather than the screen.</div>'+
    '<div class="btnrow" style="margin-top:16px"><button class="btn" data-act="signout">Sign out</button></div>');
}
