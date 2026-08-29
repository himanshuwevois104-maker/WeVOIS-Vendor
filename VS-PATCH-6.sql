-- VS-PATCH-6.sql
-- ============================================================================
-- Two things:
--
--   1. When a monthly amount goes out, the people who should know are told by
--      email. The CEO and the VP hear about every site; each vendor hears only
--      about his own. The portal writes the mail into an outbox; a small
--      function on Supabase sends it from your office address. If the sender is
--      not set up yet, the mail still queues and is still visible - nothing is
--      lost, it just waits.
--
--   2. The vendor manager can put a question or a figure to the CEO or the VP
--      and get a written yes or no. Where the request carries an amount, an
--      approval writes that amount onto the statement itself as an adjustment,
--      with the approver's name and the date as its reason.
--
-- On the second one, read this before you run it. The CEO and the VP have been
-- strict observers until now: every write refused, proved by assertions that
-- try it as them. That does not change wholesale. They get exactly ONE new
-- thing they can do - answer a request that was put to them - and they are
-- still refused everything else, including raising the request in the first
-- place. Somebody has to ask before they can answer.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-5.
-- Safe to re-run. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Where the mail is addressed from, and what it links back to
-- ---------------------------------------------------------------------------
alter table vs_settings add column if not exists mail_from    text not null default '';
alter table vs_settings add column if not exists mail_from_nm text not null default 'WeVois Vendor Settlement';
alter table vs_settings add column if not exists portal_url   text not null default '';
alter table vs_settings add column if not exists mail_on      bool not null default true;

create or replace function vs_save_mail_settings(p_from text, p_name text, p_url text, p_on bool)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform vs_require('manage_masters');
  update vs_settings
     set mail_from    = coalesce(trim(p_from), mail_from),
         mail_from_nm = coalesce(nullif(trim(p_name),''), mail_from_nm),
         portal_url   = coalesce(trim(p_url), portal_url),
         mail_on      = coalesce(p_on, mail_on)
   where id = 1;
  perform vs_audit_log('Mail settings changed',
    'From ' || coalesce(nullif(trim(p_from),''),'(not set)') ||
    ', notifications ' || case when coalesce(p_on,true) then 'ON' else 'OFF' end);
end $$;

-- ---------------------------------------------------------------------------
-- 2. The outbox
-- ---------------------------------------------------------------------------
-- Every message the portal wants sent, whether or not a sender is configured.
-- It is a record like everything else here: who it went to, what it said, and
-- whether it actually left.
create table if not exists vs_mail (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid references vs_statements(id) on delete set null,
  kind         text not null default 'shared',
  to_email     text not null,
  to_name      text not null default '',
  to_role      text not null default '',
  subject      text not null,
  body_text    text not null,
  body_html    text not null default '',
  status       text not null default 'queued' check (status in ('queued','sent','failed','skipped')),
  attempts     int  not null default 0,
  error        text not null default '',
  created_at   timestamptz not null default now(),
  sent_at      timestamptz
);
create index if not exists vs_mail_queue_idx on vs_mail (status, created_at);
create index if not exists vs_mail_stmt_idx  on vs_mail (statement_id);

alter table vs_mail enable row level security;
revoke all on table vs_mail from anon, authenticated;
grant select on table vs_mail to authenticated;
drop policy if exists p_mail_r on vs_mail;
-- staff see the outbox; a vendor does not need to watch other people's post
create policy p_mail_r on vs_mail for select to authenticated using (vs_can('view_all'));

