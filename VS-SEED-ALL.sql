-- VS-SEED-ALL.sql   (run this ONE file - it replaces the two seed files)
-- ============================================================================
-- Everything that can be lifted from 'Operation Partners Payment Details 9.xlsx':
--   * your ten sites
--   * each site's own booking heads, exactly as they read on that sheet
--   * the four vendors the workbook names
--   * the vendor-to-site tenures it evidences, including the Nawa handover
--
-- Run AFTER VS-SETUP.sql, in the Supabase SQL editor. Select the WHOLE file.
-- Safe to run more than once. Pure ASCII.
--
-- At the end it prints what was loaded and what still needs you.
-- ============================================================================

select 'BEFORE' as stage,
  (select count(*) from vs_sites)      as sites,
  (select count(*) from vs_heads)      as booking_heads,
  (select count(*) from vs_vendors)    as vendors,
  (select count(*) from vs_contracts)  as tenures,
  (select count(*) from vs_statements) as settlements;

-- ============================================================================
-- PART 1 - sites and their booking heads
-- ============================================================================
do $seed$
declare sid uuid;
begin

  -- ---------------- Kuchaman ----------------
  select id into sid from vs_sites where name = 'Kuchaman';
  if sid is null then
    insert into vs_sites (name, city) values ('Kuchaman', 'Kuchaman') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 20),
    (sid, 'maint_exp_by_shyam_ji_punit', 'Maint. Exp By Shyam Ji/Punit', 'run', 'manual', 30),
    (sid, 'fuel_exp_adj', 'Fuel Exp. (Adj)', 'run', 'manual', 40),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 50),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 60),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 70),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 80),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 90),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 100),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 110),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 120),
    (sid, 'other_exp', 'Other Exp', 'run', 'manual', 130);

  -- ---------------- Parbatsar ----------------
  select id into sid from vs_sites where name = 'Parbatsar';
  if sid is null then
    insert into vs_sites (name, city) values ('Parbatsar', 'Parbatsar') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_shyam_ji_punit', 'Maint. Exp By Shyam Ji/Punit', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 120);

  -- ---------------- Nawa ----------------
  select id into sid from vs_sites where name = 'Nawa';
  if sid is null then
    insert into vs_sites (name, city) values ('Nawa', 'Nawa') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_shyam_ji_punit', 'Maint. Exp By Shyam Ji/Punit', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 120);

  -- ---------------- Bundi ----------------
  select id into sid from vs_sites where name = 'Bundi';
  if sid is null then
    insert into vs_sites (name, city) values ('Bundi', 'Bundi') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_wevois', 'Maint. Exp By Wevois', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'fuel_exp_loader_tractor_of_wevois', 'Fuel Exp (Loader & Tractor) of wevois', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part_by_wevois', 'ESIC Pf (Employee Part)-By Wevois', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part_by_wevois', 'ESIC Pf (Employer Part)- By Wevois', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'vehicle_rent_of_5_tractor', 'Vehicle Rent of 5 Tractor', 'run', 'manual', 120);

  -- ---------------- Vidhisa ----------------
  select id into sid from vs_sites where name = 'Vidhisa';
  if sid is null then
    insert into vs_sites (name, city) values ('Vidhisa', 'Vidhisa') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp', 'R&M Exp.', 'run', 'manual', 10),
    (sid, 'maint_exp_by_co', 'Maint. Exp By Co.', 'run', 'manual', 20),
    (sid, 'miss_exp', 'Miss. Exp', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 120);

  -- Dei: terms only in the workbook, no heads yet
  if not exists (select 1 from vs_sites where name = 'Dei') then
    insert into vs_sites (name, city) values ('Dei', 'Dei');
  end if;

  -- Laxmangarh: terms only in the workbook, no heads yet
  if not exists (select 1 from vs_sites where name = 'Laxmangarh') then
    insert into vs_sites (name, city) values ('Laxmangarh', 'Laxmangarh');
  end if;

  -- ---------------- Jhunjhunu ----------------
  select id into sid from vs_sites where name = 'Jhunjhunu';
  if sid is null then
    insert into vs_sites (name, city) values ('Jhunjhunu', 'Jhunjhunu') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp_by_kishan_ji', 'R&M Exp.(By Kishan ji)', 'run', 'manual', 10),
    (sid, 'maint_exp_by_company', 'Maint. Exp By Company', 'run', 'manual', 20),
    (sid, 'parking_rent', 'Parking Rent', 'run', 'manual', 30),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 40),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 50),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 60),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 70),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 80),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 90),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 100),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 110);

  -- ---------------- Chirawa ----------------
  select id into sid from vs_sites where name = 'Chirawa';
  if sid is null then
    insert into vs_sites (name, city) values ('Chirawa', 'Chirawa') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp_paid_by_kishan_ji', 'R&M Exp.( Paid By Kishan ji)', 'run', 'manual', 10),
    (sid, 'r_m_exp_paid_by_wevois', 'R&M Exp. (Paid By Wevois)', 'run', 'manual', 20),
    (sid, 'print_exp', 'Print Exp.', 'run', 'manual', 30),
    (sid, 'maint_exp_by_shyam_ji', 'Maint. Exp By Shyam Ji', 'run', 'manual', 40),
    (sid, 'water_exp', 'Water Exp', 'run', 'manual', 50),
    (sid, 'building_rent', 'Building Rent', 'run', 'manual', 60),
    (sid, 'fuel_exp', 'Fuel Exp.', 'run', 'manual', 70),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 80),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 90),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 100),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 110),
    (sid, 'esic_pf_employee_part_2', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 120),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 130),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 140);

  -- ---------------- Sujalpur ----------------
  select id into sid from vs_sites where name = 'Sujalpur';
  if sid is null then
    insert into vs_sites (name, city) values ('Sujalpur', 'Sujalpur') returning id into sid;
  end if;
  delete from vs_heads where site_id = sid;
  insert into vs_heads (site_id, key, label, grp, src, sort) values
    (sid, 'r_m_exp_by_subham_ji', 'R&M Exp. ( By Subham ji)', 'run', 'manual', 10),
    (sid, 'print_exp', 'Print exp', 'run', 'manual', 20),
    (sid, 'maint_exp', 'Maint. Exp', 'run', 'manual', 30),
    (sid, 'water_exp', 'Water Exp', 'run', 'manual', 40),
    (sid, 'building_rent', 'Building Rent', 'run', 'manual', 50),
    (sid, 'fuel_exp_by_shubham_ji', 'Fuel Exp. (By Shubham ji)', 'run', 'manual', 60),
    (sid, 'wages_exp_driver_helper', 'Wages exp. (Driver Helper)', 'wages', 'payroll', 70),
    (sid, 'esic_pf_employee_part_from_wevois', 'ESIC Pf (Employee Part) From wevois', 'esic', 'payroll', 80),
    (sid, 'esic_pf_employer_part', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 90),
    (sid, 'salary_exp_staff', 'Salary Exp (staff)', 'staff', 'payroll', 100),
    (sid, 'esic_pf_employee_part', 'ESIC Pf (Employee Part)', 'esic', 'payroll', 110),
    (sid, 'esic_pf_employer_part_2', 'ESIC Pf (Employer Part)', 'esic', 'payroll', 120),
    (sid, 'operation_partner', 'Operation Partner', 'run', 'manual', 130);

  -- vendors named in the workbook
  insert into vs_vendors (name, code, contact_name)
  select v.n, v.c, v.n from (values
    ('Heera Ram ji','OP-HRJ'), ('Kishan Ji','OP-KSJ'), ('Shubham Ji','OP-SBJ'), ('Firoz','OP-FRZ')
  ) as v(n,c) where not exists (select 1 from vs_vendors x where x.name = v.n);

end $seed$;

-- ============================================================================
-- PART 2 - vendors and the vendor-to-site tenures
-- ============================================================================
do $seed2$
declare
  v_heera uuid; v_kishan uuid; v_shubham uuid; v_firoz uuid;
  s_kuchaman uuid; s_nawa uuid; s_chirawa uuid; s_jhunjhunu uuid; s_sujalpur uuid;
begin

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

-- ============================================================================
-- What was loaded
-- ============================================================================
select s.name as site, count(h.*) as booking_heads
  from vs_sites s left join vs_heads h on h.site_id = s.id
 group by s.name order by s.name;

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
