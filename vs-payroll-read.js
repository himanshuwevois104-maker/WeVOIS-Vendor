"use strict";
/* ============================================================================
   Reading the payroll out of the files you already get.

   Three documents, three shapes, all of them plain text inside a PDF:

     PF     EPFO "RETURN STATEMENT (Regular Return)" - one row per member,
            nine trailing numbers: gross, EPF wage, EPS wage, EDLI wage,
            EE, EPS employer share, ER, NCP days, refunds.
     ESIC   "Contribution History" - a five figure summary line, then one row
            per insured person: days, wages, IP contribution.
     Salary the bank's File Transactions report - one row per beneficiary,
            ending value date, transfer type, amount, STATUS.

   The parsers are pure functions of text so they can be tested against the
   real documents without a browser or a PDF library in the way.

   Nothing here ever posts anything. It reads, it reconciles against the totals
   the document states about itself, it says what it could not account for, and
   then a person presses the button.
   ========================================================================== */

var PDFJS_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.min.js";
var PDFJS_WORKER = "https://cdn.jsdelivr.net/npm/pdfjs-dist@3.11.174/build/pdf.worker.min.js";

function n2(x){ return Math.round(Number(x)*100)/100; }
function money(s){ return Number(String(s).replace(/,/g,"")) || 0; }

/* ------------------------------------------------------------------ PF */
function parsePF(text){
  var out = {kind:"pf", rows:[], warnings:[], ok:false};
  if(!/PROVIDENT FUND ORGANISATION|RETURN STATEMENT/i.test(text)) return null;

  var lines = text.split("\n"), rows = [];
  for(var i=0;i<lines.length;i++){
    var m = lines[i].match(/^\s*(\d{1,3})\s+(\d{12})\b.*?((?:\d+\s+){8}\d+)\s*$/);
    if(!m) continue;
    var v = m[3].trim().split(/\s+/).map(Number);
    rows.push({sl:Number(m[1]), uan:m[2], gross:v[0], epf_wage:v[1], eps_wage:v[2],
               edli:v[3], ee:v[4], eps_er:v[5], er:v[6], ncp:v[7], refund:v[8]});
  }
  out.rows = rows;
  if(!rows.length){ out.warnings.push("No member rows could be read out of this PF return."); return out; }

  var g = function(re){ var m = text.match(re); return m ? Number(m[1]) : null; };
  out.stated_members = g(/Total Members\s+(\d+)/i);
  out.stated_epf_wage = g(/Total EPF Contribution\s+(\d+)/i);
  out.stated_eps_wage = g(/Total EPS Contribution\s+(\d+)/i);

  var sum = function(k){ return rows.reduce(function(a,r){ return a + (r[k]||0); }, 0); };
  out.employee = sum("ee");                       /* the member's own 12%   */
  out.employer = sum("eps_er") + sum("er");       /* pension share + the rest */
  out.epf_wage = sum("epf_wage");
  out.eps_wage = sum("eps_wage");
  out.gross    = sum("gross");
  /* a member with nothing against him was on the return but not paid this
     month - counting him would overstate the headcount */
  out.paid_members = rows.filter(function(r){ return r.ee > 0 || r.gross > 0; }).length;
  out.zero_members = rows.length - out.paid_members;

  var est = text.match(/Establishment Id\s+([A-Z0-9]+)/i);
  var rfi = text.match(/Return File Id\s+(\d+)/i);
  var per = text.match(/Return\s*\)\s*:\s*([A-Za-z]{3,9}\s+\d{4})/i) || text.match(/:\s*([A-Za-z]{3,9}\s+\d{4})\s*-/);
  out.establishment = est ? est[1] : "";
  out.return_file_id = rfi ? rfi[1] : "";
  out.period_text = per ? per[1] : "";

  if(out.stated_members !== null && out.stated_members !== rows.length)
    out.warnings.push("The return says " + out.stated_members + " members but " + rows.length +
      " rows could be read. Check the figures before posting.");
  if(out.stated_epf_wage !== null && out.stated_epf_wage !== out.epf_wage)
    out.warnings.push("The EPF wage rows add to " + out.epf_wage + ", but the return states " +
      out.stated_epf_wage + ".");
  if(out.zero_members)
    out.warnings.push(out.zero_members + " member" + (out.zero_members===1?" is":"s are") +
      " on the return with no contribution, so they are not counted in the headcount.");
  out.ok = !!rows.length;
  return out;
}

