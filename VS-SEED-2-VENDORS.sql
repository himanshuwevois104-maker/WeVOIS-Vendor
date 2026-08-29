-- VS-SEED-2-VENDORS.sql
-- Loads the vendors and the vendor-to-site tenures that can be evidenced from
-- 'Operation Partners Payment Details 9.xlsx'.
--
-- Run this in the Supabase SQL editor AFTER VS-SETUP.sql and VS-SEED-WEVOIS.sql.
-- Safe to run more than once. Pure ASCII.
--
-- It prints three things: what is in the database now, what it just did, and
-- which sites still have nobody running them.
-- ============================================================================

-- ---------------------------------------------------------------- 1. before
select 'BEFORE' as stage,
  (select count(*) from vs_sites)      as sites,
  (select count(*) from vs_heads)      as booking_heads,
  (select count(*) from vs_vendors)    as vendors,
  (select count(*) from vs_contracts)  as tenures,
  (select count(*) from vs_statements) as settlements,
  (select count(*) from vs_profiles)   as people;
-- If sites is 0, VS-SEED-WEVOIS.sql has not run. Run that first, then come back.

do $seed2$
declare
  v_heera uuid; v_kishan uuid; v_shubham uuid; v_firoz uuid;
  s_kuchaman uuid; s_nawa uuid; s_chirawa uuid; s_jhunjhunu uuid; s_sujalpur uuid;
begin

  if not exists (select 1 from vs_sites) then
    raise exception 'No sites found. Run VS-SEED-WEVOIS.sql first, then run this file.';
  end if;

  -- ------------------------------------------------------------ 2. vendors
  -- The four named in the workbook. Contact details are blank on purpose -
  -- fill them in from Administration -> Vendors, or send them to me.
  insert into vs_vendors (name, code, contact_name)
  select v.n, v.c, v.n
  from (values
    ('Heera Ram ji','OP-HRJ'),
    ('Kishan Ji',   'OP-KSJ'),
    ('Shubham Ji',  'OP-SBJ'),
    ('Firoz',       'OP-FRZ')
  ) as v(n,c)
  where not exists (select 1 from vs_vendors x where lower(x.name) = lower(v.n));

  select id into v_heera   from vs_vendors where name = 'Heera Ram ji';
  select id into v_kishan  from vs_vendors where name = 'Kishan Ji';
  select id into v_shubham from vs_vendors where name = 'Shubham Ji';
  select id into v_firoz   from vs_vendors where name = 'Firoz';

  select id into s_kuchaman  from vs_sites where name = 'Kuchaman';
  select id into s_nawa      from vs_sites where name = 'Nawa';
  select id into s_chirawa   from vs_sites where name = 'Chirawa';
  select id into s_jhunjhunu from vs_sites where name = 'Jhunjhunu';
  select id into s_sujalpur  from vs_sites where name = 'Sujalpur';

  -- ------------------------------------------------------- 3. the tenures
  -- Only the ones the workbook actually evidences. Each is skipped if that
  -- site already has somebody assigned, so re-running changes nothing.

  -- Kuchaman: sheet header "Heera Ram ji Kuchaman", 20 vehicles at 45,000,
  -- months running from Aug 2024.
  if s_kuchaman is not null and not exists (select 1 from vs_contracts where site_id = s_kuchaman) then
    insert into vs_contracts (vendor_id, site_id, vehicles, from_date)
    values (v_heera, s_kuchaman, 20, date '2024-08-01');
  end if;

  -- Chirawa: sheet header "Kishan Ji Chirawa", 12 vehicles, from Oct 2024.
  if s_chirawa is not null and not exists (select 1 from vs_contracts where site_id = s_chirawa) then
    insert into vs_contracts (vendor_id, site_id, vehicles, from_date)
    values (v_kishan, s_chirawa, 12, date '2024-10-01');
  end if;

  -- Sujalpur: sheet header "Shubham Ji Shujalur", 12 vehicles, from Feb 2025.
  if s_sujalpur is not null and not exists (select 1 from vs_contracts where site_id = s_sujalpur) then
    insert into vs_contracts (vendor_id, site_id, vehicles, from_date)
    values (v_shubham, s_sujalpur, 12, date '2025-02-01');
  end if;

  -- Jhunjhunu: head reads "R&M Exp.(By Kishan ji)", months from Dec 2025.
  -- VEHICLE COUNT IS A PLACEHOLDER OF 1 - the sheet leaves the cell blank.
  if s_jhunjhunu is not null and not exists (select 1 from vs_contracts where site_id = s_jhunjhunu) then
    insert into vs_contracts (vendor_id, site_id, vehicles, from_date)
    values (v_kishan, s_jhunjhunu, 1, date '2025-12-01');
  end if;

  -- Nawa: Heera Ram ji from Dec 2024, 6 vehicles. The sheet says
  -- "01/04/2026 ( From 16th April Hand over to FIROJ)", so the tenure ends on
  -- 15 April 2026 and Firoz starts on the 16th. April 2026 therefore produces
  -- TWO settlements for Nawa, one per vendor, each covering only its own days.
  if s_nawa is not null and not exists (select 1 from vs_contracts where site_id = s_nawa) then
    insert into vs_contracts (vendor_id, site_id, vehicles, from_date, to_date)
    values (v_heera, s_nawa, 6, date '2024-12-01', date '2026-04-15');
    insert into vs_contracts (vendor_id, site_id, vehicles, from_date)
    values (v_firoz, s_nawa, 6, date '2026-04-16');
  end if;

  -- ------------------------------------------------------------- 4. audit
  insert into vs_audit (actor_name, actor_role, title, body)
  values ('Setup script','admin','Vendors and tenures seeded',
    'Loaded from Operation Partners Payment Details 9.xlsx: Heera Ram ji (Kuchaman, Nawa to 15 Apr 2026), '
    || 'Firoz (Nawa from 16 Apr 2026), Kishan Ji (Chirawa, Jhunjhunu), Shubham Ji (Sujalpur).');

end $seed2$;

-- ----------------------------------------------------------------- 5. after
select 'AFTER' as stage,
  (select count(*) from vs_vendors)   as vendors,
  (select count(*) from vs_contracts) as tenures;

select v.name as vendor, s.name as site, c.vehicles,
       to_char(c.from_date,'DD Mon YYYY') as from_date,
       coalesce(to_char(c.to_date,'DD Mon YYYY'),'current') as to_date
  from vs_contracts c
  join vs_vendors v on v.id = c.vendor_id
  join vs_sites   s on s.id = c.site_id
 order by s.name, c.from_date;

-- ------------------------------------------------- 6. what still needs you
select s.name as site_with_no_vendor,
       'Assign one in Administration -> Sites & tenures' as what_to_do
  from vs_sites s
 where not exists (select 1 from vs_contracts c where c.site_id = s.id)
 order by s.name;

select 'Jhunjhunu vehicle count is a placeholder of 1' as also_fix,
       'The workbook leaves that cell blank. Set the real number in Administration -> Sites & tenures.' as note
 where exists (select 1 from vs_contracts c join vs_sites s on s.id = c.site_id
                where s.name = 'Jhunjhunu' and c.vehicles = 1);
