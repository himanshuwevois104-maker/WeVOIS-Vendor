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
    '<button class="btn sm" data-act="changepw" style="background:#1c2534;border-color:#2c3648;color:#fff">Change password</button>'+
    '<button class="btn sm" data-act="signout" style="background:#1c2534;border-color:#2c3648;color:#fff">Sign out</button>'+
    '</div></div>';

  var body;
  if(S.open && S.stmt)                 body = viewStatement();
  else if(S.site)                      body = viewSite();
  else if(S.profile.role==="admin")    body = viewAdmin();
  else if(isObserver())                body = viewLeadership();
  else if(S.profile.role==="vendor")   body = viewVendorHome();
  else if(S.profile.role==="accounts") body = viewAccountsHome();
  else                                 body = viewManagerHome();

  document.getElementById("app").innerHTML = bar + '<div class="wrap">'+schemaBanner()+body+'</div>';
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

/* --------------------------------------------------- site blocks and drill-in */
/* One block per site rather than one long list of every vendor-month. A month
   only means something in the context of its site, and a site with eleven
   months of history reads as a place, not as eleven rows. */
function sitesOf(list){
  var by = {};
  list.forEach(function(x){
    var k = x.site_id;
    if(!by[k]) by[k] = {id:k, name:x.site_name, months:[], vendors:{}, vehicles:x.vehicles,
                        payable:0, outstanding:0, openPts:0, blocked:0, awaiting:0};
    var s = by[k];
    s.months.push(x);
    s.vendors[x.vendor_name] = 1;
    s.openPts += Number(x.open_points)||0;
    if(x.payroll_status !== "posted") s.blocked++;
    if(x.status==="sent"||x.status==="under_query") s.awaiting++;
    if(x.status==="approved"||x.status==="part_paid")
      s.outstanding += Number(x.approved_amount||0) - Number(x.paid_total||0);
    if(String(x.period).slice(0,10) === S.period) s.payable += Number(x.final)||0;
  });
  return Object.keys(by).map(function(k){ return by[k]; })
    .sort(function(a,b){ return a.name < b.name ? -1 : 1; });
}

function siteBlocks(list){
  var ss = sitesOf(list);
  if(!ss.length) return '<div class="empty">Nothing here yet.</div>';
  return '<div class="blocks">'+ss.map(function(s){
    var vn = Object.keys(s.vendors);
    var latest = s.months.slice().sort(function(a,b){ return String(a.period) < String(b.period) ? 1 : -1; })[0];
    var flags = [];
    if(s.blocked)  flags.push('<span class="chip c-red"><span class="d"></span>'+s.blocked+' payroll pending</span>');
    if(s.openPts)  flags.push('<span class="chip c-amber"><span class="d"></span>'+s.openPts+' open point'+(s.openPts===1?'':'s')+'</span>');
    if(s.awaiting) flags.push('<span class="chip c-blue"><span class="d"></span>'+s.awaiting+' with vendor</span>');
    if(s.outstanding > 0.005) flags.push('<span class="chip c-green"><span class="d"></span>'+inr(s.outstanding)+' to pay</span>');
    return '<div class="block" data-act="opensite" data-sid="'+s.id+'">'+
      '<div class="block-h"><h3>'+esc(s.name)+'</h3>'+
        '<div class="block-sub">'+esc(vn.join(", "))+
        (s.vehicles?' &middot; '+s.vehicles+' vehicles':'')+'</div></div>'+
      '<div class="block-v">'+inr(s.payable)+'<span>this month</span></div>'+
      '<div class="block-f">'+(flags.join("") || '<span class="chip c-grey"><span class="d"></span>nothing outstanding</span>')+'</div>'+
      '<div class="block-n">'+s.months.length+' month'+(s.months.length===1?'':'s')+' on record'+
        (latest?' &middot; latest '+esc(latest.period_label):'')+'</div>'+
      '</div>'; }).join("")+'</div>';
}

