-- VS-PATCH-3.sql
-- ============================================================================
-- The administrator can now edit a site and a tenure after creating them.
--
-- Until now a site had a name and a city and nothing else, and neither could be
-- changed once typed - a misspelt site name was permanent. A tenure could have
-- its vehicle count changed and could be given an end date, but its START date
-- could never be corrected: the only way out was to delete the tenure, which
-- itself is refused once a single settlement exists under it.
--
-- This adds:
--   a site's own operating life  - the date WeVois started there and the date
--                                  it closed, separate from who ran it
--   vs_set_site(...)             - rename, re-city, re-date, in one call
--   vs_set_contract(...)         - change a tenure's start, end and vehicles
--   vs_reopen_contract(...)      - undo an end date set by mistake
--
-- Every one of them refuses rather than corrupts. A date change that would
-- strand an existing settlement outside its own tenure, or make two vendors
-- overlap on one site, or close a site before the last month settled under it,
-- is turned away with the months named.
--
-- Run in the Supabase SQL editor, selecting the whole file, AFTER VS-PATCH-2.
-- Safe to re-run. Pure ASCII.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. A site gets a life of its own
-- ---------------------------------------------------------------------------
-- Distinct from the tenures. A site can be running with nobody assigned yet
-- (start_date set, no contract), and it can be closed while its history stays
-- readable. close_date null means still running.
alter table vs_sites add column if not exists start_date date;
alter table vs_sites add column if not exists close_date date;

do $do$
begin
  if not exists (select 1 from pg_constraint where conname = 'vs_sites_dates_ck') then
    alter table vs_sites add constraint vs_sites_dates_ck
      check (close_date is null or start_date is null or close_date >= start_date);
  end if;
end $do$;

-- Fill in what can be inferred, once, for sites that already have tenures.
update vs_sites s
   set start_date = (select min(c.from_date) from vs_contracts c where c.site_id = s.id)
 where s.start_date is null
   and exists (select 1 from vs_contracts c where c.site_id = s.id);

-- A site whose every tenure has ended is treated as closed on the last of them.
update vs_sites s
   set close_date = (select max(c.to_date) from vs_contracts c where c.site_id = s.id)
 where s.close_date is null
   and exists (select 1 from vs_contracts c where c.site_id = s.id)
   and not exists (select 1 from vs_contracts c where c.site_id = s.id and c.to_date is null);

-- ---------------------------------------------------------------------------
-- 2. Is this site open for this month?
-- ---------------------------------------------------------------------------
-- A month may be settled if it overlaps the site's operating window at all. A
-- site with no dates set is treated as always open, so nothing that exists
-- today suddenly stops working.
create or replace function vs_site_open_in(p_site uuid, p_period date) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select daterange(coalesce(s.start_date,'-infinity'::date),
                     coalesce(s.close_date,'infinity'::date), '[]')
        && daterange(date_trunc('month', p_period)::date,
                     (date_trunc('month', p_period) + interval '1 month - 1 day')::date, '[]')
      from vs_sites s where s.id = p_site), true)
$$;

create or replace function vs_site_status(p_site uuid) returns text
language sql stable security definer set search_path = public as $$
  select case
    when s.close_date is not null and s.close_date < current_date then 'closed'
    when s.start_date is not null and s.start_date > current_date then 'not_started'
    else 'running' end
  from vs_sites s where s.id = p_site
$$;

-- ---------------------------------------------------------------------------
-- 3. Edit a site
-- ---------------------------------------------------------------------------
create or replace function vs_set_site(p_site uuid, p_name text, p_city text,
                                       p_start date, p_close date)
