"use strict";
/* ============================================================================
   Views: the shell, the role home screens, and the statement tabs.
   ========================================================================== */

function render(){
  if(!S.profile) return;
  var months = {};
  S.list.forEach(function(x){ months[String(x.period).slice(0,10)] = 1; });
  months[thisMonth()] = 1;
  if(S.period) months[S.period] = 1;
  var ms = Object.keys(months).sort().reverse();
  var msel = ms.map(function(m){
    return '<option value="'+m+'"'+(m===S.period?" selected":"")+'>'+esc(monthLabel(m))+'</option>'; }).join("");

  var bar = '<div class="topbar"><div class="topbar-in">'+
    '<div class="logo"><span class="dot"></span>'+esc(window.VS_ORG||"WeVois")+' <small>Vendor Settlement</small></div>'+
    '<div class="spacer"></div>'+
    (S.profile.role==="vendor" ? '' : '<select class="rolesel" data-act="period" title="Month">'+msel+'</select>')+
    '<div class="whoami"><b>'+esc(S.profile.full_name||S.profile.email)+'</b>'+esc(ROLE_LABEL[S.profile.role])+'</div>'+
    '<button class="btn sm" data-act="signout" style="background:#1c2534;border-color:#2c3648;color:#fff">Sign out</button>'+
    '</div></div>';

  var body;
  if(S.open && S.stmt)                 body = viewStatement();
  else if(S.profile.role==="admin")    body = viewAdmin();
  else if(isObserver())                body = viewLeadership();
  else if(S.profile.role==="vendor")   body = viewVendorHome();
  else if(S.profile.role==="accounts") body = viewAccountsHome();
  else                                 body = viewManagerHome();

  document.getElementById("app").innerHTML = bar + '<div class="wrap">'+body+'</div>';
}

function observerBanner(){
  if(!isObserver()) return "";
  return '<div class="banner b-grey"><div class="ico">&#9673;</div><div><b>Observer access - '+esc(ROLE_LABEL[S.profile.role])+'</b>'+
    'You can see every vendor, every point, every reason and the full payment record. Nothing on this account can change anything, '+
    'and that is enforced in the database, not just hidden in the screen.</div></div>';
}
function listHead(){
  return '<thead><tr><th>Vendor &amp; site</th><th>Status</th><th>Points</th>'+
    '<th class="num hide-sm">Earned</th><th class="num">Final amount</th><th></th></tr></thead>';
}
function listRows(list){
  var out = list.map(function(x){
    var pend = x.payroll_status !== "posted";
    return '<tr data-act="open" data-id="'+x.id+'">'+
      '<td><b>'+esc(x.vendor_name)+'</b><div style="font-size:12px;color:var(--muted)">'+
        (x.vendor_code?esc(x.vendor_code)+' &middot; ':'')+
        '<b style="color:var(--brand-ink);font-weight:650">'+esc(x.site_name)+'</b> &middot; '+x.vehicles+' vehicles'+
        ' &middot; '+esc(x.period_label)+
        (x.covers_from ? ' &middot; '+dOnly(x.covers_from)+' to '+dOnly(x.covers_to) : '')+'</div></td>'+
      '<td>'+statusChip(x.status)+' <span style="font-size:12px;color:var(--muted)">v'+x.version+'</span>'+
        (pend?' <span class="chip c-red"><span class="d"></span>payroll pending</span>':'')+'</td>'+
      '<td>'+(x.open_points? '<span class="chip c-amber"><span class="d"></span>'+x.open_points+' open</span>'
        : '<span style="color:var(--faint);font-size:12.5px">&mdash;</span>')+'</td>'+
      '<td class="num hide-sm" style="color:var(--muted)">'+inr(x.gross||0)+'</td>'+
      '<td class="num"><b>'+inr(x.final)+'</b>'+
        (Number(x.paid_total)>0?'<div style="font-size:12px;color:var(--teal)">paid '+inr(x.paid_total)+'</div>':'')+'</td>'+
      '<td class="num"><button class="btn sm">Open</button></td></tr>';
  }).join("");
  return out || '<tr><td colspan="6" class="empty">Nothing here.</td></tr>';
}
function ofPeriod(){ return S.list.filter(function(x){ return String(x.period).slice(0,10)===S.period; }); }

/* ------------------------------------------------------------ manager home */
function viewManagerHome(){
  var mine = ofPeriod();
  var payable=0, awaiting=0, pts=0, blocked=0, paid=0;
  mine.forEach(function(x){
    payable += Number(x.final)||0;
    if(x.status==="sent"||x.status==="under_query") awaiting++;
    if(x.payroll_status!=="posted") blocked++;
    pts += Number(x.open_points)||0;
  });
  S.list.forEach(function(x){ paid += Number(x.paid_total)||0; });

  var warn = blocked ? '<div class="banner b-teal"><div class="ico">&#9203;</div><div><b>'+blocked+
    ' settlement'+(blocked===1?" is":"s are")+' waiting on Accounts</b>'+
    'Processed salary and PF/ESIC have not been posted, so those heads are still zero and the statement cannot be shared.</div></div>' : "";

  var empty = !S.list.length ? '<div class="banner b-blue"><div class="ico">&#9432;</div><div><b>No settlements yet</b>'+
    'Your administrator opens a month from the Administration screen, which creates one draft per vendor-site contract.</div></div>' : "";

  return warn+empty+
   '<div class="page-h"><div><h1>'+esc(monthLabel(S.period))+' settlements</h1>'+
   '<p>'+mine.length+' vendor-site settlement'+(mine.length===1?"":"s")+' this month</p></div></div>'+
   '<div class="kpis">'+
     '<div class="kpi"><div class="l">Payable this month</div><div class="v">'+inr(payable)+'</div><div class="n">current versions</div></div>'+
     '<div class="kpi"><div class="l">Awaiting vendor</div><div class="v">'+awaiting+'</div><div class="n">clock running</div></div>'+
     '<div class="kpi"><div class="l">Open points</div><div class="v" style="color:var(--amber)">'+pts+'</div><div class="n">every one on record</div></div>'+
     '<div class="kpi"><div class="l">Paid to date</div><div class="v" style="color:var(--teal)">'+inr(paid)+'</div><div class="n">against approved versions only</div></div>'+
   '</div>'+
   '<div class="card"><div class="card-h"><h2>This month</h2><div class="spacer"></div><span class="sub">Click a row to open</span></div>'+
   '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(mine)+'</tbody></table></div></div>';
}

