"use strict";
/* ============================================================================
   Admin console, modals, every action, and boot.
   ========================================================================== */

var CAP_ROWS = [
  ["Create and edit a draft statement", "edit_draft"],
  ["Post processed salary, PF and ESIC", "post_payroll"],
  ["Share the statement with the vendor", "share"],
  ["Log a point from a phone call", "logcall"],
  ["Answer / resolve a point", "resolve"],
  ["Issue a revised version", "revise"],
  ["Raise a point", "raise"],
  ["Approve the statement", "approve"],
  ["Release payment and enter the UTR", "pay"],
  ["Manage users and roles", "manage_users"],
  ["Manage vendors and sites", "manage_vendors"],
  ["Assign a vendor to a site", "manage_contracts"],
  ["Open or delete a settlement", "manage_settlements"],
  ["Manage booking heads and rules", "manage_masters"],
  ["View every vendor's statement", "view_all"]
];
var ROLE_ORDER = ["admin","manager","accounts","ceo","vp","vendor"];
var CAPS_BY_ROLE = {
  admin:["view_all","manage_users","manage_vendors","manage_contracts","manage_settlements","manage_masters"],
  manager:["view_all","edit_draft","share","logcall","resolve","revise","remind"],
  accounts:["view_all","post_payroll","pay"],
  ceo:["view_all"], vp:["view_all"],
  vendor:["raise","confirm","approve"]
};

/* ====================================================================== */
/*  ADMIN CONSOLE                                                         */
/* ====================================================================== */
function viewAdmin(){
  var t = S.adminTab;
  var tabs = '<div class="tabs">'+[
    ["users","Users &amp; roles"],["vendors","Vendors"],["sites","Sites &amp; tenures"],
    ["settle","Settlements"],["heads","Booking heads"],["rules","Settlement rules"],
    ["matrix","Who can do what"],["audit","Audit log"]
  ].map(function(x){
    return '<button data-act="atab" data-v="'+x[0]+'" class="'+(t===x[0]?"on":"")+'">'+x[1]+'</button>'; }).join("")+'</div>';

  var body =
      t==="users"   ? adminUsers()
    : t==="vendors" ? adminVendors()
    : t==="sites"   ? adminSites()
    : t==="settle"  ? adminSettlements()
    : t==="heads"   ? adminHeads()
    : t==="rules"   ? adminRules()
    : t==="matrix"  ? adminMatrix()
    :                 adminAudit();

  return '<div class="page-h"><div><h1>Administration</h1>'+
    '<p>People, vendors, sites, master data and the settlement lifecycle</p></div></div>'+
    tabs+'<div class="card" style="border-top:0;border-radius:0 0 var(--radius) var(--radius);margin-top:0">'+body+'</div>';
}

function adminUsers(){
  var rows = S.profiles.map(function(u){
    var cls = u.role==="vendor"?"c-grey":u.role==="admin"?"c-violet":u.role==="accounts"?"c-teal":
              (u.role==="ceo"||u.role==="vp")?"c-blue":"c-green";
    return '<tr><td><b>'+esc(u.full_name||"(no name)")+'</b>'+
      '<div style="font-size:12px;color:var(--muted)">'+esc(u.email)+'</div></td>'+
      '<td><span class="chip '+cls+'">'+esc(ROLE_LABEL[u.role]||u.role)+'</span></td>'+
      '<td style="font-size:12.5px;color:var(--muted)">'+
        (u.vendor_id ? esc(vendorName(u.vendor_id)) : esc(ROLE_NOTE[u.role]||""))+'</td>'+
      '<td>'+(u.active?'<span class="chip c-green"><span class="d"></span>Active</span>'
                      :'<span class="chip c-red"><span class="d"></span>Deactivated</span>')+'</td>'+
      '<td class="num"><button class="btn sm" data-act="edituser" data-uid="'+u.id+'" data-role="'+esc(u.role)+'" '+
        'data-name="'+esc(u.full_name||u.email)+'">Change role</button> '+
        '<button class="btn sm" data-act="toggleuser" data-uid="'+u.id+'" data-on="'+(u.active?"0":"1")+'">'+
        (u.active?"Deactivate":"Reactivate")+'</button></td></tr>';
  }).join("");
  var inv = S.invites.map(function(i){
    return '<tr><td>'+esc(i.full_name||"")+'<div style="font-size:12px;color:var(--muted)">'+esc(i.email)+'</div></td>'+
      '<td><span class="chip c-grey">'+esc(ROLE_LABEL[i.role]||i.role)+'</span></td>'+
      '<td style="font-size:12.5px;color:var(--muted)">'+(i.vendor_id?esc(vendorName(i.vendor_id)):"&mdash;")+'</td>'+
      '<td style="font-size:12.5px;color:var(--muted)">invited '+dOnly(i.created_at)+'</td></tr>'; }).join("");

  return '<div class="card-b"><div class="banner b-violet" style="margin-bottom:0"><div class="ico">&#128273;</div><div>'+
    '<b>Admin is deliberately not a settlement actor</b>This account creates people and sets roles. It cannot build a statement, '+
    'answer a point, approve, or move money. Someone who can hand out permissions should not also be able to use them.</div></div></div>'+
    '<table><thead><tr><th>Person</th><th>Role</th><th>Scope</th><th>Status</th>'+
    '<th class="num"><button class="btn sm primary" data-act="invite">Invite someone</button></th></tr></thead>'+
    '<tbody>'+(rows||'<tr><td colspan="5" class="empty">No one yet.</td></tr>')+'</tbody></table>'+
    (inv ? '<div class="card-b" style="border-top:1px solid var(--line-2)"><h3 style="font-size:14px;margin-bottom:4px">Invited, not signed in yet</h3>'+
      '<div class="hint">They get in by choosing <b>Set my password</b> on the sign-in screen with this exact email.</div></div>'+
      '<table><tbody>'+inv+'</tbody></table>' : '');
}

function adminVendors(){
  var rows = S.vendors.map(function(v){
    var cs = S.contracts.filter(function(c){ return c.vendor_id===v.id; });
    var live = cs.filter(function(c){ return !c.to_date; });
    return '<tr><td><b>'+esc(v.name)+'</b>'+(v.code?'<div style="font-size:12px;color:var(--muted)">'+esc(v.code)+'</div>':'')+'</td>'+
      '<td>'+(cs.length ? cs.map(function(c){
          return esc(siteName(c.site_id))+' <span style="color:var(--faint)">('+c.vehicles+
            (c.to_date?', to '+dOnly(c.to_date):'')+')</span>'; }).join("<br>")
        : '<span style="color:var(--faint)">no site yet</span>')+'</td>'+
      '<td class="num">'+live.reduce(function(a,c){ return a+Number(c.vehicles||0); },0)+'</td>'+
      '<td>'+esc(v.contact_name||"")+'<div style="font-size:12px;color:var(--muted)">'+esc(v.contact_email||"")+
        (v.contact_phone?' &middot; '+esc(v.contact_phone):'')+'</div></td></tr>';
  }).join("");
  return '<table><thead><tr><th>Vendor</th><th>Sites held</th><th class="num">Vehicles (live)</th><th>Contact</th>'+
    '</tr></thead><tbody>'+(rows||'<tr><td colspan="4" class="empty">No vendors yet.</td></tr>')+'</tbody></table>'+
    '<div class="card-b" style="border-top:1px solid var(--line-2)"><div class="btnrow">'+
    '<button class="btn primary" data-act="addvendor">Add a vendor</button>'+
    '<button class="btn" data-act="addsite">Add a site</button></div>'+
    '<div class="hint" style="margin-top:10px">A vendor can hold any number of sites, and a site can change hands over time. '+
    'Each pairing is its own tenure with its own vehicle count and its own monthly settlement, so a dispute at one site never holds up another.</div></div>';
}

