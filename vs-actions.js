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
  ["Attach payroll / PF / ESIC files", "attach_docs"],
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
  manager:["view_all","edit_draft","share","logcall","resolve","revise","remind","pay","post_payroll"],
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
    ["matrix","Who can do what"],["mail","Mail"],["audit","Audit log"]
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
    : t==="mail"    ? adminMail()
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
        '<button class="btn sm" data-act="sendreset" data-email="'+esc(u.email)+'">Reset password</button> '+
        '<button class="btn sm" data-act="toggleuser" data-uid="'+u.id+'" data-on="'+(u.active?"0":"1")+'">'+
        (u.active?"Deactivate":"Reactivate")+'</button></td></tr>';
  }).join("");
  var inv = S.invites.map(function(i){
    return '<tr><td>'+esc(i.full_name||"")+'<div style="font-size:12px;color:var(--muted)">'+esc(i.email)+'</div></td>'+
      '<td><span class="chip c-grey">'+esc(ROLE_LABEL[i.role]||i.role)+'</span></td>'+
      '<td style="font-size:12.5px;color:var(--muted)">'+(i.vendor_id?esc(vendorName(i.vendor_id)):"&mdash;")+'</td>'+
      '<td style="font-size:12.5px;color:var(--muted)">invited '+dOnly(i.created_at)+'</td></tr>'; }).join("");

  return '<div class="card-b"><div class="banner b-violet" style="margin-bottom:0"><div class="ico">&#128273;</div><div>'+
    '<b>Admin is deliberately not a settlement actor</b>This account creates logins and sets roles. It cannot build a statement, '+
    'answer a point, approve, or move money. Someone who can hand out permissions should not also be able to use them.</div></div></div>'+
    '<table><thead><tr><th>Person</th><th>Role</th><th>Scope</th><th>Status</th>'+
    '<th class="num"><button class="btn sm primary" data-act="createlogin">Create a login</button></th></tr></thead>'+
    '<tbody>'+(rows||'<tr><td colspan="5" class="empty">No one yet.</td></tr>')+'</tbody></table>'+
    (inv ? '<div class="card-b" style="border-top:1px solid var(--line-2)">'+
      '<h3 style="font-size:14px;margin-bottom:4px">Started but not finished</h3>'+
      '<div class="hint">A role was reserved for these email addresses but the account was not created &mdash; usually because '+
      '<b>Create a login</b> was interrupted. Run it again with the same email and it will pick this up.</div></div>'+
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

function siteStatus(st){
  var today = new Date().toISOString().slice(0,10);
  if(st.close_date && String(st.close_date).slice(0,10) < today) return "closed";
  if(st.start_date && String(st.start_date).slice(0,10) > today) return "not_started";
  return "running";
}
var SITE_CHIP = {
  running:'<span class="chip c-green"><span class="d"></span>running</span>',
  closed:'<span class="chip c-grey"><span class="d"></span>closed</span>',
  not_started:'<span class="chip c-blue"><span class="d"></span>not started yet</span>'
};

function adminSites(){
  var rows = S.sites.map(function(st){
    var cs = contractsOfSite(st.id).sort(function(a,b){ return a.from_date < b.from_date ? -1 : 1; });
    var chain = cs.length ? cs.map(function(c){
      return '<div style="display:flex;align-items:center;gap:8px;margin:3px 0">'+
        '<div style="flex:1">'+esc(vendorName(c.vendor_id))+
          ' <span style="color:var(--muted)">'+dOnly(c.from_date)+' to '+(c.to_date?dOnly(c.to_date):"current")+
          ' &middot; '+c.vehicles+' vehicles</span>'+
          (c.to_date?'':' <span class="chip c-green"><span class="d"></span>running</span>')+'</div>'+
        '<button class="btn sm" data-act="edittenure" data-cid="'+c.id+'">Edit</button>'+
        (c.to_date?'<button class="btn sm" data-act="reopentenure" data-cid="'+c.id+'">Reopen</button>':'')+
        '</div>'; }).join("")
      : '<span style="color:var(--faint)">no vendor assigned</span>';
    var live = cs.filter(function(c){ return !c.to_date; })[0];
    var stat = siteStatus(st);
    var dates = (st.start_date? 'from '+dOnly(st.start_date) : 'no start date')+
                (st.close_date? ', closed '+dOnly(st.close_date) : '');
    return '<tr><td><b>'+esc(st.name)+'</b> '+SITE_CHIP[stat]+
      '<div style="font-size:12px;color:var(--muted)">'+esc(st.city||"")+'</div>'+
      '<div style="font-size:12px;color:var(--muted)">'+dates+'</div></td>'+
      '<td>'+chain+'</td>'+
      '<td class="num" style="white-space:nowrap">'+
        '<button class="btn sm" data-act="editsite" data-sid="'+st.id+'">Edit site</button> '+
        (live ? '<button class="btn sm" data-act="changevendor" data-sid="'+st.id+'" data-sname="'+esc(st.name)+'">Change vendor</button>'
              : (stat==="closed" ? ''
                 : '<button class="btn sm primary" data-act="assign" data-sid="'+st.id+'" data-sname="'+esc(st.name)+'">Assign a vendor</button>'))+
      '</td></tr>';
  }).join("");
  return '<div class="card-b"><div class="banner b-blue" style="margin-bottom:0"><div class="ico">&#128506;</div><div>'+
    '<b>A site can change hands mid-month</b>Use <b>Change vendor</b> and give the exact day the new partner takes over. '+
    'The outgoing tenure ends the day before, and that month produces two settlements for the site &mdash; one for each vendor, '+
    'each covering only its own days. Two vendors overlapping on one site is impossible, not merely discouraged.<br>'+
    '<b>A site has its own life</b>, separate from who runs it: the day WeVois started there and the day it closed. '+
    'A closed site cannot be assigned a vendor and no month can be opened for it. Everything already settled stays readable.</div></div></div>'+
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
    return '<tr class="grp-row"><td colspan="5">'+esc(st.name)+' &mdash; '+hs.length+' booking heads</td></tr>'+
      hs.map(function(h){
        return '<tr><td style="padding-left:26px">'+esc(h.label)+(h.active?'':' <span class="chip c-grey">off</span>')+'</td>'+
          '<td>'+(h.src==="payroll"?'<span class="chip c-teal"><span class="d"></span>From the payroll posting</span>'
                                   :'<span class="chip c-grey">Entered by Vendor Manager</span>')+'</td>'+
          '<td style="font-size:12.5px;color:var(--muted)">'+esc(h.grp)+'</td>'+
          '<td><span class="'+effClass(lineEff(h))+'">'+effWord(lineEff(h))+'</span></td>'+
          '<td class="num"><button class="btn sm" data-act="edithead" data-hid="'+h.id+'" data-label="'+esc(h.label)+'" '+
            'data-sort="'+h.sort+'" data-on="'+(h.active?"1":"0")+'" data-eff="'+esc(lineEff(h))+'" '+
            'data-src="'+esc(h.src)+'">Edit</button></td></tr>'; }).join("")+
      '<tr><td colspan="5" style="padding-left:26px"><button class="btn sm" data-act="addhead" data-sid="'+st.id+'" '+
        'data-sname="'+esc(st.name)+'">+ Add a head to '+esc(st.name)+'</button></td></tr>';
  }).join("");
  return '<div class="card-b"><div class="banner b-blue" style="margin-bottom:0"><div class="ico">&#9432;</div><div>'+
    '<b>Every site has its own heads</b>That is how your workbook already works &mdash; Chirawa splits R&amp;M into "by the partner" and '+
    '"by WeVois", Bundi has loader and tractor fuel and tractor rent, Jhunjhunu has parking rent, Sujalpur has water and building rent. '+
    'Renaming a head here never changes a statement a vendor has already approved; versions freeze the label as well as the figure.</div></div></div>'+
    '<table><thead><tr><th>Booking head</th><th>Source</th><th>Group</th><th>Effect on the amount</th><th></th></tr></thead>'+
    '<tbody>'+(out||'<tr><td colspan="5" class="empty">No sites yet.</td></tr>')+'</tbody></table>'+
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
      if(row[1]==="attach_docs" && r==="vendor")
        return '<td style="text-align:center;font-size:11.5px;color:var(--muted)">can open them</td>';
      /* attaching a file is not a capability of its own: whoever can fill the
         draft or post the payroll can attach the paperwork behind it */
      var has = row[1]==="attach_docs"
        ? (CAPS_BY_ROLE[r].indexOf("edit_draft")>=0 || CAPS_BY_ROLE[r].indexOf("post_payroll")>=0)
        : CAPS_BY_ROLE[r].indexOf(row[1])>=0;
      return '<td style="text-align:center" class="'+(has?"yes":"no")+'">'+(has?"&#10003;":"&middot;")+'</td>';
    }).join("")+'</tr>'; }).join("");
  return '<div class="card-b"><div class="banner b-grey" style="margin-bottom:0"><div class="ico">&#128737;</div><div>'+
    '<b>This is the design, and the database enforces it</b>Hiding a button is not security. Each of these is a row-level policy '+
    'or a check inside the function that performs the write, so an account that should not be able to do something cannot do it '+
    'even by calling the API directly.</div></div></div>'+
    '<table class="matrix"><thead>'+head+'</thead><tbody>'+body+'</tbody></table>';
}