/* ----------------------------------------------------------- accounts home */
function viewAccountsHome(){
  var mine = ofPeriod();
  var toPost = mine.filter(function(x){ return x.payroll_status!=="posted"; });
  var toPay  = S.list.filter(function(x){ return x.status==="approved"||x.status==="part_paid"; });
  var outstanding = toPay.reduce(function(a,x){
    return a + (Number(x.approved_amount||0) - Number(x.paid_total||0)); }, 0);
  return '<div class="page-h"><div><h1>Accounts</h1><p>Processed salary, PF &amp; ESIC postings and payment release</p></div></div>'+
   '<div class="kpis">'+
     '<div class="kpi"><div class="l">Payroll to post</div><div class="v" style="color:'+(toPost.length?"var(--red)":"var(--green)")+'">'+
       toPost.length+'</div><div class="n">blocks the statement going out</div></div>'+
     '<div class="kpi"><div class="l">Awaiting payment</div><div class="v">'+toPay.length+'</div><div class="n">approved by the vendor</div></div>'+
     '<div class="kpi"><div class="l">Outstanding</div><div class="v">'+inr(outstanding)+'</div><div class="n">approved less paid</div></div>'+
   '</div>'+
   '<div class="card"><div class="card-h"><h2>Payroll to post &mdash; '+esc(monthLabel(S.period))+'</h2>'+
     '<span class="sub">the vendor manager cannot share until this is done</span></div>'+
     '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(toPost)+'</tbody></table></div></div>'+
   '<div class="card"><div class="card-h"><h2>Approved &mdash; awaiting payment</h2>'+
     '<span class="sub">money can only move against a version the vendor approved</span></div>'+
     '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(toPay)+'</tbody></table></div></div>'+
   '<div class="card"><div class="card-h"><h2>All settlements</h2><span class="sub">open any month to post a correction</span></div>'+
     '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(S.list)+'</tbody></table></div></div>';
}

/* --------------------------------------------------------- leadership home */
function viewLeadership(){
  var mine = ofPeriod();
  var payable=0, inQuery=0, unpaid=0;
  mine.forEach(function(x){
    payable += Number(x.final)||0;
    if(x.status==="under_query") inQuery += Number(x.final)||0;
    if(x.status==="approved"||x.status==="part_paid")
      unpaid += (Number(x.approved_amount||0) - Number(x.paid_total||0));
  });
  var ready = mine.filter(function(x){ return x.payroll_status==="posted" && Number(x.vehicles)>0; })
    .map(function(x){ return {name:x.site_name+" · "+x.vendor_name, cpv:(Number(x.heads_total)||0)/Number(x.vehicles)}; })
    .sort(function(a,b){ return b.cpv-a.cpv; });
  var max = ready.length ? ready[0].cpv : 0;
  var bars = ready.map(function(r){
    var w = max>0 ? Math.round((r.cpv/max)*100) : 0;
    return '<div class="barrow" title="'+esc(r.name)+'"><div class="barlab">'+esc(r.name)+'</div>'+
      '<div class="bartrack"><div class="barfill" style="width:'+w+'%"></div></div>'+
      '<div class="barval">'+inr(r.cpv)+'</div></div>';
  }).join("");
  var skipped = mine.length - ready.length;

  return observerBanner()+
   '<div class="page-h"><div><h1>Vendor settlements &mdash; '+esc(monthLabel(S.period))+'</h1>'+
   '<p>Read-only across every vendor and site</p></div></div>'+
   '<div class="kpis">'+
     '<div class="kpi"><div class="l">Payable this month</div><div class="v">'+inr(payable)+'</div><div class="n">current versions</div></div>'+
     '<div class="kpi"><div class="l">Held up in query</div><div class="v" style="color:var(--amber)">'+inr(inQuery)+'</div><div class="n">value not yet agreed</div></div>'+
     '<div class="kpi"><div class="l">Approved, not paid</div><div class="v" style="color:var(--green)">'+inr(unpaid)+'</div><div class="n">with Accounts</div></div>'+
     '<div class="kpi"><div class="l">Settlements</div><div class="v">'+mine.length+'</div><div class="n">vendor-site, this month</div></div>'+
   '</div>'+
   '<div class="card"><div class="card-h"><h2>Company spend per vehicle &mdash; '+esc(monthLabel(S.period))+'</h2>'+
     '<span class="sub">what WeVois spent on the partner&rsquo;s behalf, divided by the vehicles on that contract</span></div>'+
     '<div class="card-b">'+(bars||'<div class="empty">No settlement has a posted payroll yet.</div>')+
     (skipped>0?'<div style="font-size:12px;color:var(--muted);margin-top:10px;padding-top:10px;border-top:1px solid var(--line-2)">'+
       skipped+' left out &mdash; payroll not posted yet, so the figure would read low.</div>':'')+'</div></div>'+
   '<div class="card"><div class="card-h"><h2>By vendor and site</h2></div>'+
     '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(mine)+'</tbody></table></div></div>';
}