returns text language plpgsql security definer set search_path = public as $$
declare s vs_sites%rowtype; nm text; earliest date; latest date; running int; changed text := '';
begin
  perform vs_require('manage_vendors');
  select * into s from vs_sites where id = p_site;
  if not found then raise exception 'No such site.' using errcode='02000'; end if;

  nm := coalesce(nullif(trim(p_name),''), s.name);
  if exists (select 1 from vs_sites x where x.id <> p_site and lower(x.name) = lower(nm)) then
    raise exception 'There is already a site called %. Two sites with the same name cannot be told apart on a settlement.', nm
      using errcode='23505';
  end if;

  -- the earliest thing that has actually happened at this site
  select least(
      (select min(c.from_date) from vs_contracts c where c.site_id = p_site),
      (select min(st.period) from vs_statements st
         join vs_contracts c on c.id = st.contract_id where c.site_id = p_site))
    into earliest;
  -- and the latest
  select greatest(
      (select max(c.to_date) from vs_contracts c where c.site_id = p_site),
      (select max((date_trunc('month', st.period) + interval '1 month - 1 day')::date)
         from vs_statements st join vs_contracts c on c.id = st.contract_id
        where c.site_id = p_site))
    into latest;

  if p_start is not null and earliest is not null and p_start > earliest then
    raise exception 'This site already has work recorded from %. The start date cannot be after that.',
      to_char(earliest,'DD Mon YYYY') using errcode='22023';
  end if;

  if p_close is not null then
    select count(*) into running from vs_contracts where site_id = p_site and to_date is null;
    if running > 0 then
      raise exception 'A vendor is still running this site with no end date. End that tenure first, then close the site.'
        using errcode='23503';
    end if;
    if latest is not null and p_close < latest then
      raise exception 'There is work recorded at this site up to %. The closing date cannot be before that.',
        to_char(latest,'DD Mon YYYY') using errcode='22023';
    end if;
  end if;

  if nm <> s.name then changed := changed || 'renamed from ' || s.name || ' to ' || nm || '; '; end if;
  if coalesce(nullif(trim(p_city),''), s.city) is distinct from s.city then
    changed := changed || 'city ' || coalesce(nullif(s.city,''),'(blank)') || ' -> ' || trim(p_city) || '; '; end if;
  if p_start is distinct from s.start_date then
    changed := changed || 'started ' || coalesce(to_char(s.start_date,'DD Mon YYYY'),'(not set)') ||
               ' -> ' || coalesce(to_char(p_start,'DD Mon YYYY'),'(not set)') || '; '; end if;
  if p_close is distinct from s.close_date then
    changed := changed || 'closed ' || coalesce(to_char(s.close_date,'DD Mon YYYY'),'(still running)') ||
               ' -> ' || coalesce(to_char(p_close,'DD Mon YYYY'),'(still running)') || '; '; end if;

  update vs_sites
     set name = nm,
         city = coalesce(nullif(trim(p_city),''), city),
         start_date = p_start,
         close_date = p_close,
         -- the legacy flag is kept in step with the dates so nothing reading it
         -- can disagree with what the screen shows
         active = (p_close is null or p_close >= current_date)
   where id = p_site;

  if changed = '' then return 'nothing changed'; end if;
  perform vs_audit_log('Site changed', nm || ': ' || rtrim(changed, '; '));
  return rtrim(changed, '; ');
end $$;

-- ---------------------------------------------------------------------------
-- 4. Edit a tenure - including the start date, which could not be touched
-- ---------------------------------------------------------------------------
create or replace function vs_set_contract(p_contract uuid, p_vehicles int,
                                           p_from date, p_to date)
