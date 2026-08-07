-- VS-PATCH-1.sql
-- ============================================================================
-- Three changes, on top of VS-SETUP.sql:
--
--   1. The Vendor Manager can record payments, including for past months.
--   2. A way to load the historical months out of the workbook.
--   3. Payroll / PF / ESIC files (Excel, PDF) attached to a statement and
--      visible to the vendor.
--
-- Run in the Supabase SQL editor, selecting the whole file. Safe to re-run.
-- Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. The Vendor Manager can record payments
-- ---------------------------------------------------------------------------
-- Accounts keeps the capability too. Both can now enter a payment, which is
-- what the separation was really protecting: the vendor still has to approve
-- the amount first, and the payment can never exceed what he approved. That
-- gate is untouched.
insert into vs_caps (role, cap) values ('manager','pay') on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 3. Documents attached to a statement
-- ---------------------------------------------------------------------------
create table if not exists vs_documents (
  id           uuid primary key default gen_random_uuid(),
  statement_id uuid not null references vs_statements(id) on delete cascade,
  path         text not null,
  filename     text not null,
  kind         text not null default 'other'
               check (kind in ('payroll','pf','esic','bill','other')),
  mime         text not null default '',
  size_bytes   bigint not null default 0,
  uploaded_by  text not null,
  uploaded_at  timestamptz not null default now()
);
create index if not exists vs_documents_stmt_idx on vs_documents (statement_id, uploaded_at);

alter table vs_documents enable row level security;
revoke all on table vs_documents from anon, authenticated;
grant select on table vs_documents to authenticated;

drop policy if exists p_docs_r on vs_documents;
create policy p_docs_r on vs_documents for select to authenticated using (vs_sees(statement_id));

-- The bucket. Private - every read goes through a signed URL, so a file can
-- never be guessed at from outside.
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present - skipping the bucket (fine outside Supabase)';
  else
    execute $b$ insert into storage.buckets (id, name, public, file_size_limit)
                values ('vs-docs','vs-docs', false, 26214400)
                on conflict (id) do nothing $b$;
  end if;
end $$;

-- Storage policies. The first folder in the path IS the statement id, so the
-- same vs_sees() rule that governs the statement governs its files: a vendor
-- can open the documents on his own shared statements and nothing else.
do $$
begin
  if to_regclass('storage.objects') is null then
    raise notice 'storage schema not present - skipping storage policies (fine outside Supabase)';
    return;
  end if;

  execute 'drop policy if exists p_vsdocs_read   on storage.objects';
  execute 'drop policy if exists p_vsdocs_write  on storage.objects';
  execute 'drop policy if exists p_vsdocs_delete on storage.objects';

  execute $p$
    create policy p_vsdocs_read on storage.objects for select to authenticated
    using (
      bucket_id = 'vs-docs'
      and array_length(storage.foldername(name),1) >= 1
      and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
      and vs_sees(((storage.foldername(name))[1])::uuid)
    )$p$;

  -- writing needs the capability AND a path that begins with a real
  -- settlement id, so nothing can be parked in the bucket outside the rule
  -- that governs who may read it
  execute $p$
    create policy p_vsdocs_write on storage.objects for insert to authenticated
    with check (
      bucket_id = 'vs-docs'
      and (vs_can('edit_draft') or vs_can('post_payroll'))
      and array_length(storage.foldername(name),1) >= 1
      and (storage.foldername(name))[1] ~ '^[0-9a-fA-F-]{36}$'
      and exists (select 1 from vs_statements st
                   where st.id = ((storage.foldername(name))[1])::uuid)
    )$p$;

  execute $p$
    create policy p_vsdocs_delete on storage.objects for delete to authenticated
    using (
      bucket_id = 'vs-docs'
      and (vs_can('edit_draft') or vs_can('post_payroll'))
    )$p$;
end $$;

create or replace function vs_add_document(p_stmt uuid, p_path text, p_filename text,
                                           p_kind text, p_mime text, p_size bigint)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; st text;
begin
  if not (vs_can('edit_draft') or vs_can('post_payroll')) then
    raise exception 'Your role (%) cannot attach documents.', coalesce(vs_role(),'none')
      using errcode = '42501';
  end if;
  select status into st from vs_statements where id = p_stmt;
  if st is null then raise exception 'No such settlement.' using errcode='02000'; end if;
  if coalesce(trim(p_filename),'') = '' then
    raise exception 'The file needs a name.' using errcode='22023';
  end if;
  insert into vs_documents (statement_id, path, filename, kind, mime, size_bytes, uploaded_by)
  values (p_stmt, p_path, p_filename, coalesce(nullif(p_kind,''),'other'),
          coalesce(p_mime,''), coalesce(p_size,0), vs_actor())
  returning id into nid;
  perform vs_log(p_stmt, '', 'Document attached - ' || p_filename,
    'Kind: ' || coalesce(nullif(p_kind,''),'other') || '. The vendor can open this from his own statement.');
  return nid;
end $$;

create or replace function vs_remove_document(p_doc uuid, p_reason text)
returns text language plpgsql security definer set search_path = public as $$
declare d vs_documents%rowtype;
begin
  if not (vs_can('edit_draft') or vs_can('post_payroll')) then
    raise exception 'Your role (%) cannot remove documents.', coalesce(vs_role(),'none')
      using errcode = '42501';
  end if;
  if coalesce(trim(p_reason),'') = '' then
    raise exception 'A reason is required. The vendor may already have opened this file.'
      using errcode='22023';
  end if;
  select * into d from vs_documents where id = p_doc;
  if not found then raise exception 'No such document.' using errcode='02000'; end if;
  delete from vs_documents where id = p_doc;
  perform vs_log(d.statement_id, 'warn', 'Document removed - ' || d.filename, trim(p_reason));
  return d.path;
end $$;

-- documents ride along with the statement, so the app gets them in one call
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
    'points',   (select coalesce(jsonb_agg(to_jsonb(p) order by p.raised_at),'[]'::jsonb)
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

-- ---------------------------------------------------------------------------
-- 2. Loading a historical month out of the workbook
-- ---------------------------------------------------------------------------
-- One call per site-month. Heads are matched on their LABEL as it reads on
-- that site's sheet, so the import does not depend on any generated key.
-- Everything it creates carries a line in the record saying it was imported
-- and not raised through the portal.
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
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount)
    select vid, h.id, h.key, h.label, h.grp, 'manual', h.sort, 0
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

grant execute on function
  vs_add_document(uuid,text,text,text,text,bigint),
  vs_remove_document(uuid,text),
  vs_import_month(text,date,numeric,text,jsonb,jsonb,text)
to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table vs_documents; exception when duplicate_object then null; end;
  end if;
end $$;

-- ---------------------------------------------------------------- verification
select
  (select count(*) from vs_caps where role='manager' and cap='pay')          as manager_can_pay,
  (select count(*) from information_schema.tables
     where table_name='vs_documents')                                        as documents_table,
  (select count(*) from pg_proc where proname='vs_import_month')             as import_function,
  (select count(*) from pg_proc where proname='vs_add_document')             as upload_function;
-- Expect: 1 - 1 - 1 - 1