/* ------------------------------------------------------------ vendor home */
function viewVendorHome(){
  var mine = S.list;
  var awaitingConfirm = 0;
  var rows = mine.map(function(x){
    var need = (x.status==="sent"||x.status==="under_query");
    return '<tr data-act="open" data-id="'+x.id+'">'+
      '<td><b>'+esc(x.site_name)+'</b><div style="font-size:12px;color:var(--muted)">'+x.vehicles+' vehicles'+
        (x.covers_from?' &middot; '+dOnly(x.covers_from)+' to '+dOnly(x.covers_to):'')+'</div></td>'+
      '<td><b>'+esc(x.period_label)+'</b><div style="font-size:12px;color:var(--muted)">version '+x.version+'</div></td>'+
      '<td>'+statusChip(x.status)+
        (x.open_points? ' <span class="chip c-amber"><span class="d"></span>'+x.open_points+' open</span>':'')+'</td>'+
      '<td class="num"><b>'+inr(x.final)+'</b>'+
        (Number(x.paid_total)>0?'<div style="font-size:12px;color:var(--teal)">paid '+inr(x.paid_total)+'</div>':'')+'</td>'+
      '<td class="num"><button class="btn sm '+(need?"primary":"")+'">'+(need?"Review":"View")+'</button></td></tr>';
  }).join("");
  if(!rows) rows = '<tr><td colspan="5" class="empty">Nothing has been shared with you yet.</td></tr>';
  var v = S.vendors[0];
  var sites = {}; mine.forEach(function(x){ sites[x.site_name]=1; });
  var sl = Object.keys(sites);
  return '<div class="page-h"><div><h1>'+esc(v?v.name:"Your statements")+'</h1>'+
    '<p>'+esc(S.profile.full_name||S.profile.email)+
    (sl.length?' &middot; '+sl.length+' site'+(sl.length===1?"":"s")+': '+esc(sl.join(", ")):'')+'</p></div></div>'+
   '<div class="banner b-blue"><div class="ico">&#9432;</div><div><b>How this works</b>'+
    'Every month you get a statement for each of your sites. Check it and either <b>approve</b> it, or <b>raise a point</b> on the exact line you disagree with. '+
    'Points raised here are on record with the date and time. If you speak to WeVois on the phone, that point is written down here too and sent to you to confirm &mdash; '+
    'so nothing gets lost on either side. The <b>Payroll</b> tab carries the PF and ESIC challan numbers, so you can check the deposits yourself.</div></div>'+
   '<div class="card"><div class="card-h"><h2>Your statements</h2></div><div class="card-b tight">'+
   '<table class="hoverable"><thead><tr><th>Site</th><th>Month</th><th>Status</th>'+
   '<th class="num">Amount payable to you</th><th></th></tr></thead><tbody>'+rows+'</tbody></table></div></div>';
}

/* ====================================================================== */
/*  STATEMENT                                                             */
/* ====================================================================== */
function viewStatement(){
  var st = S.stmt, v = curVer(st);
  var prPending = !st.payroll || st.payroll.status !== "posted";
  var isDraft = st.statement.status === "draft";
  var pend = pendingChanges(st);

  var backLabel = S.profile.role==="vendor" ? "All my statements"
    : S.profile.role==="accounts" ? "Accounts queue" : "All settlements";
  var back = '<div class="brk"><a href="#" data-act="back">&larr; '+backLabel+'</a></div>';

  var covers = st.statement.covers_from
    ? ' &middot; settled for '+dOnly(st.statement.covers_from)+' to '+dOnly(st.statement.covers_to) : '';
  var tenure = (st.site_history||[]).length > 1
    ? ' <span class="lockpill">this site has changed hands &mdash; '+st.site_history.length+' tenures</span>' : '';

  var headHtml = '<div class="page-h"><div style="flex:1;min-width:240px">'+
    '<h1>'+esc(st.vendor.name)+' &mdash; '+esc(st.site.name)+'</h1>'+
    '<p>'+esc(st.period_label)+' &middot; '+(st.vendor.code?esc(st.vendor.code)+' &middot; ':'')+
    st.contract.vehicles+' vehicles &middot; version '+v.v+
    (v.sent_at? ' shared '+dt(v.sent_at) : ' (not shared yet)')+covers+tenure+'</p></div>'+
    '<div style="text-align:right">'+statusChip(st.statement.status)+
    '<div style="font-size:24px;font-weight:700;margin-top:7px;font-variant-numeric:tabular-nums;letter-spacing:-.02em">'+inr(v.final)+'</div>'+
    '<div style="font-size:12px;color:var(--muted)">final amount for payment</div></div></div>';

  var b = observerBanner();
  if(isDraft && prPending)
    b += '<div class="banner b-teal"><div class="ico">&#9203;</div><div><b>Waiting on Accounts</b>'+
      'Processed salary, wages and PF/ESIC have not been posted for this month, so those heads are still zero and this statement cannot be shared. '+
      (can("post_payroll")?'Open the <b>Payroll</b> tab to post them.':'Accounts posts them from the Payroll tab.')+'</div></div>';
  if(can("edit_draft") && isDraft && !prPending)
    b += '<div class="banner b-blue"><div class="ico">&#9998;</div><div><b>Draft &mdash; only WeVois can see this</b>'+
      'Enter what the partner earned and the running heads, then share. The moment you share, this version freezes: it can never be edited, '+
      'only replaced by a new version with a visible list of what changed.</div></div>';
  if(can("revise") && pend>0 && ["approved","part_paid","paid"].indexOf(st.statement.status)<0)
    b += '<div class="banner b-amber"><div class="ico">&#8635;</div><div><b>'+pend+' change'+(pend===1?"":"s")+' not yet sent to the vendor</b>'+
      'Issue a revised statement so he sees the corrected figures and the reasons.</div>'+
      '<div style="margin-left:auto"><button class="btn primary" data-act="revise">Issue revised statement</button></div></div>';
  if(st.payroll && st.payroll.pending_fix)
    b += '<div class="banner b-teal"><div class="ico">&#8635;</div><div><b>Accounts posted a payroll correction</b>'+
      esc(st.payroll.pending_fix_why||"")+' &mdash; '+esc(st.payroll.pending_fix_by||"")+', '+dt(st.payroll.pending_fix_at)+
      '. It reaches the vendor when the next version is issued.</div></div>';
  if(S.profile.role==="vendor"){
    var ac = (st.points||[]).filter(function(p){ return p.status==="awaiting_confirm"; })[0];
    if(ac) b += '<div class="banner b-violet"><div class="ico">&#9742;</div><div><b>Confirm what you said on the call</b>'+
      'On '+dt(ac.raised_at)+' WeVois recorded this point on your behalf, against <b>'+esc(ac.target_label)+'</b>:<br><i>&ldquo;'+esc(ac.note)+'&rdquo;</i></div>'+
      '<div style="margin-left:auto;display:flex;gap:8px">'+
      '<button class="btn" data-act="denycall" data-pid="'+ac.id+'">Not what I said</button>'+
      '<button class="btn primary" data-act="confirmcall" data-pid="'+ac.id+'">Yes, confirm</button></div></div>';
    if(["sent","under_query"].indexOf(st.statement.status)>=0 && st.statement.due_at)
      b += '<div class="banner b-amber"><div class="ico">&#9201;</div><div><b>Please respond by '+dt(st.statement.due_at)+'</b>'+
        'If nothing is raised by then, this statement is treated as accepted and goes for payment &mdash; and that is recorded too.</div></div>';
  }
  if(["approved","part_paid","paid"].indexOf(st.statement.status)>=0){
    var bal = Number(st.statement.approved_amount||0) - Number(st.paid_total||0);
    b += '<div class="banner b-green"><div class="ico">&#10003;</div><div><b>Approved by the vendor</b>'+
      esc(st.statement.approved_by||"")+' approved '+inr(st.statement.approved_amount)+' against version '+
      st.statement.approved_version+' on '+dt(st.statement.approved_at)+'. '+
      ((st.payments||[]).length
        ? 'Paid so far '+inr(st.paid_total)+(bal>0.005?', balance outstanding '+inr(bal)+'.':' &mdash; settled in full.')
        : 'Awaiting payment release by Accounts.')+'</div></div>';
  }

  var op = openPoints(st);
  var tabDefs = [
    ["sheet","Statement"],
    ["payroll","Payroll &amp; PF/ESIC"+(prPending?'<span class="cnt" style="background:var(--red)">!</span>':'')],
    ["points","Points"+((st.points||[]).length?'<span class="cnt" style="'+(op?'':'background:var(--faint)')+'">'+st.points.length+'</span>':'')],
    ["versions","Versions ("+st.versions.length+")"],
    ["payments","Payments ("+(st.payments||[]).length+")"],
    ["record","Full record"]
  ];
  var tabs = '<div class="tabs">'+tabDefs.map(function(t){
    return '<button data-act="tab" data-v="'+t[0]+'" class="'+(S.tab===t[0]?"on":"")+'">'+t[1]+'</button>'; }).join("")+'</div>';

  var body = S.tab==="sheet" ? tabSheet() : S.tab==="payroll" ? tabPayroll()
    : S.tab==="points" ? tabPoints() : S.tab==="versions" ? tabVersions()
    : S.tab==="payments" ? tabPayments() : tabRecord();

  return back+headHtml+b+tabs+
    '<div class="card" style="border-top:0;border-radius:0 0 var(--radius) var(--radius);margin-top:0">'+body+'</div>';
}