/* ---------------------------------------------------------------- ESIC */
function parseESIC(text){
  var out = {kind:"esic", rows:[], warnings:[], ok:false};
  if(!/STATE INSURANCE CORPORATION|Contribution History/i.test(text)) return null;

  var lines = text.split("\n"), rows = [];
  for(var i=0;i<lines.length;i++){
    var m = lines[i].match(/^\s*(\d{1,3})\s+-?\s*(\d{10})\s+(.*?)\s+(\d{1,3})\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})/);
    if(!m) continue;
    rows.push({sl:Number(m[1]), ip:m[2], name:m[3].trim(), days:Number(m[4]),
               wages:money(m[5]), ee:money(m[6])});
  }
  out.rows = rows;

  var h = text.match(/([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})\s+([\d,]+\.\d{2})/);
  if(h){
    out.stated_employee = money(h[1]);
    out.stated_employer = money(h[2]);
    out.stated_total    = money(h[3]);
    out.stated_govt     = money(h[4]);
    out.stated_wages    = money(h[5]);
  }
  if(!rows.length && !h){
    out.warnings.push("Nothing could be read out of this ESIC statement.");
    return out;
  }

  out.employee = out.stated_employee != null ? out.stated_employee
                 : n2(rows.reduce(function(a,r){ return a + r.ee; }, 0));
  out.employer = out.stated_employer != null ? out.stated_employer : 0;
  out.wages    = out.stated_wages != null ? out.stated_wages
                 : n2(rows.reduce(function(a,r){ return a + r.wages; }, 0));
  out.paid_members = rows.length;

  var code = text.match(/Contribution History Of\s+(\d+)/i);
  out.employer_code = code ? code[1] : "";
  var per = text.match(/for\s+([A-Za-z]{3,9}\s*\d{4})/i);
  out.period_text = per ? per[1] : "";

  if(rows.length){
    var sumEE = n2(rows.reduce(function(a,r){ return a + r.ee; }, 0));
    var sumW  = n2(rows.reduce(function(a,r){ return a + r.wages; }, 0));
    if(out.stated_employee != null && Math.abs(sumEE - out.stated_employee) >= 0.01)
      out.warnings.push("The rows add to " + sumEE + " of employee contribution but the statement says " +
        out.stated_employee + ".");
    if(out.stated_wages != null && Math.abs(sumW - out.stated_wages) >= 0.01)
      out.warnings.push("The wage rows add to " + sumW + " but the statement says " + out.stated_wages + ".");
  }
  if(out.stated_employee != null && out.stated_employer != null && out.stated_total != null &&
     Math.abs(out.stated_employee + out.stated_employer - out.stated_total) >= 0.01)
    out.warnings.push("Employee plus employer does not equal the total on this statement.");
  out.ok = !!(rows.length || h);
  return out;
}

