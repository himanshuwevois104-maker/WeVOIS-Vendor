-- VS-PATCH-5.sql
-- ============================================================================
-- Five things, all of them about the vendor having a voice and the payroll
-- telling the truth when it arrives in pieces.
--
--   1. The vendor can raise a point on the EARNED amount itself, not just on
--      an expense head or an adjustment line.
--   2. A general query - anything not about a figure on this month's sheet -
--      with a written answer from the vendor manager and a running set of
--      remarks from either side.
--   3. The vendor can attach a file to his own statement. Until now only the
--      manager and Accounts could, so "send me the bill" stayed a phone call.
--   4. Salary processed late goes on as a TOP-UP entry with its own challan,
--      its own date and its own note, instead of overwriting the month.
--   5. Everything above rides along in vs_statement_json, so the app gets it
--      in the same single call.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-4.
-- Safe to re-run. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. What a point can be about, and what can become of it
-- ---------------------------------------------------------------------------
alter table vs_points drop constraint if exists vs_points_target_kind_check;
alter table vs_points add constraint vs_points_target_kind_check
  check (target_kind in ('head','adjustment','gross','general'));

alter table vs_points drop constraint if exists vs_points_status_check;
alter table vs_points add constraint vs_points_status_check
  check (status in ('open','awaiting_confirm','disputed_record',
                    'accepted','partial','rejected','carry_forward','answered'));

-- ---------------------------------------------------------------------------
-- 2. Remarks - a thread hanging off any point
-- ---------------------------------------------------------------------------
create table if not exists vs_point_remarks (
  id        uuid primary key default gen_random_uuid(),
  point_id  uuid not null references vs_points(id) on delete cascade,
  body      text not null,
  by_name   text not null,
  by_role   text not null,
  at        timestamptz not null default now()
);
create index if not exists vs_point_remarks_idx on vs_point_remarks (point_id, at);

alter table vs_point_remarks enable row level security;
revoke all on table vs_point_remarks from anon, authenticated;
grant select on table vs_point_remarks to authenticated;

drop policy if exists p_remarks_r on vs_point_remarks;
create policy p_remarks_r on vs_point_remarks for select to authenticated
  using (exists (select 1 from vs_points p where p.id = point_id and vs_sees(p.statement_id)));

-- ---------------------------------------------------------------------------
-- 3. A general query, and the answer to it
-- ---------------------------------------------------------------------------
-- Deliberately does NOT move the statement to "under query". A question about
-- a fuel card or next month's vehicles should not hold up a settlement whose
-- figures nobody is disputing. It also stays raisable after approval, because
-- that is exactly when people remember things.
create or replace function vs_raise_query(p_stmt uuid, p_note text, p_attach text default '')
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; vno int;
begin
  perform vs_require('raise');
  if not vs_sees(p_stmt) then
    raise exception 'That is not your statement.' using errcode='42501';
  end if;
  if coalesce(trim(p_note),'') = '' then
    raise exception 'Write the question down. That text is the record.' using errcode='22023';
  end if;
  select v into vno from vs_versions where id = vs_current_version(p_stmt);
  insert into vs_points (statement_id, target_kind, target_key, target_label, source,
                         raised_by, version_no, note, attachment, status)
  values (p_stmt, 'general', '', 'General query', 'portal', vs_actor(),
          coalesce(vno,1), trim(p_note), coalesce(p_attach,''), 'open')
  returning id into nid;
  perform vs_log(p_stmt, 'warn', 'Query raised', '"' || trim(p_note) || '"');
  return nid;
end $$;

create or replace function vs_answer_query(p_point uuid, p_reply text)
returns void language plpgsql security definer set search_path = public as $$
declare pt vs_points%rowtype;
begin
  perform vs_require('resolve');
  select * into pt from vs_points where id = p_point;
  if not found then raise exception 'No such query.' using errcode='02000'; end if;
  if pt.target_kind <> 'general' then
    raise exception 'That is a point on a figure. Answer it from the Points tab, where the amount can move.'
      using errcode='22023';
  end if;
  if coalesce(trim(p_reply),'') = '' then
    raise exception 'An answer is required. It is what the vendor sees.' using errcode='22023';
  end if;
  update vs_points
     set status = 'answered', decision = trim(p_reply),
         decided_by = vs_actor(), decided_at = now()
   where id = p_point;
  perform vs_log(pt.statement_id, 'ok', 'Query answered', '"' || trim(p_reply) || '"');