/* ------------------------------------------------------------- tab: sheet */
var GRP_LABEL = {run:"Vehicle &amp; Running", wages:"Manpower &mdash; Driver / Helper",
                 staff:"Manpower &mdash; Staff", esic:"ESIC / PF", other:"Other"};

function tabSheet(){
  var st = S.stmt, v = curVer(st);
  var isDraft = st.statement.status === "draft";
  var editable = can("edit_draft") && isDraft;
  var prPending = !st.payroll || st.payroll.status !== "posted";
  var canRaise = can("raise") && ["sent","under_query"].indexOf(st.statement.status)>=0;
  var canLog   = can("logcall") && ["sent","under_query"].indexOf(st.statement.status)>=0;

  if(editable && !S.draft){
    var lines = {};
    v.lines.forEach(function(l){ lines[l.head_key] = Number(l.amount)||0; });
    S.draft = {
      gross: Number(v.gross)||0,
      note: v.gross_note||"",
      lines: lines,
      adj: (v.adjustments||[]).filter(function(a){ return !a.payroll_linked; }).map(function(a){
        return {label:a.label, effect:a.effect, amount:Number(a.amount)||0,
                reference:a.reference||"", note:a.note||""}; })
    };
  }
  var D = S.draft;

  var rows = '<tr class="gross-row"><td>Total Expenses Should Be Paid'+
    ' <span style="font-weight:400;color:var(--muted)">&mdash; what the partner earned this month</span></td>'+
    '<td class="num">'+(editable
      ? '<input class="inp num" style="max-width:160px;display:inline-block" value="'+D.gross+'" data-act="draft" data-k="__gross">'
      : '<b>'+inr(v.gross)+'</b>')+'</td><td></td></tr>';
  if(editable)
    rows += '<tr class="memo-row"><td colspan="3" style="padding-left:26px">Basis / note: '+
      '<input class="inp" style="max-width:460px;display:inline-block" value="'+esc(D.note)+'" data-act="draft" data-k="__note" '+
      'placeholder="e.g. 20 vehicles x 45,000 per the duty sheet"></td></tr>';
  else if(v.gross_note)
    rows += '<tr class="memo-row"><td colspan="3" style="padding-left:26px">Basis: '+esc(v.gross_note)+'</td></tr>';

  var groups = {};
  (v.lines||[]).forEach(function(l){ (groups[l.grp] = groups[l.grp] || []).push(l); });
  Object.keys(groups).forEach(function(g){
    rows += '<tr class="grp-row"><td colspan="3">less &mdash; '+(GRP_LABEL[g]||esc(g))+'</td></tr>';
    groups[g].forEach(function(l){
      var pt = (st.points||[]).filter(function(p){ return p.target_kind==="head" && p.target_key===l.head_key; })[0];
      var chip = pt ? ' <span class="chip '+(pt.status==="open"?"c-amber":pt.status==="awaiting_confirm"?"c-violet":
        (pt.status==="rejected"||pt.status==="disputed_record")?"c-red":pt.status==="carry_forward"?"c-blue":"c-green")+
        '"><span class="d"></span>'+esc(String(pt.status).replace(/_/g," "))+'</span>' : '';
      var ed = editable && l.src==="manual";
      rows += '<tr><td style="padding-left:26px">'+esc(l.head_label)+
        (l.src==="payroll"?' <span class="lockpill">payroll</span>':'')+chip+'</td>'+
        '<td class="num">'+(ed
          ? '<input class="inp num" style="max-width:150px;display:inline-block" value="'+(D.lines[l.head_key]||0)+
            '" data-act="draft" data-k="'+esc(l.head_key)+'">'
          : '<b>'+inr(l.amount)+'</b>')+'</td>'+
        '<td class="num" style="width:112px">'+(canRaise
          ? '<button class="btn sm" data-act="raise" data-kind="head" data-key="'+esc(l.head_key)+'" data-label="'+esc(l.head_label)+'">Raise point</button>'
          : canLog
          ? '<button class="btn sm" data-act="logcall" data-kind="head" data-key="'+esc(l.head_key)+'" data-label="'+esc(l.head_label)+'">&#9742; Log call</button>'
          : '')+'</td></tr>';
    });
  });

  rows += '<tr class="memo-row"><td>Expenses paid by company <span style="color:var(--faint)">(sum of the heads)</span></td>'+
    '<td class="num">'+inr(v.heads_total)+'</td><td></td></tr>';
  rows += '<tr class="tot-row"><td><b>Total</b> <span style="font-weight:400;color:var(--muted)">'+
    '&mdash; earned, less what we spent for him</span></td><td class="num">'+inr(v.total)+'</td><td></td></tr>';

  rows += '<tr class="grp-row"><td colspan="3">Adjustments</td></tr>';
  if(editable){
    var linked = (v.adjustments||[]).filter(function(a){ return a.payroll_linked; });
    rows += '<tr><td colspan="3" style="padding:12px 14px">'+adjEditor(D.adj)+
      '<div class="btnrow" style="margin-top:6px"><button class="btn sm" data-act="adj-add">+ Add an adjustment line</button></div>'+
      linked.map(function(a){
        return '<div class="hint" style="margin-top:8px">Posted by Accounts: <b>'+esc(a.label)+'</b> '+
          '<span class="'+effClass(a.effect)+'">'+effSign(a.effect)+inr(a.amount)+'</span>'+
          (a.note?' &mdash; '+esc(a.note):'')+'</div>'; }).join("")+
      '</td></tr>';
  } else {
    (v.adjustments||[]).forEach(function(a){
      var pt = (st.points||[]).filter(function(p){ return p.target_kind==="adjustment" && p.target_label===a.label; })[0];
      var chip = pt ? ' <span class="chip '+(pt.status==="open"?"c-amber":
        (pt.status==="accepted"||pt.status==="partial")?"c-green":"c-red")+
        '"><span class="d"></span>'+esc(String(pt.status).replace(/_/g," "))+'</span>' : '';
      rows += '<tr class="ded-row"><td style="padding-left:26px">'+esc(a.label)+
        (a.payroll_linked?' <span class="lockpill">payroll</span>':'')+chip+
        (a.reference?'<div style="font-size:12px;color:var(--muted)">ref '+esc(a.reference)+'</div>':'')+
        (a.note?'<div style="font-size:12px;color:var(--muted)">'+esc(a.note)+'</div>':'')+
        (a.effect==="note"?'<div style="font-size:12px;color:var(--faint)">recorded only &mdash; does not change the amount</div>':'')+'</td>'+
        '<td class="num"><span class="'+effClass(a.effect)+'">'+effSign(a.effect)+inr(a.amount)+'</span></td>'+
        '<td class="num">'+(canRaise
          ? '<button class="btn sm" data-act="raise" data-kind="adjustment" data-key="'+esc(a.id)+'" data-label="'+esc(a.label)+'">Raise point</button>'
          : canLog
          ? '<button class="btn sm" data-act="logcall" data-kind="adjustment" data-key="'+esc(a.id)+'" data-label="'+esc(a.label)+'">&#9742; Log call</button>'
          : '')+'</td></tr>';
    });
    if(!(v.adjustments||[]).length)
      rows += '<tr><td colspan="3" style="color:var(--faint);padding-left:26px">No adjustments on this version.</td></tr>';
  }

  rows += '<tr class="final-row"><td>Final amount for payment</td><td class="num">'+inr(v.final)+'</td><td></td></tr>';
  if(Number(st.contract.vehicles)>0)
    rows += '<tr class="memo-row"><td>Memo &mdash; company spend per vehicle ('+st.contract.vehicles+' vehicles)</td>'+
      '<td class="num">'+inr(Number(v.heads_total)/Number(st.contract.vehicles))+'</td><td></td></tr>';

  var acts = [];
  if(editable) acts.push('<button class="btn primary" data-act="savedraft">Save draft</button>');
  if(can("share") && isDraft){
    acts.push('<button class="btn go" data-act="share"'+(prPending?" disabled":"")+'>Share with vendor</button>');
    if(prPending) acts.push('<span style="font-size:12.5px;color:var(--muted)">Blocked until Accounts posts the payroll.</span>');
  }
  if(canLog) acts.push('<button class="btn" data-act="logcall" data-kind="head" data-key="" data-label="">&#9742; Log a point from a call</button>');
  if(can("remind") && ["sent","under_query"].indexOf(st.statement.status)>=0)
    acts.push('<button class="btn" data-act="remind">Send reminder</button>');
  if(canRaise){
    var blocked = openPoints(st)>0;
    acts.push('<button class="btn go" data-act="approve"'+(blocked?" disabled":"")+'>Approve '+inr(v.final)+'</button>');
    acts.push('<button class="btn" data-act="raise" data-kind="head" data-key="" data-label="">Raise a point</button>');
    if(blocked) acts.push('<span style="font-size:12.5px;color:var(--muted)">You have an open point &mdash; approval opens once WeVois responds.</span>');
  }
  if(can("pay") && ["approved","part_paid"].indexOf(st.statement.status)>=0)
    acts.push('<button class="btn go" data-act="pay">Release a payment</button>');
  acts.push('<button class="btn" data-act="print">Print / PDF</button>');

  return '<div class="card-b"><div class="btnrow">'+acts.join("")+'</div></div>'+
    '<table><thead><tr><th>Working</th><th class="num">'+esc(st.period_label)+'</th><th></th></tr></thead>'+
    '<tbody>'+rows+'</tbody></table>';
}