function adminSites(){
  var rows = S.sites.map(function(st){
    var cs = contractsOfSite(st.id).sort(function(a,b){ return a.from_date < b.from_date ? -1 : 1; });
    var chain = cs.length ? cs.map(function(c){
      return '<div style="margin:2px 0">'+esc(vendorName(c.vendor_id))+
        ' <span style="color:var(--muted)">'+dOnly(c.from_date)+' to '+(c.to_date?dOnly(c.to_date):"current")+
        ' &middot; '+c.vehicles+' vehicles</span>'+
        (c.to_date?'':' <span class="chip c-green"><span class="d"></span>running</span>')+'</div>'; }).join("")
      : '<span style="color:var(--faint)">no vendor assigned</span>';
    var live = cs.filter(function(c){ return !c.to_date; })[0];
    return '<tr><td><b>'+esc(st.name)+'</b><div style="font-size:12px;color:var(--muted)">'+esc(st.city||"")+'</div></td>'+
      '<td>'+chain+'</td>'+
      '<td class="num">'+
        (live ? '<button class="btn sm" data-act="changevendor" data-sid="'+st.id+'" data-sname="'+esc(st.name)+'">Change vendor</button> '
              : '<button class="btn sm primary" data-act="assign" data-sid="'+st.id+'" data-sname="'+esc(st.name)+'">Assign a vendor</button> ')+
      '</td></tr>';
  }).join("");
  return '<div class="card-b"><div class="banner b-blue" style="margin-bottom:0"><div class="ico">&#128506;</div><div>'+
    '<b>A site can change hands mid-month</b>Use <b>Change vendor</b> and give the exact day the new partner takes over. '+
    'The outgoing tenure ends the day before, and that month produces two settlements for the site &mdash; one for each vendor, '+
    'each covering only its own days. Two vendors overlapping on one site is impossible, not merely discouraged.</div></div></div>'+
    '<table><thead><tr><th>Site</th><th>Who has run it</th>'+
    '<th class="num"><button class="btn sm" data-act="addsite">Add a site</button></th></tr></thead>'+
    '<tbody>'+(rows||'<tr><td colspan="3" class="empty">No sites yet.</td></tr>')+'</tbody></table>';
}

function adminSettlements(){
  var missing = S.contracts.filter(function(c){
    if(c.to_date && String(c.to_date) < S.period) return false;
    if(String(c.from_date).slice(0,7) > S.period.slice(0,7)) return false;
    return !S.list.some(function(x){ return x.contract_id===c.id && String(x.period).slice(0,10)===S.period; });
  }).length;

  var rows = S.list.slice().sort(function(a,b){
    var x=a.vendor_name+a.site_name+a.period, y=b.vendor_name+b.site_name+b.period; return x<y?-1:1;
  }).map(function(x){
    return '<tr><td><b>'+esc(x.vendor_name)+'</b>'+
      '<div style="font-size:12px;color:var(--muted)">'+esc(x.site_name)+' &middot; '+x.vehicles+' vehicles</div></td>'+
      '<td>'+esc(x.period_label)+'</td><td>'+statusChip(x.status)+
        ' <span style="font-size:12px;color:var(--muted)">v'+x.version+'</span></td>'+
      '<td class="num" style="font-size:12.5px;color:var(--muted)">'+x.version_count+' version'+(x.version_count==1?"":"s")+
        ' &middot; '+x.point_count+' point'+(x.point_count==1?"":"s")+' &middot; '+x.event_count+' events</td>'+
      '<td class="num"><b>'+inr(x.final)+'</b></td>'+
      '<td class="num"><button class="btn sm" data-act="open" data-id="'+x.id+'">Open</button> '+
      '<button class="btn sm" style="color:var(--red);border-color:#f0c9c5" data-act="askdel" data-id="'+x.id+'" '+
      'data-desc="'+esc(x.vendor_name+" - "+x.site_name+", "+x.period_label)+'" data-status="'+esc(x.status)+'" '+
      'data-v="'+x.version_count+'" data-p="'+x.point_count+'" data-e="'+x.event_count+'" '+
      'data-paid="'+(x.paid_total||0)+'">Delete</button></td></tr>';
  }).join("");

  var top = missing
    ? '<div class="banner b-amber" style="margin:0"><div class="ico">+</div><div><b>'+missing+
      ' contract'+(missing===1?" has":"s have")+' no '+esc(monthLabel(S.period))+' settlement yet</b>'+
      'Open the month to create them all at once, or add a single one.</div>'+
      '<div style="margin-left:auto;display:flex;gap:8px">'+
      '<button class="btn" data-act="addsettle">Add one settlement</button>'+
      '<button class="btn primary" data-act="openmonth">Open '+esc(monthLabel(S.period))+' for all</button></div></div>'
    : '<div class="banner b-green" style="margin:0"><div class="ico">&#10003;</div><div>'+
      '<b>Every running contract has a '+esc(monthLabel(S.period))+' settlement</b>Nothing missing for this month.</div>'+
      '<div style="margin-left:auto;display:flex;gap:8px">'+
      '<button class="btn" data-act="addsettle">Add one settlement</button>'+
      '<button class="btn" data-act="openmonth">Open '+esc(monthLabel(S.period))+' for all</button></div></div>';

  return '<div class="card-b">'+top+
    '<div class="banner b-grey" style="margin:14px 0 0"><div class="ico">&#9888;</div><div>'+
    '<b>Delete removes the settlement and everything attached to it</b>Versions, points, decisions, the approval and the payment record '+
    'all go with it. The fact of the deletion, who did it and why stays in the audit log below and cannot be removed. '+
    'If a vendor later disputes a month you have deleted, there is nothing left to show him.</div></div></div>'+
    '<table><thead><tr><th>Vendor &amp; site</th><th>Month</th><th>Status</th><th class="num">Contains</th>'+
    '<th class="num">Final amount</th><th></th></tr></thead>'+
    '<tbody>'+(rows||'<tr><td colspan="6" class="empty">No settlements yet.</td></tr>')+'</tbody></table>';
}