function viewSite(){
  var list = S.list.filter(function(x){ return x.site_id === S.site; });
  if(!list.length){ S.site = null; return ""; }
  var name = list[0].site_name;
  var months = list.slice().sort(function(a,b){ return String(a.period) < String(b.period) ? 1 : -1; });
  var total = months.reduce(function(a,x){ return a + (Number(x.final)||0); }, 0);
  var paid  = months.reduce(function(a,x){ return a + (Number(x.paid_total)||0); }, 0);
  var vn = {}; months.forEach(function(x){ vn[x.vendor_name] = 1; });

  return '<div class="page-h"><div>'+
      '<button class="btn sm" data-act="backsites" style="margin-bottom:10px">&larr; All sites</button>'+
      '<h1>'+esc(name)+'</h1><p>'+esc(Object.keys(vn).join(", "))+' &middot; '+
      months.length+' month'+(months.length===1?'':'s')+' on record</p></div></div>'+
    '<div class="kpis">'+
      '<div class="kpi"><div class="l">Settled to date</div><div class="v">'+inr(total)+'</div>'+
        '<div class="n">every version currently in force</div></div>'+
      '<div class="kpi"><div class="l">Paid to date</div><div class="v" style="color:var(--teal)">'+inr(paid)+'</div>'+
        '<div class="n">against approved versions only</div></div>'+
      '<div class="kpi"><div class="l">Outstanding</div><div class="v" style="color:var(--amber)">'+
        inr(months.reduce(function(a,x){ return a + (["approved","part_paid"].indexOf(x.status)>=0
          ? Number(x.approved_amount||0) - Number(x.paid_total||0) : 0); },0))+'</div>'+
        '<div class="n">approved, not yet cleared</div></div>'+
    '</div>'+
    '<div class="card"><div class="card-h"><h2>Month by month</h2><div class="spacer"></div>'+
      '<span class="sub">newest first &mdash; click a row to open</span></div>'+
      '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(months)+'</tbody></table></div></div>';
}

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
    ' settlement'+(blocked===1?" is":"s are")+' waiting on a payroll posting</b>'+
    'Processed salary and PF/ESIC have not been posted, so those heads are still zero and the statement cannot be shared. '+
    (can("post_payroll")?'Open one and use the <b>Payroll &amp; PF/ESIC</b> tab &mdash; you can post it yourself, or leave it to Accounts.'
                        :'Accounts or the vendor manager posts them.')+'</div></div>' : "";

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
   '<div class="card"><div class="card-h"><h2>Your sites</h2><div class="spacer"></div>'+
     '<span class="sub">click a site for its months</span></div>'+
   '<div class="card-b">'+siteBlocks(S.list)+'</div></div>'+
   payQueue();
}

/* Approved but not yet fully paid, across every month - not just this one.
   Old months are exactly the ones that get forgotten, so they go at the top
   of their own card rather than being buried in the month you are looking at. */