end $$;

-- Either side may add a remark, on a general query or on a point about a
-- figure. It never moves an amount and never changes a status - it is the
-- written trail of what was said around the decision.
create or replace function vs_add_remark(p_point uuid, p_body text)
returns uuid language plpgsql security definer set search_path = public as $$
declare pt vs_points%rowtype; nid uuid; r text;
begin
  r := vs_role();
  if r is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  if r in ('ceo','vp') then
    raise exception 'Observer accounts cannot write on a settlement.' using errcode='42501';
  end if;
  select * into pt from vs_points where id = p_point;
  if not found then raise exception 'No such point.' using errcode='02000'; end if;
  if not vs_sees(pt.statement_id) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  if coalesce(trim(p_body),'') = '' then
    raise exception 'A remark cannot be blank.' using errcode='22023';
  end if;
  insert into vs_point_remarks (point_id, body, by_name, by_role)
  values (p_point, trim(p_body), vs_actor(), r)
  returning id into nid;
  perform vs_log(pt.statement_id, '', 'Remark added on ' || pt.target_label, '"' || trim(p_body) || '"');
  return nid;
end $$;

-- ---------------------------------------------------------------------------
-- 4. An accepted point on the earned amount moves the earned amount
-- ---------------------------------------------------------------------------
create or replace function vs_issue_revision(p_stmt uuid)
returns int language plpgsql security definer set search_path = public as $$
declare oldv uuid; oldn int; newv uuid; ch jsonb := '[]'::jsonb; n int := 0;
        pt record; fix jsonb; e jsonb; d int; opencount int; oldgross numeric; why text;
begin
  perform vs_require('revise');
  oldv := vs_current_version(p_stmt);
  select v, gross_amount into oldn, oldgross from vs_versions where id = oldv;

  -- whoever parked the correction wrote a reason; that is what the vendor
  -- should read, not a stock phrase naming a role that may not have done it
  select pending_fix, pending_fix_why into fix, why from vs_payroll where statement_id = p_stmt;
  if fix is not null and jsonb_array_length(fix) > 0 then n := n + 1; end if;
  select count(*) into opencount from vs_points
   where statement_id = p_stmt and not published
     and status in ('accepted','partial','rejected','carry_forward','disputed_record');
  n := n + opencount;
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
        -- what the partner earned, agreed after the vendor questioned it
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
  return oldn + 1;
end $$;

-- ---------------------------------------------------------------------------
-- 5. The vendor can attach his own files
-- ---------------------------------------------------------------------------
alter table vs_documents add column if not exists uploaded_uid uuid;