function adjEditor(list){
  var opts = S.adjTypes.map(function(t){
    return '<option value="'+esc(t.label)+'" data-eff="'+esc(t.effect)+'">'+esc(t.label)+'</option>'; }).join("");
  var out = '<div class="adjrow" style="font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--faint);font-weight:650">'+
    '<div>Line</div><div>Effect</div><div style="text-align:right">Amount</div><div>Reference</div><div></div></div>';
  out += list.map(function(a,i){
    var known = S.adjTypes.some(function(t){ return t.label===a.label; });
    return '<div class="adjrow">'+
      '<select class="inp" data-act="adjf" data-i="'+i+'" data-f="label">'+
        (known?'':'<option value="'+esc(a.label)+'" selected>'+esc(a.label)+'</option>')+
        S.adjTypes.map(function(t){
          return '<option value="'+esc(t.label)+'" data-eff="'+esc(t.effect)+'"'+(t.label===a.label?" selected":"")+'>'+
            esc(t.label)+'</option>'; }).join("")+'</select>'+
      '<select class="inp" data-act="adjf" data-i="'+i+'" data-f="effect">'+
        [["add","credits him"],["deduct","reduces payment"],["note","recorded only"]].map(function(o){
          return '<option value="'+o[0]+'"'+(a.effect===o[0]?" selected":"")+'>'+o[1]+'</option>'; }).join("")+'</select>'+
      '<input class="inp num" data-act="adjf" data-i="'+i+'" data-f="amount" value="'+a.amount+'">'+
      '<input class="inp" data-act="adjf" data-i="'+i+'" data-f="reference" value="'+esc(a.reference)+'" placeholder="UTR, date, bill no.">'+
      '<button class="rmx" data-act="adj-del" data-i="'+i+'" title="remove">&times;</button></div>';
  }).join("");
  if(!list.length) out += '<div class="hint">No adjustment lines yet. Advances, direct payments, penalties, '+
    'reimbursements, TDS &mdash; anything that moves the final amount away from the total goes here. '+
    'A line marked <b>recorded only</b> appears on the statement without changing the figure.</div>';
  return out;
}

