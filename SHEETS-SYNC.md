# Connecting each site's working sheet

The portal mirrors the sheets your office already keeps for a site — the month
totals, every penalty with its proof, the day counts and the duty log — and lets
the vendor put a question on **any row or any column** of them. You answer in
writing and the thread closes, exactly like the queries on a statement.

Nothing here writes back to Google. The sheet stays the operating tool; the
portal becomes the record of the conversation about it.

## The six sites

From **Site Salary Link → Operation Partner**, rows 1 to 6:

| # | Site | Files that feed it |
|---|---|---|
| 1 | Kuchaman | Kuchaman Daily Payment, Kuchaman Daily Payment_1, Kuchaman operation Partner Penalty |
| 2 | Tonk | Tonk Daily Payment |
| 3 | Parbatsar | Parbatsar Daily Payment, Parbatsar operation partner penalty |
| 4 | Nawa | Nawa Daily Payment, Nawa Operation Partner Penalty |
| 5 | Bundi | Bundi Daily Payment, Bundi Daily Payment_1, Bundi operation Partner Penalty |
| 6 | Vidisha | Vidisha Daily Payment, Vidisha operation Partner penalty |

**A site is fed by more than one file, and that is handled.** Every row the
portal stores remembers which file it came from, and a sync only ever speaks for
its own file. Kuchaman's second payment sheet cannot mark the first one's rows as
gone. Put the same script in every file belonging to a site, with the same
`SITE_NAME`, and they add up rather than fight.

The site name in the script must match the site's name in the portal exactly —
`Kuchaman`, not `Kuchaman Daily Payment`.

## Step 1 — connect the sheet to the site

Administration → Sites → the site → **Working sheet**. Paste the sheet's URL and
give it a name. That is one row saying "this site's sheet lives here". You only
need to do it once per site, for whichever file you think of as the main one.

## Step 2 — the script, in each file

The portal reads the sheet through a small script that lives **in the sheet
itself**, so no Google service account and no new Google project is needed.

In each file: **Extensions → Apps Script**, delete what is there, paste the
script below, change `SITE_NAME`, **Save**, then run `syncToPortal` once by hand
(Google will ask you to authorise it the first time). When that works, go to
**Triggers → Add trigger → `syncToPortal` → Time-driven → Hour timer → every
hour**.

The script needs whoever owns the file to add it. If a site's sheet belongs to
somebody else, send them this page.

**You do not have to tell it which tab is which.** It reads each tab's heading
row and works it out: a tab with *Penalty Amount* and *Penalty Type* is the
penalty list, one with *Month-Year* and *Net Payable* is the month totals, one
with *Duty ON* and *Vehicle* is the duty log, one with *NO Of D2D* or *Per Day
Amount* is the day counts. Tabs it does not recognise — the helper lists, the
vehicle lists, the zone rates — are left alone and never reach the vendor.