returns text language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; f date; t date; clash text; bad text; s vs_sites%rowtype;
        redrawn int := 0; frozen int := 0; changed text := ''; vn text;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such tenure.' using errcode='02000'; end if;
  select * into s from vs_sites where id = c.site_id;

  f := coalesce(p_from, c.from_date);
  t := p_to;                                   -- null here genuinely means "no end date"
  if p_vehicles is not null and p_vehicles < 1 then
    raise exception 'Vehicle count must be at least 1.' using errcode='22023';
  end if;
  if t is not null and t < f then
    raise exception 'The end date cannot be before the start date.' using errcode='22023';
  end if;

  -- no two vendors on one site at the same time
  select v.name || ' (' || to_char(o.from_date,'DD Mon YYYY') || ' to ' ||
         coalesce(to_char(o.to_date,'DD Mon YYYY'),'current') || ')'
    into clash
    from vs_contracts o join vs_vendors v on v.id = o.vendor_id
   where o.site_id = c.site_id and o.id <> p_contract
     and daterange(o.from_date, coalesce(o.to_date,'infinity'::date), '[]')
      && daterange(f, coalesce(t,'infinity'::date), '[]')
   limit 1;
  if clash is not null then
    raise exception 'Those dates run into %. Two vendors cannot hold one site at the same time.', clash
      using errcode='23P01';
  end if;

  -- every settlement already raised under this tenure must still sit inside it
  select string_agg(vs_period_label(st.period), ', ' order by st.period) into bad
    from vs_statements st
   where st.contract_id = p_contract
     and not (daterange(f, coalesce(t,'infinity'::date), '[]')
           && daterange(st.period, (st.period + interval '1 month - 1 day')::date, '[]'));
  if bad is not null then
    raise exception 'That would leave % outside this tenure. Move the dates to cover it, or delete that settlement first.', bad
      using errcode='23503';
  end if;

  -- and inside the site's own operating life
  if s.start_date is not null and f < s.start_date then
    raise exception 'The site itself only starts on %. Change the site first if the partner really began earlier.',
      to_char(s.start_date,'DD Mon YYYY') using errcode='22023';
  end if;
  if s.close_date is not null and (t is null or t > s.close_date) then
    raise exception 'The site closed on %. A tenure cannot run past it.',
      to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;

  if f is distinct from c.from_date then
    changed := changed || 'start ' || to_char(c.from_date,'DD Mon YYYY') || ' -> ' || to_char(f,'DD Mon YYYY') || '; '; end if;
  if t is distinct from c.to_date then
    changed := changed || 'end ' || coalesce(to_char(c.to_date,'DD Mon YYYY'),'(open)') ||
               ' -> ' || coalesce(to_char(t,'DD Mon YYYY'),'(open)') || '; '; end if;
  if p_vehicles is not null and p_vehicles is distinct from c.vehicles then
    changed := changed || 'vehicles ' || c.vehicles || ' -> ' || p_vehicles || '; '; end if;

  update vs_contracts
     set from_date = f, to_date = t, vehicles = coalesce(p_vehicles, vehicles)
   where id = p_contract;

  -- A statement carries the days it covers, taken from the tenure the day it was
  -- opened. Redraw that on drafts, which nobody has seen yet. Leave anything
  -- shared, approved or paid exactly as the vendor received it - a settlement
  -- that has gone out is a record, not a view.
  update vs_statements st
     set covers_from = greatest(f, st.period),
         covers_to   = least(coalesce(t,'infinity'::date),
                             (st.period + interval '1 month - 1 day')::date)
   where st.contract_id = p_contract and st.status = 'draft';
  get diagnostics redrawn = row_count;
  select count(*) into frozen from vs_statements
   where contract_id = p_contract and status <> 'draft';

  if changed = '' then return 'nothing changed'; end if;
  select v.name into vn from vs_vendors v where v.id = c.vendor_id;
  perform vs_audit_log('Tenure changed', vn || ' at ' || s.name || ': ' || rtrim(changed,'; ') ||
    case when redrawn > 0 then ' (' || redrawn || ' draft settlement(s) redrawn)' else '' end ||
    case when frozen  > 0 then ' (' || frozen  || ' already sent, left untouched)' else '' end);
  return rtrim(changed,'; ') ||
    case when frozen > 0 then '. ' || frozen || ' settlement(s) already sent keep the dates the vendor saw.' else '' end;
end $$;