function adminHeads(){
  var out = S.sites.map(function(st){
    var hs = S.heads.filter(function(h){ return h.site_id===st.id; });
    return '<tr class="grp-row"><td colspan="4">'+esc(st.name)+' &mdash; '+hs.length+' booking heads</td></tr>'+
      hs.map(function(h){
        return '<tr><td style="padding-left:26px">'+esc(h.label)+(h.active?'':' <span class="chip c-grey">off</span>')+'</td>'+
          '<td>'+(h.src==="payroll"?'<span class="chip c-teal"><span class="d"></span>Posted by Accounts</span>'
                                   :'<span class="chip c-grey">Entered by Vendor Manager</span>')+'</td>'+
          '<td style="font-size:12.5px;color:var(--muted)">'+esc(h.grp)+'</td>'+
          '<td class="num"><button class="btn sm" data-act="edithead" data-hid="'+h.id+'" data-label="'+esc(h.label)+'" '+
            'data-sort="'+h.sort+'" data-on="'+(h.active?"1":"0")+'">Edit</button></td></tr>'; }).join("")+
      '<tr><td colspan="4" style="padding-left:26px"><button class="btn sm" data-act="addhead" data-sid="'+st.id+'" '+
        'data-sname="'+esc(st.name)+'">+ Add a head to '+esc(st.name)+'</button></td></tr>';
  }).join("");
  return '<div class="card-b"><div class="banner b-blue" style="margin-bottom:0"><div class="ico">&#9432;</div><div>'+
    '<b>Every site has its own heads</b>That is how your workbook already works &mdash; Chirawa splits R&amp;M into "by the partner" and '+
    '"by WeVois", Bundi has loader and tractor fuel and tractor rent, Jhunjhunu has parking rent, Sujalpur has water and building rent. '+
    'Renaming a head here never changes a statement a vendor has already approved; versions freeze the label as well as the figure.</div></div></div>'+
    '<table><thead><tr><th>Booking head</th><th>Source</th><th>Group</th><th></th></tr></thead>'+
    '<tbody>'+(out||'<tr><td colspan="4" class="empty">No sites yet.</td></tr>')+'</tbody></table>'+
    '<div class="card-b" style="border-top:1px solid var(--line-2)">'+
    '<h3 style="font-size:14px;margin-bottom:8px">Adjustment types</h3>'+
    '<div style="display:flex;flex-wrap:wrap;gap:7px;margin-bottom:12px">'+
    S.adjTypes.map(function(a){
      return '<span class="chip '+(a.effect==="add"?"c-green":a.effect==="deduct"?"c-red":"c-grey")+'">'+
        esc(a.label)+' &middot; '+esc(a.effect)+'</span>'; }).join("")+'</div>'+
    '<button class="btn sm" data-act="addadj">+ Add an adjustment type</button></div>';
}

function adminRules(){
  return '<div class="card-b" style="max-width:620px">'+
    '<div class="fld"><label class="fl">Response window (working days)</label>'+
      '<input class="inp num" id="ru-days" value="'+S.settings.window_days+'">'+
      '<div class="hint">How long a vendor has to approve or raise a point before the statement is deemed accepted.</div></div>'+
    '<div class="fld"><label class="fl">Silence after the window</label>'+
      '<select class="inp" id="ru-deemed">'+
      '<option value="1"'+(S.settings.deemed_approve?" selected":"")+'>Deemed approved &mdash; goes for payment, and the deeming is logged</option>'+
      '<option value="0"'+(!S.settings.deemed_approve?" selected":"")+'>Escalate to the Vendor Manager, do not auto-approve</option>'+
      '</select></div>'+
    '<div class="fld"><label class="fl">Variance flag threshold (%)</label>'+
      '<input class="inp num" id="ru-var" value="'+S.settings.variance_pct+'">'+
      '<div class="hint">Heads more than this far from last month are flagged before the statement can be shared.</div></div>'+
    '<div class="btnrow"><button class="btn primary" data-act="saverules">Save rules</button></div>'+
    '<div class="banner b-blue" style="margin:16px 0 0"><div class="ico">&#128274;</div><div>'+
    '<b>Changing a rule never touches a shared version</b>Rules apply to statements shared after the change. '+
    'Anything already with a vendor keeps the window it was sent under.</div></div></div>';
}

function adminMatrix(){
  var head = '<tr><th>Capability</th>'+ROLE_ORDER.map(function(r){
    return '<th style="text-align:center">'+esc(ROLE_LABEL[r])+'</th>'; }).join("")+'</tr>';
  var body = CAP_ROWS.map(function(row){
    return '<tr><td>'+esc(row[0])+'</td>'+ROLE_ORDER.map(function(r){
      if(row[1]==="view_all" && r==="vendor")
        return '<td style="text-align:center;font-size:11.5px;color:var(--muted)">own only</td>';
      var has = CAPS_BY_ROLE[r].indexOf(row[1])>=0;
      return '<td style="text-align:center" class="'+(has?"yes":"no")+'">'+(has?"&#10003;":"&middot;")+'</td>';
    }).join("")+'</tr>'; }).join("");
  return '<div class="card-b"><div class="banner b-grey" style="margin-bottom:0"><div class="ico">&#128737;</div><div>'+
    '<b>This is the design, and the database enforces it</b>Hiding a button is not security. Each of these is a row-level policy '+
    'or a check inside the function that performs the write, so an account that should not be able to do something cannot do it '+
    'even by calling the API directly.</div></div></div>'+
    '<table class="matrix"><thead>'+head+'</thead><tbody>'+body+'</tbody></table>';
}

function adminAudit(){
  var rows = S.audit.map(function(a){
    return '<tr><td style="white-space:nowrap;font-size:12.5px;color:var(--muted)">'+dt(a.at)+'</td>'+
      '<td><b>'+esc(a.title)+'</b><div style="font-size:12.5px;color:var(--ink-2)">'+esc(a.body||"")+'</div></td>'+
      '<td style="font-size:12.5px">'+esc(a.actor_name)+'<div style="color:var(--muted)">'+
      esc(ROLE_LABEL[a.actor_role]||a.actor_role)+'</div></td></tr>'; }).join("");
  return '<div class="card-b"><div class="banner b-grey" style="margin-bottom:0"><div class="ico">&#128209;</div><div>'+
    '<b>Append-only</b>Nothing in this log can be edited or deleted by any role, including this one. It lives outside the settlements, '+
    'so a deleted settlement still leaves its line here.</div></div></div>'+
    '<table><thead><tr><th>When</th><th>Event</th><th>Who</th></tr></thead>'+
    '<tbody>'+(rows||'<tr><td colspan="3" class="empty">Nothing logged yet.</td></tr>')+'</tbody></table>';
}

