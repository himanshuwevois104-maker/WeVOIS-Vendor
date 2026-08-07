-- VS-PATCH-2.sql
-- ============================================================================
-- A vendor was able to read other vendors' sites, months and figures.
--
-- The row-level policies were right all along: reading vs_sites, vs_vendors,
-- vs_contracts or vs_statements directly, a vendor already saw only his own.
-- The hole was on the other side. Several reader functions are SECURITY
-- DEFINER, which is what lets them do the joins and the arithmetic without
-- every caller needing rights on every table - and being SECURITY DEFINER,
-- row-level security does not apply inside them. They never asked who was
-- calling. vs_list_statements, which is what fills the home screen, returned
-- EVERY settlement in the company to whoever asked.
--
-- Nine functions are corrected here. Each one now answers only for a
-- settlement, version or site the caller is entitled to, using the same
-- vs_sees() rule that governs the tables.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER
-- VS-PATCH-1.sql. Safe to re-run. Changes no data. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Can this person see this site at all?
-- ---------------------------------------------------------------------------
-- Staff see every site. A vendor sees a site only where he holds, or has held,
-- a tenure. Past tenures count: a partner who ran Nawa until April still has
-- settlements there to look at.
create or replace function vs_sees_site(p_site uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when vs_role() is null then false
    when vs_can('view_all') then true
    else exists (select 1 from vs_contracts c
                  where c.site_id = p_site and c.vendor_id = vs_my_vendor())
  end
$$;

-- and the same question about a version, which hangs off a statement
create or replace function vs_sees_version(p_ver uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select vs_sees((select statement_id from vs_versions where id = p_ver))
$$;

-- ---------------------------------------------------------------------------
-- 2. The home screen list - the one that was leaking
-- ---------------------------------------------------------------------------
-- One line added: "and vs_sees(s.id)". A vendor now gets his own shared
-- settlements and nothing else; every other role is unchanged.
create or replace function vs_list_statements(p_period date default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'vendor_name', x->>'site_name', x->>'period'), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', s.id, 'period', s.period, 'period_label', vs_period_label(s.period),
      'status', s.status, 'contract_id', c.id, 'vehicles', c.vehicles,
      'tenure_from', c.from_date, 'tenure_to', c.to_date,
      'covers_from', s.covers_from, 'covers_to', s.covers_to,
      'gross', (select gross_amount from vs_versions ve where ve.id = vs_current_version(s.id)),
      'heads_total', vs_version_heads(vs_current_version(s.id)),
      'vendor_id', v.id, 'vendor_name', v.name, 'vendor_code', v.code,
      'site_id', si.id, 'site_name', si.name,
      'version', (select max(ve.v) from vs_versions ve where ve.statement_id = s.id),
      'final', vs_version_final(vs_current_version(s.id)),
      'total', vs_version_total(vs_current_version(s.id)),
      'payroll_status', coalesce(pr.status,'pending'),
      'open_points', (select count(*) from vs_points p where p.statement_id = s.id
                       and p.status in ('open','awaiting_confirm')),
      'point_count', (select count(*) from vs_points p where p.statement_id = s.id),
      'version_count', (select count(*) from vs_versions ve where ve.statement_id = s.id),
      'event_count', (select count(*) from vs_events e where e.statement_id = s.id),
      'approved_amount', s.approved_amount, 'approved_at', s.approved_at,
      'paid_total', vs_paid_total(s.id), 'due_at', s.due_at
    ) as x
    from vs_statements s
    join vs_contracts c on c.id = s.contract_id
    join vs_vendors  v  on v.id = c.vendor_id
    join vs_sites    si on si.id = c.site_id
    left join vs_payroll pr on pr.statement_id = s.id
    where (p_period is null or s.period = date_trunc('month', p_period)::date)
      and vs_sees(s.id)
  ) q
$$;