-- ---------------------------------------------------------------------------
-- 5. Undo an end date
-- ---------------------------------------------------------------------------
create or replace function vs_reopen_contract(p_contract uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; clash text; s vs_sites%rowtype; vn text;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such tenure.' using errcode='02000'; end if;
  if c.to_date is null then raise exception 'That tenure is already open.' using errcode='22023'; end if;
  select * into s from vs_sites where id = c.site_id;
  if s.close_date is not null then
    raise exception 'The site is closed as of %. Reopen the site first.',
      to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;
  select v.name into clash from vs_contracts o join vs_vendors v on v.id = o.vendor_id
   where o.site_id = c.site_id and o.id <> p_contract and o.from_date > c.to_date limit 1;
  if clash is not null then
    raise exception '% took this site over afterwards. End or move that tenure first.', clash
      using errcode='23P01';
  end if;
  update vs_contracts set to_date = null where id = p_contract;
  select v.name into vn from vs_vendors v where v.id = c.vendor_id;
  perform vs_audit_log('Tenure reopened', vn || ' at ' || s.name || ' is running again, no end date');
end $$;

-- ---------------------------------------------------------------------------
-- 5b. Assigning and ending a tenure respect the site's life too
-- ---------------------------------------------------------------------------
-- vs_set_contract checks the site window, but vs_add_contract did not, so a
-- vendor could still be assigned to a site that had already closed - and even
-- given no end date, which vs_set_site refuses to allow in the other order.
-- Both doors now carry the same lock.
create or replace function vs_add_contract(p_vendor uuid, p_site uuid, p_vehicles int,
                                          p_from date default null, p_to date default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare nid uuid; vn text; f date; t date; clash text; s vs_sites%rowtype;
begin
  perform vs_require('manage_contracts');
  if p_vehicles is null or p_vehicles < 1 then
    raise exception 'Vehicle count must be at least 1.' using errcode = '22023';
  end if;
  f := coalesce(p_from, current_date);
  t := p_to;

  select * into s from vs_sites where id = p_site;
  if not found then raise exception 'No such site.' using errcode='02000'; end if;
  if s.start_date is not null and f < s.start_date then
    raise exception '% only opens on %. Move the start date on the site first if the partner really began earlier.',
      s.name, to_char(s.start_date,'DD Mon YYYY') using errcode='22023';
  end if;
  if s.close_date is not null and (t is null or t > s.close_date) then
    raise exception '% closed on %. A tenure cannot run past it, and cannot be left open ended.',
      s.name, to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;

  select v.name || ' (' || to_char(c.from_date,'DD Mon YYYY') || ' to ' ||
         coalesce(to_char(c.to_date,'DD Mon YYYY'), 'current') || ')'
    into clash
    from vs_contracts c join vs_vendors v on v.id = c.vendor_id
   where c.site_id = p_site
     and daterange(c.from_date, coalesce(c.to_date,'infinity'::date), '[]')
      && daterange(f, coalesce(t,'infinity'::date), '[]')
   limit 1;
  if clash is not null then
    raise exception 'This site is already held over that period by %. End that tenure first.', clash
      using errcode = '23P01';
  end if;

  insert into vs_contracts (vendor_id, site_id, vehicles, from_date, to_date)
  values (p_vendor, p_site, p_vehicles, f, t) returning id into nid;
  select name into vn from vs_vendors where id = p_vendor;
  perform vs_audit_log('Site assigned',
    vn || ' holds ' || s.name || ' with ' || p_vehicles || ' vehicles from ' || to_char(f,'DD Mon YYYY')
    || coalesce(' to ' || to_char(t,'DD Mon YYYY'), ''));
  return nid;
end $$;

create or replace function vs_end_contract(p_contract uuid, p_last_date date)
returns void language plpgsql security definer set search_path = public as $$
declare c vs_contracts%rowtype; n int; vn text; s vs_sites%rowtype;
begin
  perform vs_require('manage_contracts');
  select * into c from vs_contracts where id = p_contract;
  if not found then raise exception 'No such contract.' using errcode='02000'; end if;
  if p_last_date < c.from_date then
    raise exception 'The last day cannot be before the tenure started (%).', to_char(c.from_date,'DD Mon YYYY')
      using errcode='22023';
  end if;
  select * into s from vs_sites where id = c.site_id;
  if s.close_date is not null and p_last_date > s.close_date then
    raise exception '% closed on %. The tenure cannot run past it.',
      s.name, to_char(s.close_date,'DD Mon YYYY') using errcode='22023';
  end if;
  select count(*) into n from vs_statements
   where contract_id = p_contract and period > date_trunc('month', p_last_date)::date;
  if n > 0 then
    raise exception 'There are % settlement(s) for this vendor after %. Delete those first.',
      n, to_char(p_last_date,'Mon YYYY') using errcode='23503';
  end if;
  update vs_contracts set to_date = p_last_date where id = p_contract;
  select v.name into vn from vs_vendors v where v.id = c.vendor_id;
  perform vs_audit_log('Tenure ended', vn || ' ran ' || s.name || ' until ' || to_char(p_last_date,'DD Mon YYYY'));
end $$;

-- ---------------------------------------------------------------------------
-- 6. A month cannot be opened outside the site's own life
-- ---------------------------------------------------------------------------
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
  insert into vs_version_lines (version_id, head_id, head_key, head_label, grp, src, sort, amount)
    select vid, h.id, h.key, h.label, h.grp, h.src, h.sort, 0
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

create or replace function vs_open_month(p_period date)
returns int language plpgsql security definer set search_path = public as $$
declare c record; n int := 0; per date;
begin
  perform vs_require('manage_settlements');
  per := date_trunc('month', p_period)::date;
  for c in select vs_contracts.id from vs_contracts
           where daterange(from_date, coalesce(to_date,'infinity'::date), '[]')
              && daterange(per, (per + interval '1 month - 1 day')::date, '[]')
             and vs_site_open_in(site_id, per)
             and not exists (select 1 from vs_statements s where s.contract_id = vs_contracts.id and s.period = per)
  loop
    perform vs_add_statement(c.id, per);
    n := n + 1;
  end loop;
  if n > 0 then
    perform vs_audit_log('Month opened', n || ' settlement(s) created for ' || vs_period_label(per));
  end if;
  return n;
end $$;

grant execute on function
  vs_set_site(uuid,text,text,date,date),
  vs_set_contract(uuid,int,date,date),
  vs_reopen_contract(uuid),
  vs_site_open_in(uuid,date),
  vs_site_status(uuid)
to authenticated;

-- ---------------------------------------------------------------- verification
select
  (select count(*) = 2 from information_schema.columns
    where table_name='vs_sites' and column_name in ('start_date','close_date'))  as site_dates,
  (select count(*) = 1 from pg_proc where proname='vs_set_site')                 as edit_site,
  (select count(*) = 1 from pg_proc where proname='vs_set_contract')             as edit_tenure,
  (select count(*) = 1 from pg_proc where proname='vs_reopen_contract')          as reopen,
  (select count(*) = 1 from pg_constraint where conname='vs_sites_dates_ck')     as date_check;
-- Expect: t | t | t | t | t