/* ====================================================================== */
/*  MODALS                                                                */
/* ====================================================================== */
function ask(title, body, okLabel, okAct, extra){
  modal(title, body,
    '<button class="btn" data-act="closemodal">Cancel</button>'+
    '<button class="btn '+(extra&&extra.danger?"danger":"primary")+'" data-act="'+okAct+'"'+
    (extra&&extra.data?extra.data:"")+'>'+okLabel+'</button>');
}
function vendorOptions(sel){
  return S.vendors.map(function(v){
    return '<option value="'+v.id+'"'+(sel===v.id?" selected":"")+'>'+esc(v.name)+'</option>'; }).join("");
}
function headOptionsForStatement(sel){
  var v = curVer(S.stmt);
  var o = (v.lines||[]).map(function(l){
    return '<option value="head|'+esc(l.head_key)+'|'+esc(l.head_label)+'"'+
      (sel===l.head_key?" selected":"")+'>'+esc(l.head_label)+'</option>'; }).join("");
  var a = (v.adjustments||[]).map(function(x){
    return '<option value="adjustment|'+esc(x.id)+'|'+esc(x.label)+'"'+
      (sel===x.id?" selected":"")+'>'+esc(x.label)+' (adjustment)</option>'; }).join("");
  return '<optgroup label="Booking heads">'+o+'</optgroup>'+(a?'<optgroup label="Adjustments">'+a+'</optgroup>':'');
}