```javascript
// ---- fill these in -------------------------------------------------------
const SITE_NAME   = 'Vidisha';                 // exactly as the site is named in the portal
const PORTAL_URL  = 'https://<your-project>.supabase.co';
const PORTAL_KEY  = '<the anon key from supabase-config.js>';
const PORTAL_USER = 'sync@wevois.com';         // a login that has the sync_sheets right
const PORTAL_PASS = '<that login\'s password>';
// --------------------------------------------------------------------------

/** What each kind of tab looks like. First match wins, so the most specific
    signature has to come first: the month-totals tab in these sheets also
    carries a penalty-type summary beside it, and would otherwise be mistaken
    for the penalty list. And a duty log has to be DATED - without that, a
    vehicle list headed "Duty On Vehicle List" looks like one. */
const KINDS = [
  { tab: 'monthly', label: 'Month totals', needs: [/month\s*-?\s*year/i, /net\s*payable/i] },
  { tab: 'penalty', label: 'Penalties',    needs: [/penalty\s*amount/i, /penalty\s*type/i] },
  { tab: 'duty',    label: 'Duty log',     needs: [/duty\s*on/i, /duty\s*off/i, /(^|\|)\s*date\s*(\||$)/i] },
  { tab: 'counts',  label: 'Day counts',   needs: [/no\s*of\s*d2d|per\s*day\s*amount/i,
                                                  /(^|\|)\s*date\s*(\||$)/i] }
];

function syncToPortal() {
  const token  = signIn_();
  const siteId = siteId_(token);
  const source = SpreadsheetApp.getActive().getName();
  const done   = {};
  SpreadsheetApp.getActive().getSheets().forEach(function (sh) {
    const found = readTab_(sh);
    if (!found) { Logger.log('skipped: ' + sh.getName()); return; }
    if (done[found.kind.tab]) {                    // two tabs of the same kind in one file
      Logger.log('already have a ' + found.kind.tab + ' tab in this file, skipping ' + sh.getName());
      return;
    }
    done[found.kind.tab] = true;
    const res = rpc_(token, 'vs_import_sheet', {
      p_site: siteId, p_tab: found.kind.tab, p_label: found.kind.label,
      p_cols: found.cols, p_rows: found.rows, p_source: source + ' / ' + sh.getName()
    });
    Logger.log(sh.getName() + ' -> ' + found.kind.tab + ': ' + found.rows.length +
               ' rows, ' + (res && res.gone) + ' no longer there');
  });
}

function signIn_() {
  const r = UrlFetchApp.fetch(PORTAL_URL + '/auth/v1/token?grant_type=password', {
    method: 'post', contentType: 'application/json',
    headers: { apikey: PORTAL_KEY }, muteHttpExceptions: true,
    payload: JSON.stringify({ email: PORTAL_USER, password: PORTAL_PASS })
  });
  const j = JSON.parse(r.getContentText() || '{}');
  if (!j.access_token) throw new Error('Could not sign in to the portal: ' + r.getContentText());
  return j.access_token;
}

function rpc_(token, fn, args) {
  const r = UrlFetchApp.fetch(PORTAL_URL + '/rest/v1/rpc/' + fn, {
    method: 'post', contentType: 'application/json',
    headers: { apikey: PORTAL_KEY, Authorization: 'Bearer ' + token },
    payload: JSON.stringify(args), muteHttpExceptions: true
  });
  if (r.getResponseCode() >= 300) throw new Error(fn + ': ' + r.getContentText());
  return JSON.parse(r.getContentText() || 'null');
}

function siteId_(token) {
  const r = UrlFetchApp.fetch(PORTAL_URL + '/rest/v1/vs_sites?select=id,name&name=eq.' +
    encodeURIComponent(SITE_NAME),
    { headers: { apikey: PORTAL_KEY, Authorization: 'Bearer ' + token }, muteHttpExceptions: true });
  const rows = JSON.parse(r.getContentText() || '[]');
  if (!rows.length) throw new Error('No site called "' + SITE_NAME + '" in the portal.');
  return rows[0].id;
}

/** The heading row is the first row with three or more headings on it. */
function headerRow_(values) {
  for (var i = 0; i < Math.min(values.length, 12); i++) {
    var filled = values[i].filter(function (c) { return String(c).trim() !== ''; }).length;
    if (filled >= 3) return i;
  }
  return -1;
}

function slug_(s, used) {
  var k = String(s).toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '') || 'col';
  var base = k, n = 2;
  while (used[k]) { k = base + '_' + n; n++; }
  used[k] = true;
  return k;
}

function asDate_(v) {
  if (v instanceof Date && !isNaN(v)) {
    return Utilities.formatDate(v, Session.getScriptTimeZone(), 'yyyy-MM-dd');
  }
  var m = String(v).match(/^\s*(\d{1,2})[-\/\s]([A-Za-z]{3,})[-\/\s](\d{4})/);
  if (!m) return null;
  var mm = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec']
             .indexOf(m[2].slice(0,3).toLowerCase()) + 1;
  if (!mm) return null;
  return m[3] + '-' + ('0' + mm).slice(-2) + '-' + ('0' + m[1]).slice(-2);
}

function asMonth_(v) {
  if (v instanceof Date && !isNaN(v)) {
    return Utilities.formatDate(v, Session.getScriptTimeZone(), 'yyyy-MM') + '-01';
  }
  var m = String(v).match(/([A-Za-z]{3})[^0-9]*(\d{4})/);
  if (!m) return null;
  var mm = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec']
             .indexOf(m[1].toLowerCase()) + 1;
  return mm ? m[2] + '-' + ('0' + mm).slice(-2) + '-01' : null;
}

function readTab_(sh) {
  var values = sh.getDataRange().getValues();
  var h = headerRow_(values);
  if (h < 0) return null;

  var head = values[h].map(function (c) { return String(c).trim(); });
  var joined = head.join(' | ');
  var kind = null;
  for (var i = 0; i < KINDS.length && !kind; i++) {
    if (KINDS[i].needs.every(function (re) { return re.test(joined); })) kind = KINDS[i];
  }
  if (!kind) return null;

  var used = {}, cols = [];
  head.forEach(function (label, i) {
    if (!label) return;
    cols.push({ i: i, key: slug_(label, used), label: label,
      kind: /amount|penalty|salary|deduction|payable|rate/i.test(label) ? 'money'
          : /date|month/i.test(label) ? 'date' : 'text' });
  });
  if (!cols.length) return null;

  // which column carries the row's date, and which its month
  var dateCol  = null, monthCol = null;
  cols.forEach(function (c) {
    if (dateCol === null  && /^date$/i.test(c.label)) dateCol = c;
    if (monthCol === null && /month/i.test(c.label))  monthCol = c;
  });

  var seen = {}, rows = [];
  for (var r = h + 1; r < values.length; r++) {
    var row = values[r];
    if (row.every(function (c) { return String(c).trim() === ''; })) continue;
    if (/^\s*total\s*$/i.test(String(row[0]))) continue;      // the sheet's own total line

    var data = {};
    cols.forEach(function (c) {
      var v = row[c.i];
      data[c.key] = (v instanceof Date && !isNaN(v))
        ? Utilities.formatDate(v, Session.getScriptTimeZone(), 'd-MMM-yyyy')
        : String(v === null || v === undefined ? '' : v).trim();
    });

    var onDate = dateCol ? asDate_(row[dateCol.i]) : null;
    var period = onDate ? onDate.slice(0, 8) + '01'
                        : (monthCol ? asMonth_(row[monthCol.i]) : null);

    // THE KEY. Built from the row's own values, never its position, so a
    // question a vendor asked stays on the row he asked it about when the
    // sheet is re-sorted tomorrow. Rows that really are identical get a number.
    var parts;
    if (kind.tab === 'monthly')      parts = [period];
    else if (kind.tab === 'counts')  parts = [onDate];
    else {
      parts = [onDate];
      cols.slice(0, 5).forEach(function (c) {
        if (c !== dateCol) parts.push(String(data[c.key] || '').slice(0, 40));
      });
    }
    var base = parts.join('|');
    if (base.replace(/\|/g, '').trim() === '') continue;
    seen[base] = (seen[base] || 0) + 1;

    rows.push({ key: seen[base] === 1 ? base : base + '#' + seen[base],
                period: period, on_date: onDate, sort: r, data: data });
  }
  if (!rows.length) return null;

  return { kind: kind,
           cols: cols.map(function (c) { return { key: c.key, label: c.label, kind: c.kind }; }),
           rows: rows };
}
```

## What happens to a row that disappears

It is marked **gone** and kept, never deleted, because a vendor may have a
question hanging off it and he is entitled to see what he was looking at when he
asked. Those rows show struck through with the date they left.

## The login the script uses

It signs in as a real portal login, so everything it writes is attributed to
that person in the audit log. Make a login for the purpose — Administration →
Users → Create a login, role **Vendor Manager** — rather than using your own,
because Apps Script keeps the file inside the sheet where anyone who can edit
the sheet can read it.

## Checking it worked

Open the site in the portal. The **Working sheet** card shows each tab, when it
was last read, and how many rows. Or in the Supabase SQL editor:

```sql
select s.name as site, t.tab_key, r.source, count(*) as rows,
       count(*) filter (where r.gone) as gone, max(t.synced_at) as last_read
  from vs_sheet_rows r
  join vs_sheet_tabs t on t.id = r.tab_id
  join vs_sheets sh on sh.id = t.sheet_id
  join vs_sites s on s.id = sh.site_id
 group by 1,2,3 order by 1,2,3;
```