-- ---------------------------------------------------------------------------
-- 3. The money helpers
-- ---------------------------------------------------------------------------
-- These take a version or a statement id and hand back a figure. They were
-- happy to price anybody's month. They now return null for a month the caller
-- is not entitled to, rather than raising - they are called inside aggregates
-- and a refusal there would break a legitimate screen for an illegitimate row
-- that should simply not be counted.
create or replace function vs_version_heads(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then (select coalesce(sum(amount),0) from vs_version_lines where version_id = p_ver)
  end
$$;

create or replace function vs_version_adj_total(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver) then
    (select coalesce(sum(case effect when 'add' then amount when 'deduct' then -amount else 0 end),0)
       from vs_version_adj where version_id = p_ver)
  end
$$;

create or replace function vs_version_total(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then coalesce((select gross_amount from vs_versions where id = p_ver),0) - vs_version_heads(p_ver)
  end
$$;

create or replace function vs_version_final(p_ver uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees_version(p_ver)
    then vs_version_total(p_ver) + vs_version_adj_total(p_ver)
  end
$$;

create or replace function vs_current_version(p_stmt uuid) returns uuid
language sql stable security definer set search_path = public as $$
  select case when vs_sees(p_stmt)
    then (select id from vs_versions where statement_id = p_stmt order by v desc limit 1)
  end
$$;

create or replace function vs_paid_total(p_stmt uuid) returns numeric
language sql stable security definer set search_path = public as $$
  select case when vs_sees(p_stmt)
    then (select coalesce(sum(amount),0) from vs_payments where statement_id = p_stmt)
  end
$$;

-- ---------------------------------------------------------------------------
-- 4. Which vendor was running a site on a given day
-- ---------------------------------------------------------------------------
create or replace function vs_contract_at(p_site uuid, p_on date) returns uuid
language sql stable security definer set search_path = public as $$
  select case when vs_sees_site(p_site) then
    (select id from vs_contracts
      where site_id = p_site and p_on between from_date and coalesce(to_date,'infinity'::date)
      limit 1)
  end
$$;

-- ---------------------------------------------------------------------------
-- 5. The chain of tenures on a site
-- ---------------------------------------------------------------------------
-- Staff see the whole chain, which is the point of it - who ran this site,
-- when, and how many settlements each one had. A vendor sees only his own
-- stretch of it. He learns nothing about who came before him or after, and the
-- "this site has changed hands" banner simply does not appear for him.
create or replace function vs_site_history(p_site uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'contract_id', c.id, 'vendor_id', v.id, 'vendor_name', v.name, 'vehicles', c.vehicles,
    'from_date', c.from_date, 'to_date', c.to_date,
    'from_label', to_char(c.from_date,'DD Mon YYYY'),
    'to_label', coalesce(to_char(c.to_date,'DD Mon YYYY'),'current'),
    'settlements', (select count(*) from vs_statements s where s.contract_id = c.id)
  ) order by c.from_date), '[]'::jsonb)
  from vs_contracts c join vs_vendors v on v.id = c.vendor_id
  where c.site_id = p_site
    and vs_sees_site(p_site)
    and (vs_can('view_all') or c.vendor_id = vs_my_vendor())
$$;

-- ---------------------------------------------------------------------------
-- 6. The payroll correction diff
-- ---------------------------------------------------------------------------
-- This one raises rather than returning empty: it is called directly by a
-- screen, never inside an aggregate, so a refusal is the honest answer.
create or replace function vs_payroll_diff(p_stmt uuid, p_ver uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare pr vs_payroll%rowtype; out jsonb := '[]'::jsonb; cur numeric;
begin
  if not vs_sees(p_stmt) then
    raise exception 'Not visible to you.' using errcode='42501';
  end if;
  select * into pr from vs_payroll where statement_id = p_stmt;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages';
  if cur is distinct from pr.dh_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages','from',cur,'to',pr.dh_pay,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_ee';
  if cur is distinct from pr.dh_pf_ee + pr.dh_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_ee','from',cur,'to',pr.dh_pf_ee+pr.dh_esic_ee,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='wages_er';
  if cur is distinct from pr.dh_pf_er + pr.dh_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','wages_er','from',cur,'to',pr.dh_pf_er+pr.dh_esic_er,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='salary';
  if cur is distinct from pr.stf_pay then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','salary','from',cur,'to',pr.stf_pay,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_ee';
  if cur is distinct from pr.stf_pf_ee + pr.stf_esic_ee then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_ee','from',cur,'to',pr.stf_pf_ee+pr.stf_esic_ee,'why','Payroll correction posted by Accounts.')); end if;
  select amount into cur from vs_version_lines where version_id=p_ver and head_key='staff_er';
  if cur is distinct from pr.stf_pf_er + pr.stf_esic_er then out := out || jsonb_build_array(jsonb_build_object(
    'kind','head','key','staff_er','from',cur,'to',pr.stf_pf_er+pr.stf_esic_er,'why','Payroll correction posted by Accounts.')); end if;
  select coalesce(amount,0) into cur from vs_version_adj where version_id=p_ver and payroll_linked;
  if coalesce(cur,0) is distinct from pr.not_processed_amount then out := out || jsonb_build_array(jsonb_build_object(
    'kind','adj','key','not_processed','from',coalesce(cur,0),'to',pr.not_processed_amount,
    'why','Payroll correction posted by Accounts.')); end if;
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Booking heads, tightened the same way
-- ---------------------------------------------------------------------------
-- The old policy let a vendor read the heads of a site he currently runs. It
-- now uses the same rule as everything else, so a site he used to run stays
-- readable - otherwise his own old statements would render with blank labels.
drop policy if exists p_heads_r on vs_heads;
create policy p_heads_r on vs_heads for select to authenticated
  using (vs_sees_site(site_id));

drop policy if exists p_sites_r on vs_sites;
create policy p_sites_r on vs_sites for select to authenticated
  using (vs_sees_site(id));

grant execute on function vs_sees_site(uuid), vs_sees_version(uuid) to authenticated;

-- ---------------------------------------------------------------- verification
-- Every one of these should say t.
select
  (select count(*) = 0 from pg_proc
     where proname = 'vs_list_statements'
       and prosrc not like '%vs_sees(s.id)%')                     as list_is_filtered,
  (select count(*) = 2 from pg_proc
     where proname in ('vs_sees_site','vs_sees_version'))         as gates_exist,
  (select count(*) = 0 from pg_proc
     where proname in ('vs_version_heads','vs_version_total','vs_version_final',
                       'vs_version_adj_total','vs_current_version','vs_paid_total',
                       'vs_contract_at','vs_site_history','vs_payroll_diff')
       and prosrc not like '%vs_sees%')                           as helpers_are_gated,
  (select count(*) = 9 from pg_proc
     where proname in ('vs_version_heads','vs_version_total','vs_version_final',
                       'vs_version_adj_total','vs_current_version','vs_paid_total',
                       'vs_contract_at','vs_site_history','vs_payroll_diff'))
                                                                  as all_nine_present;
-- Expect: t | t | t | t