/* ====================================================================== */
/*  EVENTS                                                                */
/* ====================================================================== */
document.addEventListener("click", async function(e){
  var el = e.target.closest ? e.target.closest("[data-act]") : null;
  if(!el) return;
  var a = el.getAttribute("data-act");
  var D = function(k){ return el.getAttribute("data-"+k); };

  if(a==="mdlstop") return;
  if(a==="ovl" || a==="closemodal"){ closeModal(); return; }
  if(a==="print"){ window.print(); return; }
  if(a==="back"){ e.preventDefault(); S.open=null; S.stmt=null; S.draft=null; window.scrollTo(0,0); render(); return; }
  if(a==="tab"){ S.tab = D("v"); render(); return; }
  if(a==="atab"){ S.adminTab = D("v"); render(); return; }
  if(a==="open"){ e.preventDefault(); await openStatement(D("id")); return; }

  /* ---- auth ---- */
  if(a==="signin" || a==="signup-first" || a==="signup-invited"){
    var email = val("g-email"), pass = val("g-pass");
    if(!email || !pass){ S.err="Enter your email and password."; return viewSignIn(a==="signup-first"); }
    busy(true, "signing in...");
    try{
      var r;
      if(a==="signin") r = await SB.auth.signInWithPassword({email:email, password:pass});
      else r = await SB.auth.signUp({email:email, password:pass,
             options:{ data:{ full_name: val("g-name") || "" } }});
      if(r.error) throw r.error;
      S.err = null;
      await boot();
    }catch(err){
      S.err = friendly(err);
      viewSignIn(a==="signup-first");
    } finally { busy(false); }
    return;
  }
  if(a==="signout"){ await SB.auth.signOut(); location.reload(); return; }
  if(a==="period"){ return; }

  /* ---- draft editing ---- */
  if(a==="adj-add"){
    var t0 = S.adjTypes[0]||{label:"Other Adjustment", effect:"deduct"};
    S.draft.adj.push({label:t0.label, effect:t0.effect, amount:0, reference:"", note:""});
    render(); return;
  }
  if(a==="adj-del"){ S.draft.adj.splice(Number(D("i")),1); render(); return; }
  if(a==="savedraft"){
    var lines = {};
    Object.keys(S.draft.lines).forEach(function(k){ lines[k] = S.draft.lines[k]; });
    var r = await call("vs_save_draft", {
      p_stmt:S.open, p_gross:S.draft.gross, p_gross_note:S.draft.note,
      p_lines:lines, p_adj:S.draft.adj }, "Draft saved", "saving...");
    if(r.ok) await refresh(true);
    return;
  }

  /* ---- statement flow ---- */
  if(a==="share"){
    var st = S.stmt;
    ask("Share with the vendor",
      '<div class="decl">Once you share, <b>version '+curVer(st).v+' freezes permanently</b>. Nobody can edit it afterwards - '+
      'not you, not Accounts, not an administrator. Corrections go out as a new version with a visible list of what changed.<br><br>'+
      esc(st.vendor.name)+' will be able to approve '+inr(curVer(st).final)+' or raise a point on any line.</div>',
      "Share it", "share-go");
    return;
  }
  if(a==="share-go"){
    closeModal();
    var r2 = await call("vs_share", {p_stmt:S.open}, "Shared - this version is now frozen", "sharing...");
    if(r2.ok) await refresh(true);
    return;
  }
  if(a==="remind"){
    var r3 = await call("vs_remind", {p_stmt:S.open}, "Reminder sent, and logged");
    if(r3.ok) await refresh(true);
    return;
  }
  if(a==="postpayroll"){
    var p = {
      dh_pay:num("dh_pay"), dh_heads:num("dh_heads"), dh_pf_ee:num("dh_pf_ee"), dh_pf_er:num("dh_pf_er"),
      dh_esic_ee:num("dh_esic_ee"), dh_esic_er:num("dh_esic_er"),
      stf_pay:num("stf_pay"), stf_heads:num("stf_heads"), stf_pf_ee:num("stf_pf_ee"), stf_pf_er:num("stf_pf_er"),
      stf_esic_ee:num("stf_esic_ee"), stf_esic_er:num("stf_esic_er"),
      pf_trrn:val("pf_trrn"), pf_paid_on:val("pf_paid_on"),
      esic_challan:val("esic_challan"), esic_paid_on:val("esic_paid_on"),
      processed_on:val("processed_on"),
      not_processed_amount:num("not_processed_amount"),
      not_processed_reason:val("not_processed_reason")
    };
    var r4 = await call("vs_post_payroll", {p_stmt:S.open, p:p}, null, "posting payroll...");
    if(r4.ok){
      toast(r4.data==="parked" ? "Correction posted - the vendor manager must issue a new version"
           : r4.data==="nochange" ? "Re-posted, no figure changed"
           : "Payroll posted - the statement can now be shared");
      await refresh(true);
    }
    return;
  }

  /* ---- points ---- */
  if(a==="raise"){
    var key = D("key")||"", kind = D("kind")||"head", label = D("label")||"";
    var vv = curVer(S.stmt), our = 0;
    if(kind==="head") (vv.lines||[]).forEach(function(l){ if(l.head_key===key) our=Number(l.amount)||0; });
    else (vv.adjustments||[]).forEach(function(x){ if(x.id===key) our=Number(x.amount)||0; });
    modal("Raise a point",
      '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#9432;</div><div>'+
      'Pick the exact line you disagree with. A point tied to a line can be checked and closed. A general complaint cannot.</div></div>'+
      '<div class="fld"><label class="fl">Which line?</label><select class="inp" id="q-target">'+
        headOptionsForStatement(key)+'</select></div>'+
      '<div class="fld"><label class="fl">Your figure (optional)</label><input class="inp num" id="q-claim" placeholder="leave blank if you only want an explanation"></div>'+
      '<div class="fld"><label class="fl">What is the issue?</label><textarea class="inp" id="q-note" '+
        'placeholder="Be specific - dates, vehicle numbers, bill numbers."></textarea></div>'+
      '<div class="fld"><label class="fl">Attach proof (file name or reference, optional)</label>'+
        '<input class="inp" id="q-att" placeholder="e.g. workshop-bill-4417.pdf"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="raise-go">Submit point</button>');
    return;
  }
  if(a==="raise-go"){
    var tv = (val("q-target")||"").split("|");
    var claim = val("q-claim").replace(/[^0-9.\-]/g,"");
    var r5 = await call("vs_raise_point", {
      p_stmt:S.open, p_kind:tv[0], p_key:tv[1]||"", p_label:tv[2]||"",
      p_claimed: claim===""?null:Number(claim), p_note:val("q-note"), p_attach:val("q-att")
    }, "Point recorded - WeVois notified", "saving...");
    if(r5.ok){ closeModal(); S.tab="points"; await refresh(true); }
    return;
  }
  if(a==="logcall"){
    modal("Log a point the vendor made on a call",
      '<div class="banner b-violet" style="margin-bottom:16px"><div class="ico">&#9742;</div><div>'+
      '<b>This is the piece that closes the gap</b>Write down what he said while you are still on the call. '+
      'He then gets it back to confirm. After that neither of you can say it was never raised - or that it was raised when it was not.</div></div>'+
      '<div class="fld"><label class="fl">Which line did he talk about?</label><select class="inp" id="c-target">'+
        headOptionsForStatement(D("key")||"")+'</select></div>'+
      '<div class="fld"><label class="fl">His figure, if he gave one</label><input class="inp num" id="c-claim"></div>'+
      '<div class="fld"><label class="fl">What exactly did he say?</label>'+
        '<textarea class="inp" id="c-note" placeholder="In his words as far as possible."></textarea></div>'+
      '<div class="decl">On saving, the vendor is sent this text and must confirm it. Until he confirms, the point sits as '+
      '<b>Awaiting confirmation</b>.</div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="logcall-go">Save &amp; send for confirmation</button>');
    return;
  }
  if(a==="logcall-go"){
    var tv2 = (val("c-target")||"").split("|");
    var claim2 = val("c-claim").replace(/[^0-9.\-]/g,"");
    var r6 = await call("vs_log_call_point", {
      p_stmt:S.open, p_kind:tv2[0], p_key:tv2[1]||"", p_label:tv2[2]||"",
      p_claimed: claim2===""?null:Number(claim2), p_note:val("c-note")
    }, "Logged and sent to the vendor to confirm", "saving...");
    if(r6.ok){ closeModal(); S.tab="points"; await refresh(true); }
    return;
  }
  if(a==="confirmcall" || a==="denycall"){
    var r7 = await call("vs_confirm_call_point", {p_point:D("pid"), p_ok:(a==="confirmcall")},
      a==="confirmcall" ? "Confirmed - now an open point on record"
                        : "Recorded - the disagreement itself is now on record");
    if(r7.ok) await refresh(true);
    return;
  }
  if(a==="resolve"){
    var our2 = Number(D("our"))||0, claimed = D("claimed");
    modal("Resolve - "+esc(D("label")),
      '<div class="pt-body" style="margin-bottom:14px">&ldquo;'+esc(D("note"))+'&rdquo;'+
      '<div class="pt-figs"><div>Our figure<b>'+inr(our2)+'</b></div>'+
      (claimed!==""?'<div>He says<b>'+inr(claimed)+'</b></div>':'')+'</div></div>'+
      (D("kind")==="head" ? '<div class="banner b-teal" style="margin:0 0 14px"><div class="ico">&#9203;</div><div>'+
        'If this is a payroll head you cannot change the figure yourself &mdash; accepting means Accounts posts a correction, '+
        'which then goes out as a new version.</div></div>' : '')+
      '<label class="radio"><input type="radio" name="dec" value="accepted" checked>'+
        '<span><span class="t">Accept his figure</span><span class="d">Amount becomes '+inr(claimed!==""?claimed:our2)+'</span></span></label>'+
      '<label class="radio"><input type="radio" name="dec" value="partial">'+
        '<span><span class="t">Partly accept &mdash; set a different figure</span><span class="d">You decide the number below</span></span></label>'+
      '<label class="radio"><input type="radio" name="dec" value="rejected">'+
        '<span><span class="t">Reject, with reason</span><span class="d">Figure stays at '+inr(our2)+'. Your reason goes to him in writing.</span></span></label>'+
      '<label class="radio"><input type="radio" name="dec" value="carry_forward">'+
        '<span><span class="t">Carry forward to next month</span><span class="d">It stays open and reappears until closed.</span></span></label>'+
      '<div class="fld" style="margin-top:14px"><label class="fl">Revised amount</label>'+
        '<input class="inp num" id="r-amt" value="'+(claimed!==""?claimed:our2)+'">'+
        '<div class="hint">Used for Accept and Partly accept.</div></div>'+
      '<div class="fld"><label class="fl">Your reason &mdash; he sees this word for word</label>'+
        '<textarea class="inp" id="r-note" placeholder="What you checked, against what, and the conclusion."></textarea></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="resolve-go" data-pid="'+D("pid")+'">Save decision</button>');
    return;
  }
  if(a==="resolve-go"){
    var radios = document.getElementsByName("dec"), dec = "accepted";
    for(var i=0;i<radios.length;i++) if(radios[i].checked) dec = radios[i].value;
    var r8 = await call("vs_resolve_point", {
      p_point:D("pid"), p_decision:dec,
      p_amount:(dec==="accepted"||dec==="partial")?num("r-amt"):null,
      p_reason:val("r-note")
    }, "Decision saved - issue a revised statement to send it", "saving...");
    if(r8.ok){ closeModal(); await refresh(true); }
    return;
  }
  if(a==="revise"){
    var r9 = await call("vs_issue_revision", {p_stmt:S.open}, null, "issuing...");
    if(r9.ok){ toast("Version "+r9.data+" sent - the previous version stays on record, untouched"); S.tab="versions"; await refresh(true); }
    return;
  }

  /* ---- approval ---- */
  if(a==="approve"){
    var stA = S.stmt, vA = curVer(stA);
    var cf = (stA.points||[]).filter(function(p){ return p.status==="carry_forward"; });
    modal("Approve "+esc(stA.period_label),
      '<div class="decl">I, <b>'+esc(S.profile.full_name||S.profile.email)+'</b> of <b>'+esc(stA.vendor.name)+'</b>, approve '+
      '<b>'+inr(vA.final)+'</b> as the full and final amount payable to me for <b>'+esc(stA.site.name)+', '+esc(stA.period_label)+'</b>, '+
      'against version '+vA.v+' shared on '+dt(vA.sent_at)+'. I confirm I have checked every head, including the processed salary and '+
      'the PF/ESIC challans shown on the Payroll tab, and have no further claim for this month other than any point marked as carried forward.</div>'+
      (cf.length?'<div class="banner b-blue" style="margin:14px 0 0"><div class="ico">&#8618;</div><div>'+
        '<b>Except '+cf.length+' carried-forward point'+(cf.length===1?"":"s")+'</b>Your approval does not close them. '+
        'They stay open and appear again next month.</div></div>':'')+
      '<div class="hint" style="margin-top:14px">Your name, the exact figures, the version number and the time are stamped on this '+
      'approval and cannot be changed afterwards by anybody, including WeVois.</div>',
      '<button class="btn" data-act="closemodal">Not yet</button>'+
      '<button class="btn go" data-act="approve-go">I approve '+inr(vA.final)+'</button>');
    return;
  }
  if(a==="approve-go"){
    var rA = await call("vs_approve", {p_stmt:S.open}, null, "approving...");
    if(rA.ok){ closeModal(); toast("Approved "+inr(rA.data)+" - snapshot locked, now with Accounts"); S.tab="record"; await refresh(true); }
    return;
  }

  /* ---- payment ---- */
  if(a==="pay"){
    var stP = S.stmt;
    var bal = Number(stP.statement.approved_amount||0) - Number(stP.paid_total||0);
    modal("Release a payment",
      '<div class="banner b-green" style="margin-bottom:16px"><div class="ico">&#10003;</div><div>'+
      'Approved '+inr(stP.statement.approved_amount)+' (version '+stP.statement.approved_version+') by '+
      esc(stP.statement.approved_by||"")+'. Paid so far '+inr(stP.paid_total)+
      '. <b>Balance '+inr(bal)+'</b>.</div></div>'+
      '<div class="fld"><label class="fl">Amount</label><input class="inp num" id="p-amt" value="'+bal+'">'+
        '<div class="hint">Pay it in full, or enter part of it. The balance stays visible until it clears.</div></div>'+
      '<div class="fld"><label class="fl">UTR / reference</label><input class="inp" id="p-utr" placeholder="e.g. HDFC0X4471822"></div>'+
      '<div class="fld"><label class="fl">Date</label><input class="inp" id="p-date" type="date" value="'+
        new Date().toISOString().slice(0,10)+'"></div>'+
      '<div class="fld"><label class="fl">Mode</label><input class="inp" id="p-mode" value="NEFT"></div>'+
      '<div class="fld"><label class="fl">Note (optional)</label><input class="inp" id="p-note" placeholder="e.g. first tranche"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn go" data-act="pay-go">Release payment</button>');
    return;
  }
  if(a==="pay-go"){
    var rP = await call("vs_record_payment", {
      p_stmt:S.open, p_amount:num("p-amt"), p_on:val("p-date"),
      p_utr:val("p-utr"), p_mode:val("p-mode"), p_note:val("p-note")
    }, null, "recording payment...");
    if(rP.ok){
      closeModal();
      toast(Number(rP.data)<=0.005 ? "Paid in full - month closed" : "Part payment recorded. Balance "+inr(rP.data));
      S.tab="payments"; await refresh(true);
    }
    return;
  }

  /* ---- admin: people ---- */
  if(a==="invite"){
    modal("Invite someone",
      '<div class="fld"><label class="fl">Full name</label><input class="inp" id="i-name"></div>'+
      '<div class="fld"><label class="fl">Email</label><input class="inp" id="i-email" type="email"></div>'+
      '<div class="fld"><label class="fl">Role</label><select class="inp" id="i-role">'+
        ROLE_ORDER.map(function(r){ return '<option value="'+r+'">'+esc(ROLE_LABEL[r])+' &mdash; '+esc(ROLE_NOTE[r])+'</option>'; }).join("")+
        '</select></div>'+
      '<div class="fld"><label class="fl">If a vendor login, which vendor?</label>'+
        '<select class="inp" id="i-vendor"><option value="">— not a vendor login —</option>'+vendorOptions()+'</select></div>'+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'They set their own password by choosing <b>Set my password</b> on the sign-in screen with this exact email. '+
      'Until they do, and until this invite exists, that account can see nothing at all.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="invite-go">Send invitation</button>');
    return;
  }
  if(a==="invite-go"){
    var vend = val("i-vendor");
    var rI = await call("vs_invite", {p_email:val("i-email"), p_name:val("i-name"),
      p_role:val("i-role"), p_vendor: vend||null}, "Invited", "saving...");
    if(rI.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="edituser"){
    modal("Change role - "+esc(D("name")),
      '<div class="fld"><label class="fl">Role</label><select class="inp" id="u-role">'+
      ROLE_ORDER.map(function(r){
        return '<option value="'+r+'"'+(D("role")===r?" selected":"")+'>'+esc(ROLE_LABEL[r])+' &mdash; '+esc(ROLE_NOTE[r])+'</option>'; }).join("")+
      '</select></div>'+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'A role change takes effect the next time the person signs in. Everything they did under the old role stays on the record '+
      'under that role.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="edituser-go" data-uid="'+D("uid")+'">Save</button>');
    return;
  }
  if(a==="edituser-go"){
    var rU = await call("vs_set_role", {p_profile:D("uid"), p_role:val("u-role")}, "Role changed");
    if(rU.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="toggleuser"){
    var rT = await call("vs_set_active", {p_profile:D("uid"), p_active: D("on")==="1"}, "Saved");
    if(rT.ok) await refresh(false);
    return;
  }

  /* ---- admin: vendors, sites, tenures ---- */
  if(a==="addvendor"){
    modal("Add a vendor",
      '<div class="fld"><label class="fl">Name</label><input class="inp" id="v-name" placeholder="e.g. Heera Ram ji"></div>'+
      '<div class="fld"><label class="fl">Short code (optional)</label><input class="inp" id="v-code" placeholder="OP-01"></div>'+
      '<div class="fld"><label class="fl">Contact person</label><input class="inp" id="v-contact"></div>'+
      '<div class="fld"><label class="fl">Email</label><input class="inp" id="v-email" type="email"></div>'+
      '<div class="fld"><label class="fl">Mobile</label><input class="inp" id="v-phone"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="addvendor-go">Add vendor</button>');
    return;
  }
  if(a==="addvendor-go"){
    var rV = await call("vs_add_vendor", {p_name:val("v-name"), p_code:val("v-code"),
      p_contact:val("v-contact"), p_email:val("v-email"), p_phone:val("v-phone")}, "Vendor added");
    if(rV.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="addsite"){
    modal("Add a site",
      '<div class="fld"><label class="fl">Site name</label><input class="inp" id="s-name" placeholder="e.g. Kuchaman"></div>'+
      '<div class="fld"><label class="fl">City / district</label><input class="inp" id="s-city"></div>'+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'A new site starts with the standard booking heads. Edit them on the <b>Booking heads</b> tab to match how that site actually bills.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="addsite-go">Add site</button>');
    return;
  }
  if(a==="addsite-go"){
    var rS = await call("vs_add_site", {p_name:val("s-name"), p_city:val("s-city")}, "Site added");
    if(rS.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="assign" || a==="changevendor"){
    var isChange = (a==="changevendor");
    modal((isChange?"Change the vendor at ":"Assign a vendor to ")+esc(D("sname")),
      (isChange?'<div class="banner b-amber" style="margin-bottom:16px"><div class="ico">&#8618;</div><div>'+
        '<b>The handover does not have to fall on the 1st</b>Give the exact day the new partner takes over. The outgoing tenure ends '+
        'the day before, and that month produces two settlements for this site &mdash; one for each vendor, each covering only its own days.</div></div>':'')+
      '<div class="fld"><label class="fl">'+(isChange?"New vendor":"Vendor")+'</label>'+
        '<select class="inp" id="c-vendor">'+vendorOptions()+'</select></div>'+
      '<div class="fld"><label class="fl">Vehicles on this contract</label><input class="inp num" id="c-veh" value="10"></div>'+
      '<div class="fld"><label class="fl">'+(isChange?"Takes over on":"Starts from")+'</label>'+
        '<input class="inp" id="c-from" type="date" value="'+new Date().toISOString().slice(0,10)+'"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="'+(isChange?"changevendor-go":"assign-go")+'" data-sid="'+D("sid")+'">'+
      (isChange?"Hand over":"Assign")+'</button>');
    return;
  }
  if(a==="assign-go"){
    var rC = await call("vs_add_contract", {p_vendor:val("c-vendor"), p_site:D("sid"),
      p_vehicles:num("c-veh"), p_from:val("c-from"), p_to:null}, "Assigned");
    if(rC.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="changevendor-go"){
    var rCV = await call("vs_change_vendor", {p_site:D("sid"), p_new_vendor:val("c-vendor"),
      p_vehicles:num("c-veh"), p_from:val("c-from")}, "Handover recorded");
    if(rCV.ok){ closeModal(); await refresh(false); }
    return;
  }

  /* ---- admin: settlements ---- */
  if(a==="openmonth"){
    var rOM = await call("vs_open_month", {p_period:S.period}, null, "opening the month...");
    if(rOM.ok){
      toast(Number(rOM.data)>0 ? rOM.data+" settlement"+(rOM.data==1?"":"s")+" created"
                               : "Every running contract already has one");
      await refresh(false);
    }
    return;
  }
  if(a==="addsettle"){
    var copts = S.contracts.map(function(c){
      return '<option value="'+c.id+'">'+esc(contractLabel(c))+' &mdash; '+c.vehicles+' vehicles ('+
        dOnly(c.from_date)+' to '+(c.to_date?dOnly(c.to_date):"current")+')</option>'; }).join("");
    modal("Add a settlement",
      '<div class="fld"><label class="fl">Vendor &amp; site</label><select class="inp" id="ns-c">'+copts+'</select>'+
        '<div class="hint">One settlement per vendor-site pairing per month.</div></div>'+
      '<div class="fld"><label class="fl">Month</label><input class="inp" id="ns-p" type="month" value="'+
        S.period.slice(0,7)+'"></div>'+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'It is created as an empty draft. Accounts posts the payroll and the vendor manager fills the rest before it can go out.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="addsettle-go">Create settlement</button>');
    return;
  }
  if(a==="addsettle-go"){
    var rAS = await call("vs_add_statement", {p_contract:val("ns-c"), p_period:val("ns-p")+"-01"}, "Created");
    if(rAS.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="askdel"){
    var paid = Number(D("paid"))||0, status = D("status");
    var hot = (["approved","part_paid","paid"].indexOf(status)>=0);
    modal("Delete this settlement",
      (hot?'<div class="banner b-amber" style="margin:0 0 14px"><div class="ico">&#9888;</div><div>'+
        '<b>This one has been '+(paid>0?"paid":"approved by the vendor")+'</b>'+
        'The signed approval'+(paid>0?' and '+inr(paid)+' of payment record':'')+' will be destroyed with it. '+
        'This is the record you would need if the vendor ever disputes this month.</div></div>':'')+
      '<div class="decl">You are about to permanently delete <b>'+esc(D("desc"))+'</b>.<br><br>'+
      'This removes <b>'+D("v")+' version'+(D("v")=="1"?"":"s")+'</b>, <b>'+D("p")+' point'+(D("p")=="1"?"":"s")+
      '</b> with their decisions and reasons, <b>'+D("e")+' record entries</b>, the payroll posting'+
      (hot?', the signed approval':'')+(paid>0?', and the payment record':'')+'. It cannot be undone.<br><br>'+
      'A line naming you, the time and your reason stays in the audit log. Nothing else survives.</div>'+
      '<div class="fld" style="margin-top:14px"><label class="fl">Why are you deleting it?</label>'+
        '<textarea class="inp" id="del-why" placeholder="e.g. opened against the wrong site"></textarea></div>'+
      '<div class="fld"><label class="fl">Type DELETE to confirm</label><input class="inp" id="del-ok" placeholder="DELETE"></div>',
      '<button class="btn" data-act="closemodal">Keep it</button>'+
      '<button class="btn danger" data-act="del-go" data-id="'+D("id")+'">Delete permanently</button>');
    return;
  }
  if(a==="del-go"){
    if(val("del-ok") !== "DELETE"){ toast("Type DELETE in capitals to confirm"); return; }
    var rD = await call("vs_delete_statement", {p_stmt:D("id"), p_reason:val("del-why")},
      "Deleted - only the audit line remains");
    if(rD.ok){ closeModal(); if(S.open===D("id")){ S.open=null; S.stmt=null; } await refresh(false); }
    return;
  }

  /* ---- admin: masters ---- */
  if(a==="saverules"){
    var rR = await call("vs_save_settings", {p_days:num("ru-days"),
      p_deemed: val("ru-deemed")==="1", p_var:num("ru-var")}, "Rules saved");
    if(rR.ok) await refresh(false);
    return;
  }
  if(a==="addhead"){
    modal("Add a booking head to "+esc(D("sname")),
      '<div class="fld"><label class="fl">Label &mdash; exactly as it reads on your sheet</label>'+
        '<input class="inp" id="h-label" placeholder="e.g. Vehicle Rent of 5 Tractor"></div>'+
      '<div class="fld"><label class="fl">Short key (letters and underscores)</label>'+
        '<input class="inp" id="h-key" placeholder="tractor_rent"></div>'+
      '<div class="fld"><label class="fl">Group</label><select class="inp" id="h-grp">'+
        '<option value="run">Vehicle &amp; running</option><option value="wages">Driver / helper</option>'+
        '<option value="staff">Staff</option><option value="esic">ESIC / PF</option><option value="other">Other</option></select></div>'+
      '<div class="fld"><label class="fl">Who enters it?</label><select class="inp" id="h-src">'+
        '<option value="manual">Vendor Manager types it</option>'+
        '<option value="payroll">Derived from the Accounts payroll posting</option></select></div>'+
      '<div class="fld"><label class="fl">Sort order</label><input class="inp num" id="h-sort" value="900"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="addhead-go" data-sid="'+D("sid")+'">Add head</button>');
    return;
  }
  if(a==="addhead-go"){
    var rH = await call("vs_add_head", {p_site:D("sid"), p_key:val("h-key"), p_label:val("h-label"),
      p_grp:val("h-grp"), p_src:val("h-src"), p_sort:num("h-sort")}, "Head added");
    if(rH.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="edithead"){
    modal("Edit booking head",
      '<div class="fld"><label class="fl">Label</label><input class="inp" id="eh-label" value="'+esc(D("label"))+'"></div>'+
      '<div class="fld"><label class="fl">Sort order</label><input class="inp num" id="eh-sort" value="'+D("sort")+'"></div>'+
      '<div class="fld"><label class="fl">Active</label><select class="inp" id="eh-on">'+
        '<option value="1"'+(D("on")==="1"?" selected":"")+'>Yes</option>'+
        '<option value="0"'+(D("on")==="0"?" selected":"")+'>No - hide from new statements</option></select></div>'+
      '<div class="hint">Statements already shared keep the label they were shared with.</div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="edithead-go" data-hid="'+D("hid")+'">Save</button>');
    return;
  }
  if(a==="edithead-go"){
    var rEH = await call("vs_set_head", {p_head:D("hid"), p_label:val("eh-label"),
      p_sort:num("eh-sort"), p_active: val("eh-on")==="1"}, "Saved");
    if(rEH.ok){ closeModal(); await refresh(false); }
    return;
  }
  if(a==="addadj"){
    modal("Add an adjustment type",
      '<div class="fld"><label class="fl">Label</label><input class="inp" id="at-label" placeholder="e.g. Marriage Vehicle Charge"></div>'+
      '<div class="fld"><label class="fl">Effect on the final amount</label><select class="inp" id="at-eff">'+
        '<option value="deduct">Deduct &mdash; reduces what we pay him</option>'+
        '<option value="add">Add &mdash; credits him</option>'+
        '<option value="note">Note only &mdash; shown on the statement, does not change the figure</option></select></div>'+
      '<div class="fld"><label class="fl">Require a reference?</label><select class="inp" id="at-ref">'+
        '<option value="0">No</option><option value="1">Yes - UTR, date or bill number</option></select></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="addadj-go">Add type</button>');
    return;
  }
  if(a==="addadj-go"){
    var rAT = await call("vs_add_adj_type", {p_label:val("at-label"), p_effect:val("at-eff"),
      p_needs_ref: val("at-ref")==="1"}, "Adjustment type added");
    if(rAT.ok){ closeModal(); await refresh(false); }
    return;
  }
});

/* ---- live edits that must not re-render on every keystroke ---- */
document.addEventListener("input", function(e){
  var el = e.target.closest ? e.target.closest("[data-act]") : null;
  if(!el) return;
  var a = el.getAttribute("data-act");
  if(a==="draft" && S.draft){
    var k = el.getAttribute("data-k");
    if(k==="__gross") S.draft.gross = Number(String(el.value).replace(/[^0-9.\-]/g,"")||0);
    else if(k==="__note") S.draft.note = el.value;
    else S.draft.lines[k] = Number(String(el.value).replace(/[^0-9.\-]/g,"")||0);
  }
  if(a==="adjf" && S.draft){
    var i = Number(el.getAttribute("data-i")), f = el.getAttribute("data-f");
    if(!S.draft.adj[i]) return;
    S.draft.adj[i][f] = (f==="amount") ? Number(String(el.value).replace(/[^0-9.\-]/g,"")||0) : el.value;
  }
});
document.addEventListener("change", async function(e){
  var el = e.target.closest ? e.target.closest("[data-act]") : null;
  if(!el) return;
  var a = el.getAttribute("data-act");
  if(a==="period"){ S.period = el.value; S.open=null; S.stmt=null; render(); return; }
  if(a==="adjf" && S.draft && el.getAttribute("data-f")==="label"){
    var i = Number(el.getAttribute("data-i"));
    var opt = el.options[el.selectedIndex];
    var eff = opt && opt.getAttribute("data-eff");
    if(eff && S.draft.adj[i]) { S.draft.adj[i].effect = eff; render(); }
    return;
  }
});

/* ====================================================================== */
/*  BOOT                                                                  */
/* ====================================================================== */
async function boot(){
  var sess = await SB.auth.getSession();
  S.user = sess.data && sess.data.session ? sess.data.session.user : null;

  if(!S.user){
    var ns = false;
    try{ var r = await SB.rpc("vs_needs_setup"); ns = !!r.data; }catch(e){}
    return viewSignIn(ns);
  }
  var pr = await SB.from("vs_profiles").select("*").eq("id", S.user.id).limit(1);
  if(!pr.data || !pr.data.length){ S.profile = null; return viewNoProfile(); }
  S.profile = pr.data[0];
  if(!S.profile.active){ S.profile = null; return viewNoProfile(); }

  var cp = await SB.from("vs_caps").select("cap").eq("role", S.profile.role);
  S.caps = (cp.data||[]).map(function(x){ return x.cap; });

  await loadAll();
  render();

  /* keep the screen honest while somebody else is working on the same month */
  try{
    SB.channel("vs-live")
      .on("postgres_changes", {event:"*", schema:"public", table:"vs_statements"}, scheduleRefresh)
      .on("postgres_changes", {event:"*", schema:"public", table:"vs_points"},     scheduleRefresh)
      .on("postgres_changes", {event:"*", schema:"public", table:"vs_versions"},   scheduleRefresh)
      .on("postgres_changes", {event:"*", schema:"public", table:"vs_payments"},   scheduleRefresh)
      .on("postgres_changes", {event:"*", schema:"public", table:"vs_payroll"},    scheduleRefresh)
      .subscribe();
  }catch(e){}
}
var _rt = null;
function scheduleRefresh(){
  if(document.getElementById("modal").innerHTML) return;   /* never yank a form away mid-typing */
  if(S.draft) return;
  clearTimeout(_rt);
  _rt = setTimeout(function(){ refresh(true); }, 1200);
}

(function start(){
  var url = window.VS_URL || "", key = window.VS_ANON || "";
  if(!url || !key || url.indexOf("PASTE_") === 0 || key.indexOf("PASTE_") === 0) return viewConfigNeeded();
  if(!window.supabase || !window.supabase.createClient){
    return gate('<h1>Could not load the Supabase library</h1><p class="sub">Check the internet connection and reload.</p>');
  }
  SB = window.supabase.createClient(url, key);
  boot().catch(function(e){
    gate('<div class="err">'+esc(friendly(e))+'</div><h1>Something went wrong starting up</h1>'+
      '<p class="sub">Reload the page. If it keeps happening, check that VS-SETUP.sql ran completely.</p>');
  });
})();