create or replace function vs_add_document(p_stmt uuid, p_path text, p_filename text,
                                           p_kind text, p_mime text, p_size bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; st text; r text;
begin
  r := vs_role();
  if r is null then raise exception 'Not signed in.' using errcode='42501'; end if;
  if not (vs_can('edit_draft') or vs_can('post_payroll') or r = 'vendor') then
    raise exception 'Your role (%) cannot attach documents.', r using errcode = '42501';
  end if;
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if coalesce(trim(p_filename),'') = '' then
    raise exception 'The file needs a name.' using errcode='22023';
  end if;
  insert into vs_documents (statement_id, path, filename, kind, mime, size_bytes,
                            uploaded_by, uploaded_uid)
  values (p_stmt, p_path, p_filename, coalesce(nullif(p_kind,''),'other'),
          coalesce(p_mime,''), coalesce(p_size,0), vs_actor(), auth.uid())
  returning id into nid;
  perform vs_log(p_stmt, '', 'Document attached - ' || p_filename,
    'Kind: ' || coalesce(nullif(p_kind,''),'other') || '. Attached by ' || vs_actor() || '.');
  return nid;
end $$;

-- A vendor may take back only what he himself put up. Staff may remove any of
-- it, with a reason, exactly as before.
create or replace function vs_remove_document(p_doc uuid, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
declare d vs_documents%rowtype; r text;
begin
  r := vs_role();
  select * into d from vs_documents where id = p_doc;
  if not found then raise exception 'No such document.' using errcode='02000'; end if;
  if vs_can('edit_draft') or vs_can('post_payroll') then
    null;
  elsif r = 'vendor' and d.uploaded_uid is not distinct from auth.uid() then
    null;
  else
    raise exception 'You can only remove a file you attached yourself.' using errcode = '42501';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required. Somebody may already have opened this file.'
      using errcode='22023';
  end if;
  delete from vs_documents where id = p_doc;
  perform vs_log(d.statement_id, 'warn', 'Document removed - ' || d.filename, trim(p_reason));
  return d.path;
end $$;

do $do$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage schema not present - skipping storage policies';
    return;
  end if;
  execute 'drop policy if exists p_vsdocs_write  on storage.objects';
  execute 'drop policy if exists p_vsdocs_delete on storage.objects';
  execute $p$
    create policy p_vsdocs_write on storage.objects for insert to authenticated
    with check (
      bucket_id = 'vs-docs'
      and array_length(storage.foldername(name),1) >= 1
      and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
      and vs_sees(((storage.foldername(name))[1])::uuid)
      and (vs_can('edit_draft') or vs_can('post_payroll') or vs_role() = 'vendor')
    )$p$;
  execute $p$
    create policy p_vsdocs_delete on storage.objects for delete to authenticated
    using (
      bucket_id = 'vs-docs'
      and (vs_can('edit_draft') or vs_can('post_payroll') or vs_role() = 'vendor')
    )$p$;
end $do$;

-- ---------------------------------------------------------------------------
-- 6. Payroll that arrives in pieces
-- ---------------------------------------------------------------------------
-- The first posting is the month as Accounts or the manager knew it then. When
-- people left off that run are processed later, the top-up goes on as its own
-- entry with its own challan and date. vs_payroll keeps the running total, so
-- everything downstream - the derived heads, the statement, the vendor's copy -
-- is unchanged; the entries are what let you see how the total was reached.
create table if not exists vs_payroll_batches (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  seq          int  not null,
  dh_pay      numeric(14,2) not null default 0,
  dh_heads    int not null default 0,
  dh_pf_ee    numeric(14,2) not null default 0,
  dh_pf_er    numeric(14,2) not null default 0,
  dh_esic_ee  numeric(14,2) not null default 0,
  dh_esic_er  numeric(14,2) not null default 0,
  stf_pay     numeric(14,2) not null default 0,
  stf_heads   int not null default 0,
  stf_pf_ee   numeric(14,2) not null default 0,
  stf_pf_er   numeric(14,2) not null default 0,
  stf_esic_ee numeric(14,2) not null default 0,
  stf_esic_er numeric(14,2) not null default 0,
  pf_trrn      text not null default '',
  pf_paid_on   date,
  esic_challan text not null default '',
  esic_paid_on date,
  processed_on date,
  note         text not null default '',
  posted_by    text not null,
  posted_at    timestamptz not null default now(),
  unique (statement_id, seq)
);
create index if not exists vs_payroll_batches_idx on vs_payroll_batches (statement_id, seq);

alter table vs_payroll_batches enable row level security;
revoke all on table vs_payroll_batches from anon, authenticated;
grant select on table vs_payroll_batches to authenticated;
drop policy if exists p_prbatch_r on vs_payroll_batches;
create policy p_prbatch_r on vs_payroll_batches for select to authenticated
  using (vs_sees(statement_id));

create or replace function vs_add_payroll_batch(p_stmt uuid, p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare st text; nseq int; vid uuid; already bool; det text; heads int;
begin
  perform vs_require('post_payroll');
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st = 'paid' then raise exception 'This settlement is closed.' using errcode='42501'; end if;
  select (status = 'posted') into already from vs_payroll where statement_id = p_stmt;
  if not coalesce(already,false) then
    raise exception 'Post the month first. A top-up only makes sense on top of a posting.'
      using errcode='22023';
  end if;
  if coalesce(p->>'pf_trrn','') = '' or coalesce(p->>'esic_challan','') = '' then
    raise exception 'PF TRRN and ESIC challan are both required on a top-up too. They are what the vendor verifies against.'
      using errcode='22023';
  end if;
  if coalesce(trim(p->>'note'),'') = '' then
    raise exception 'Say why this batch is going on late. The vendor sees it.' using errcode='22023';
  end if;
  if coalesce((p->>'dh_pay')::numeric,0) + coalesce((p->>'stf_pay')::numeric,0) <= 0 then
    raise exception 'A top-up with no wages and no salary in it would change nothing.' using errcode='22023';
  end if;

  select coalesce(max(seq),1) + 1 into nseq from vs_payroll_batches where statement_id = p_stmt;

  insert into vs_payroll_batches (statement_id, seq,
    dh_pay, dh_heads, dh_pf_ee, dh_pf_er, dh_esic_ee, dh_esic_er,
    stf_pay, stf_heads, stf_pf_ee, stf_pf_er, stf_esic_ee, stf_esic_er,
    pf_trrn, pf_paid_on, esic_challan, esic_paid_on, processed_on, note, posted_by)
  values (p_stmt, nseq,
    coalesce((p->>'dh_pay')::numeric,0), coalesce((p->>'dh_heads')::int,0),
    coalesce((p->>'dh_pf_ee')::numeric,0), coalesce((p->>'dh_pf_er')::numeric,0),
    coalesce((p->>'dh_esic_ee')::numeric,0), coalesce((p->>'dh_esic_er')::numeric,0),
    coalesce((p->>'stf_pay')::numeric,0), coalesce((p->>'stf_heads')::int,0),
    coalesce((p->>'stf_pf_ee')::numeric,0), coalesce((p->>'stf_pf_er')::numeric,0),
    coalesce((p->>'stf_esic_ee')::numeric,0), coalesce((p->>'stf_esic_er')::numeric,0),
    p->>'pf_trrn', nullif(p->>'pf_paid_on','')::date,
    p->>'esic_challan', nullif(p->>'esic_paid_on','')::date,
    nullif(p->>'processed_on','')::date, trim(p->>'note'), vs_actor());

  update vs_payroll set
    dh_pay = dh_pay + coalesce((p->>'dh_pay')::numeric,0),
    dh_heads = dh_heads + coalesce((p->>'dh_heads')::int,0),
    dh_pf_ee = dh_pf_ee + coalesce((p->>'dh_pf_ee')::numeric,0),
    dh_pf_er = dh_pf_er + coalesce((p->>'dh_pf_er')::numeric,0),
    dh_esic_ee = dh_esic_ee + coalesce((p->>'dh_esic_ee')::numeric,0),
    dh_esic_er = dh_esic_er + coalesce((p->>'dh_esic_er')::numeric,0),
    stf_pay = stf_pay + coalesce((p->>'stf_pay')::numeric,0),
    stf_heads = stf_heads + coalesce((p->>'stf_heads')::int,0),
    stf_pf_ee = stf_pf_ee + coalesce((p->>'stf_pf_ee')::numeric,0),
    stf_pf_er = stf_pf_er + coalesce((p->>'stf_pf_er')::numeric,0),
    stf_esic_ee = stf_esic_ee + coalesce((p->>'stf_esic_ee')::numeric,0),
    stf_esic_er = stf_esic_er + coalesce((p->>'stf_esic_er')::numeric,0),
    posted_by = vs_actor(), posted_at = now()
  where statement_id = p_stmt;

  select dh_heads + stf_heads into heads from vs_payroll where statement_id = p_stmt;
  det := 'Top-up ' || nseq || ': ' ||
         coalesce((p->>'dh_heads')::int,0) + coalesce((p->>'stf_heads')::int,0) ||
         ' more person(s), wages ' || coalesce((p->>'dh_pay')::numeric,0) ||
         ', staff salary ' || coalesce((p->>'stf_pay')::numeric,0) ||
         '. PF TRRN ' || (p->>'pf_trrn') || ', ESIC challan ' || (p->>'esic_challan') ||
         '. The month now totals ' || heads || ' persons. "' || trim(p->>'note') || '"';

  vid := vs_current_version(p_stmt);
  if st = 'draft' then
    perform vs_apply_payroll(p_stmt, vid);
    perform vs_log(p_stmt, 'pay', 'Payroll top-up posted', det);
    return 'posted';
  end if;

  update vs_payroll
     set pending_fix = vs_payroll_diff(p_stmt, vid),
         pending_fix_why = 'Salary processed late: ' || trim(p->>'note'),
         pending_fix_by = vs_actor(), pending_fix_at = now()
   where statement_id = p_stmt;
  perform vs_log(p_stmt, 'warn', 'Payroll top-up parked for the next version', det);
  return 'parked';
end $$;

-- The first posting is batch 1, recorded the same way so the entries read as
-- one list rather than "the original, plus some others".
create or replace function vs_sync_first_batch(p_stmt uuid) returns void
language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype;
begin
  select * into pr from vs_payroll where statement_id = p_stmt;
  if not found or pr.status <> 'posted' then return; end if;
  insert into vs_payroll_batches (statement_id, seq,
    dh_pay, dh_heads, dh_pf_ee, dh_pf_er, dh_esic_ee, dh_esic_er,
    stf_pay, stf_heads, stf_pf_ee, stf_pf_er, stf_esic_ee, stf_esic_er,
    pf_trrn, pf_paid_on, esic_challan, esic_paid_on, processed_on, note, posted_by, posted_at)
  values (p_stmt, 1, pr.dh_pay, pr.dh_heads, pr.dh_pf_ee, pr.dh_pf_er, pr.dh_esic_ee, pr.dh_esic_er,
    pr.stf_pay, pr.stf_heads, pr.stf_pf_ee, pr.stf_pf_er, pr.stf_esic_ee, pr.stf_esic_er,
    pr.pf_trrn, pr.pf_paid_on, pr.esic_challan, pr.esic_paid_on, pr.processed_on,
    'The month as posted.', coalesce(pr.posted_by,'unknown'), coalesce(pr.posted_at, now()))
  on conflict (statement_id, seq) do update set
    dh_pay = excluded.dh_pay, dh_heads = excluded.dh_heads,
    dh_pf_ee = excluded.dh_pf_ee, dh_pf_er = excluded.dh_pf_er,
    dh_esic_ee = excluded.dh_esic_ee, dh_esic_er = excluded.dh_esic_er,
    stf_pay = excluded.stf_pay, stf_heads = excluded.stf_heads,
    stf_pf_ee = excluded.stf_pf_ee, stf_pf_er = excluded.stf_pf_er,
    stf_esic_ee = excluded.stf_esic_ee, stf_esic_er = excluded.stf_esic_er,
    pf_trrn = excluded.pf_trrn, esic_challan = excluded.esic_challan,
    posted_by = excluded.posted_by, posted_at = excluded.posted_at;
end $$;


-- The generic wording no longer names Accounts, because the vendor manager can
-- post a payroll too. Where a reason was written it is used instead of this.
create or replace function vs_payroll_diff(p_stmt uuid, p_ver uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype; out jsonb := '[]'::jsonb; cur numeric;
        w text := 'Payroll correction posted.';
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select * into pr from vs_payroll where statement_id = p_stmt;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages';
  if cur is distinct from pr.dh_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages','from',cur,'to',pr.dh_pay,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_ee';
  if cur is distinct from pr.dh_pf_ee + pr.dh_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_ee','from',cur,'to',pr.dh_pf_ee+pr.dh_esic_ee,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_er';
  if cur is distinct from pr.dh_pf_er + pr.dh_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_er','from',cur,'to',pr.dh_pf_er+pr.dh_esic_er,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='salary';
  if cur is distinct from pr.stf_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','salary','from',cur,'to',pr.stf_pay,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_ee';
  if cur is distinct from pr.stf_pf_ee + pr.stf_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_ee','from',cur,'to',pr.stf_pf_ee+pr.stf_esic_ee,'why',w)); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_er';
  if cur is distinct from pr.stf_pf_er + pr.stf_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_er','from',cur,'to',pr.stf_pf_er+pr.stf_esic_er,'why',w)); end if;
  select coalesce(amount,0) into cur from vs_version_adj where version_id=p_ver and payroll_linked;
  if coalesce(cur,0) is distinct from pr.not_processed_amount then out := out || jsonb_build_array(jsonb_build_object(
    'kind','adj','key','not_processed','from',coalesce(cur,0),'to',pr.not_processed_amount,'why',w)); end if;
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Remarks and payroll entries ride along in the same single call
-- ---------------------------------------------------------------------------
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

-- The original posting logic, unchanged, renamed so the wrapper below can add
-- the batch record without touching a line of the arithmetic.
create or replace function vs_post_payroll_base(p_stmt uuid, p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare vid uuid; st text; already bool; ch jsonb := '[]'::jsonb; nowline numeric;
        was_np numeric; det text; np_label text := 'Salary Not Processed From WeVois';
        np_type uuid; heads int;
begin
  perform vs_require('post_payroll');
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if st = 'paid' then raise exception 'This settlement is closed.' using errcode='42501'; end if;

  if coalesce(p->>'pf_trrn','') = '' or coalesce(p->>'esic_challan','') = '' then
    raise exception 'PF TRRN and ESIC challan number are both required. They are what the vendor verifies against.'
      using errcode='22023';
  end if;
  if (p->>'not_processed_amount')::numeric > 0 and coalesce(p->>'not_processed_reason','') = '' then
    raise exception 'A reason is required for salary not processed from WeVois.' using errcode='22023';
  end if;

  select (status = 'posted') into already from vs_payroll where statement_id = p_stmt;
  vid := vs_current_version(p_stmt);
  select amount into was_np from vs_version_adj where version_id = vid and payroll_linked limit 1;

  update vs_payroll set
    status='posted', posted_by = vs_actor(), posted_at = now(),
    processed_on = nullif(p->>'processed_on','')::date,
    dh_pay=(p->>'dh_pay')::numeric, dh_heads=(p->>'dh_heads')::int,
    dh_pf_ee=(p->>'dh_pf_ee')::numeric, dh_pf_er=(p->>'dh_pf_er')::numeric,
    dh_esic_ee=(p->>'dh_esic_ee')::numeric, dh_esic_er=(p->>'dh_esic_er')::numeric,
    stf_pay=(p->>'stf_pay')::numeric, stf_heads=(p->>'stf_heads')::int,
    stf_pf_ee=(p->>'stf_pf_ee')::numeric, stf_pf_er=(p->>'stf_pf_er')::numeric,
    stf_esic_ee=(p->>'stf_esic_ee')::numeric, stf_esic_er=(p->>'stf_esic_er')::numeric,
    pf_trrn=p->>'pf_trrn', pf_paid_on=nullif(p->>'pf_paid_on','')::date,
    esic_challan=p->>'esic_challan', esic_paid_on=nullif(p->>'esic_paid_on','')::date,
    not_processed_amount=(p->>'not_processed_amount')::numeric,
    not_processed_reason=coalesce(p->>'not_processed_reason','')
  where statement_id = p_stmt;

  select dh_heads + stf_heads into heads from vs_payroll where statement_id = p_stmt;
  det := heads || ' persons. Wages ' || (p->>'dh_pay') || ', staff salary ' || (p->>'stf_pay')
       || '. PF TRRN ' || (p->>'pf_trrn') || ', ESIC challan ' || (p->>'esic_challan')
       || '. Not processed from WeVois ' || (p->>'not_processed_amount') || '.';

  if not already and st = 'draft' then
    perform vs_apply_payroll(p_stmt, vid);
    perform vs_log(p_stmt, 'pay', 'Payroll posted for ' ||
      vs_period_label((select period from vs_statements where id = p_stmt)), det);
    return 'posted';
  end if;

  -- correction after the statement has gone out: park it, do not touch the frozen version
  ch := vs_payroll_diff(p_stmt, vid);
  if jsonb_array_length(ch) = 0 then
    perform vs_log(p_stmt, 'pay', 'Payroll re-posted', det || ' No figure changed.');
    return 'nochange';
  end if;
  update vs_payroll set pending_fix = ch,
    pending_fix_why = jsonb_array_length(ch) || ' manpower figure(s) corrected after the statement went out.',
    pending_fix_by = vs_actor(), pending_fix_at = now()
   where statement_id = p_stmt;
  perform vs_log(p_stmt, 'pay', 'Payroll correction posted', det || ' Reaches the vendor with the next version.');
  return 'parked';
end $$;

-- the first posting records itself as batch 1, so the entries read as one list
create or replace function vs_post_payroll(p_stmt uuid, p jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare r text;
begin
  r := vs_post_payroll_base(p_stmt, p);
  perform vs_sync_first_batch(p_stmt);
  return r;
end $$;

grant execute on function
  vs_raise_query(uuid,text,text), vs_answer_query(uuid,text), vs_add_remark(uuid,text),
  vs_add_payroll_batch(uuid,jsonb), vs_sync_first_batch(uuid),
  vs_post_payroll_base(uuid,jsonb)
to authenticated;

-- ---------------------------------------------------------------- verification
select
  (select count(*) = 1 from pg_proc where proname='vs_raise_query')        as query_fn,
  (select count(*) = 1 from pg_proc where proname='vs_answer_query')       as answer_fn,
  (select count(*) = 1 from pg_proc where proname='vs_add_remark')         as remark_fn,
  (select count(*) = 1 from pg_proc where proname='vs_add_payroll_batch')  as topup_fn,
  (select count(*) = 1 from information_schema.tables
     where table_name='vs_point_remarks')                                  as remarks_table,
  (select count(*) = 1 from information_schema.tables
     where table_name='vs_payroll_batches')                                as batches_table;
-- Expect: t | t | t | t | t | t