/* ----------------------------------------------------------- tab: payroll */
function tabPayroll(){
  var st = S.stmt, p = st.payroll || {};
  var ed = can("post_payroll") && st.statement.status!=="paid";
  function fMoney(id,v){ return ed
    ? '<input class="inp num" id="'+id+'" value="'+(Number(v)||0)+'">'
    : '<div style="padding:7px 0;font-weight:650;font-variant-numeric:tabular-nums">'+inr(v)+'</div>'; }
  function fCount(id,v){ return ed
    ? '<input class="inp num" id="'+id+'" value="'+(Number(v)||0)+'">'
    : '<div style="padding:7px 0;font-weight:650">'+(Number(v)||0)+' persons</div>'; }
  function fText(id,v,ph){ return ed
    ? '<input class="inp" id="'+id+'" value="'+esc(v||"")+'" placeholder="'+esc(ph||"")+'">'
    : '<div style="padding:7px 0;font-weight:650">'+(v?esc(v):'<span style="color:var(--faint);font-weight:400">not entered</span>')+'</div>'; }

  var status = p.status==="posted"
    ? '<div class="banner b-green"><div class="ico">&#10003;</div><div><b>Payroll posted</b>'+
      esc(p.posted_by||"")+' &middot; '+dt(p.posted_at)+
      '. These figures feed six heads and one adjustment on the statement, and are locked to every other role.</div></div>'
    : '<div class="banner b-teal"><div class="ico">&#9203;</div><div><b>Not posted yet</b>'+
      (ed?'Enter the processed figures below and post them. The vendor manager cannot share the statement until you do.'
         :'Accounts has not posted the processed salary and PF/ESIC for this month. The manpower heads stay at zero until they do.')+'</div></div>';

  var pf = (Number(p.dh_pf_ee)||0)+(Number(p.dh_pf_er)||0)+(Number(p.stf_pf_ee)||0)+(Number(p.stf_pf_er)||0);
  var es = (Number(p.dh_esic_ee)||0)+(Number(p.dh_esic_er)||0)+(Number(p.stf_esic_ee)||0)+(Number(p.stf_esic_er)||0);

  var vendorNote = (S.profile.role==="vendor" && p.status==="posted")
    ? '<div class="banner b-blue"><div class="ico">&#129534;</div><div><b>Check the deposits yourself</b>'+
      'PF was deposited under TRRN <b>'+esc(p.pf_trrn||"—")+'</b> on '+dOnly(p.pf_paid_on)+
      ' and ESIC under challan <b>'+esc(p.esic_challan||"—")+'</b> on '+dOnly(p.esic_paid_on)+
      '. These are the same references filed with the departments.</div></div>' : "";

  var act = ed ? '<div class="btnrow" style="margin-bottom:16px"><button class="btn teal" data-act="postpayroll">'+
    (p.status==="posted"?"Post a payroll correction":"Post payroll to the statement")+'</button>'+
    (p.status==="posted"?'<span style="font-size:12.5px;color:var(--muted)">A correction after sharing goes out as a new version, with the reason.</span>':'')+
    '</div>' : "";

  return '<div class="card-b">'+status+vendorNote+act+
    '<h3 style="font-size:14px;margin:4px 0 10px">Driver / helper &mdash; processed by WeVois</h3>'+
    '<div class="grid2">'+
      '<div class="fld"><label class="fl">Wages processed</label>'+fMoney("dh_pay",p.dh_pay)+'</div>'+
      '<div class="fld"><label class="fl">Headcount</label>'+fCount("dh_heads",p.dh_heads)+'</div>'+
      '<div class="fld"><label class="fl">PF &mdash; employee part</label>'+fMoney("dh_pf_ee",p.dh_pf_ee)+'</div>'+
      '<div class="fld"><label class="fl">PF &mdash; employer part</label>'+fMoney("dh_pf_er",p.dh_pf_er)+'</div>'+
      '<div class="fld"><label class="fl">ESIC &mdash; employee part</label>'+fMoney("dh_esic_ee",p.dh_esic_ee)+'</div>'+
      '<div class="fld"><label class="fl">ESIC &mdash; employer part</label>'+fMoney("dh_esic_er",p.dh_esic_er)+'</div>'+
    '</div>'+
    '<h3 style="font-size:14px;margin:14px 0 10px">Staff &mdash; processed by WeVois</h3>'+
    '<div class="grid2">'+
      '<div class="fld"><label class="fl">Salary processed</label>'+fMoney("stf_pay",p.stf_pay)+'</div>'+
      '<div class="fld"><label class="fl">Headcount</label>'+fCount("stf_heads",p.stf_heads)+'</div>'+
      '<div class="fld"><label class="fl">PF &mdash; employee part</label>'+fMoney("stf_pf_ee",p.stf_pf_ee)+'</div>'+
      '<div class="fld"><label class="fl">PF &mdash; employer part</label>'+fMoney("stf_pf_er",p.stf_pf_er)+'</div>'+
      '<div class="fld"><label class="fl">ESIC &mdash; employee part</label>'+fMoney("stf_esic_ee",p.stf_esic_ee)+'</div>'+
      '<div class="fld"><label class="fl">ESIC &mdash; employer part</label>'+fMoney("stf_esic_er",p.stf_esic_er)+'</div>'+
    '</div>'+
    '<h3 style="font-size:14px;margin:14px 0 10px">Challan references</h3>'+
    '<div class="grid2">'+
      '<div class="fld"><label class="fl">PF challan / TRRN</label>'+fText("pf_trrn",p.pf_trrn,"RJRAJ...")+'</div>'+
      '<div class="fld"><label class="fl">PF deposited on</label>'+fText("pf_paid_on",p.pf_paid_on,"YYYY-MM-DD")+'</div>'+
      '<div class="fld"><label class="fl">ESIC challan no.</label>'+fText("esic_challan",p.esic_challan,"ESIC/...")+'</div>'+
      '<div class="fld"><label class="fl">ESIC deposited on</label>'+fText("esic_paid_on",p.esic_paid_on,"YYYY-MM-DD")+'</div>'+
      '<div class="fld"><label class="fl">Payroll processed on</label>'+fText("processed_on",p.processed_on,"YYYY-MM-DD")+'</div>'+
      '<div class="fld"><label class="fl">PF total / ESIC total</label>'+
        '<div style="padding:7px 0;font-weight:650;font-variant-numeric:tabular-nums">'+inr(pf)+' / '+inr(es)+'</div></div>'+
    '</div>'+
    '<h3 style="font-size:14px;margin:14px 0 10px">Not processed from WeVois</h3>'+
    '<div class="fld"><label class="fl">Amount &mdash; credited back to the partner</label>'+
      fMoney("not_processed_amount",p.not_processed_amount)+'</div>'+
    '<div class="fld"><label class="fl">Reason &mdash; the vendor sees this</label>'+
      (ed?'<textarea class="inp" id="not_processed_reason">'+esc(p.not_processed_reason||"")+'</textarea>'
         :'<div style="padding:7px 0;color:var(--ink-2)">'+esc(p.not_processed_reason||"—")+'</div>')+'</div>'+
    '</div>';
}

