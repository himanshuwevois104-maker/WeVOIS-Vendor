-- VS-PATCH-7.sql
-- ============================================================================
-- Each booking head gets an EFFECT - the same three choices the adjustment
-- lines under the Total already have:
--
--   reduces payment  the head is money WeVois spent for him, taken off what we
--                    pay. This is what every head has always done, and every
--                    head that exists today keeps doing it.
--   credits him      the head is added to what we pay instead of taken off.
--   recorded only    the row appears on the statement with its figure and does
--                    NOT move the Total. This is the payment-record case: a
--                    line that has to be on the sheet because it happened, but
--                    that must not be counted a second time.
--
-- The vendor manager chooses it per month, on the draft, beside the amount.
-- The administrator sets the site's standing choice under Sites & heads, so a
-- head that is always a credit is not re-chosen every month.
--
-- Payroll heads are not offered the choice. Those figures are posted by
-- Accounts out of the PF, ESIC and bank files, and money that has left the
-- company for his men is a deduction by definition. Anything else about a
-- payroll belongs in an adjustment line, where it already can go.
--
-- Run AFTER VS-PATCH-6.sql, in the Supabase SQL editor, selecting the whole
-- file. Safe to re-run. Nothing already shared changes: every line that exists
-- is written as 'deduct', which is exactly what it was, so every historical
-- Final amount stands to the rupee.
-- Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------- 1. columns
alter table vs_head_templates add column if not exists effect text not null default 'deduct';
alter table vs_heads          add column if not exists effect text not null default 'deduct';
alter table vs_version_lines  add column if not exists effect text not null default 'deduct';