/* -------------------------------------------------------------- salary */
function parseSalary(text){
  var out = {kind:"salary", rows:[], rejected:[], warnings:[], ok:false};
  if(!/File Transactions|FILE_PAY_AMT/i.test(text)) return null;

  var lines = text.split("\n"), rows = [];
  for(var i=0;i<lines.length;i++){
    var m = lines[i].match(/(\d{2}\/\d{2}\/\d{4})\s+(IMPS|NEFT|RTGS|Intra[\s-]?Bank\s+Transfer)\s+([\d,]+(?:\.\d+)?)\s+([A-Za-z]+)\s*$/);
    if(!m) continue;
    var who = lines[i].match(/^\s*\d+\s+(\S+)\s+(.*?)\s+\d{6,}/);
    rows.push({date:m[1], mode:m[2], amount:money(m[3]), status:m[4],
               code:(who?who[1]:""), name:(who?who[2].trim():"")});
  }
  out.rows = rows;
  if(!rows.length){ out.warnings.push("No payment rows could be read out of this bank file."); return out; }

  var tr = text.match(/Total Records\s*:\s*(\d+)/i);
  out.stated_records = tr ? Number(tr[1]) : null;

  var done = rows.filter(function(r){ return /^processed$/i.test(r.status); });
  out.rejected = rows.filter(function(r){ return !/^processed$/i.test(r.status); });
  out.paid_members = done.length;
  out.amount = n2(done.reduce(function(a,r){ return a + r.amount; }, 0));
  out.amount_all = n2(rows.reduce(function(a,r){ return a + r.amount; }, 0));

  var ref = text.match(/((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{4})\s+Salary/i);
  out.period_text = ref ? ref[1] : "";
  var dates = {}; rows.forEach(function(r){ dates[r.date] = 1; });
  out.value_dates = Object.keys(dates);

  var pre = {};
  rows.forEach(function(r){ var p = (r.code||"").match(/^([A-Za-z]{2,4})/); if(p) pre[p[1].toUpperCase()] = (pre[p[1].toUpperCase()]||0)+1; });
  out.code_prefixes = pre;

  if(out.stated_records !== null && out.stated_records !== rows.length)
    out.warnings.push("The file says " + out.stated_records + " records but " + rows.length +
      " could be read. Check before posting.");
  if(out.rejected.length){
    out.warnings.push(out.rejected.length + " payment" + (out.rejected.length===1?"":"s") +
      " did NOT go through, worth " + n2(out.amount_all - out.amount) +
      ". That money is excluded from the total above - it is a candidate for " +
      "'Salary Not Processed From WeVois' rather than a wage cost.");
  }
  if(Object.keys(pre).length > 1)
    out.warnings.push("This file carries more than one employee code prefix (" +
      Object.keys(pre).map(function(k){ return k + " " + pre[k]; }).join(", ") +
      "), so it may cover more than one site. Only put the part that belongs to this site on this statement.");
  if(out.value_dates.length > 1)
    out.warnings.push("More than one value date in this file: " + out.value_dates.join(", ") + ".");
  out.ok = true;
  return out;
}

/* ------------------------------------------------------------ dispatch */
function parsePayrollText(text){
  return parsePF(text) || parseESIC(text) || parseSalary(text) || null;
}

/* --------------------------------------------------- pdf text, in browser */
var _pdfjs = null;
function loadPdfJs(){
  if(_pdfjs) return Promise.resolve(_pdfjs);
  if(window.pdfjsLib){ _pdfjs = window.pdfjsLib; return Promise.resolve(_pdfjs); }
  return new Promise(function(res, rej){
    var s = document.createElement("script");
    s.src = PDFJS_URL;
    s.onload = function(){
      _pdfjs = window.pdfjsLib;
      if(_pdfjs) _pdfjs.GlobalWorkerOptions.workerSrc = PDFJS_WORKER;
      res(_pdfjs);
    };
    s.onerror = function(){ rej(new Error("Could not load the PDF reader. Check the internet connection.")); };
    document.head.appendChild(s);
  });
}

async function pdfText(file){
  var lib = await loadPdfJs();
  var buf = await file.arrayBuffer();
  var doc = await lib.getDocument({data:buf}).promise;
  var all = [];
  for(var p=1; p<=doc.numPages; p++){
    var page = await doc.getPage(p);
    var c = await page.getTextContent();
    /* rebuild lines from the item positions, because the payroll rows only
       mean anything as lines */
    var byY = {};
    c.items.forEach(function(it){
      var y = Math.round(it.transform[5]);
      (byY[y] = byY[y] || []).push({x:it.transform[4], s:it.str});
    });
    Object.keys(byY).map(Number).sort(function(a,b){ return b-a; }).forEach(function(y){
      all.push(byY[y].sort(function(a,b){ return a.x-b.x; })
        .map(function(i){ return i.s; }).join(" ").replace(/\s+/g," ").trim());
    });
  }
  return all.join("\n");
}

async function readPayrollFile(file){
  var name = (file.name||"").toLowerCase();
  var text;
  if(/\.pdf$/.test(name)) text = await pdfText(file);
  else text = await file.text();
  var parsed = parsePayrollText(text);
  if(!parsed) throw new Error("That does not look like a PF return, an ESIC contribution history, or a bank salary file.");
  parsed.filename = file.name;
  return parsed;
}

if(typeof module !== "undefined" && module.exports)
  module.exports = {parsePF:parsePF, parseESIC:parseESIC, parseSalary:parseSalary,
                    parsePayrollText:parsePayrollText};