/* ------------------------------------------------------------ tab: points */
var PT_CHIP = {
  open:'<span class="chip c-amber"><span class="d"></span>Open - with WeVois</span>',
  awaiting_confirm:'<span class="chip c-violet"><span class="d"></span>Awaiting vendor confirmation</span>',
  accepted:'<span class="chip c-green"><span class="d"></span>Accepted</span>',
  partial:'<span class="chip c-green"><span class="d"></span>Partly accepted</span>',
  rejected:'<span class="chip c-red"><span class="d"></span>Rejected, with reason</span>',
  disputed_record:'<span class="chip c-red"><span class="d"></span>Vendor disputes the written record</span>',
  carry_forward:'<span class="chip c-blue"><span class="d"></span>Carried forward to next month</span>'
};
function tabPoints(){
  var st = S.stmt, pts = st.points||[];
  if(!pts.length) return '<div class="empty">No points raised on this statement.</div>';
  var out = pts.map(function(p){
    var k = p.status==="open"?"open":p.status==="awaiting_confirm"?"confirm":p.status==="carry_forward"?"cf":"done";
    var ourV = verByNo(st, p.version_no), our = 0;
    if(ourV){
      if(p.target_kind==="head") (ourV.lines||[]).forEach(function(l){ if(l.head_key===p.target_key) our = Number(l.amount)||0; });
      else (ourV.adjustments||[]).forEach(function(a){ if(a.label===p.target_label) our = Number(a.amount)||0; });
    }
    return '<div class="pt '+k+'">'+
      '<div class="pt-h">'+(PT_CHIP[p.status]||"")+
        '<span class="chip c-grey">'+(p.source==="call"?"&#9742; raised by phone":"raised in portal")+'</span>'+
        '<span class="pt-head">'+esc(p.target_label)+'</span><div style="flex:1"></div>'+
        '<span class="when">v'+p.version_no+' &middot; '+dt(p.raised_at)+'</span></div>'+
      '<div class="pt-h" style="margin-bottom:4px"><span class="who">'+esc(p.raised_by)+'</span></div>'+
      '<div class="pt-body">&ldquo;'+esc(p.note)+'&rdquo;</div>'+
      (p.attachment?'<div class="pt-att">&#128206; '+esc(p.attachment)+'</div>':'')+
      '<div class="pt-figs"><div>Our figure<b>'+inr(our)+'</b></div>'+
        (p.claimed!=null?'<div>Vendor says<b>'+inr(p.claimed)+'</b></div>'+
          '<div>Difference<b>'+inr(Number(p.claimed)-our)+'</b></div>':'')+'</div>'+
      (p.confirmed_at && p.status!=="disputed_record"
        ? '<div class="pt-att" style="color:var(--violet)">&#10003; Vendor confirmed this is what he said on the call &mdash; '+dt(p.confirmed_at)+'</div>':'')+
      (p.decision?'<div class="pt-dec"><b>WeVois response:</b> '+esc(p.decision)+
        (p.new_amount!=null?'<br>Amount revised to <b>'+inr(p.new_amount)+'</b>.':'')+
        '<div class="m">'+esc(p.decided_by||"")+' &middot; '+dt(p.decided_at)+
        (p.published?' &middot; published in v'+p.published_in:' &middot; not yet sent to the vendor')+'</div></div>':'')+
      (can("resolve") && p.status==="open"
        ? '<div class="btnrow" style="margin-top:12px"><button class="btn primary sm" data-act="resolve" data-pid="'+p.id+'" '+
          'data-label="'+esc(p.target_label)+'" data-our="'+our+'" data-claimed="'+(p.claimed==null?"":p.claimed)+'" '+
          'data-note="'+esc(p.note)+'" data-kind="'+esc(p.target_kind)+'" data-src="'+esc(p.target_key)+'">Resolve this point</button></div>':'')+
      (can("resolve") && p.status==="awaiting_confirm"
        ? '<div class="pt-att" style="color:var(--violet)">Waiting for the vendor to confirm this is what he said. '+
          'Until he confirms it is not worked on &mdash; and it can never be denied later.</div>':'')+
      '</div>';
  }).join("");
  return '<div class="card-b">'+out+
    (can("revise") && pendingChanges(st)
      ? '<div class="btnrow"><button class="btn primary" data-act="revise">Issue revised statement</button></div>':'')+
    '</div>';
}