function payQueue(){
  if(!can("pay")) return "";
  var due = S.list.filter(function(x){ return x.status==="approved"||x.status==="part_paid"; })
    .sort(function(a,b){ return String(a.period) < String(b.period) ? -1 : 1; });
  if(!due.length) return "";
  var out = due.reduce(function(a,x){
    return a + (Number(x.approved_amount||0) - Number(x.paid_total||0)); }, 0);
  var old = due.filter(function(x){ return String(x.period).slice(0,10) !== S.period; }).length;
  return '<div class="card"><div class="card-h"><h2>Approved &mdash; still to pay</h2><div class="spacer"></div>'+
    '<span class="sub">'+inr(out)+' outstanding'+(old?' &middot; '+old+' from an earlier month':'')+'</span></div>'+
    '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+listRows(due)+'</tbody></table></div>'+
    '<div class="card-b" style="padding-top:0"><div class="hint" style="margin:0">A payment can be entered against any '+
    'approved month, however far back. Open the row, go to <b>Payments</b>, and put the date the money actually left '+
    '&mdash; not today&rsquo;s date. Part payments are fine; the balance stays visible until it clears.</div></div></div>';
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
     '<span class="sub">every month, oldest first &mdash; money can only move against a version the vendor approved</span></div>'+
     '<div class="card-b tight"><table class="hoverable">'+listHead()+'<tbody>'+
       listRows(toPay.slice().sort(function(a,b){ return String(a.period) < String(b.period) ? -1 : 1; }))+
     '</tbody></table></div></div>'+
   '<div class="card"><div class="card-h"><h2>Sites</h2><div class="spacer"></div>'+
     '<span class="sub">click a site for its months</span></div>'+
     '<div class="card-b">'+siteBlocks(S.list)+'</div></div>';
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
     '<div class="kpi"><div class="l">Approved, not paid</div><div class="v" style="color:var(--green)">'+inr(unpaid)+'</div><div class="n">awaiting release</div></div>'+
     '<div class="kpi"><div class="l">Settlements</div><div class="v">'+mine.length+'</div><div class="n">vendor-site, this month</div></div>'+
   '</div>'+
   '<div class="card"><div class="card-h"><h2>Company spend per vehicle &mdash; '+esc(monthLabel(S.period))+'</h2>'+
     '<span class="sub">what WeVois spent on the partner&rsquo;s behalf, divided by the vehicles on that contract</span></div>'+
     '<div class="card-b">'+(bars||'<div class="empty">No settlement has a posted payroll yet.</div>')+
     (skipped>0?'<div style="font-size:12px;color:var(--muted);margin-top:10px;padding-top:10px;border-top:1px solid var(--line-2)">'+
       skipped+' left out &mdash; payroll not posted yet, so the figure would read low.</div>':'')+'</div></div>'+
   '<div class="card"><div class="card-h"><h2>Sites</h2><div class="spacer"></div>'+
     '<span class="sub">click a site for its months</span></div>'+
     '<div class="card-b">'+siteBlocks(S.list)+'</div></div>';
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
    b += '<div class="banner b-teal"><div class="ico">&#9203;</div><div><b>The payroll is not posted yet</b>'+
      'Processed salary, wages and PF/ESIC have not been posted for this month, so those heads are still zero and this statement cannot be shared. '+
      (can("post_payroll")?'Open the <b>Payroll &amp; PF/ESIC</b> tab and post them.'
                          :'Accounts or the vendor manager posts them from the Payroll tab.')+'</div></div>';
  if(can("edit_draft") && isDraft && !prPending)
    b += '<div class="banner b-blue"><div class="ico">&#9998;</div><div><b>Draft &mdash; only WeVois can see this</b>'+
      'Enter what the partner earned and the running heads, then share. The moment you share, this version freezes: it can never be edited, '+
      'only replaced by a new version with a visible list of what changed.</div></div>';
  if(can("revise") && pend>0 && ["approved","part_paid","paid"].indexOf(st.statement.status)<0)
    b += '<div class="banner b-amber"><div class="ico">&#8635;</div><div><b>'+pend+' change'+(pend===1?"":"s")+' not yet sent to the vendor</b>'+
      'Issue a revised statement so he sees the corrected figures and the reasons.</div>'+
      '<div style="margin-left:auto"><button class="btn primary" data-act="revise">Issue revised statement</button></div></div>';
  if(st.payroll && st.payroll.pending_fix)
    b += '<div class="banner b-teal"><div class="ico">&#8635;</div><div><b>A payroll correction has been posted</b>'+
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
        : 'Approved and awaiting payment release.')+'</div></div>';
  }

  var op = openPoints(st);
  var tabDefs = [
    ["sheet","Statement"],
    ["payroll","Payroll &amp; PF/ESIC"+(prPending?'<span class="cnt" style="background:var(--red)">!</span>'
       :((st.documents||[]).length?'<span class="cnt" style="background:var(--faint)">&#128206;'+st.documents.length+'</span>':''))],
    ["points","Points"+((st.points||[]).length?'<span class="cnt" style="'+(op?'':'background:var(--faint)')+'">'+st.points.length+'</span>':'')],
    ["versions","Versions ("+st.versions.length+")"],
    ["payments","Payments ("+(st.payments||[]).length+")"],
    ["queries","Queries"+(openQueries(st)?'<span class="cnt" style="background:var(--amber)">'+openQueries(st)+'</span>'
        :((st.points||[]).filter(isQuery).length?'<span class="cnt" style="background:var(--faint)">'+
          (st.points||[]).filter(isQuery).length+'</span>':''))],
    ["record","Full record"]
  ];
  /* the vendor never sees what WeVois asked its own leadership */
  if(can("view_all"))
    tabDefs.splice(tabDefs.length-1, 0,
      ["approvals","CEO / VP"+(openApprovals()?'<span class="cnt" style="background:var(--amber)">'+
        openApprovals()+'</span>':(apprList().length?'<span class="cnt" style="background:var(--faint)">'+
        apprList().length+'</span>':''))]);
  var tabs = '<div class="tabs">'+tabDefs.map(function(t){
    return '<button data-act="tab" data-v="'+t[0]+'" class="'+(S.tab===t[0]?"on":"")+'">'+t[1]+'</button>'; }).join("")+'</div>';

  var body = S.tab==="sheet" ? tabSheet() : S.tab==="payroll" ? tabPayroll()
    : S.tab==="points" ? tabPoints() : S.tab==="versions" ? tabVersions()
    : S.tab==="payments" ? tabPayments()
    : S.tab==="queries" ? tabQueries()
    : S.tab==="approvals" ? tabApprovals() : tabRecord();

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
    var effs = {};
    v.lines.forEach(function(l){ effs[l.head_key] = l.effect || "deduct"; });
    S.draft = {
      gross: Number(v.gross)||0,
      note: v.gross_note||"",
      lines: lines,
      effects: effs,
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
      : '<b>'+inr(v.gross)+'</b>')+'</td><td class="num">'+
    (canRaise
      ? '<button class="btn sm" data-act="raise" data-kind="gross" data-key="" data-label="Total Expenses Should Be Paid">Raise point</button>'
      : canLog
      ? '<button class="btn sm" data-act="logcall" data-kind="gross" data-key="" data-label="Total Expenses Should Be Paid">&#9742; Log call</button>'
      : '')+'</td></tr>';
  if(editable)
    rows += '<tr class="memo-row"><td colspan="3" style="padding-left:26px">Basis / note: '+
      '<input class="inp" style="max-width:460px;display:inline-block" value="'+esc(D.note)+'" data-act="draft" data-k="__note" '+
      'placeholder="e.g. 20 vehicles x 45,000 per the duty sheet"></td></tr>';
  else if(v.gross_note)
    rows += '<tr class="memo-row"><td colspan="3" style="padding-left:26px">Basis: '+esc(v.gross_note)+'</td></tr>';

  var groups = {};
  (v.lines||[]).forEach(function(l){ (groups[l.grp] = groups[l.grp] || []).push(l); });
  Object.keys(groups).forEach(function(g){
    /* the heading still reads "less" while every head in the group is one -
       which is the ordinary month - and drops the word as soon as one of them
       credits him or is recorded only, because then it would be a lie */
    var allLess = groups[g].every(function(l){ return lineEff(l) === "deduct"; });
    rows += '<tr class="grp-row"><td colspan="3">'+(allLess?'less &mdash; ':'')+
      (GRP_LABEL[g]||esc(g))+'</td></tr>';
    groups[g].forEach(function(l){
      var pt = (st.points||[]).filter(function(p){ return p.target_kind==="head" && p.target_key===l.head_key; })[0];
      var chip = pt ? ' <span class="chip '+(pt.status==="open"?"c-amber":pt.status==="awaiting_confirm"?"c-violet":
        (pt.status==="rejected"||pt.status==="disputed_record")?"c-red":pt.status==="carry_forward"?"c-blue":"c-green")+
        '"><span class="d"></span>'+esc(String(pt.status).replace(/_/g," "))+'</span>' : '';
      var ed = editable && l.src==="manual";
      var ef = ed ? (D.effects[l.head_key]||"deduct") : lineEff(l);
      rows += '<tr><td style="padding-left:26px">'+esc(l.head_label)+
        (l.src==="payroll"?' <span class="lockpill">payroll</span>':'')+chip+
        (!ed && ef==="note"
          ? '<div style="font-size:12px;color:var(--faint)">recorded only &mdash; does not change the amount</div>'
          : !ed && ef==="add"
          ? '<div style="font-size:12px;color:var(--muted)">credited to him, not taken off</div>' : '')+'</td>'+
        '<td class="num">'+(ed
          ? '<div class="effcell">'+effSelect("draft-eff", l.head_key, ef)+
            '<input class="inp num" value="'+(D.lines[l.head_key]||0)+
            '" data-act="draft" data-k="'+esc(l.head_key)+'"></div>'
          /* colour marks the exception, not the rule: an ordinary deduction reads
             exactly as it always did, and the eye goes straight to the line that
             is doing something else */
          : ef==="deduct" ? '<b>'+inr(l.amount)+'</b>'
          : '<b class="'+effClass(ef)+'">'+effSign(ef)+inr(l.amount)+'</b>')+'</td>'+
        '<td class="num" style="width:112px">'+(canRaise
          ? '<button class="btn sm" data-act="raise" data-kind="head" data-key="'+esc(l.head_key)+'" data-label="'+esc(l.head_label)+'">Raise point</button>'
          : canLog
          ? '<button class="btn sm" data-act="logcall" data-kind="head" data-key="'+esc(l.head_key)+'" data-label="'+esc(l.head_label)+'">&#9742; Log call</button>'
          : '')+'</td></tr>';
    });
  });

  /* three different questions, three different numbers, and they only agree
     while every head is a deduction. Spend is what WeVois paid out; the net is
     what comes off the earned amount; the recorded-only rows are neither. */
  var mix = headMix(v);
  rows += '<tr class="memo-row"><td>'+
    (mix.plain ? 'Expenses paid by company <span style="color:var(--faint)">(sum of the heads)</span>'
               : 'Net taken off under the heads'+
                 '<div style="font-size:12px;color:var(--muted)">company spend '+inr(mix.spend)+
                 (mix.credit ? ' &middot; credited back to him '+inr(mix.credit) : '')+
                 (mix.noted  ? ' &middot; recorded only '+inr(mix.noted) : '')+'</div>')+'</td>'+
    '<td class="num">'+inr(mix.net)+'</td><td></td></tr>';
  rows += '<tr class="tot-row"><td><b>Total</b> <span style="font-weight:400;color:var(--muted)">'+
    '&mdash; earned, less what we spent for him</span></td><td class="num">'+
    inr(v.total)+'</td><td></td></tr>';

  rows += '<tr class="grp-row"><td colspan="3">Adjustments</td></tr>';
  if(editable){
    var linked = (v.adjustments||[]).filter(function(a){ return a.payroll_linked; });
    rows += '<tr><td colspan="3" style="padding:12px 14px">'+adjEditor(D.adj)+
      '<div class="btnrow" style="margin-top:6px"><button class="btn sm" data-act="adj-add">+ Add an adjustment line</button></div>'+
      linked.map(function(a){
        return '<div class="hint" style="margin-top:8px">From the payroll posting: <b>'+esc(a.label)+'</b> '+
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
  /* the per-vehicle cost is what WeVois reads to compare one site against
     another. It is not part of what the partner is owed, and showing it to him
     invites an argument about somebody else's site. */
  if(Number(st.contract.vehicles)>0 && S.profile.role !== "vendor")
    rows += '<tr class="memo-row"><td>Memo &mdash; company spend per vehicle ('+st.contract.vehicles+' vehicles)'+
      '<span class="lockpill" style="margin-left:6px">not shown to the vendor</span></td>'+
      '<td class="num">'+inr(mix.spend/Number(st.contract.vehicles))+'</td><td></td></tr>';

  var acts = [];
  if(editable) acts.push('<span id="autosave" class="autosave">'+
    (S.dirty ? 'unsaved changes' : 'saved')+'</span>'+
    '<button class="btn" data-act="savedraft">Save now</button>');
  if(can("share") && isDraft){
    acts.push('<button class="btn go" data-act="share"'+(prPending?" disabled":"")+'>Share with vendor</button>');
    if(prPending) acts.push('<span style="font-size:12.5px;color:var(--muted)">Blocked until the payroll is posted'+
      (can("post_payroll")?' &mdash; the Payroll &amp; PF/ESIC tab.':'.')+'</span>');
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
      (ed?'Enter the processed figures below and post them. The statement cannot be shared with the vendor until they are in.'
         :'The processed salary and PF/ESIC have not been posted for this month. The manpower heads stay at zero until they are.')+'</div></div>';

  var pf = (Number(p.dh_pf_ee)||0)+(Number(p.dh_pf_er)||0)+(Number(p.stf_pf_ee)||0)+(Number(p.stf_pf_er)||0);
  var es = (Number(p.dh_esic_ee)||0)+(Number(p.dh_esic_er)||0)+(Number(p.stf_esic_ee)||0)+(Number(p.stf_esic_er)||0);

  var vendorNote = (S.profile.role==="vendor" && p.status==="posted")
    ? '<div class="banner b-blue"><div class="ico">&#129534;</div><div><b>Check the deposits yourself</b>'+
      'PF was deposited under TRRN <b>'+esc(p.pf_trrn||"—")+'</b> on '+dOnly(p.pf_paid_on)+
      ' and ESIC under challan <b>'+esc(p.esic_challan||"—")+'</b> on '+dOnly(p.esic_paid_on)+
      '. These are the same references filed with the departments.</div></div>' : "";

  var readbar = ed ? '<div class="btnrow" style="margin-bottom:14px">'+
    '<input type="file" id="pr-file" style="display:none" accept=".pdf,.txt,application/pdf">'+
    '<button class="btn" data-act="readpayroll">&#128196; Read from a PF, ESIC or bank file</button>'+
    '<span style="font-size:12.5px;color:var(--muted)">Fills the figures below. It never posts on its own.</span>'+
    '</div>' : "";

  var act = ed ? '<div class="btnrow" style="margin-bottom:16px"><button class="btn teal" data-act="postpayroll">'+
    (p.status==="posted"?"Post a payroll correction":"Post payroll to the statement")+'</button>'+
    (p.status==="posted"?'<span style="font-size:12.5px;color:var(--muted)">A correction after sharing goes out as a new version, with the reason.</span>':'')+
    '</div>' : "";

  return '<div class="card-b">'+status+vendorNote+readbar+act+
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
    payrollBatches()+
    docSection()+
    '</div>';
}

/* the review card: what was read, what it reconciles to, what it could not
   account for. Nothing is posted from here - the figures go into the form and
   a person still presses Post. */
function readReview(P){
  function row(l, v, note){
    return '<tr><td>'+l+(note?'<div style="font-size:12px;color:var(--muted)">'+note+'</div>':'')+
      '</td><td class="num"><b>'+v+'</b></td></tr>';
  }
  var body = "", title = "", sub = "";
  if(P.kind === "pf"){
    title = "PF return";
    sub = (P.period_text||"") + (P.establishment?" &middot; "+esc(P.establishment):"");
    body = row("Members on the return", P.rows.length) +
           row("Counted as paid", P.paid_members, P.zero_members? P.zero_members+" had nothing against them":"") +
           row("Employee PF", inr(P.employee)) +
           row("Employer PF", inr(P.employer), "pension share plus the balance") +
           row("EPF wage base", inr(P.epf_wage),
               P.stated_epf_wage===P.epf_wage ? "matches the total the return states" : "");
  } else if(P.kind === "esic"){
    title = "ESIC contribution history";
    sub = (P.period_text||"") + (P.employer_code?" &middot; "+esc(P.employer_code):"");
    body = row("Insured persons", P.paid_members) +
           row("Employee ESIC", inr(P.employee)) +
           row("Employer ESIC", inr(P.employer)) +
           row("Wages", inr(P.wages));
  } else {
    title = "Bank salary file";
    sub = (P.period_text||"") + (P.value_dates && P.value_dates.length===1 ? " &middot; paid "+P.value_dates[0] : "");
    body = row("Payments in the file", P.rows.length) +
           row("Actually processed", P.paid_members) +
           row("Paid out", inr(P.amount), "only the payments the bank processed") +
           (P.rejected.length ? row("Did NOT go through", inr(P.amount_all - P.amount),
              P.rejected.map(function(r){ return esc(r.name||"(unnamed)"); }).join(", ")) : "");
  }

  var warns = (P.warnings||[]).map(function(w){
    return '<div class="banner b-amber" style="margin:0 0 10px"><div class="ico">&#9888;</div><div>'+esc(w)+'</div></div>';
  }).join("");

  var np = (P.kind==="salary" && P.rejected.length)
    ? '<div class="fld"><label class="fl"><input type="checkbox" id="rd-np" value="1" checked '+
        'style="width:auto;margin-right:7px;vertical-align:middle"> Put the '+
        inr(P.amount_all-P.amount)+' that did not go through into <b>Salary not processed from WeVois</b></label>'+
        '<div class="hint">It is credited back to the partner rather than counted as a wage cost, with the names as the reason.</div></div>'
    : '';

  return '<div class="banner b-blue" style="margin-bottom:14px"><div class="ico">&#128196;</div><div>'+
      '<b>'+title+' read from '+esc(P.filename||"the file")+'</b>'+
      (sub?esc(sub.replace(/&middot;/g,"·"))+'<br>':'')+
      'Nothing is posted yet. Check these against the document, choose where they belong, and they go into the '+
      'form for you to post.</div></div>'+
    warns+
    '<table style="margin-bottom:14px"><tbody>'+body+'</tbody></table>'+
    '<div class="fld"><label class="fl">Where do these people belong?</label>'+
      '<select class="inp" id="rd-split" data-act="rd-split">'+
        '<option value="dh">All driver / helper</option>'+
        '<option value="stf">All staff</option>'+
        '<option value="split">Split between the two</option>'+
      '</select>'+
      '<div class="hint">Neither the PF return nor the ESIC statement nor the bank file says which is which, '+
      'so this is the one thing the file cannot tell us.</div></div>'+
    '<div class="fld" id="rd-split-box" style="display:none">'+
      '<label class="fl">How many of the '+P.paid_members+' are staff?</label>'+
      '<input class="inp num" id="rd-stf-heads" value="0">'+
      '<div class="hint">The amounts are apportioned by headcount. Adjust them by hand afterwards if the split is not even.</div></div>'+
    np;
}

/* ------------------------------------------------- payroll entries (top-ups) */
/* Salary that arrives in pieces. The first posting is entry 1; people left off
   that run and processed later go on as their own entry, with their own challan
   and their own date, instead of quietly overwriting the month. */
function payrollBatches(){
  var st = S.stmt, bs = st.payroll_batches || [];
  var posted = st.payroll && st.payroll.status === "posted";
  var may = can("post_payroll") && st.statement.status !== "paid";
  if(!posted && !bs.length) return "";

  var rows = bs.map(function(b){
    var n = (Number(b.dh_heads)||0) + (Number(b.stf_heads)||0);
    return '<tr><td><b>'+(b.seq===1?"The month as posted":"Top-up "+b.seq)+'</b>'+
      '<div style="font-size:12px;color:var(--muted)">'+esc(b.posted_by||"")+' &middot; '+dt(b.posted_at)+
      (b.processed_on?' &middot; processed '+dOnly(b.processed_on):'')+'</div>'+
      (b.note?'<div style="font-size:12.5px;color:var(--ink-2);margin-top:4px">'+esc(b.note)+'</div>':'')+'</td>'+
      '<td class="num">'+n+'</td>'+
      '<td class="num">'+inr(Number(b.dh_pay)+Number(b.stf_pay))+'</td>'+
      '<td style="font-size:12px;color:var(--muted)">'+esc(b.pf_trrn||"—")+'<br>'+esc(b.esic_challan||"—")+'</td></tr>';
  }).join("");

  var tot = bs.reduce(function(a,b){
    return {n: a.n + (Number(b.dh_heads)||0) + (Number(b.stf_heads)||0),
            p: a.p + Number(b.dh_pay) + Number(b.stf_pay)}; }, {n:0,p:0});

  return '<h3 style="font-size:14px;margin:22px 0 10px">How this month\'s payroll was built up</h3>'+
    '<div class="banner b-blue" style="margin-bottom:12px"><div class="ico">&#8721;</div><div>'+
    '<b>Late salary goes on as its own entry, not over the top of the month</b>'+
    'People left off the first run and processed later keep their own challan, their own date and their own note. '+
    'The figures above are the sum of the entries below, so the statement never disagrees with the challans behind it. '+
    'A top-up on a statement the vendor already has waits for the next version, like any other correction.</div></div>'+
    (may?'<div class="btnrow" style="margin-bottom:12px">'+
      '<button class="btn teal" data-act="topup">Add salary processed late</button></div>':'')+
    '<table><thead><tr><th>Entry</th><th class="num">Persons</th><th class="num">Wages + salary</th>'+
    '<th>PF TRRN / ESIC challan</th></tr></thead><tbody>'+
    (rows||'<tr><td colspan="4" class="empty">Nothing posted yet.</td></tr>')+
    (bs.length>1?'<tr class="final-row"><td><b>Total</b></td><td class="num"><b>'+tot.n+'</b></td>'+
      '<td class="num"><b>'+inr(tot.p)+'</b></td><td></td></tr>':'')+
    '</tbody></table>';
}

/* -------------------------------------------------------- attached files */
var DOC_KIND = { payroll:"Payroll sheet", pf:"PF", esic:"ESIC", bill:"Bill", other:"Other" };

function fileSize(n){
  n = Number(n)||0;
  return n >= 1048576 ? (n/1048576).toFixed(1)+" MB"
       : n >= 1024    ? Math.round(n/1024)+" KB" : n+" bytes";
}

function docSection(){
  var st = S.stmt, docs = st.documents || [];
  var staff  = can("post_payroll") || can("edit_draft");
  var isVend = S.profile.role === "vendor";
  /* the partner can put his own bills up here too - that is the whole point of
     "send me the bill" not being a phone call any more. He can take back only
     what he put up himself; staff can remove any of it, with a reason. */
  var ed = (staff || isVend) && st.statement.status !== "paid";

  var rows = docs.map(function(d){
    return '<tr>'+
      '<td><b>'+esc(d.filename)+'</b>'+
        '<div style="font-size:12px;color:var(--muted)">'+esc(d.uploaded_by||"")+' &middot; '+dt(d.uploaded_at)+'</div></td>'+
      '<td><span class="chip c-blue">'+esc(DOC_KIND[d.kind]||d.kind)+'</span></td>'+
      '<td style="font-size:12.5px;color:var(--muted)">'+fileSize(d.size_bytes)+'</td>'+
      '<td class="num"><button class="btn sm" data-act="docopen" data-p="'+esc(d.path)+'">Open</button>'+
        ((ed && (staff || d.uploaded_uid === S.profile.id))
          ? ' <button class="btn sm danger" data-act="docdel" data-id="'+d.id+'" data-n="'+esc(d.filename)+'">Remove</button>':'')+
      '</td></tr>'; }).join("");

  if(!rows) rows = '<tr><td colspan="4" class="empty">'+
    (isVend ? 'Nothing attached yet. Put up a bill, a log sheet or a photo and WeVois can open it from here.'
     : ed ? 'Nothing attached yet. Add the payroll sheet, the PF ECR or the ESIC challan and the vendor can open it himself.'
        : 'No file attached to this month.')+'</td></tr>';

  return '<h3 style="font-size:14px;margin:22px 0 10px">Payroll, PF and ESIC files</h3>'+
    '<div class="banner b-blue" style="margin-bottom:12px"><div class="ico">&#128206;</div><div>'+
    '<b>The proof, attached to the month it belongs to</b>'+
    (isVend
      ? 'Bills, log sheets, photos &mdash; anything backing up what you have raised. WeVois opens them from here, so '+
        '&ldquo;send it again on WhatsApp&rdquo; stops being a phone call. You can take back a file you put up yourself; '+
        'a file WeVois attached stays.'
      : 'Excel or PDF &mdash; the payroll sheet, the PF ECR, the ESIC challan. The vendor opens them from his own copy of '+
        'this statement, and he can attach his own bills here too. Every attachment and every removal is written into '+
        'the record below.')+'</div></div>'+
    (ed ? '<div class="btnrow" style="margin-bottom:12px">'+
          '<input type="file" id="doc-file" style="display:none" '+
            'accept=".xlsx,.xls,.csv,.pdf,.png,.jpg,.jpeg,application/pdf,image/*,'+
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel">'+
          '<select class="inp" id="doc-kind" style="width:auto;min-width:170px">'+
            Object.keys(DOC_KIND).map(function(k){
              return '<option value="'+k+'">'+DOC_KIND[k]+'</option>'; }).join("")+'</select>'+
          '<button class="btn teal" data-act="docpick">Choose a file and attach</button>'+
          '<span id="doc-status" style="font-size:12.5px;color:var(--muted)"></span>'+
          '</div>' : "")+
    '<table><thead><tr><th>File</th><th>Kind</th><th>Size</th><th class="num">'+
    (ed?'Open / remove':'Open')+'</th></tr></thead><tbody>'+rows+'</tbody></table>';
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


/* ----------------------------------------------------------- tab: queries */
/* Anything the vendor wants to raise that is not a figure on this month's
   sheet. It deliberately does not put the settlement under query, so a
   question about next month's vehicles cannot hold up this month's money. */
function isQuery(p){ return p.target_kind === "general"; }
function openQueries(st){
  return (st.points||[]).filter(function(p){ return isQuery(p) && p.status === "open"; }).length;
}

function remarkList(p){
  var rs = p.remarks || [];
  var out = rs.map(function(r){
    return '<div class="rmk '+(r.by_role==="vendor"?"them":"us")+'">'+
      '<div class="rmk-h">'+esc(r.by_name)+' <span>'+esc(ROLE_LABEL[r.by_role]||r.by_role)+
      ' &middot; '+dt(r.at)+'</span></div>'+
      '<div class="rmk-b">'+esc(r.body)+'</div></div>'; }).join("");
  return out ? '<div class="rmks">'+out+'</div>' : "";
}

function tabQueries(){
  var st = S.stmt;
  var qs = (st.points||[]).filter(isQuery);
  var mayRaise  = can("raise") && S.profile.role === "vendor";
  var mayAnswer = can("resolve");
  var mayRemark = ["vendor","manager","accounts","admin"].indexOf(S.profile.role) >= 0;

  var out = qs.map(function(p){
    var open = p.status === "open";
    return '<div class="pt '+(open?"open":"done")+'">'+
      '<div class="pt-h">'+
        (open ? '<span class="chip c-amber"><span class="d"></span>Waiting for an answer</span>'
              : '<span class="chip c-green"><span class="d"></span>Answered</span>')+
        '<div style="flex:1"></div><span class="when">'+esc(p.raised_by)+' &middot; '+dt(p.raised_at)+'</span></div>'+
      '<div class="pt-body">'+esc(p.note)+'</div>'+
      (p.attachment?'<div class="hint">Attached: '+esc(p.attachment)+'</div>':'')+
      (p.decision
        ? '<div class="pt-ans"><b>'+esc(p.decided_by||"")+' answered</b> <span class="when">'+dt(p.decided_at)+'</span>'+
          '<div>'+esc(p.decision)+'</div></div>' : '')+
      remarkList(p)+
      '<div class="btnrow" style="margin-top:10px">'+
        (mayAnswer && open ? '<button class="btn sm primary" data-act="answerq" data-id="'+p.id+'">Answer this</button>' : '')+
        (mayAnswer && !open ? '<button class="btn sm" data-act="answerq" data-id="'+p.id+'">Revise the answer</button>' : '')+
        (mayRemark ? '<button class="btn sm" data-act="remark" data-id="'+p.id+'">Add a remark</button>' : '')+
      '</div></div>';
  }).join("");

  var head = '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#128172;</div><div>'+
    '<b>Anything that is not a figure on this sheet</b>'+
    'Vehicles, drivers, fuel cards, documents, next month &mdash; whatever needs saying that is not a dispute about an '+
    'amount. It is written down against this month and answered in writing, so it never becomes '+
    '&ldquo;I told you on the phone&rdquo;. Raising one here does <b>not</b> hold up the settlement.'+
    (mayAnswer?' A point about an amount belongs on the <b>Points</b> tab, where the figure can actually move.':'')+
    '</div></div>';

  return '<div class="card-b">'+head+
    (mayRaise?'<div class="btnrow" style="margin-bottom:16px">'+
      '<button class="btn primary" data-act="raiseq">Raise a query</button></div>':'')+
    (out || '<div class="empty">No queries on this month.</div>')+'</div>';
}


/* -------------------------------------------------------- tab: approvals */
/* The vendor manager puts a question or a figure to the CEO or the VP. This is
   the one place an observer account may write, and only here: they can answer
   what was put to them, and nothing else. */
function apprList(){
  return (S.extra && S.extra.approvals) || [];
}
function openApprovals(){
  return apprList().filter(function(a){ return a.status === "open"; }).length;
}
var APPR_CHIP = {
  open:'<span class="chip c-amber"><span class="d"></span>Waiting on the CEO / VP</span>',
  approved:'<span class="chip c-green"><span class="d"></span>Confirmed</span>',
  declined:'<span class="chip c-red"><span class="d"></span>Declined</span>'
};

function tabApprovals(){
  var st = S.stmt, list = apprList();
  var mayAsk    = can("revise");
  var mayDecide = can("approve_request");
  var draft = st.statement.status === "draft";

  var out = list.map(function(a){
    var amt = a.amount != null
      ? '<div class="pt-body"><b>'+esc(a.adj_label)+'</b> &mdash; '+
        (a.effect==="add"?"added to":"deducted from")+' the partner, <b>'+inr(a.amount)+'</b>'+
        (a.status==="approved"
          ? (a.applied
              ? '<div class="hint">On the statement'+(a.applied_in?' from version '+a.applied_in:'')+'.</div>'
              : '<div class="hint">Waiting for the next version to be issued.</div>')
          : '')+'</div>' : "";
    return '<div class="pt '+(a.status==="open"?"open":a.status==="declined"?"":"done")+'">'+
      '<div class="pt-h">'+(APPR_CHIP[a.status]||"")+
        '<div style="flex:1"></div><span class="when">'+esc(a.asked_by)+' asked &middot; '+dt(a.asked_at)+'</span></div>'+
      '<div class="pt-body">'+esc(a.question)+'</div>'+ amt +
      (a.decided_by
        ? '<div class="pt-ans"><b>'+esc(a.decided_by)+' ('+esc(ROLE_LABEL[a.decided_role]||a.decided_role||"")+') '+
          (a.status==="approved"?"confirmed":"declined")+'</b> <span class="when">'+dt(a.decided_at)+'</span>'+
          (a.decision_note?'<div>'+esc(a.decision_note)+'</div>':'')+'</div>' : '')+
      (mayDecide && a.status==="open"
        ? '<div class="btnrow" style="margin-top:10px">'+
          '<button class="btn sm go" data-act="decide" data-id="'+a.id+'" data-ok="1">Confirm</button>'+
          '<button class="btn sm danger" data-act="decide" data-id="'+a.id+'" data-ok="0">Decline</button></div>'
        : '')+
      '</div>';
  }).join("");

  var head = '<div class="banner b-blue" style="margin-bottom:16px"><div class="ico">&#9878;</div><div>'+
    '<b>Confirmation from the CEO or the VP, in writing</b>'+
    (mayDecide
      ? 'Somebody has asked you to confirm something on this month. Your answer is recorded against your name and '+
        'the date. Where a request carries an <b>amount</b>, confirming it writes that line onto the statement '+
        'itself &mdash; on a draft straight away, on a statement the vendor already holds when the next version '+
        'goes out. Declining writes nothing, but the refusal and your reason stay on the record.'
      : 'Put a question or a figure to them and get an answer that is written down rather than remembered. '+
        'If the request carries an amount and they confirm it, that line appears on the statement by itself, '+
        'with their name and the date as its reason'+(draft?'':' when you issue the next version')+'.')+
    '</div></div>';

  return '<div class="card-b">'+head+
    (mayAsk?'<div class="btnrow" style="margin-bottom:16px">'+
      '<button class="btn primary" data-act="askappr">Ask the CEO / VP</button></div>':'')+
    (out || '<div class="empty">Nothing has been put to them on this month.</div>')+'</div>';
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