do $do$ begin
  if not exists (select 1 from pg_constraint where conname = 'vs_head_templates_effect_ck') then
    alter table vs_head_templates add constraint vs_head_templates_effect_ck
      check (effect in ('add','deduct','note'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vs_heads_effect_ck') then
    alter table vs_heads add constraint vs_heads_effect_ck
      check (effect in ('add','deduct','note'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'vs_version_lines_effect_ck') then
    alter table vs_version_lines add constraint vs_version_lines_effect_ck
      check (effect in ('add','deduct','note'));
  end if;
end $do$;

-- ---------------------------------------------------------- 2. the arithmetic
-- vs_version_heads keeps its meaning: THE NET AMOUNT TAKEN OFF the gross. So
-- Total = gross - heads still reads the same, and every screen, every stored
-- change diff and every mail that already quotes it stays correct. A credit
-- head lowers that net; a recorded-only head does not touch it at all.
create or replace function vs_version_heads(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then (select coalesce(sum(case effect when 'add'  then -amount
                                          when 'note' then 0
                                          else amount end), 0)
            from vs_version_lines where version_id = p_ver)
  end
$$;

-- What WeVois actually SPENT under the heads. Not the same number any more:
-- the per-vehicle memo exists to compare one site's running cost against
-- another's, and a credit back to the partner is not a cost of running a site.
create or replace function vs_version_spend(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then (select coalesce(sum(amount) filter (where effect = 'deduct'), 0)
            from vs_version_lines where version_id = p_ver)
  end
$$;

-- ------------------------------------------------- 3. carrying the choice forward
-- A new month starts from the site's standing choice. Payroll heads are
-- forced to reduces-payment whatever the site says.
create or replace function vs_add_statement(p_contract uuid, p_period date)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid; vid uuid; per date; lbl text; sname text;
begin
  perform vs_require('manage_settlements');
  per := date_trunc('month', p_period)::date;
  if not exists (select 1 from vs_contracts c where c.id = p_contract
                  and daterange(c.from_date, coalesce(c.to_date,'infinity'::date), '[]')
                   && daterange(per, (per + interval '1 month - 1 day')::date, '[]')) then
    raise exception 'That vendor was not running this site in %.', vs_period_label(per) using errcode = '22023';
  end if;
  select s.name into sname from vs_contracts c join vs_sites s on s.id = c.site_id where c.id = p_contract;
  if not (select vs_site_open_in(c.site_id, per) from vs_contracts c where c.id = p_contract) then
    raise exception '% was not open in % - check the site''s start and closing dates.',
      sname, vs_period_label(per) using errcode = '22023';
  end if;
  if exists (select 1 from vs_statements where contract_id = p_contract and period = per) then
    raise exception 'That vendor and site already has a settlement for %.', vs_period_label(per)
      using errcode = '23505';
  end if;
  insert into vs_statements (contract_id, period, covers_from, covers_to, created_by)
  select p_contract, per,
         greatest(c.from_date, per),
         least(coalesce(c.to_date,'infinity'::date), (per + interval '1 month - 1 day')::date),
         auth.uid()
    from vs_contracts c where c.id = p_contract
  returning id into sid;
  insert into vs_versions (statement_id, v) values (sid, 1) returning id into vid;
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount, effect)
    select vid, h.id, h.key, h.label, h.grp, h.src, h.sort, 0,
           case when h.src = 'payroll' then 'deduct' else h.effect end
      from vs_heads h join vs_contracts c on c.site_id = h.site_id
     where c.id = p_contract and h.active;
  insert into vs_payroll (statement_id) values (sid);
  select v.name || ' - ' || s.name into lbl
    from vs_contracts c join vs_vendors v on v.id = c.vendor_id join vs_sites s on s.id = c.site_id
   where c.id = p_contract;
  perform vs_log(sid, 'hi', 'Settlement opened for ' || vs_period_label(per),
    'Created by the administrator for ' || lbl || '. Heads start at zero; Accounts posts the payroll, the vendor manager fills the running heads.');
  perform vs_audit_log('Settlement opened', lbl || ' - ' || vs_period_label(per));
  return sid;
end $$;

-- A revision inherits the choice that was on the version it corrects.
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
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount, effect)
    select newv, head_id, head_key, head_label, grp, src, sort, amount, effect
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

-- The workbook import carries the site's standing choice too, so re-importing
-- a month lands the same way a fresh month would.
create or replace function vs_import_month(
  p_site    text,
  p_period  date,
  p_gross   numeric,
  p_status  text,            -- 'paid' or anything else for approved-not-paid
  p_heads   jsonb,           -- {"r_m_exp": 12345, ...} keyed on the head key
  p_adj     jsonb,           -- [{"label":"...","effect":"add|deduct|note","amount":n}]
  p_hint    text default null -- 'incoming' picks the vendor who took over mid-month
) returns text
language plpgsql security definer set search_path = public as $$
declare
  sid uuid; cid uuid; stid uuid; vid uuid; per date; mend date;
  k text; n int := 0; miss text := ''; fin numeric; a jsonb; i int := 0;
begin
  perform vs_require('manage_settlements');
  per  := date_trunc('month', p_period)::date;
  mend := (per + interval '1 month - 1 day')::date;

  select id into sid from vs_sites where lower(name) = lower(p_site);
  if sid is null then return 'no such site: ' || p_site; end if;

  if p_hint = 'incoming' then
    select id into cid from vs_contracts
     where site_id = sid and from_date between per and mend
     order by from_date desc limit 1;
  else
    select id into cid from vs_contracts
     where site_id = sid
       and daterange(from_date, coalesce(to_date,'infinity'::date), '[]') && daterange(per, mend, '[]')
     order by from_date limit 1;
  end if;
  if cid is null then return 'no vendor on ' || p_site || ' in ' || vs_period_label(per); end if;

  if exists (select 1 from vs_statements where contract_id = cid and period = per) then
    return 'already there: ' || p_site || ' ' || vs_period_label(per);
  end if;

  insert into vs_statements (contract_id, period, covers_from, covers_to, created_by)
  select cid, per, greatest(c.from_date, per),
         least(coalesce(c.to_date,'infinity'::date), mend), auth.uid()
    from vs_contracts c where c.id = cid
  returning id into stid;

  insert into vs_versions (statement_id, v, gross_amount, gross_note, sent_at)
  values (stid, 1, coalesce(p_gross,0),
          'Imported from Operation Partners Payment Details 9.xlsx', now())
  returning id into vid;

  -- start from that site's own heads, then fill by label
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount, effect)
    select vid, h.id, h.key, h.label, h.grp, 'manual', h.sort, 0, h.effect
      from vs_heads h join vs_contracts c on c.site_id = h.site_id
     where c.id = cid and h.active;

  for k in select jsonb_object_keys(coalesce(p_heads,'{}'::jsonb)) loop
    -- matched on key, not label: several sites carry two rows both called
    -- "ESIC Pf (Employee Part)" (the vendor's own staff and the site staff),
    -- and matching on the label would collapse them into one figure
    update vs_version_lines set amount = (p_heads ->> k)::numeric
     where version_id = vid and head_key = k;
    if found then n := n + 1; else miss := miss || k || '; '; end if;
  end loop;

  for a in select * from jsonb_array_elements(coalesce(p_adj,'[]'::jsonb)) loop
    i := i + 1;
    insert into vs_version_adj (version_id, label, effect, amount, note, sort)
    values (vid, a->>'label', coalesce(a->>'effect','deduct'), (a->>'amount')::numeric,
            'Imported from the workbook', i * 10);
  end loop;

  -- historical months did not go through the payroll posting, so mark it done
  -- and leave the figures where the sheet put them
  insert into vs_payroll (statement_id, status, posted_by, posted_at,
                          pf_trrn, esic_challan, not_processed_reason)
  values (stid, 'posted', 'Imported from workbook', now(), 'n/a - imported', 'n/a - imported',
          'Historical month loaded from the spreadsheet.')
  on conflict (statement_id) do nothing;

  fin := vs_version_final(vid);
  update vs_statements
     set status = case when lower(coalesce(p_status,'')) = 'paid' then 'paid' else 'approved' end,
         approved_at = now(), approved_by = 'Imported from workbook',
         approved_version = 1, approved_amount = fin
   where id = stid;

  if lower(coalesce(p_status,'')) = 'paid' and fin > 0 then
    insert into vs_payments (statement_id, amount, paid_on, utr, mode, note, recorded_by)
    values (stid, fin, mend, 'IMPORTED', 'n/a',
            'Marked paid on the spreadsheet. No UTR was recorded there.', 'Imported from workbook');
  end if;

  perform vs_log(stid, 'hi', 'Imported from the workbook',
    'Loaded from Operation Partners Payment Details 9.xlsx for ' || vs_period_label(per) ||
    '. Earned ' || coalesce(p_gross,0) || ', ' || n || ' expense heads, final ' || fin ||
    '. This month was settled on the spreadsheet, not raised through the portal.' ||
    case when miss <> '' then ' Heads not found on this site: ' || miss else '' end);

  return case when miss = '' then 'ok' else 'ok, but unmatched heads: ' || miss end;
end $$;

-- ------------------------------------------- 4. the vendor manager's choice
-- p_effects is {"head_key":"add|deduct|note"}.
drop function if exists vs_save_draft(uuid, numeric, text, jsonb, jsonb);
create or replace function vs_save_draft(p_stmt uuid, p_gross numeric, p_gross_note text,
                                         p_lines jsonb, p_adj jsonb,
                                         p_effects jsonb default null)
returns void language plpgsql security definer set search_path = public as $$
declare vid uuid; st text; k text; a jsonb; i int := 0; eff text;
begin
  perform vs_require('edit_draft');
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st <> 'draft' then
    raise exception 'This version has already gone to the vendor. It is frozen; corrections go out as a new version.'
      using errcode='42501';
  end if;
  vid := vs_current_version(p_stmt);

  update vs_versions set gross_amount = coalesce(p_gross, gross_amount),
                         gross_note   = coalesce(p_gross_note, gross_note)
   where id = vid;

  for k in select jsonb_object_keys(coalesce(p_lines,'{}'::jsonb)) loop
    update vs_version_lines set amount = (p_lines ->> k)::numeric
     where version_id = vid and head_key = k and src = 'manual';
  end loop;

  -- the same two rules that govern the amounts govern the effect: only a
  -- manual head, only on a draft. A payroll figure belongs to Accounts.
  for k in select jsonb_object_keys(coalesce(p_effects,'{}'::jsonb)) loop
    eff := p_effects ->> k;
    if eff not in ('add','deduct','note') then
      raise exception 'A head can only credit him, reduce the payment, or be recorded only. "%" is none of those.', eff
        using errcode='22023';
    end if;
    update vs_version_lines set effect = eff
     where version_id = vid and head_key = k and src = 'manual';
  end loop;

  if p_adj is not null then
    delete from vs_version_adj where version_id = vid and not payroll_linked;
    for a in select * from jsonb_array_elements(p_adj) loop
      i := i + 1;
      insert into vs_version_adj (version_id, adj_type_id, label, effect, amount, reference, note, sort)
      values (vid, nullif(a->>'adj_type_id','')::uuid, a->>'label',
              coalesce(a->>'effect','deduct'), (a->>'amount')::numeric,
              coalesce(a->>'reference',''), coalesce(a->>'note',''), i * 10);
    end loop;
  end if;
end $$;

-- ------------------------------------------- 5. the site's standing choice
drop function if exists vs_add_head(uuid, text, text, text, text, int);
create or replace function vs_add_head(p_site uuid, p_key text, p_label text, p_grp text,
                                       p_src text, p_sort int, p_effect text default 'deduct')
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; eff text;
begin
  perform vs_require('manage_masters');
  eff := coalesce(nullif(p_effect,''), 'deduct');
  if eff not in ('add','deduct','note') then
    raise exception 'A head can only credit him, reduce the payment, or be recorded only.' using errcode='22023';
  end if;
  if coalesce(nullif(p_src,''),'manual') = 'payroll' then eff := 'deduct'; end if;
  insert into vs_heads (site_id, key, label, grp, src, sort, effect)
  values (p_site, p_key, p_label, coalesce(nullif(p_grp,''),'run'),
          coalesce(nullif(p_src,''),'manual'), coalesce(p_sort,900), eff)
  returning id into nid;
  perform vs_audit_log('Booking head added',
    p_label || ' at ' || (select name from vs_sites where id = p_site) || ' - ' ||
    case eff when 'add' then 'credits him' when 'note' then 'recorded only'
             else 'reduces payment' end);
  return nid;
end $$;

drop function if exists vs_set_head(uuid, text, int, bool);
create or replace function vs_set_head(p_head uuid, p_label text, p_sort int, p_active bool,
                                       p_effect text default null)
returns void language plpgsql security definer set search_path = public as $$
declare src text; was text;
begin
  perform vs_require('manage_masters');
  select h.src, h.effect into src, was from vs_heads h where h.id = p_head;
  if src is null then raise exception 'No such booking head.' using errcode='02000'; end if;
  if p_effect is not null and p_effect <> '' then
    if p_effect not in ('add','deduct','note') then
      raise exception 'A head can only credit him, reduce the payment, or be recorded only.' using errcode='22023';
    end if;
    if src = 'payroll' and p_effect <> 'deduct' then
      raise exception 'A payroll head is money that has already left the company for his men, so it always reduces the payment. Put the exception in an adjustment line instead.'
        using errcode='22023';
    end if;
  end if;
  update vs_heads set label  = coalesce(nullif(p_label,''), label),
                      sort   = coalesce(p_sort, sort),
                      active = coalesce(p_active, active),
                      effect = coalesce(nullif(p_effect,''), effect)
   where id = p_head;
  perform vs_audit_log('Booking head changed', coalesce(p_label,'') ||
    ' at ' || (select st.name from vs_heads h join vs_sites st on st.id = h.site_id where h.id = p_head) ||
    case when p_effect is not null and p_effect <> '' and p_effect is distinct from was
         then ' - now ' || case p_effect when 'add' then 'credits him'
                                         when 'note' then 'recorded only'
                                         else 'reduces payment' end
         else '' end);
end $$;

-- --------------------------------------------------------------- 6. the payload
create or replace function vs_statement_json(p_stmt uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare out jsonb;
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select jsonb_build_object(
    'statement', to_jsonb(s) - 'created_by',
    'period_label', vs_period_label(s.period),
    'vendor', to_jsonb(v), 'site', to_jsonb(si), 'contract', to_jsonb(c),
    'site_history', vs_site_history(si.id),
    'adj_types', (select coalesce(jsonb_agg(to_jsonb(t) order by t.sort),'[]'::jsonb)
                    from vs_adj_types t where t.active),
    'payroll', to_jsonb(pr),
    'payroll_batches', (select coalesce(jsonb_agg(to_jsonb(b) order by b.seq),'[]'::jsonb)
                    from vs_payroll_batches b where b.statement_id = s.id),
    'paid_total', vs_paid_total(s.id),
    'documents', (select coalesce(jsonb_agg(to_jsonb(dc) order by dc.uploaded_at),'[]'::jsonb)
                    from vs_documents dc where dc.statement_id = s.id),
    'versions', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', ve.id, 'v', ve.v, 'sent_at', ve.sent_at, 'viewed_at', ve.viewed_at,
        'note', ve.note, 'changes', ve.changes,
        'gross', ve.gross_amount, 'gross_note', ve.gross_note,
        'heads_total', vs_version_heads(ve.id),
        'spend_total', vs_version_spend(ve.id),
        'total', vs_version_total(ve.id), 'adj_total', vs_version_adj_total(ve.id),
        'final', vs_version_final(ve.id),
        'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.sort),'[]'::jsonb)
                    from vs_version_lines l where l.version_id = ve.id),
        'adjustments', (select coalesce(jsonb_agg(to_jsonb(a) order by a.sort),'[]'::jsonb)
                    from vs_version_adj a where a.version_id = ve.id)
      ) order by ve.v), '[]'::jsonb) from vs_versions ve where ve.statement_id = s.id),
    'points',   (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'target_kind', p.target_kind, 'target_key', p.target_key,
        'target_label', p.target_label, 'source', p.source, 'raised_by', p.raised_by,
        'raised_at', p.raised_at, 'version_no', p.version_no, 'claimed', p.claimed,
        'note', p.note, 'attachment', p.attachment, 'status', p.status,
        'confirmed_at', p.confirmed_at, 'decision', p.decision, 'decided_by', p.decided_by,
        'decided_at', p.decided_at, 'new_amount', p.new_amount, 'published', p.published,
        'published_in', p.published_in,
        'remarks', (select coalesce(jsonb_agg(to_jsonb(rm) order by rm.at),'[]'::jsonb)
                      from vs_point_remarks rm where rm.point_id = p.id)
      ) order by p.raised_at), '[]'::jsonb)
                   from vs_points p where p.statement_id = s.id),
    'payments', (select coalesce(jsonb_agg(to_jsonb(pm) order by pm.paid_on),'[]'::jsonb)
                   from vs_payments pm where pm.statement_id = s.id),
    'events',   (select coalesce(jsonb_agg(to_jsonb(e) order by e.at),'[]'::jsonb)
                   from vs_events e where e.statement_id = s.id)
  ) into out
  from vs_statements s
  join vs_contracts c on c.id = s.contract_id
  join vs_vendors  v  on v.id = c.vendor_id
  join vs_sites    si on si.id = c.site_id
  left join vs_payroll pr on pr.statement_id = s.id
  where s.id = p_stmt;
  return out;
end $$;

-- ---------------------------------------------------------------- 7. permission
grant execute on function
  vs_version_spend(uuid),
  vs_version_heads(uuid),
  vs_save_draft(uuid,numeric,text,jsonb,jsonb,jsonb),
  vs_add_head(uuid,text,text,text,text,int,text),
  vs_set_head(uuid,text,int,bool,text),
  vs_add_statement(uuid,date),
  vs_issue_revision(uuid),
  vs_import_month(text,date,numeric,text,jsonb,jsonb,text),
  vs_statement_json(uuid)
to authenticated;

-- ------------------------------------------------------------------ 8. proof
select 'every line that already exists reads as reduces-payment' as check,
       count(*) filter (where effect = 'deduct') as deduct,
       count(*) filter (where effect <> 'deduct') as other
  from vs_version_lines;