function adminMail(){
  var s = S.settings || {};
  var ready = !!(s.mail_from||"").trim();
  var rows = (S.mail||[]).map(function(m){
    var chip = m.status==="sent"  ? '<span class="chip c-green"><span class="d"></span>sent</span>'
             : m.status==="failed"? '<span class="chip c-red"><span class="d"></span>failed</span>'
             : m.status==="skipped"?'<span class="chip c-grey"><span class="d"></span>not sent - notifications off</span>'
             :                      '<span class="chip c-amber"><span class="d"></span>waiting</span>';
    return '<tr><td><b>'+esc(m.to_name||m.to_email)+'</b>'+
      '<div style="font-size:12px;color:var(--muted)">'+esc(m.to_email)+
      (m.to_role?' &middot; '+esc(ROLE_LABEL[m.to_role]||m.to_role):'')+'</div></td>'+
      '<td style="font-size:13px">'+esc(m.subject)+
        (m.error?'<div style="font-size:12px;color:var(--red)">'+esc(m.error)+'</div>':'')+'</td>'+
      '<td>'+chip+'</td>'+
      '<td style="font-size:12px;color:var(--muted);white-space:nowrap">'+dt(m.sent_at||m.created_at)+'</td></tr>';
  }).join("");

  return '<div class="card-b">'+
    (ready?'':'<div class="banner b-amber" style="margin-bottom:16px"><div class="ico">&#9888;</div><div>'+
      '<b>No sending address yet</b>Messages are being written down but nothing is going out. '+
      'Fill in the address below and follow <b>SETUP-MAIL.md</b> to deploy the sender. Nothing already queued is lost.'+
      '</div></div>')+
    '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#9993;</div><div>'+
    '<b>Who is told, and when</b>'+
    'Sharing a month, or issuing a revised version, emails that site&rsquo;s vendor and both observers. '+
    'The vendor only ever hears about his own sites; the CEO and the VP hear about all of them. '+
    'Asking for a confirmation emails the CEO and the VP. '+
    'The portal writes every message down whether or not it can send it, so nothing is ever silently dropped.'+
    '</div></div>'+
    '<div class="grid2">'+
      '<div class="fld"><label class="fl">From address</label>'+
        '<input class="inp" id="m-from" value="'+esc(s.mail_from||"")+'" placeholder="himanshu.wevois104@gmail.com">'+
        '<div class="hint">The same mailbox the sender signs in as. Sending as an address you do not own gets mail marked as spam.</div></div>'+
      '<div class="fld"><label class="fl">From name</label>'+
        '<input class="inp" id="m-name" value="'+esc(s.mail_from_nm||"WeVois Vendor Settlement")+'"></div>'+
    '</div>'+
    '<div class="fld"><label class="fl">Address of this portal</label>'+
      '<input class="inp" id="m-url" value="'+esc(s.portal_url||"")+'" placeholder="https://...">'+
      '<div class="hint">So the mail can link back here. Without it the mail still goes, just with no link.</div></div>'+
    '<div class="fld"><label class="fl"><input type="checkbox" id="m-on"'+(s.mail_on===false?"":" checked")+
      ' style="width:auto;margin-right:7px;vertical-align:middle"> Send notifications</label>'+
      '<div class="hint">Off means messages are still written down and marked <b>not sent</b>, so you can see what would have gone.</div></div>'+
    '<div class="btnrow" style="margin-bottom:4px">'+
      '<button class="btn primary" data-act="mailsave">Save</button>'+
      '<button class="btn" data-act="mailsend">Send the queue now</button>'+
      '<span style="font-size:12.5px;color:var(--muted)">The sender normally runs by itself every few minutes.</span>'+
    '</div></div>'+
    '<table><thead><tr><th>To</th><th>Subject</th><th>State</th><th>When</th></tr></thead><tbody>'+
    (rows||'<tr><td colspan="4" class="empty">Nothing has been queued yet.</td></tr>')+'</tbody></table>';
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
  var g = '<option value="gross||Total Expenses Should Be Paid"'+(sel==="__gross"?" selected":"")+
          '>Total Expenses Should Be Paid (what the partner earned)</option>';
  return '<optgroup label="The earned amount">'+g+'</optgroup>'+
         '<optgroup label="Booking heads">'+o+'</optgroup>'+
         (a?'<optgroup label="Adjustments">'+a+'</optgroup>':'');
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
  if(a==="signin" || a==="signup-first"){
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
    markDirty(); render(); return;
  }
  if(a==="adj-del"){ S.draft.adj.splice(Number(D("i")),1); markDirty(); render(); return; }
  if(a==="savedraft"){
    if(autosaveTimer) clearTimeout(autosaveTimer);
    var r = await autosave();
    if(r.ok){ toast("Draft saved"); await refresh(true); }
    return;
  }

  /* ---- statement flow ---- */
  if(a==="share"){
    if(autosaveTimer) clearTimeout(autosaveTimer);
    if(S.dirty) await autosave();
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
    if(kind==="gross"){ our = Number(vv.gross)||0; key = "__gross"; }
    else if(kind==="head") (vv.lines||[]).forEach(function(l){ if(l.head_key===key) our=Number(l.amount)||0; });
    else (vv.adjustments||[]).forEach(function(x){ if(x.id===key) our=Number(x.amount)||0; });
    modal("Raise a point",
      '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#9432;</div><div>'+
      'Pick the exact line you disagree with. A point tied to a line can be checked and closed. A general complaint cannot.</div></div>'+
      '<div class="fld"><label class="fl">Which line?</label><select class="inp" id="q-target">'+
        headOptionsForStatement(key)+'</select></div>'+
      '<div class="fld"><label class="fl">Your figure (optional)</label><input class="inp num" id="q-claim" placeholder="leave blank if you only want an explanation"></div>'+
      '<div class="fld"><label class="fl">What is the issue?</label><textarea class="inp" id="q-note" '+
        'placeholder="Be specific - dates, vehicle numbers, bill numbers."></textarea></div>'+
      '<div class="fld"><label class="fl">Attach proof (optional)</label>'+
        '<input type="file" id="q-file" class="inp">'+
        '<div class="hint">The bill, the log sheet, a photo &mdash; up to 25 MB. It goes on this month&rsquo;s '+
        'record where WeVois can open it, and stays there.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="raise-go">Submit point</button>');
    return;
  }
  if(a==="raise-go"){
    var tv = (val("q-target")||"").split("|");
    var claim = val("q-claim").replace(/[^0-9.\-]/g,"");
    if(!val("q-note").trim()){ toast("Describe the issue. That text is the record."); return; }
    var qfile = document.getElementById("q-file"), qatt = "";
    if(qfile && qfile.files && qfile.files[0]){
      var qup = await uploadDoc(qfile.files[0], "bill", true);
      if(qup.ok){
        qatt = qfile.files[0].name;
      } else {
        /* the file could not go up. Losing the point as well would be the worse
           of the two failures, so offer to send it with the file named instead
           of attached, and say so plainly. */
        if(!window.confirm(
            "The file could not be attached.\n\n" +
            "Send the point anyway, without it? The file name will be written into the point so " +
            "WeVois knows what to ask you for.\n\n" +
            "OK  - send the point now\n" +
            "Cancel - keep this open and try the file again")) return;
        qatt = qfile.files[0].name + " (could not be uploaded)";
      }
    }
    var r5 = await call("vs_raise_point", {
      p_stmt:S.open, p_kind:tv[0], p_key:tv[1]||"", p_label:tv[2]||"",
      p_claimed: claim===""?null:Number(claim), p_note:val("q-note"), p_attach:qatt
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
        'If this is a payroll head the figure does not move here &mdash; accepting means a payroll correction is posted, '+
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
    if(rA.ok){ closeModal(); toast("Approved "+inr(rA.data)+" - snapshot locked, now awaiting payment"); S.tab="record"; await refresh(true); }
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

  /* ---- site blocks ---- */
  if(a==="opensite"){ S.site = D("sid"); window.scrollTo(0,0); render(); return; }
  if(a==="backsites"){ S.site = null; window.scrollTo(0,0); render(); return; }

  /* ---- general queries ---- */
  if(a==="raiseq"){
    modal("Raise a query",
      '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#128172;</div><div>'+
      'For anything that is not a figure on this month&rsquo;s sheet &mdash; vehicles, drivers, fuel cards, documents, '+
      'next month. It is answered in writing and stays on this month&rsquo;s record. It does <b>not</b> hold up the '+
      'settlement. If you disagree with an <b>amount</b>, go back to the Statement tab and raise a point on that line '+
      'instead, so the figure can actually move.</div></div>'+
      '<div class="fld"><label class="fl">What do you need?</label>'+
        '<textarea class="inp" id="qq-note" placeholder="Be specific - dates, vehicle numbers, names."></textarea></div>'+
      '<div class="fld"><label class="fl">Attach a file (optional)</label>'+
        '<input type="file" id="qq-file" class="inp">'+
        '<div class="hint">Up to 25 MB. It goes on this month&rsquo;s record where WeVois can open it.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="raiseq-go">Send the query</button>');
    return;
  }
  if(a==="raiseq-go"){
    var qnote = val("qq-note");
    if(!qnote.trim()){ toast("Write the question down. That text is the record."); return; }
    var qf = document.getElementById("qq-file");
    var qname = "";
    if(qf && qf.files && qf.files[0]){
      var up = await uploadDoc(qf.files[0], "other", true);
      if(up.ok) qname = qf.files[0].name;
      else {
        if(!window.confirm(
            "The file could not be attached.\n\nSend the query anyway, without it?")) return;
        qname = qf.files[0].name + " (could not be uploaded)";
      }
    }
    var rQ = await call("vs_raise_query", {p_stmt:S.open, p_note:qnote, p_attach:qname},
      "Query sent - WeVois will answer in writing");
    if(rQ.ok){ closeModal(); S.tab="queries"; await refresh(true); }
    return;
  }
  if(a==="answerq"){
    var aid = D("id");
    var apt = (S.stmt.points||[]).filter(function(p){ return p.id===aid; })[0] || {};
    modal("Answer this query",
      '<div class="banner b-grey" style="margin-bottom:14px"><div class="ico">&#10077;</div><div>'+
      '<b>'+esc(apt.raised_by||"")+' asked</b>'+esc(apt.note||"")+'</div></div>'+
      '<div class="fld"><label class="fl">Your answer &mdash; the vendor sees this word for word</label>'+
        '<textarea class="inp" id="aq-text">'+esc(apt.decision||"")+'</textarea></div>'+
      '<input type="hidden" id="aq-id" value="'+esc(aid)+'">',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="answerq-go">Send the answer</button>');
    return;
  }
  if(a==="answerq-go"){
    var rAQ = await call("vs_answer_query", {p_point:val("aq-id"), p_reply:val("aq-text")}, "Answer sent");
    if(rAQ.ok){ closeModal(); await refresh(true); }
    return;
  }
  if(a==="remark"){
    modal("Add a remark",
      '<div class="banner b-grey" style="margin-bottom:14px"><div class="ico">&#9998;</div><div>'+
      'A remark never moves an amount and never closes anything. It is the written trail of what was said '+
      'around the decision, and both sides can see it.</div></div>'+
      '<div class="fld"><label class="fl">Remark</label><textarea class="inp" id="rk-text"></textarea></div>'+
      '<input type="hidden" id="rk-id" value="'+esc(D("id"))+'">',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="remark-go">Add it</button>');
    return;
  }
  if(a==="remark-go"){
    var rRK = await call("vs_add_remark", {p_point:val("rk-id"), p_body:val("rk-text")}, "Remark added");
    if(rRK.ok){ closeModal(); await refresh(true); }
    return;
  }

  /* ---- asking the CEO / VP, and their answer ---- */
  if(a==="askappr"){
    modal("Ask the CEO or the VP",
      '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#9878;</div><div>'+
      'Both of them are emailed. Either can answer, and whoever does is named on the record with the date. '+
      'Leave the amount blank to ask a plain question.</div></div>'+
      '<div class="fld"><label class="fl">What are you asking?</label>'+
        '<textarea class="inp" id="ap-q" placeholder="Be specific. This is the text they answer."></textarea></div>'+
      '<div class="fld"><label class="fl">Is there an amount to confirm?</label>'+
        '<select class="inp" id="ap-has" data-act="ap-has">'+
          '<option value="0">No &mdash; it is a question</option>'+
          '<option value="1">Yes &mdash; confirm a figure</option>'+
        '</select></div>'+
      '<div id="ap-money" style="display:none">'+
        '<div class="grid2">'+
          '<div class="fld"><label class="fl">Amount</label><input class="inp num" id="ap-amt" value="0"></div>'+
          '<div class="fld"><label class="fl">Which way?</label><select class="inp" id="ap-eff">'+
            '<option value="add">Added to the partner</option>'+
            '<option value="deduct">Deducted from the partner</option></select></div>'+
        '</div>'+
        '<div class="fld"><label class="fl">Label &mdash; this becomes the line the vendor reads</label>'+
          '<input class="inp" id="ap-label" placeholder="e.g. Extra tipper hire"></div>'+
        '<div class="banner b-amber" style="margin:0"><div class="ico">&#9888;</div><div>'+
        'If they confirm it, this line goes onto the statement by itself'+
        (S.stmt && S.stmt.statement.status==="draft" ? ' straight away.' :
         ' when you issue the next version.')+'</div></div>'+
      '</div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="askappr-go">Send it to them</button>');
    return;
  }
  if(a==="askappr-go"){
    var hasAmt = val("ap-has") === "1";
    if(!val("ap-q").trim()){ toast("Write down what you are asking."); return; }
    var rAP = await call("vs_request_approval", {
      p_stmt:S.open, p_question:val("ap-q"),
      p_amount: hasAmt ? num("ap-amt") : null,
      p_effect: hasAmt ? val("ap-eff") : null,
      p_label:  hasAmt ? val("ap-label") : ""
    }, "Sent - the CEO and the VP have been emailed");
    if(rAP.ok){ closeModal(); S.tab="approvals"; await refresh(true); }
    return;
  }
  if(a==="decide"){
    var did = D("id"), ok = D("ok")==="1";
    var dap = apprList().filter(function(x){ return x.id===did; })[0] || {};
    modal(ok ? "Confirm this" : "Decline this",
      '<div class="banner b-grey" style="margin-bottom:14px"><div class="ico">&#10077;</div><div>'+
      '<b>'+esc(dap.asked_by||"")+' asked</b>'+esc(dap.question||"")+'</div></div>'+
      (dap.amount != null
        ? '<div class="banner '+(ok?"b-amber":"b-grey")+'" style="margin:0 0 14px"><div class="ico">&#8377;</div><div>'+
          '<b>'+esc(dap.adj_label||"")+' &mdash; '+inr(dap.amount)+' '+
          (dap.effect==="add"?"added to":"deducted from")+' the partner</b>'+
          (ok ? 'Confirming writes this line onto the statement with your name and today&rsquo;s date as its reason.'
              : 'Declining writes nothing. The refusal and your reason stay on the record.')+'</div></div>'
        : '')+
      '<div class="fld"><label class="fl">'+(ok?'Note (optional)':'Why are you declining? &mdash; required')+'</label>'+
        '<textarea class="inp" id="dc-note"></textarea></div>'+
      '<input type="hidden" id="dc-id" value="'+esc(did)+'">'+
      '<input type="hidden" id="dc-ok" value="'+(ok?"1":"0")+'">',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn '+(ok?"go":"danger")+'" data-act="decide-go">'+(ok?"Confirm it":"Decline it")+'</button>');
    return;
  }
  if(a==="decide-go"){
    var dOk = val("dc-ok")==="1";
    if(!dOk && !val("dc-note").trim()){ toast("Say why you are declining. That reason is the record."); return; }
    var rD = await call("vs_decide_approval",
      {p_id:val("dc-id"), p_ok:dOk, p_note:val("dc-note")}, null, "recording...");
    if(rD.ok){ closeModal(); toast(String(rD.data)); await refresh(true); }
    return;
  }

  /* ---- admin: mail ---- */
  if(a==="mailsave"){
    var rM = await call("vs_save_mail_settings", {
      p_from:val("m-from"), p_name:val("m-name"), p_url:val("m-url"),
      p_on: document.getElementById("m-on").checked }, "Mail settings saved");
    if(rM.ok) await refresh(false);
    return;
  }
  if(a==="mailsend"){
    var url = (window.VS_URL||"").replace(".supabase.co", ".functions.supabase.co") + "/send-mail";
    toast("Asking the sender to run...");
    try{
      var res = await fetch(url, {method:"POST", headers:{
        "Authorization":"Bearer "+(window.VS_ANON||""), "Content-Type":"application/json"}});
      var j = await res.json();
      toast(j.ok ? ("Sent "+j.sent+(j.failed?", "+j.failed+" failed":"")) 
                 : (j.reason || j.error || "The sender is not set up yet."));
    }catch(e){
      toast("Could not reach the sender. It may not be deployed yet - see SETUP-MAIL.md.");
    }
    await refresh(false);
    return;
  }

  /* ---- reading the payroll out of a file ---- */
  if(a==="readpayroll"){
    var fi2 = document.getElementById("pr-file");
    if(fi2){ fi2.value = ""; fi2.click(); }
    return;
  }
  if(a==="useread"){
    var P = S.read;
    if(!P) return;
    var mode = val("rd-split") || "dh";
    var sh = mode==="split" ? num("rd-stf-heads") : (mode==="stf" ? P.paid_members : 0);
    var frac = P.paid_members ? Math.min(Math.max(sh,0), P.paid_members) / P.paid_members : 0;
    if(mode==="stf") frac = 1;
    if(mode==="dh")  frac = 0;

    var kept = false;
    function put(id, v){ var el = document.getElementById(id); if(el){ el.value = v; } }
    function split(dhId, stfId, total){
      var stf = Math.round(total * frac * 100)/100;
      put(stfId, stf); put(dhId, Math.round((total - stf)*100)/100);
    }
    var dhH = P.paid_members - sh;
    if(P.kind === "salary"){
      split("dh_pay","stf_pay", P.amount);
      put("dh_heads", dhH); put("stf_heads", sh);
      if(P.rejected.length && val("rd-np")==="1"){
        put("not_processed_amount", Math.round((P.amount_all - P.amount)*100)/100);
        var el = document.getElementById("not_processed_reason");
        if(el) el.value = P.rejected.map(function(r){
          return r.name + " " + inr(r.amount) + " did not go through the bank"; }).join("; ") + ".";
      }
    } else if(P.kind === "pf"){
      split("dh_pf_ee","stf_pf_ee", P.employee);
      split("dh_pf_er","stf_pf_er", P.employer);
      /* the bank file is the better answer to "how many people were paid" -
         PF and ESIC each cover a subset - so a headcount already set is left
         alone rather than quietly replaced by a smaller one */
      if(!num("dh_heads") && !num("stf_heads")){ put("dh_heads", dhH); put("stf_heads", sh); }
      else kept = true;
    } else if(P.kind === "esic"){
      split("dh_esic_ee","stf_esic_ee", P.employee);
      split("dh_esic_er","stf_esic_er", P.employer);
    }
    closeModal();
    toast("Figures filled in from " + P.filename +
      (kept ? " - the headcount already on the form was left as it is" : "") +
      " - check them, then post");
    S.read = null;
    return;
  }
  if(a==="rd-split"){ /* handled on change */ return; }

  /* ---- payroll processed late ---- */
  if(a==="topup"){
    modal("Salary processed late",
      '<div class="banner b-teal" style="margin-bottom:16px"><div class="ico">&#8721;</div><div>'+
      '<b>This goes on as its own entry, not over the top of the month</b>'+
      'Enter only the people who were left off the first run. Their wages, PF and ESIC are added to what is already '+
      'posted, and the entry keeps its own challan and date so the statement always agrees with the challans behind it.'+
      (S.stmt.statement.status!=="draft"
        ? ' This statement is already with the vendor, so the top-up waits for the next version, like any other correction.'
        : '')+'</div></div>'+
      '<h3 style="font-size:14px;margin:4px 0 10px">Driver / helper &mdash; the late batch only</h3>'+
      '<div class="grid2">'+
        '<div class="fld"><label class="fl">Wages processed</label><input class="inp num" id="tu-dh_pay" value="0"></div>'+
        '<div class="fld"><label class="fl">How many people</label><input class="inp num" id="tu-dh_heads" value="0"></div>'+
        '<div class="fld"><label class="fl">PF &mdash; employee part</label><input class="inp num" id="tu-dh_pf_ee" value="0"></div>'+
        '<div class="fld"><label class="fl">PF &mdash; employer part</label><input class="inp num" id="tu-dh_pf_er" value="0"></div>'+
        '<div class="fld"><label class="fl">ESIC &mdash; employee part</label><input class="inp num" id="tu-dh_esic_ee" value="0"></div>'+
        '<div class="fld"><label class="fl">ESIC &mdash; employer part</label><input class="inp num" id="tu-dh_esic_er" value="0"></div>'+
      '</div>'+
      '<h3 style="font-size:14px;margin:14px 0 10px">Staff &mdash; the late batch only</h3>'+
      '<div class="grid2">'+
        '<div class="fld"><label class="fl">Salary processed</label><input class="inp num" id="tu-stf_pay" value="0"></div>'+
        '<div class="fld"><label class="fl">How many people</label><input class="inp num" id="tu-stf_heads" value="0"></div>'+
        '<div class="fld"><label class="fl">PF &mdash; employee part</label><input class="inp num" id="tu-stf_pf_ee" value="0"></div>'+
        '<div class="fld"><label class="fl">PF &mdash; employer part</label><input class="inp num" id="tu-stf_pf_er" value="0"></div>'+
        '<div class="fld"><label class="fl">ESIC &mdash; employee part</label><input class="inp num" id="tu-stf_esic_ee" value="0"></div>'+
        '<div class="fld"><label class="fl">ESIC &mdash; employer part</label><input class="inp num" id="tu-stf_esic_er" value="0"></div>'+
      '</div>'+
      '<h3 style="font-size:14px;margin:14px 0 10px">This batch&rsquo;s own references</h3>'+
      '<div class="grid2">'+
        '<div class="fld"><label class="fl">PF challan / TRRN</label><input class="inp" id="tu-pf_trrn"></div>'+
        '<div class="fld"><label class="fl">PF deposited on</label><input class="inp" id="tu-pf_paid_on" type="date"></div>'+
        '<div class="fld"><label class="fl">ESIC challan no.</label><input class="inp" id="tu-esic_challan"></div>'+
        '<div class="fld"><label class="fl">ESIC deposited on</label><input class="inp" id="tu-esic_paid_on" type="date"></div>'+
        '<div class="fld"><label class="fl">Processed on</label><input class="inp" id="tu-processed_on" type="date"></div>'+
      '</div>'+
      '<div class="fld"><label class="fl">Why is it going on late? &mdash; the vendor sees this</label>'+
        '<input class="inp" id="tu-note" placeholder="e.g. four helpers left off the first run, processed on the 22nd"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn teal" data-act="topup-go">Add this entry</button>');
    return;
  }
  if(a==="topup-go"){
    var tp = {};
    ["dh_pay","dh_heads","dh_pf_ee","dh_pf_er","dh_esic_ee","dh_esic_er",
     "stf_pay","stf_heads","stf_pf_ee","stf_pf_er","stf_esic_ee","stf_esic_er"]
      .forEach(function(k){ tp[k] = num("tu-"+k); });
    ["pf_trrn","pf_paid_on","esic_challan","esic_paid_on","processed_on","note"]
      .forEach(function(k){ tp[k] = val("tu-"+k); });
    var rTU = await call("vs_add_payroll_batch", {p_stmt:S.open, p:tp}, null, "adding the entry...");
    if(rTU.ok){
      closeModal();
      toast(String(rTU.data)==="parked"
        ? "Entry added - it lands when you issue the next version"
        : "Entry added and applied to the statement");
      await refresh(true);
    }
    return;
  }

  /* ---- attached files ---- */
  if(a==="docpick"){
    var fi = document.getElementById("doc-file");
    if(fi){ fi.value = ""; fi.click(); }
    return;
  }
  if(a==="docopen"){
    var pth = D("p");
    var sg = await SB.storage.from("vs-docs").createSignedUrl(pth, 120);
    if(sg.error || !sg.data || !sg.data.signedUrl){
      toast("Could not open that file. " + ((sg.error&&sg.error.message)||""));
      return;
    }
    window.open(sg.data.signedUrl, "_blank", "noopener");
    return;
  }
  if(a==="docdel"){
    var did = D("id"), dn = D("n");
    modal("Remove this file",
      '<div class="banner b-amber" style="margin-bottom:14px"><div class="ico">&#9888;</div><div>'+
      '<b>'+esc(dn)+'</b>The vendor will no longer be able to open it. The removal, and your reason, '+
      'stay in the record permanently.</div></div>'+
      '<div class="fld"><label class="fl">Why is it coming off?</label>'+
        '<input class="inp" id="dd-why" placeholder="e.g. wrong month attached by mistake"></div>'+
      '<input type="hidden" id="dd-id" value="'+esc(did)+'">',
      '<button class="btn" data-act="closemodal">Keep it</button>'+
      '<button class="btn danger" data-act="docdel-go">Remove the file</button>');
    return;
  }
  if(a==="docdel-go"){
    var ddid = val("dd-id"), why = val("dd-why");
    if(!why.trim()){ toast("A reason is required."); return; }
    var rD = await call("vs_remove_document", {p_doc:ddid, p_reason:why}, null, "removing...");
    if(rD.ok){
      /* the row goes first; the object is best-effort, and an orphan blob that
         nothing points at is far better than a live row with no file */
      try{ await SB.storage.from("vs-docs").remove([rD.data]); }catch(e){}
      closeModal(); toast("File removed"); await refresh(true);
    }
    return;
  }

  /* ---- admin: people ---- */
  if(a==="createlogin"){
    modal("Create a login",
      '<div class="fld"><label class="fl">Full name</label><input class="inp" id="i-name" placeholder="e.g. Ramesh Chand"></div>'+
      '<div class="fld"><label class="fl">Email</label><input class="inp" id="i-email" type="email" autocomplete="off"></div>'+
      '<div class="fld"><label class="fl">Role</label><select class="inp" id="i-role">'+
        ROLE_ORDER.map(function(r){
          return '<option value="'+r+'">'+esc(ROLE_LABEL[r])+' &mdash; '+esc(ROLE_NOTE[r])+'</option>'; }).join("")+
        '</select></div>'+
      '<div class="fld"><label class="fl">If a vendor login, which vendor?</label>'+
        '<select class="inp" id="i-vendor"><option value="">&mdash; not a vendor login &mdash;</option>'+
        vendorOptions()+'</select></div>'+
      '<div class="fld"><label class="fl">Password to give them</label>'+
        '<input class="inp" id="i-pass" value="'+tempPassword()+'">'+
        '<div class="hint">Generated for you. Change it if you prefer. They can set their own from '+
        '<b>Change password</b> once they are in.</div></div>'+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'This creates the account outright and shows you the credentials to pass on. '+
      'You stay signed in as yourself the whole time.</div></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="createlogin-go">Create the login</button>');
    return;
  }
  if(a==="createlogin-go"){
    /* read every field BEFORE anything can close the modal, or the credentials
       card ends up showing a blank password */
    var cName = val("i-name"), cEmail = val("i-email").toLowerCase(),
        cRole = val("i-role"), cVendor = val("i-vendor"), cPass = val("i-pass");
    if(!cName){ toast("Enter their name"); return; }
    if(!cEmail || cEmail.indexOf("@") < 1){ toast("Enter a valid email address"); return; }
    if(cPass.length < 8){ toast("The password needs at least 8 characters"); return; }
    if(cRole === "vendor" && !cVendor){ toast("A vendor login must be tied to a vendor"); return; }
    if(cRole !== "vendor" && cVendor){ toast("Only a vendor login can be tied to a vendor"); return; }
    if(S.profiles.some(function(p){ return String(p.email).toLowerCase() === cEmail; })){
      toast("Somebody already has a login with that email"); return;
    }

    /* 1. pre-authorise: this row is what tells the database which role the new
          account gets. Without it the account is created but gets no profile
          and can see nothing. */
    var pre = await call("vs_invite", {p_email:cEmail, p_name:cName,
      p_role:cRole, p_vendor: cVendor||null}, null, "preparing...");
    if(!pre.ok) return;

    /* 2. create the account on a throwaway client so the administrator's own
          session is untouched */
    busy(true, "creating the account...");
    var made = false, why = "";
    try{
      var prov = provisionClient();
      var up = await prov.auth.signUp({email:cEmail, password:cPass,
                 options:{ data:{ full_name:cName } }});
      if(up.error) throw up.error;
      made = true;
      try{ await prov.auth.signOut(); }catch(e){}
    }catch(e){ why = friendly(e); }
    finally{ busy(false); }

    if(!made){
      toast(why || "Could not create the account");
      return;
    }

    /* 3. confirm the profile actually landed with the right role */
    await refresh(false);
    var got = S.profiles.filter(function(p){ return String(p.email).toLowerCase() === cEmail; })[0];

    closeModal();
    modal("Login created &mdash; pass these on",
      (got
        ? '<div class="banner b-green" style="margin-bottom:16px"><div class="ico">&#10003;</div><div>'+
          '<b>'+esc(cName)+' is set up as '+esc(ROLE_LABEL[got.role])+'</b>'+
          (got.vendor_id?'For '+esc(vendorName(got.vendor_id))+'. ':'')+
          'They can sign in right now.</div></div>'
        : '<div class="banner b-amber" style="margin-bottom:16px"><div class="ico">&#9888;</div><div>'+
          '<b>The account was created, but no role landed on it</b>'+
          'Check that <b>Confirm email</b> is switched OFF in Supabase &rarr; Authentication &rarr; Email. '+
          'While it is on, the account is not final until they click a link, and the role is not applied. '+
          'The credentials below still work once that is sorted.</div></div>')+
      '<div class="decl" style="font-size:14px;line-height:1.9">'+
        'Portal: <b id="cred-url">'+esc(location.origin + location.pathname.replace(/[^/]*$/,""))+'</b><br>'+
        'Email: <b id="cred-email">'+esc(cEmail)+'</b><br>'+
        'Password: <b id="cred-pass" style="font-family:ui-monospace,Menlo,Consolas,monospace">'+esc(cPass)+'</b>'+
      '</div>'+
      '<div class="btnrow" style="margin-top:14px">'+
        '<button class="btn" data-act="copycred">Copy all three</button>'+
        '<button class="btn" data-act="copypass">Copy just the password</button></div>'+
      '<div class="hint" style="margin-top:14px">This password is shown once and is not stored anywhere you can read it back. '+
      'Send it now. Ask them to change it from <b>Change password</b> after their first sign-in.</div>',
      '<button class="btn primary" data-act="closemodal">Done</button>');
    return;
  }
  if(a==="copycred" || a==="copypass"){
    var g = function(id){ var el=document.getElementById(id); return el?el.textContent:""; };
    var text = (a==="copypass") ? g("cred-pass")
      : "WeVois Vendor Settlement\n"+g("cred-url")+"\nEmail: "+g("cred-email")+"\nPassword: "+g("cred-pass");
    try{
      if(navigator.clipboard && navigator.clipboard.writeText){ await navigator.clipboard.writeText(text); }
      else {
        var ta=document.createElement("textarea"); ta.value=text; document.body.appendChild(ta);
        ta.select(); document.execCommand("copy"); document.body.removeChild(ta);
      }
      toast("Copied");
    }catch(e){ toast("Could not copy - select the text and copy it manually"); }
    return;
  }
  if(a==="sendreset"){
    var em = D("email");
    busy(true, "sending...");
    try{
      var rr = await SB.auth.resetPasswordForEmail(em, {redirectTo: location.href});
      if(rr && rr.error) throw rr.error;
      toast("Reset link sent to "+em);
    }catch(e){
      toast("Could not send: "+friendly(e)+" - you can also reset it from Supabase, Authentication then Users.");
    } finally { busy(false); }
    return;
  }
  if(a==="changepw"){
    modal("Change your password",
      '<div class="fld"><label class="fl">New password</label><input class="inp" id="pw-1" type="password" autocomplete="new-password"></div>'+
      '<div class="fld"><label class="fl">Type it again</label><input class="inp" id="pw-2" type="password" autocomplete="new-password"></div>'+
      '<div class="hint">At least 8 characters. This changes only your own password.</div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="changepw-go">Change it</button>');
    return;
  }
  if(a==="changepw-go"){
    var p1 = val("pw-1"), p2 = val("pw-2");
    if(p1.length < 8){ toast("At least 8 characters"); return; }
    if(p1 !== p2){ toast("The two do not match"); return; }
    busy(true, "changing...");
    try{
      var ru = await SB.auth.updateUser({password:p1});
      if(ru && ru.error) throw ru.error;
      closeModal(); toast("Password changed");
    }catch(e){ toast(friendly(e)); }
    finally{ busy(false); }
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

  /* ---- admin: edit a site and its tenures ---- */
  if(a==="editsite"){
    var esid = D("sid");
    var siteE = S.sites.filter(function(x){ return x.id===esid; })[0];
    if(!siteE) return;
    var csE = contractsOfSite(esid);
    var liveE = csE.filter(function(c){ return !c.to_date; })[0];
    modal("Edit "+esc(siteE.name),
      '<div class="fld"><label class="fl">Site name</label>'+
        '<input class="inp" id="es-name" value="'+esc(siteE.name)+'"></div>'+
      '<div class="fld"><label class="fl">City</label>'+
        '<input class="inp" id="es-city" value="'+esc(siteE.city||"")+'"></div>'+
      '<div class="grid2">'+
        '<div class="fld"><label class="fl">Started here on</label>'+
          '<input class="inp" id="es-start" type="date" value="'+(siteE.start_date?String(siteE.start_date).slice(0,10):"")+'">'+
          '<div class="hint">Leave blank if you would rather not date it.</div></div>'+
        '<div class="fld"><label class="fl">Closed on</label>'+
          '<input class="inp" id="es-close" type="date" value="'+(siteE.close_date?String(siteE.close_date).slice(0,10):"")+'">'+
          '<div class="hint">Blank means still running.</div></div>'+
      '</div>'+
      (liveE?'<div class="banner b-amber" style="margin:0 0 14px"><div class="ico">&#9888;</div><div>'+
        '<b>'+esc(vendorName(liveE.vendor_id))+' is still running this site with no end date</b>'+
        'To close the site, end that tenure first &mdash; use <b>Edit</b> next to it and give the last day.</div></div>':'')+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'Both dates are saved exactly as they read above, so clearing one clears it. '+
      'The start date cannot be after work already recorded here, and the closing date cannot be before it.</div></div>'+
      '<input type="hidden" id="es-id" value="'+esc(esid)+'">',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="editsite-go">Save the site</button>');
    return;
  }
  if(a==="editsite-go"){
    var rES = await call("vs_set_site", {
      p_site:val("es-id"), p_name:val("es-name"), p_city:val("es-city"),
      p_start:val("es-start")||null, p_close:val("es-close")||null });
    if(rES.ok){ closeModal(); toast(String(rES.data)==="nothing changed"?"Nothing changed":"Saved - "+rES.data); await refresh(false); }
    return;
  }

  if(a==="edittenure"){
    var ecid = D("cid");
    var conE = S.contracts.filter(function(x){ return x.id===ecid; })[0];
    if(!conE) return;
    var siteT = S.sites.filter(function(x){ return x.id===conE.site_id; })[0] || {};
    var mine = S.list.filter(function(x){ return x.contract_id===ecid; });
    var sent = mine.filter(function(x){ return x.status!=="draft"; }).length;
    modal("Edit tenure &mdash; "+esc(vendorName(conE.vendor_id))+" at "+esc(siteT.name||""),
      '<div class="grid2">'+
        '<div class="fld"><label class="fl">Started on</label>'+
          '<input class="inp" id="et-from" type="date" value="'+String(conE.from_date).slice(0,10)+'"></div>'+
        '<div class="fld"><label class="fl">Last day</label>'+
          '<input class="inp" id="et-to" type="date" value="'+(conE.to_date?String(conE.to_date).slice(0,10):"")+'">'+
          '<div class="hint">Blank means still running.</div></div>'+
      '</div>'+
      '<div class="fld"><label class="fl">Vehicles</label>'+
        '<input class="inp num" id="et-veh" value="'+(conE.vehicles||1)+'"></div>'+
      (mine.length?'<div class="banner b-teal" style="margin:0 0 14px"><div class="ico">&#128209;</div><div>'+
        '<b>'+mine.length+' settlement'+(mine.length===1?'':'s')+' sit under this tenure</b>'+
        (sent?sent+' of them have already gone to the vendor. Those keep the covering dates he was sent &mdash; a statement that has gone out is a record, not a view. ':'')+
        'Dates that would leave any month outside the tenure are refused, and the months are named.</div></div>':'')+
      '<div class="banner b-blue" style="margin:0"><div class="ico">&#9432;</div><div>'+
      'Two vendors cannot hold one site at the same time, so dates running into the next partner are refused.</div></div>'+
      '<input type="hidden" id="et-id" value="'+esc(ecid)+'">',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="edittenure-go">Save the tenure</button>');
    return;
  }
  if(a==="edittenure-go"){
    var rET = await call("vs_set_contract", {
      p_contract:val("et-id"), p_vehicles:num("et-veh"),
      p_from:val("et-from")||null, p_to:val("et-to")||null });
    if(rET.ok){ closeModal(); toast(String(rET.data)==="nothing changed"?"Nothing changed":"Saved - "+rET.data); await refresh(false); }
    return;
  }
  if(a==="reopentenure"){
    var rcid = D("cid");
    var conR = S.contracts.filter(function(x){ return x.id===rcid; })[0];
    modal("Reopen this tenure",
      '<div class="banner b-amber" style="margin:0 0 14px"><div class="ico">&#8635;</div><div>'+
      '<b>'+esc(conR?vendorName(conR.vendor_id):"")+'</b>'+
      'The end date comes off and the tenure runs on with no finish. Use this when an end date was entered by mistake. '+
      'If another partner has since taken the site over, this is refused.</div></div>'+
      '<input type="hidden" id="rt-id" value="'+esc(rcid)+'">',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="reopentenure-go">Reopen it</button>');
    return;
  }
  if(a==="reopentenure-go"){
    var rRT = await call("vs_reopen_contract", {p_contract:val("rt-id")}, "Tenure reopened");
    if(rRT.ok){ closeModal(); await refresh(false); }
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
      'It is created as an empty draft. The payroll is posted, the running heads are filled in, and only then can it go out.</div></div>',
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
        '<option value="payroll">Derived from the payroll posting</option></select></div>'+
      '<div class="fld"><label class="fl">What does it do to the amount?</label><select class="inp" id="h-eff">'+
        '<option value="deduct">Reduces payment &mdash; money WeVois spent for him</option>'+
        '<option value="add">Credits him &mdash; added to what we pay</option>'+
        '<option value="note">Recorded only &mdash; on the statement, not counted</option></select>'+
        '<div class="hint">The vendor manager can still choose differently for one month on the draft. '+
        'A payroll head always reduces the payment.</div></div>'+
      '<div class="fld"><label class="fl">Sort order</label><input class="inp num" id="h-sort" value="900"></div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="addhead-go" data-sid="'+D("sid")+'">Add head</button>');
    return;
  }
  if(a==="addhead-go"){
    var rH = await call("vs_add_head", {p_site:D("sid"), p_key:val("h-key"), p_label:val("h-label"),
      p_grp:val("h-grp"), p_src:val("h-src"), p_sort:num("h-sort"),
      p_effect:val("h-eff")}, "Head added");
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
      (D("src")==="payroll"
        ? '<div class="hint">This head is derived from the payroll posting. Money that has already left '+
          'the company for his men always reduces the payment, so it cannot be set to anything else. '+
          'An exception to a payroll figure belongs in an adjustment line.</div>'
        : '<div class="fld"><label class="fl">What does it do to the amount?</label>'+
          '<select class="inp" id="eh-eff">'+
          EFFECTS.map(function(o){
            return '<option value="'+o[0]+'"'+(D("eff")===o[0]?" selected":"")+'>'+
              (o[0]==="deduct"?"Reduces payment &mdash; money WeVois spent for him"
               :o[0]==="add"?"Credits him &mdash; added to what we pay"
               :"Recorded only &mdash; on the statement, not counted")+'</option>'; }).join("")+
          '</select><div class="hint">This is the standing choice for new months at this site. '+
          'The vendor manager can still choose differently for one month while the draft is open.</div></div>')+
      '<div class="hint">Statements already shared keep the label and the choice they were shared with.</div>',
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="edithead-go" data-hid="'+D("hid")+'">Save</button>');
    return;
  }
  if(a==="edithead-go"){
    var rEH = await call("vs_set_head", {p_head:D("hid"), p_label:val("eh-label"),
      p_sort:num("eh-sort"), p_active: val("eh-on")==="1",
      p_effect: document.getElementById("eh-eff") ? val("eh-eff") : null}, "Saved");
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
    markDirty();
  }
  if(a==="adjf" && S.draft){
    var i = Number(el.getAttribute("data-i")), f = el.getAttribute("data-f");
    if(!S.draft.adj[i]) return;
    S.draft.adj[i][f] = (f==="amount") ? Number(String(el.value).replace(/[^0-9.\-]/g,"")||0) : el.value;
    markDirty();
  }
});

/* ------------------------------------------------------------- autosave */
/* Typing a figure and forgetting to press Save is exactly the kind of gap
   this whole system exists to close, so the draft saves itself. It waits for
   a pause in typing rather than firing on every keystroke, never runs while
   another save is in flight, and only ever touches a DRAFT - a version that
   has gone to the vendor is frozen and no amount of typing can reach it. */
var AUTOSAVE_MS = 900;
var autosaveTimer = null;

function autosaveNote(txt, cls){
  var el = document.getElementById("autosave");
  if(!el) return;
  el.textContent = txt;
  el.className = "autosave" + (cls ? " " + cls : "");
}

function markDirty(){
  if(!S.draft || !S.open) return;
  if(!S.stmt || S.stmt.statement.status !== "draft") return;
  S.dirty = true;
  autosaveNote("unsaved changes", "warn");
  if(autosaveTimer) clearTimeout(autosaveTimer);
  autosaveTimer = setTimeout(function(){ autosave(); }, AUTOSAVE_MS);
}

async function autosave(silent){
  if(!S.draft || !S.open || S.saving) return {ok:false};
  if(!S.stmt || S.stmt.statement.status !== "draft") return {ok:false};
  if(!S.dirty && silent) return {ok:true};
  S.saving = true;
  autosaveNote("saving...", "");
  var lines = {};
  Object.keys(S.draft.lines).forEach(function(k){ lines[k] = S.draft.lines[k]; });
  var effects = {};
  Object.keys(S.draft.effects||{}).forEach(function(k){ effects[k] = S.draft.effects[k]; });
  var res;
  try{
    res = await rpc("vs_save_draft", {
      p_stmt:S.open, p_gross:S.draft.gross, p_gross_note:S.draft.note,
      p_lines:lines, p_adj:S.draft.adj, p_effects:effects }, "saving...");
    S.dirty = false;
    autosaveNote("saved " + new Date().toLocaleTimeString(), "ok");
    res = {ok:true};
  }catch(e){
    autosaveNote("not saved - " + friendly(e), "bad");
    res = {ok:false, error:e};
  }
  S.saving = false;
  return res;
}

/* nothing should leave the screen with an unsaved figure on it */
window.addEventListener("beforeunload", function(e){
  if(S.dirty){ e.preventDefault(); e.returnValue = ""; }
});

/* ------------------------------------------------------ attaching a file */
var DOC_MAX = 25 * 1024 * 1024;

function safeName(n){
  return String(n||"file").replace(/[^A-Za-z0-9._ -]+/g,"_").replace(/\s+/g," ").trim().slice(0,120) || "file";
}
function rid(){
  try{ if(window.crypto && crypto.randomUUID) return crypto.randomUUID().slice(0,8); }catch(e){}
  return Math.random().toString(36).slice(2,10);
}
function docStatus(t){
  var el = document.getElementById("doc-status");
  if(el) el.textContent = t || "";
}

async function uploadDoc(file, kindOverride, quiet){
  if(!file || !S.open) return {ok:false};
  if(file.size > DOC_MAX){
    toast("That file is "+Math.round(file.size/1048576)+" MB. The limit is 25 MB.");
    return {ok:false};
  }
  var kindEl = document.getElementById("doc-kind");
  var kind = kindOverride || (kindEl ? kindEl.value : "other");
  var name = safeName(file.name);
  /* the statement id is the first folder, which is what the storage policy
     reads to decide who may open the file */
  var path = S.open + "/" + rid() + "-" + name;

  docStatus("uploading " + name + "...");
  var up;
  try{
    up = await SB.storage.from("vs-docs").upload(path, file, {
      contentType: file.type || "application/octet-stream", upsert: false });
  }catch(err){ up = {error:err}; }
  if(up && up.error){
    docStatus("");
    var msg = String(up.error.message || "");
    if(/row-level security|not authorized|violates/i.test(msg)){
      msg = (S.profile && S.profile.role === "vendor")
        ? "The portal is not set up to accept files from vendors yet. Tell WeVois: VS-PATCH-5.sql has not been run on the database."
        : "The storage rules refused that file. If VS-PATCH-5.sql has not been run yet, run it - that is what lets a vendor attach.";
    }
    toast(msg);
    return {ok:false, error:up.error, denied:true};
  }

  var r = await call("vs_add_document", {
    p_stmt:S.open, p_path:path, p_filename:file.name,
    p_kind:kind, p_mime:file.type||"", p_size:file.size });
  docStatus("");
  if(!r.ok){
    /* the row is what the vendor reads; a blob with no row is invisible, so
       take it back out rather than leave it lying in the bucket */
    try{ await SB.storage.from("vs-docs").remove([path]); }catch(e){}
    return {ok:false};
  }
  if(!quiet){
    toast(file.name + " attached - it is on this month's record now");
    await refresh(true);
  }
  return {ok:true, path:path};
}

document.addEventListener("change", async function(e){
  if(e.target && e.target.id === "pr-file"){
    var pf = e.target.files && e.target.files[0];
    if(!pf) return;
    toast("Reading " + pf.name + "...");
    var parsed;
    try{ parsed = await readPayrollFile(pf); }
    catch(err){ toast(err.message || "Could not read that file."); return; }
    S.read = parsed;
    modal("What the file says",
      readReview(parsed),
      '<button class="btn" data-act="closemodal">Cancel</button>'+
      '<button class="btn primary" data-act="useread">Use these figures</button>');
    /* the document itself belongs on the record beside the figures it produced */
    try{ await uploadDoc(pf, parsed.kind === "salary" ? "payroll" : parsed.kind, true); }catch(e2){}
    return;
  }
  if(e.target && e.target.id === "ap-has"){
    var mb = document.getElementById("ap-money");
    if(mb) mb.style.display = (e.target.value === "1") ? "" : "none";
    return;
  }
  if(e.target && e.target.id === "rd-split"){
    var box = document.getElementById("rd-split-box");
    if(box) box.style.display = (e.target.value === "split") ? "" : "none";
    return;
  }
  if(e.target && e.target.id === "doc-file"){
    var f = e.target.files && e.target.files[0];
    if(f) await uploadDoc(f);
    return;
  }
  var el = e.target.closest ? e.target.closest("[data-act]") : null;
  if(!el) return;
  var a = el.getAttribute("data-act");
  if(a==="period"){ S.period = el.value; S.open=null; S.stmt=null; render(); return; }
  if(a==="draft-eff" && S.draft){
    /* Unlike a figure being typed, this is one click with an immediate
       consequence for the Total. So it is saved and read back straight away,
       and every number on the screen is the database's own, not this
       browser's arithmetic. */
    var ek = el.getAttribute("data-k");
    var prev = S.draft.effects[ek];
    S.draft.effects[ek] = el.value;
    S.dirty = true;
    var rEf = await autosave();
    if(!rEf.ok){ S.draft.effects[ek] = prev; render(); return; }
    await refresh(true);
    return;
  }
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

  try{ await checkSchema(); }catch(e){ S.missing = []; }

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
      .on("postgres_changes", {event:"*", schema:"public", table:"vs_documents"},  scheduleRefresh)
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