/* ---------------------------------------------------------- tab: versions */
function tabVersions(){
  var st = S.stmt, out = "";
  for(var i=st.versions.length-1;i>=0;i--){
    var v = st.versions[i], ch = "";
    if(v.changes && v.changes.length){
      ch = '<table style="margin-top:10px"><thead><tr><th>Line</th><th class="num">Was</th>'+
        '<th class="num">Now</th><th>Why</th></tr></thead><tbody>'+
        v.changes.map(function(c){
          return '<tr><td>'+esc(c.label)+'</td><td class="num diff-old">'+inr(c.from)+'</td>'+
            '<td class="num diff-new">'+inr(c.to)+'</td>'+
            '<td style="font-size:12.5px;color:var(--ink-2)">'+esc(c.why)+'</td></tr>'; }).join("")+
        '</tbody></table>';
    } else if(v.v>1){
      ch = '<div style="font-size:13px;color:var(--muted);margin-top:8px">No amount changed &mdash; reissued after points were answered.</div>';
    }
    out += '<div class="pt '+(i===st.versions.length-1?"cf":"done")+'">'+
      '<div class="pt-h"><span class="who">Version '+v.v+'</span>'+
      (v.sent_at?'<span class="chip c-grey">shared '+dt(v.sent_at)+'</span>':'<span class="chip c-grey">draft</span>')+
      (v.viewed_at?'<span class="chip c-grey">vendor opened '+dt(v.viewed_at)+'</span>':'')+
      (i===st.versions.length-1?'<span class="chip c-blue"><span class="d"></span>current</span>':'')+
      '<div style="flex:1"></div><span class="when">Earned '+inr(v.gross)+' &middot; Final '+inr(v.final)+'</span></div>'+
      (v.note?'<div class="pt-body">'+esc(v.note)+'</div>':'')+ch+'</div>';
  }
  return '<div class="card-b"><div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#128274;</div><div>'+
    '<b>Shared versions are frozen</b>A version that has gone to the vendor can never be edited &mdash; not by the vendor manager, '+
    'not by Accounts, not by an administrator, and not by calling the database directly. Corrections create a new version, '+
    'and every changed figure is listed with its reason.</div></div>'+out+'</div>';
}

/* ---------------------------------------------------------- tab: payments */
function tabPayments(){
  var st = S.stmt, ps = st.payments||[];
  var appr = Number(st.statement.approved_amount||0), paid = Number(st.paid_total||0), bal = appr-paid;
  var rows = ps.map(function(p){
    return '<tr><td>'+dOnly(p.paid_on)+'</td><td><b>'+esc(p.utr)+'</b>'+
      '<div style="font-size:12px;color:var(--muted)">'+esc(p.mode||"")+(p.note?' &middot; '+esc(p.note):'')+'</div></td>'+
      '<td style="font-size:12.5px;color:var(--muted)">'+esc(p.recorded_by||"")+'</td>'+
      '<td class="num"><b>'+inr(p.amount)+'</b></td></tr>'; }).join("");
  if(!rows) rows = '<tr><td colspan="4" class="empty">No payment recorded yet.</td></tr>';
  var box = appr>0
    ? '<div class="kpis" style="margin:0">'+
      '<div class="kpi"><div class="l">Approved</div><div class="v">'+inr(appr)+'</div><div class="n">version '+st.statement.approved_version+'</div></div>'+
      '<div class="kpi"><div class="l">Paid so far</div><div class="v" style="color:var(--teal)">'+inr(paid)+'</div>'+
        '<div class="n">'+ps.length+' payment'+(ps.length===1?"":"s")+'</div></div>'+
      '<div class="kpi"><div class="l">Balance</div><div class="v" style="color:'+(bal>0.005?"var(--amber)":"var(--green)")+'">'+inr(bal)+'</div>'+
        '<div class="n">'+(bal>0.005?"outstanding":"settled in full")+'</div></div></div>'
    : '<div class="banner b-grey" style="margin:0"><div class="ico">&#9432;</div><div>Payment opens once the vendor approves a version.</div></div>';
  return '<div class="card-b">'+box+
    (can("pay") && ["approved","part_paid"].indexOf(st.statement.status)>=0
      ? '<div class="btnrow" style="margin-top:14px"><button class="btn go" data-act="pay">Release a payment</button></div>':'')+
    '<div class="hint" style="margin-top:12px">One approved statement can be paid in parts. Each part carries its own UTR and date, '+
    'and the balance stays visible until it clears.</div></div>'+
    '<table><thead><tr><th>Date</th><th>UTR / reference</th><th>Recorded by</th><th class="num">Amount</th></tr></thead>'+
    '<tbody>'+rows+'</tbody></table>';
}

/* ------------------------------------------------------------ tab: record */
function tabRecord(){
  var st = S.stmt;
  var out = (st.events||[]).map(function(e){
    var cls = ["hi","ok","warn","pay"].indexOf(e.kind)>=0 ? e.kind : "";
    return '<div class="tl-i '+cls+'"><div class="tl-t">'+esc(e.title)+'</div>'+
      '<div class="tl-m">'+esc(e.actor_name)+' ('+esc(ROLE_LABEL[e.actor_role]||e.actor_role)+') &middot; '+dt(e.at)+'</div>'+
      (e.body?'<div class="tl-x">'+esc(e.body)+'</div>':'')+'</div>'; }).join("");
  var hist = (st.site_history||[]).length>1
    ? '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#8618;</div><div><b>This site has changed hands</b>'+
      st.site_history.map(function(h){
        return esc(h.vendor_name)+' ('+esc(h.from_label)+' to '+esc(h.to_label)+', '+h.settlements+' settlements)'; })
      .join(' &rarr; ')+'</div></div>' : "";
  return '<div class="card-b"><div class="banner b-grey" style="margin-bottom:18px"><div class="ico">&#128209;</div><div>'+
    '<b>Everything, in order, with a timestamp and a role</b>Created, payroll posted, shared, opened, every point, '+
    'every phone call written down, every decision and its reason, the approval, each payment. '+
    'Nothing here can be edited or deleted by any role. This is the answer to &ldquo;I told you&rdquo; and to &ldquo;you never told me&rdquo;.'+
    '</div></div>'+hist+'<div class="tl">'+(out||'<div class="empty">No events yet.</div>')+'</div></div>';
}