create or replace function vs_queue_mail(p_stmt uuid, p_kind text, p_email text, p_name text,
                                         p_role text, p_subject text, p_text text, p_html text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; on_ bool;
begin
  select mail_on into on_ from vs_settings where id = 1;
  if coalesce(trim(p_email),'') = '' then return null; end if;
  insert into vs_mail (statement_id, kind, to_email, to_name, to_role, subject, body_text, body_html, status)
  values (p_stmt, p_kind, lower(trim(p_email)), coalesce(p_name,''), coalesce(p_role,''),
          p_subject, p_text, coalesce(p_html,''),
          case when coalesce(on_,true) then 'queued' else 'skipped' end)
  returning id into nid;
  return nid;
end $$;

-- ---------------------------------------------------------------------------
-- 3. The message itself
-- ---------------------------------------------------------------------------
create or replace function vs_notify_shared(p_stmt uuid, p_kind text default 'shared')
returns int language plpgsql security definer set search_path = public as $$
declare s record; vno int; fin numeric; n int := 0; r record; url text; org text;
        subj text; body text; html text; whatv text; whats text;
begin
  select st.id, st.period, st.covers_from, st.covers_to, v.name as vendor, v.id as vendor_id,
         si.name as site
    into s
    from vs_statements st
    join vs_contracts c on c.id = st.contract_id
    join vs_vendors   v on v.id = c.vendor_id
    join vs_sites    si on si.id = c.site_id
   where st.id = p_stmt;
  if not found then return 0; end if;

  select v into vno from vs_versions where id = vs_current_version(p_stmt);
  fin := vs_version_final(vs_current_version(p_stmt));
  select coalesce(nullif(portal_url,''),''), coalesce(nullif(org_name,''),'WeVois')
    into url, org from vs_settings where id = 1;

  whats := case when p_kind = 'revised' then 'Revised statement' else 'Statement' end;

  -- the vendor: his own site only
  subj := org || ' - ' || s.site || ' - ' || vs_period_label(s.period) || ' - ' ||
          to_char(fin, 'FM99,99,99,999') ;
  body := 'Dear ' || s.vendor || ',' || chr(10) || chr(10) ||
     whats || ' version ' || vno || ' for ' || s.site || ', ' || vs_period_label(s.period) ||
     ' is now on the portal.' || chr(10) || chr(10) ||
     'Amount for payment: ' || to_char(fin, 'FM99,99,99,999') || chr(10) ||
     'Covering: ' || to_char(s.covers_from,'DD Mon YYYY') || ' to ' || to_char(s.covers_to,'DD Mon YYYY') || chr(10) ||
     chr(10) ||
     'Please open the portal to check it line by line. If you disagree with any figure, raise a point on that '||
     'exact line so it can be checked and answered in writing. If anything else needs saying, use the Queries tab.' ||
     chr(10) || chr(10) ||
     case when url <> '' then url || chr(10) || chr(10) else '' end ||
     'This is an automatic message from the ' || org || ' vendor settlement portal.';
  html := '<p>Dear ' || s.vendor || ',</p><p>' || whats || ' <b>version ' || vno || '</b> for <b>' ||
     s.site || '</b>, ' || vs_period_label(s.period) || ' is now on the portal.</p>' ||
     '<p style="font-size:20px"><b>' || to_char(fin,'FM99,99,99,999') || '</b><br>' ||
     '<span style="color:#666;font-size:13px">covering ' || to_char(s.covers_from,'DD Mon YYYY') ||
     ' to ' || to_char(s.covers_to,'DD Mon YYYY') || '</span></p>' ||
     '<p>Please open the portal and check it line by line. If you disagree with a figure, raise a point on that ' ||
     'exact line so it can be checked and answered in writing.</p>' ||
     case when url <> '' then '<p><a href="' || url || '">Open the portal</a></p>' else '' end ||
     '<p style="color:#888;font-size:12px">Automatic message from the ' || org || ' vendor settlement portal.</p>';

  for r in select p.email, p.full_name from vs_profiles p
            where p.role = 'vendor' and p.active and p.vendor_id = s.vendor_id loop
    perform vs_queue_mail(p_stmt, p_kind, r.email, r.full_name, 'vendor', subj, body, html);
    n := n + 1;
  end loop;

  -- the CEO and the VP: every site
  whatv := whats || ' sent - ' || s.site || ' - ' || s.vendor;
  subj := org || ' - ' || whatv || ' - ' || vs_period_label(s.period);
  body := whats || ' version ' || vno || ' has gone to the vendor.' || chr(10) || chr(10) ||
     'Site: ' || s.site || chr(10) ||
     'Partner: ' || s.vendor || chr(10) ||
     'Month: ' || vs_period_label(s.period) || chr(10) ||
     'Amount for payment: ' || to_char(fin, 'FM99,99,99,999') || chr(10) || chr(10) ||
     case when url <> '' then url || chr(10) || chr(10) else '' end ||
     'You are receiving this because you have observer access to every site.';
  html := '<p>' || whats || ' <b>version ' || vno || '</b> has gone to the vendor.</p>' ||
     '<table style="font-size:14px"><tr><td style="color:#666;padding-right:14px">Site</td><td><b>' || s.site ||
     '</b></td></tr><tr><td style="color:#666">Partner</td><td>' || s.vendor ||
     '</td></tr><tr><td style="color:#666">Month</td><td>' || vs_period_label(s.period) ||
     '</td></tr><tr><td style="color:#666">Amount</td><td><b>' || to_char(fin,'FM99,99,99,999') ||
     '</b></td></tr></table>' ||
     case when url <> '' then '<p><a href="' || url || '">Open the portal</a></p>' else '' end ||
     '<p style="color:#888;font-size:12px">You receive this because you have observer access to every site.</p>';

  for r in select p.email, p.full_name, p.role from vs_profiles p
            where p.role in ('ceo','vp') and p.active loop
    perform vs_queue_mail(p_stmt, p_kind, r.email, r.full_name, r.role, subj, body, html);
    n := n + 1;
  end loop;

  return n;
end $$;

-- ---------------------------------------------------------------------------
-- 4. Sharing tells people
-- ---------------------------------------------------------------------------
-- The mail is queued inside its own block. A settlement going out must never
-- fail because the post did not.
create or replace function vs_share(p_stmt uuid)
returns void language plpgsql security definer set search_path = public as $$
declare st text; pr text; vid uuid; d int;
begin
  perform vs_require('share');
  select status into st from vs_statements where id = p_stmt;
  select status into pr from vs_payroll    where statement_id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st <> 'draft' then raise exception 'Only a draft can be shared.' using errcode='42501'; end if;
  if pr <> 'posted' then
    raise exception 'The processed salary and PF/ESIC have not been posted for this month yet. The statement cannot go out until they are.'
      using errcode='42501';
  end if;
  vid := vs_current_version(p_stmt);
  select window_days into d from vs_settings where id = 1;
  update vs_versions set sent_at = now() where id = vid;
  update vs_statements set status = 'sent', due_at = now() + (d + 2) * interval '1 day' where id = p_stmt;
  perform vs_log(p_stmt, 'hi', 'Statement v' || (select v from vs_versions where id=vid) || ' shared',
    'Final amount ' || vs_version_final(vid) || '. Response window ' || d || ' working days.');
  begin
    perform vs_notify_shared(p_stmt, 'shared');
  exception when others then
    perform vs_log(p_stmt, 'warn', 'Notification could not be queued', sqlerrm);
  end;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Asking the CEO or the VP
-- ---------------------------------------------------------------------------
create table if not exists vs_approvals (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  question     text not null,
  amount       numeric(14,2),
  effect       text check (effect in ('add','deduct')),
  adj_label    text not null default '',
  asked_by     text not null,
  asked_uid    uuid,
  asked_at     timestamptz not null default now(),
  status       text not null default 'open' check (status in ('open','approved','declined')),
  decided_by   text,
  decided_role text,
  decided_at   timestamptz,
  decision_note text not null default '',
  applied      bool not null default false,
  applied_in   int
);
create index if not exists vs_approvals_idx on vs_approvals (statement_id, asked_at);

alter table vs_approvals enable row level security;
revoke all on table vs_approvals from anon, authenticated;
grant select on table vs_approvals to authenticated;
drop policy if exists p_appr_r on vs_approvals;
-- the vendor does not see what WeVois asked its own leadership
create policy p_appr_r on vs_approvals for select to authenticated using (vs_can('view_all'));

insert into vs_caps (role, cap) values ('ceo','approve_request'), ('vp','approve_request')
on conflict do nothing;

create or replace function vs_request_approval(p_stmt uuid, p_question text, p_amount numeric,
                                               p_effect text, p_label text)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; nm text; sn text; r record; url text; org text; subj text; body text; html text;
begin
  perform vs_require('revise');           -- the vendor manager, and the admin
  if not exists (select 1 from vs_statements where id = p_stmt) then
    raise exception 'No such settlement.' using errcode='02000';
  end if;
  if coalesce(trim(p_question),'') = '' then
    raise exception 'Write down what you are asking. That text is what they answer.' using errcode='22023';
  end if;
  if p_amount is not null then
    if p_amount = 0 then
      raise exception 'An amount of zero would change nothing. Leave it blank to ask a plain question.'
        using errcode='22023';
    end if;
    if coalesce(p_effect,'') not in ('add','deduct') then
      raise exception 'Say whether the amount is added to the partner or deducted from him.' using errcode='22023';
    end if;
    if coalesce(trim(p_label),'') = '' then
      raise exception 'The amount needs a label. It becomes the line the vendor reads.' using errcode='22023';
    end if;
  end if;

  insert into vs_approvals (statement_id, question, amount, effect, adj_label, asked_by, asked_uid)
  values (p_stmt, trim(p_question), p_amount, nullif(p_effect,''), coalesce(trim(p_label),''),
          vs_actor(), auth.uid())
  returning id into nid;

  perform vs_log(p_stmt, 'warn', 'Sent to the CEO and VP for confirmation',
    trim(p_question) ||
    case when p_amount is not null
      then ' [' || trim(p_label) || ' ' || p_effect || ' ' || p_amount || ']' else '' end);

  select v.name || ' - ' || si.name into sn
    from vs_statements st join vs_contracts c on c.id = st.contract_id
    join vs_vendors v on v.id = c.vendor_id join vs_sites si on si.id = c.site_id
   where st.id = p_stmt;
  select coalesce(nullif(portal_url,''),''), coalesce(nullif(org_name,''),'WeVois')
    into url, org from vs_settings where id = 1;

  subj := org || ' - your confirmation is needed - ' || sn;
  body := vs_actor() || ' has asked for your confirmation on ' || sn || '.' || chr(10) || chr(10) ||
    trim(p_question) || chr(10) || chr(10) ||
    case when p_amount is not null
      then 'Proposed: ' || trim(p_label) || ', ' ||
           case p_effect when 'add' then 'added to' else 'deducted from' end ||
           ' the partner, ' || to_char(p_amount,'FM99,99,99,999') || chr(10) ||
           'If you approve, that line is written onto the statement with your name against it.' || chr(10) || chr(10)
      else '' end ||
    case when url <> '' then url || chr(10) || chr(10) else '' end ||
    'Approve or decline it in the portal. Either way your answer is recorded in writing.';
  html := '<p><b>' || vs_actor() || '</b> has asked for your confirmation on <b>' || sn || '</b>.</p>' ||
    '<blockquote style="border-left:3px solid #ccc;padding-left:12px;color:#333">' || trim(p_question) || '</blockquote>' ||
    case when p_amount is not null
      then '<p>Proposed: <b>' || trim(p_label) || '</b>, ' ||
           case p_effect when 'add' then 'added to' else 'deducted from' end || ' the partner, <b>' ||
           to_char(p_amount,'FM99,99,99,999') || '</b><br><span style="color:#666;font-size:13px">' ||
           'If you approve, that line is written onto the statement with your name against it.</span></p>'
      else '' end ||
    case when url <> '' then '<p><a href="' || url || '">Open the portal</a></p>' else '' end;

  for r in select p.email, p.full_name, p.role from vs_profiles p
            where p.role in ('ceo','vp') and p.active loop
    perform vs_queue_mail(p_stmt, 'approval', r.email, r.full_name, r.role, subj, body, html);
  end loop;
  return nid;
end $$;

-- The one thing an observer may do. Note what it does NOT allow: raising the
-- request, editing the question, changing the amount, or touching anything else
-- on the settlement.
create or replace function vs_decide_approval(p_id uuid, p_ok bool, p_note text)
returns text language plpgsql security definer set search_path = public as $$
declare ap vs_approvals%rowtype; st text; vid uuid; org text; url text; r record;
begin
  perform vs_require('approve_request');
  select * into ap from vs_approvals where id = p_id;
  if not found then raise exception 'No such request.' using errcode='02000'; end if;
  if ap.status <> 'open' then
    raise exception 'That was already % by %.', ap.status, ap.decided_by using errcode='22023';
  end if;
  if p_ok is null then raise exception 'Approve it or decline it.' using errcode='22023'; end if;
  if not p_ok and coalesce(trim(p_note),'') = '' then
    raise exception 'Say why you are declining. That reason is the record.' using errcode='22023';
  end if;

  update vs_approvals
     set status = case when p_ok then 'approved' else 'declined' end,
         decided_by = vs_actor(), decided_role = vs_role(), decided_at = now(),
         decision_note = coalesce(trim(p_note),'')
   where id = p_id;

  perform vs_log(ap.statement_id, case when p_ok then 'ok' else 'warn' end,
    case when p_ok then 'Confirmed by ' || vs_actor() else 'Declined by ' || vs_actor() end,
    ap.question || case when coalesce(trim(p_note),'') <> '' then ' -- "' || trim(p_note) || '"' else '' end);

  if not p_ok or ap.amount is null then
    return case when p_ok then 'approved' else 'declined' end;
  end if;

  -- an approved amount becomes a line on the statement
  select status into st from vs_statements where id = ap.statement_id;
  vid := vs_current_version(ap.statement_id);
  if st = 'draft' then
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (vid, ap.adj_label, ap.effect, ap.amount,
            'Approved by ' || vs_actor() || ' (' || vs_role() || ') on ' ||
            to_char(now(),'DD Mon YYYY') || '. ' || ap.question, 900);
    update vs_approvals set applied = true where id = p_id;
    perform vs_log(ap.statement_id, 'ok', 'Approved amount added to the draft',
      ap.adj_label || ' ' || ap.effect || ' ' || ap.amount || ', on ' || vs_actor() || '''s approval.');
    return 'approved and applied';
  end if;

  perform vs_log(ap.statement_id, 'warn', 'Approved amount waiting for the next version',
    ap.adj_label || ' ' || ap.effect || ' ' || ap.amount ||
    ' will appear when the vendor manager issues the next version.');
  return 'approved, lands on the next version';
end $$;

-- ---------------------------------------------------------------------------
-- 6. An approved amount lands with the next version
-- ---------------------------------------------------------------------------
create or replace function vs_apply_approvals(p_stmt uuid, p_ver uuid, p_vno int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare ap record; ch jsonb := '[]'::jsonb;
begin
  for ap in select * from vs_approvals
             where statement_id = p_stmt and status = 'approved' and not applied and amount is not null
             order by asked_at loop
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (p_ver, ap.adj_label, ap.effect, ap.amount,
            'Approved by ' || ap.decided_by || ' on ' || to_char(ap.decided_at,'DD Mon YYYY') || '. ' || ap.question, 900);
    ch := ch || jsonb_build_array(jsonb_build_object('label', ap.adj_label, 'from', 0, 'to',
            case ap.effect when 'deduct' then -ap.amount else ap.amount end,
            'why', 'Approved by ' || ap.decided_by || '. ' || ap.question));
    update vs_approvals set applied = true, applied_in = p_vno where id = ap.id;
  end loop;
  return ch;
end $$;


-- ---------------------------------------------------------------------------
-- 7. The revision picks up approved amounts, and tells people again
-- ---------------------------------------------------------------------------
create or replace function vs_issue_revision(p_stmt uuid)
returns int language plpgsql security definer set search_path = public as $$
declare oldv uuid; oldn int; newv uuid; ch jsonb := '[]'::jsonb; n int := 0;
        pt record; fix jsonb; e jsonb; d int; opencount int; oldgross numeric; why text;
        appr int;
begin
  perform vs_require('revise');
  oldv := vs_current_version(p_stmt);
  select v, gross_amount into oldn, oldgross from vs_versions where id = oldv;

  select pending_fix, pending_fix_why into fix, why from vs_payroll where statement_id = p_stmt;
  if fix is not null and jsonb_array_length(fix) > 0 then n := n + 1; end if;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and not published
     and status in ('accepted','partial','rejected','carry_forward','disputed_record');
  n := n + opencount;
  select count(*) into appr from vs_approvals
   where statement_id = p_stmt and status = 'approved' and not applied and amount is not null;
  n := n + appr;
  if n = 0 then raise exception 'Nothing has been decided yet.' using errcode='22023'; end if;

  insert into vs_versions (statement_id, v, gross_amount, gross_note, sent_at)
    select p_stmt, oldn + 1, gross_amount, gross_note, now() from vs_versions where id = oldv
  returning id into newv;
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount)
    select newv, head_id, head_key, head_label, grp, src, sort, amount
      from vs_version_lines where version_id = oldv;
  insert into vs_version_adj (version_id, adj_type_id, label, effect, amount, reference, note, payroll_linked, sort)
    select newv, adj_type_id, label, effect, amount, reference, note, payroll_linked, sort
      from vs_version_adj where version_id = oldv;

  if fix is not null then
    for e in select * from jsonb_array_elements(fix) loop
      if e->>'kind' = 'head' then
        update vs_version_lines set amount = (e->>'to')::numeric where version_id = newv and head_key = e->>'key';
        ch := ch || jsonb_build_array(jsonb_build_object('label',
          (select head_label from vs_version_lines where version_id = newv and head_key = e->>'key'),
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      else
        perform vs_apply_payroll(p_stmt, newv);
        ch := ch || jsonb_build_array(jsonb_build_object('label','Salary Not Processed From WeVois',
          'from', e->'from', 'to', e->'to', 'why', coalesce(nullif(why,''), e->>'why')));
      end if;
    end loop;
    update vs_payroll set pending_fix = null, pending_fix_why = null, pending_fix_by = null, pending_fix_at = null
     where statement_id = p_stmt;
  end if;

  for pt in select * from vs_points where statement_id = p_stmt and not published
             and status in ('accepted','partial','rejected','carry_forward','disputed_record')
  loop
    if pt.status in ('accepted','partial') then
      if pt.target_kind = 'gross' then
        ch := ch || jsonb_build_array(jsonb_build_object('label','Total Expenses Should Be Paid',
          'from', oldgross, 'to', pt.new_amount, 'why', pt.decision));
        update vs_versions set gross_amount = pt.new_amount where id = newv;
      elsif pt.target_kind = 'head'
         and exists (select 1 from vs_version_lines
                      where version_id = newv and head_key = pt.target_key and src = 'manual') then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_lines where version_id=newv and head_key=pt.target_key),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_lines set amount = pt.new_amount where version_id = newv and head_key = pt.target_key;
      elsif pt.target_kind = 'adjustment' then
        ch := ch || jsonb_build_array(jsonb_build_object('label', pt.target_label,
          'from', (select amount from vs_version_adj where version_id=newv and label=pt.target_label),
          'to', pt.new_amount, 'why', pt.decision));
        update vs_version_adj set amount = pt.new_amount
         where version_id = newv and label = pt.target_label;
      end if;
    end if;
    update vs_points set published = true, published_in = oldn + 1 where id = pt.id;
  end loop;

  -- anything the CEO or VP approved that has not gone on yet
  ch := ch || vs_apply_approvals(p_stmt, newv, oldn + 1);

  update vs_versions set changes = ch,
    note = n || ' item(s) answered. ' || jsonb_array_length(ch) || ' amount(s) changed.'
   where id = newv;

  select window_days into d from vs_settings where id = 1;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and status in ('open','awaiting_confirm')
     and target_kind <> 'general';
  update vs_statements
     set status = case when opencount > 0 then 'under_query' else 'sent' end,
         due_at = now() + (d + 2) * interval '1 day'
   where id = p_stmt;

  perform vs_log(p_stmt, 'hi', 'Statement v' || (oldn + 1) || ' shared',
    jsonb_array_length(ch) || ' amount change(s) from v' || oldn ||
    '. New final amount ' || vs_version_final(newv) || '.');
  begin
    perform vs_notify_shared(p_stmt, 'revised');
  exception when others then
    perform vs_log(p_stmt, 'warn', 'Notification could not be queued', sqlerrm);
  end;
  return oldn + 1;
end $$;

-- the app reads approvals and the outbox with everything else
create or replace function vs_statement_extra(p_stmt uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  return jsonb_build_object(
    'approvals', case when vs_can('view_all') then
       (select coalesce(jsonb_agg(to_jsonb(a) order by a.asked_at),'[]'::jsonb)
          from vs_approvals a where a.statement_id = p_stmt) else '[]'::jsonb end,
    'mail', case when vs_can('view_all') then
       (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'to_email',m.to_email,'to_name',m.to_name,
                'to_role',m.to_role,'subject',m.subject,'status',m.status,'error',m.error,
                'created_at',m.created_at,'sent_at',m.sent_at) order by m.created_at desc),'[]'::jsonb)
          from vs_mail m where m.statement_id = p_stmt) else '[]'::jsonb end);
end $$;

grant execute on function vs_statement_extra(uuid) to authenticated;

grant execute on function
  vs_save_mail_settings(text,text,text,bool), vs_queue_mail(uuid,text,text,text,text,text,text,text),
  vs_notify_shared(uuid,text), vs_request_approval(uuid,text,numeric,text,text),
  vs_decide_approval(uuid,bool,text), vs_apply_approvals(uuid,uuid,int),
  vs_statement_extra(uuid)
to authenticated;

-- ---------------------------------------------------------------- verification
select
  (select count(*) = 1 from information_schema.tables where table_name='vs_mail')       as outbox,
  (select count(*) = 1 from information_schema.tables where table_name='vs_approvals')  as approvals,
  (select count(*) = 2 from vs_caps where cap='approve_request')                        as ceo_and_vp,
  (select count(*) = 0 from vs_caps where cap='approve_request'
     and role not in ('ceo','vp'))                                                      as nobody_else,
  (select count(*) = 1 from pg_proc where proname='vs_notify_shared')                   as notifier,
  (select count(*) = 1 from pg_proc where proname='vs_decide_approval')                 as decider;
-- Expect: t | t | t | t | t | t
